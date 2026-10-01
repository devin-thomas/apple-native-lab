import Foundation
import LabDomain
import LabJobs
import Observation
import RenderThatSurvives
import Synchronization
#if os(iOS)
import UIKit
#endif

/// Render That Survives in this app (LAB-032): the fixture recipes, the render jobs the store
/// holds, the running job's progress, and the published movie.
///
/// Every job step goes through `RenderStudio` and `LibraryJobBackend` into `LabLibrary.submit`,
/// so it leaves a receipt in the session's list. The model never polls: it reads the jobs again
/// when a receipt arrives, and it shows progress the worker reports. When the store opens it runs
/// recovery, so a job an earlier process left running reads as stopped and resumable, never as a
/// spinner. When Reset Demo removes the demo jobs, it removes the experiment's files.
@MainActor
@Observable
final class RenderStudioModel {
    enum Phase: Hashable {
        case notStarted
        case ready
        /// The store or the experiment's folder cannot be used. The reason is a sentence.
        case unavailable(String)
    }

    /// The published movie of the selected recipe, read from the file itself.
    struct Output: Hashable {
        let name: String
        let url: URL
        let byteCount: Int64
        let sha256: String
        /// The finished job whose recorded digest matches the file, if one does.
        let job: LabJob?
    }

    static let shared = RenderStudioModel()

    static let preferGPUKey = "RenderThatSurvives.preferGPU"
    static let wantsBackgroundKey = "RenderThatSurvives.wantsBackground"

    private(set) var phase: Phase = .notStarted
    let recipes: [RenderRecipe]
    var selectedRecipeID: String
    var preferGPU: Bool { didSet { defaults.set(preferGPU, forKey: Self.preferGPUKey) } }
    var wantsBackground: Bool { didSet { defaults.set(wantsBackground, forKey: Self.wantsBackgroundKey) } }
    /// Every render job in the store: unfinished ones first.
    private(set) var jobs: [LabJob] = []
    /// The latest progress each running job reported in this app session.
    private(set) var progress: [JobID: RenderProgress] = [:]
    /// How each job ended in this app session.
    private(set) var reports: [JobID: RenderReport] = [:]
    private(set) var output: Output?
    /// The result of the latest action, as a sentence.
    private(set) var lastMessage: String?
    private(set) var isWorking = false

    @ObservationIgnored private var library: LabLibrary?
    @ObservationIgnored private var studio: RenderStudio?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let foreground = ForegroundFlag()
    @ObservationIgnored private var handledResets: Set<OperationID> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recipes = (try? RenderThatSurvives.bundledRecipes()) ?? []
        selectedRecipeID = recipes.first?.id ?? ""
        preferGPU = defaults.object(forKey: Self.preferGPUKey) as? Bool ?? true
        wantsBackground = defaults.object(forKey: Self.wantsBackgroundKey) as? Bool ?? true
    }

    var selectedRecipe: RenderRecipe? { recipes.first { $0.id == selectedRecipeID } }

    // MARK: Connection

    /// Composes the studio over this app's library and platform runway, runs recovery when the
    /// store opens, and follows receipts. Call once at launch.
    func connect(_ library: LabLibrary, runway: any JobRunway, workspace: RenderWorkspace? = nil) {
        self.library = library
        let folder: RenderWorkspace
        do {
            folder = try workspace ?? RenderWorkspace.appSupport(folder: LabStoreLocation.folderName)
        } catch {
            phase = .unavailable("The app's Application Support folder is unavailable, so renders cannot run.")
            return
        }
        let flag = foreground
        studio = RenderStudio(
            backend: LibraryJobBackend(library: library), workspace: folder,
            gpu: .live(isAllowedNow: { flag.isForeground }), runway: runway
        )
        observeLifecycle()
        Task { @MainActor in
            // The first value, then each change: the store opening and every new receipt.
            for await marker in Observations({ Marker(isReady: library.phase == .ready, newest: library.receipts.first?.id) }) {
                guard marker.isReady else { continue }
                if phase == .notStarted { await recover() }
                await handleResets()
                await refresh()
            }
        }
    }

    private struct Marker: Hashable, Sendable {
        let isReady: Bool
        let newest: OperationID?
    }

    private func recover() async {
        guard let studio else { return }
        do {
            let receipts = try await studio.recover()
            phase = .ready
            if let latest = receipts.last { lastMessage = latest.summary }
        } catch {
            phase = .unavailable(error.message)
        }
    }

    /// After Reset Demo removed demo jobs, stops their workers and removes the experiment's files.
    private func handleResets() async {
        guard let library, let studio else { return }
        let resets = library.receipts.filter { record in
            record.receipt.admitted.operation.kind == .resetDemo && !handledResets.contains(record.id)
        }
        handledResets.formUnion(resets.map(\.id))
        guard resets.contains(where: { $0.receipt.removed.contains { $0.kind == .job } }) else { return }
        await studio.removeEverything()
        progress = [:]
        reports = [:]
    }

    // MARK: Reading

    func refresh() async {
        guard let library, let studio else { return }
        do {
            let service = try await library.openedService()
            let stored = try await service.jobs(kind: .render, as: LabDataService.appUI)
            jobs = stored.sorted { lhs, rhs in
                if lhs.phase.isFinished != rhs.phase.isFinished { return !lhs.phase.isFinished }
                return (lhs.title.value, lhs.id.rawValue.uuidString) < (rhs.title.value, rhs.id.rawValue.uuidString)
            }
        } catch {
            return
        }
        guard let recipe = selectedRecipe else { output = nil; return }
        let url = studio.workspace.output(for: recipe)
        guard let published = await Self.digest(of: url) else { output = nil; return }
        let match = jobs.first { job in
            if case .succeeded(let recorded) = job.phase { recorded.sha256 == published.digest.hex } else { false }
        }
        output = Output(
            name: recipe.outputName, url: url, byteCount: published.byteCount, sha256: published.digest.hex, job: match
        )
    }

    /// Reads a file's digest off the main actor.
    private nonisolated static func digest(of url: URL) async -> AtomicPublication.Published? {
        try? AtomicPublication.digest(of: url)
    }

    /// Unfinished jobs: running or stopped and resumable.
    var activeJobs: [LabJob] { jobs.filter { !$0.phase.isFinished } }
    var finishedJobs: [LabJob] { jobs.filter(\.phase.isFinished) }

    func isLive(_ job: LabJob) -> Bool { studio?.isLive(job.id) ?? false }

    /// Render receipts from this app session, newest first.
    var receipts: [ReceiptRecord] {
        (library?.receipts ?? []).filter { record in
            let kind = record.receipt.admitted.operation.kind
            return kind == .startJob || kind == .updateJob || record.receipt.removed.contains { $0.kind == .job }
        }
    }

    // MARK: Actions

    var canStart: Bool {
        phase == .ready && !isWorking && library?.canAct == true && selectedRecipe != nil
            && !activeJobs.contains { isLive($0) && $0.title.value == selectedRecipe?.title }
    }

    /// Starts the selected recipe as a new job.
    func start() async {
        guard let studio, let recipe = selectedRecipe, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let job = try await studio.start(recipe, options: options, onProgress: progressSink())
            lastMessage = "Started “\(recipe.title)”."
            follow(job.id)
        } catch {
            lastMessage = error.message
        }
        await refresh()
    }

    func resume(_ job: LabJob) async {
        guard let studio, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await studio.resume(job.id, options: options, onProgress: progressSink())
            lastMessage = "Resumed “\(job.title)” from \(job.progress.phrase)."
            follow(job.id)
        } catch {
            lastMessage = error.message
        }
        await refresh()
    }

    /// Pauses a running job at its next safe point; it keeps its finished segments.
    func pause(_ job: LabJob) async {
        await stop(job, .interrupt(.paused))
    }

    /// Cancels a running or stopped job. Its work is discarded; the published movie is kept.
    func cancel(_ job: LabJob) async {
        await stop(job, .cancel)
    }

    private func stop(_ job: LabJob, _ request: JobStopSignal.Request) async {
        guard let studio else { return }
        do {
            try await studio.stop(job.id, request)
        } catch {
            lastMessage = error.message
        }
        await refresh()
    }

    private var options: RenderStudio.Options {
        RenderStudio.Options(preferGPU: preferGPU, wantsBackground: wantsBackground)
    }

    /// Waits for a worker to end, then reports how it ended.
    private func follow(_ id: JobID) {
        guard let studio else { return }
        Task { @MainActor in
            guard let outcome = await studio.outcome(of: id) else { return }
            progress[id] = nil
            if let report = outcome.report { reports[id] = report }
            lastMessage = Self.sentence(for: outcome)
            await refresh()
            LabAnnouncement(text: lastMessage ?? "").post()
        }
    }

    static func sentence(for outcome: RenderOutcome) -> String {
        switch outcome {
        case .succeeded(let job, let report):
            "Finished “\(job.title)”: \(report.output.name), \(ByteCountFormatter.string(fromByteCount: report.output.byteCount, countStyle: .file))."
        case .cancelled(let job):
            "Cancelled “\(job.title)”. The published movie, if there was one, is unchanged."
        case .interrupted(let job, let reason):
            "Stopped “\(job.title)” at \(job.progress.phrase) because \(reason.clause). It can resume."
        case .failed(let job, let failure):
            "“\(job.title)” failed: \(failure.message)"
        case .superseded(let phase):
            phase == nil
                ? "The job was removed, so the render stopped without publishing."
                : "The job changed elsewhere, so the render stopped without publishing."
        case .unrecorded(let error):
            "The render stopped, and its last step could not be saved: \(error.message)"
        }
    }

    /// Delivers a worker's progress to the main actor, at most about ten times a second per job,
    /// and always when its step changes.
    private func progressSink() -> @Sendable (RenderProgress) -> Void {
        let gate = ProgressGate()
        return { [weak self] update in
            guard gate.shouldDeliver(update) else { return }
            Task { @MainActor in
                guard let self, self.studio?.isLive(update.job) == true else { return }
                self.progress[update.job] = update
            }
        }
    }

    // MARK: Leaving the foreground (iPhone and iPad)

    private func observeLifecycle() {
        #if os(iOS)
        let center = NotificationCenter.default
        Task { @MainActor [weak self] in
            for await _ in center.notifications(named: UIApplication.didEnterBackgroundNotification) {
                await self?.didEnterBackground()
            }
        }
        Task { @MainActor [weak self] in
            for await _ in center.notifications(named: UIApplication.willEnterForegroundNotification) {
                self?.foreground.set(true)
                await self?.refresh()
            }
        }
        #endif
    }

    #if os(iOS)
    /// The GPU may not be used from here on. A job with no background time stops at its next
    /// frame; the app asks for a short grace period so that stop is recorded before suspension.
    private func didEnterBackground() async {
        foreground.set(false)
        guard let studio else { return }
        let stopping = activeJobs.filter { job in
            guard studio.isLive(job.id) else { return false }
            if case .continuedProcessing = studio.runway(of: job.id) { return false }
            return true
        }
        guard !stopping.isEmpty else { return }
        let grace = UIApplication.shared.beginBackgroundTask(withName: "Stop render at a checkpoint")
        await studio.appWillLeaveForeground()
        for job in stopping { _ = await studio.outcome(of: job.id) }
        if grace != .invalid { UIApplication.shared.endBackgroundTask(grace) }
    }
    #endif
}

/// Whether the app is in the foreground, readable from the worker's thread.
final class ForegroundFlag: Sendable {
    private let state = Mutex(true)
    var isForeground: Bool { state.withLock { $0 } }
    func set(_ value: Bool) { state.withLock { $0 = value } }
}

/// Lets through a job's progress when its step changes or a tenth of a second has passed.
private final class ProgressGate: Sendable {
    private struct Last {
        var step: RenderProgress.Step?
        var at: ContinuousClock.Instant?
    }

    private let state = Mutex(Last())

    func shouldDeliver(_ update: RenderProgress) -> Bool {
        let now = ContinuousClock.now
        return state.withLock { last in
            let due = last.at.map { now - $0 >= .milliseconds(100) } ?? true
            guard due || last.step != update.step || update.framesDone == update.frameTotal else { return false }
            last = Last(step: update.step, at: now)
            return true
        }
    }
}
