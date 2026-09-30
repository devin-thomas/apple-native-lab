#if !os(watchOS)
import Foundation
import LabDomain
import LabJobs
import Synchronization

/// Why a render did not start, resume, or stop. Each refusal recorded nothing.
public enum RenderRefusal: Error, Hashable, Sendable {
    case destination(DestinationProblem)
    /// A job for the same output is already running in this app.
    case alreadyRunning
    /// Only an interrupted job can resume; this one is in another phase.
    case notResumable(JobPhase.Name)
    /// The recipe saved with the job is missing or unreadable, so it cannot resume.
    case recipeMissing
    case job(JobError)

    public var message: String {
        switch self {
        case .destination(let problem): problem.message
        case .alreadyRunning: "This render is already running. Nothing new was started."
        case .notResumable(let phase): "Only a stopped render can resume; this one is \(phase.rawValue)."
        case .recipeMissing: "This render's saved recipe is gone, so it cannot resume. Cancel it and start again."
        case .job(let error): error.message
        }
    }
}

/// The host's render service: starts, resumes, stops, and recovers render jobs, and owns the one
/// worker task per running job.
///
/// Every state change is a job operation through the host's `JobBackend`, so the app UI, a
/// recovery at launch, and the worker all leave receipts in one list. A running job's worker is
/// stopped through its signal, never by cancelling its task, so it always records why it stopped.
public actor RenderStudio {
    public struct Options: Hashable, Sendable {
        public var preferGPU: Bool
        public var wantsBackground: Bool

        public init(preferGPU: Bool = true, wantsBackground: Bool = true) {
            self.preferGPU = preferGPU
            self.wantsBackground = wantsBackground
        }
    }

    public nonisolated let workspace: RenderWorkspace
    private let backend: any JobBackend
    private let destination: DestinationCheck
    private let gpu: GPUAccess
    private let runway: any JobRunway
    private let onStage: @Sendable (JobID, RenderStage) async -> Void

    private var workers: [JobID: Worker] = [:]
    /// Running jobs and their runway, readable without awaiting the actor.
    private let live = LiveJobs()

    private struct Worker {
        let recipe: RenderRecipe
        let signal: JobStopSignal
        let task: Task<RenderOutcome, Never>
    }

    public init(
        backend: any JobBackend,
        workspace: RenderWorkspace,
        destination: DestinationCheck = DestinationCheck(),
        gpu: GPUAccess,
        runway: any JobRunway,
        onStage: @escaping @Sendable (JobID, RenderStage) async -> Void = { _, _ in }
    ) {
        self.backend = backend
        self.workspace = workspace
        self.destination = destination
        self.gpu = gpu
        self.runway = runway
        self.onStage = onStage
    }

    // MARK: Starting

    /// Checks the folder and its space, records a new job, and starts its worker.
    public func start(
        _ recipe: RenderRecipe,
        options: Options,
        requestID: RequestID = RequestID(),
        onProgress: @escaping @Sendable (RenderProgress) -> Void = { _ in }
    ) async throws(RenderRefusal) -> LabJob {
        guard !workers.values.contains(where: { $0.recipe.outputName == recipe.outputName }) else { throw .alreadyRunning }
        do { _ = try destination.prepare(workspace.root, needing: recipe.requiredBytes) } catch { throw .destination(error) }
        let draft: JobDraft
        do {
            draft = try JobDraft(kind: .render, title: EntityTitle(recipe.title), total: recipe.jobUnits, namespace: .demo)
        } catch {
            throw .job(.refused(.invalidPayload(error)))
        }
        let recorder: JobRecorder
        do { recorder = try await JobRecorder.start(draft, backend: backend, requestID: requestID).recorder } catch { throw .job(error) }
        saveRecipe(recipe, for: draft.id)
        let job = await recorder.job
        launch(recorder, recipe: recipe, options: options, onProgress: onProgress)
        return job
    }

    /// Resumes an interrupted job from its last checkpoint with the recipe it started with.
    public func resume(
        _ id: JobID,
        options: Options,
        onProgress: @escaping @Sendable (RenderProgress) -> Void = { _ in }
    ) async throws(RenderRefusal) -> LabJob {
        guard workers[id] == nil else { throw .alreadyRunning }
        let job: LabJob
        do { job = try await backend.job(id) } catch { throw .job(error) }
        guard case .interrupted = job.phase else { throw .notResumable(job.phase.name) }
        guard let recipe = savedRecipe(for: id) else { throw .recipeMissing }
        guard !workers.values.contains(where: { $0.recipe.outputName == recipe.outputName }) else { throw .alreadyRunning }
        do { _ = try destination.prepare(workspace.root, needing: recipe.requiredBytes) } catch { throw .destination(error) }
        let recorder = JobRecorder(job: job, backend: backend)
        do { try await recorder.advance(.resume) } catch { throw .job(error) }
        let resumed = await recorder.job
        launch(recorder, recipe: recipe, options: options, onProgress: onProgress)
        return resumed
    }

    private func launch(
        _ recorder: JobRecorder,
        recipe: RenderRecipe,
        options: Options,
        onProgress: @escaping @Sendable (RenderProgress) -> Void
    ) {
        let signal = JobStopSignal()
        let id = recorder.id
        live.state.withLock { $0[id] = .some(nil) }
        let worker = RenderWorker(
            recipe: recipe, workspace: workspace, gpu: gpu, runway: runway,
            preferGPU: options.preferGPU, wantsBackground: options.wantsBackground, stop: signal,
            onProgress: { [live] progress in
                live.state.withLock { if $0[id] != nil { $0[id] = .some(progress.runway) } }
                onProgress(progress)
            },
            onStage: { [onStage] stage in await onStage(id, stage) }
        )
        let task = Task { [weak self] in
            let outcome = await worker.run(recorder)
            await self?.finished(id)
            return outcome
        }
        workers[id] = Worker(recipe: recipe, signal: signal, task: task)
    }

    private func finished(_ id: JobID) {
        workers[id] = nil
        live.state.withLock { $0[id] = nil }
    }

    // MARK: Stopping

    /// Asks a running job to stop at its next safe point, or cancels a stopped one directly.
    ///
    /// A pause or an interruption of a job that is not running does nothing.
    public func stop(_ id: JobID, _ request: JobStopSignal.Request) async throws(RenderRefusal) {
        if let worker = workers[id] {
            worker.signal.request(request)
            return
        }
        guard request == .cancel else { return }
        let job: LabJob
        do { job = try await backend.job(id) } catch { throw .job(error) }
        guard case .interrupted = job.phase else { throw .notResumable(job.phase.name) }
        do { try await JobRecorder(job: job, backend: backend).advance(.cancel) } catch { throw .job(error) }
        workspace.discardWork(of: id)
    }

    /// Interrupts every running job that has no background time, because the app is leaving the
    /// foreground. Jobs with continued processing, and the Mac worker, keep running.
    public func appWillLeaveForeground() {
        for (id, worker) in workers {
            let mode = live.state.withLock { $0[id] ?? nil }
            if case .continuedProcessing = mode { continue }
            if case .whileAppRuns = mode { continue }
            worker.signal.request(.interrupt(.leftForeground))
        }
    }

    /// Waits for a running job's worker to finish and returns how it ended, or `nil` when no
    /// worker runs it.
    public func outcome(of id: JobID) async -> RenderOutcome? {
        guard let task = workers[id]?.task else { return nil }
        return await task.value
    }

    /// Whether a worker in this process runs the job. Safe to call from any thread.
    public nonisolated func isLive(_ id: JobID) -> Bool {
        live.state.withLock { $0[id] != nil }
    }

    /// The runway a running job holds, once its worker has begun.
    public nonisolated func runway(of id: JobID) -> RunwayMode? {
        live.state.withLock { $0[id] ?? nil }
    }

    // MARK: Recovery and reset

    /// Marks render jobs left running by an earlier process as interrupted, and removes work
    /// folders no stored, unfinished job owns. Call when the store opens.
    @discardableResult
    public func recover() async throws(JobError) -> [ActionReceipt] {
        let receipts = try await JobRecovery.reconcile(kind: .render, backend: backend, isLive: { [live] id in
            live.state.withLock { $0[id] != nil }
        })
        let unfinished = try await backend.jobs(of: .render).filter { !$0.phase.isFinished }.map(\.id)
        workspace.sweep(keeping: Set(unfinished).union(workers.keys))
        return receipts
    }

    /// Stops every worker, waits for each, and removes the experiment's folder. Called after Reset
    /// Demo removed the demo jobs, so the workers find their jobs gone and record nothing.
    public func removeEverything() async {
        for worker in workers.values { worker.signal.request(.cancel) }
        for worker in workers.values { _ = await worker.task.value }
        workspace.removeEverything()
    }

    // MARK: The saved recipe

    private func recipeURL(for id: JobID) -> URL {
        workspace.workFolder(for: id).appending(path: "recipe.json", directoryHint: .notDirectory)
    }

    private func saveRecipe(_ recipe: RenderRecipe, for id: JobID) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(RecipeEnvelope(recipes: [recipe])) else { return }
        try? FileManager.default.createDirectory(at: workspace.workFolder(for: id), withIntermediateDirectories: true)
        try? data.write(to: recipeURL(for: id), options: .atomic)
    }

    /// The recipe saved when the job started, read with the same strict rules as any recipe.
    func savedRecipe(for id: JobID) -> RenderRecipe? {
        guard let data = try? Data(contentsOf: recipeURL(for: id)),
              let recipes = try? RenderRecipe.recipes(from: data), recipes.count == 1
        else { return nil }
        return recipes[0]
    }

    private struct RecipeEnvelope: Encodable {
        let recipes: [RenderRecipe]
    }
}
/// The running jobs of one studio and the runway each holds (`nil` until its worker begins).
private final class LiveJobs: Sendable {
    let state = Mutex<[JobID: RunwayMode?]>([:])
}
#endif
