#if !os(watchOS)
import Foundation
import LabDomain
import LabJobs

/// A point in a run, reported to the host and to tests that stop a run at an exact moment.
public enum RenderStage: Hashable, Sendable {
    case segmentStarted(Int)
    case segmentSaved(Int)
    case assembling
    /// The movie is assembled and checked. The last point at which a stop request is honored.
    case aboutToPublish
    case published
}

/// What a run is doing now, for a progress view and a system surface.
public struct RenderProgress: Hashable, Sendable {
    public enum Step: Hashable, Sendable {
        /// Re-encoding a segment whose file was missing after a stop.
        case repairing(segment: Int)
        case rendering(segment: Int)
        case assembling
        case publishing
    }

    public let job: JobID
    /// Frames durable or drawn so far, of `frameTotal`.
    public let framesDone: Int
    public let frameTotal: Int
    public let step: Step
    /// Which hardware drew the most recent frame.
    public let lastPath: RenderPath?
    public let runway: RunwayMode

    public var fraction: Double { frameTotal == 0 ? 0 : Double(framesDone) / Double(frameTotal) }
}

/// What a finished run produced.
public struct RenderReport: Hashable, Sendable {
    public let output: JobOutput
    public let facts: MovieFacts
    public let tally: PathTally
    /// Segments that were encoded again because their file was missing on resume.
    public let repairedSegments: [Int]
    public let runway: RunwayMode
}

/// How a run ended. Every case except `unrecorded` matches what the store now holds.
public enum RenderOutcome: Hashable, Sendable {
    case succeeded(LabJob, RenderReport)
    /// Cancelled: the work folder is gone and the previous output, if any, is untouched.
    case cancelled(LabJob)
    /// Stopped with finished segments kept, so it can resume.
    case interrupted(LabJob, JobInterruption)
    case failed(LabJob, JobFailure)
    /// The job was changed elsewhere (cancelled in another window, or removed by Reset Demo), so
    /// this run stopped without publishing and recorded nothing more.
    case superseded(JobPhase.Name?)
    /// A step could not be recorded. The job stays as the store has it; the next launch's
    /// recovery marks it interrupted. Finished segments are kept.
    case unrecorded(JobError)

    /// The report of a successful run, or `nil`.
    public var report: RenderReport? {
        if case .succeeded(_, let report) = self { report } else { nil }
    }

    public var job: LabJob? {
        switch self {
        case .succeeded(let job, _), .cancelled(let job), .interrupted(let job, _), .failed(let job, _): job
        case .superseded, .unrecorded: nil
        }
    }
}

/// Runs one render job from its last durable checkpoint to a published movie.
///
/// 1. It asks the runway for time: continued processing on iOS when qualified, the Mac worker's
///    activity, or foreground only.
/// 2. It re-encodes any finished segment whose file is gone, without moving progress back.
/// 3. It encodes each remaining segment to its own file and records a checkpoint after each one.
/// 4. It joins the segments, checks the movie's frame count and size, and only then publishes it
///    over the previous output with one rename, and records the job as finished.
///
/// A stop request is honored at every frame, between segments, during assembly, and just before
/// publishing, never after: a cancel removes the work folder and leaves the previous output as it
/// was, and an interruption keeps finished segments. The good output is only ever replaced by a
/// complete, checked movie.
public struct RenderWorker: Sendable {
    public let recipe: RenderRecipe
    public let workspace: RenderWorkspace
    public let gpu: GPUAccess
    public let runway: any JobRunway
    public let preferGPU: Bool
    public let wantsBackground: Bool
    public let stop: JobStopSignal
    public let onProgress: @Sendable (RenderProgress) -> Void
    public let onStage: @Sendable (RenderStage) async -> Void

    public init(
        recipe: RenderRecipe,
        workspace: RenderWorkspace,
        gpu: GPUAccess,
        runway: any JobRunway,
        preferGPU: Bool,
        wantsBackground: Bool,
        stop: JobStopSignal,
        onProgress: @escaping @Sendable (RenderProgress) -> Void = { _ in },
        onStage: @escaping @Sendable (RenderStage) async -> Void = { _ in }
    ) {
        self.recipe = recipe
        self.workspace = workspace
        self.gpu = gpu
        self.runway = runway
        self.preferGPU = preferGPU
        self.wantsBackground = wantsBackground
        self.stop = stop
        self.onProgress = onProgress
        self.onStage = onStage
    }

    // A fixed, valid message: the initializer cannot fail on it.
    private static let genericFailure = try! JobFailure(code: "render-failed", message: "The render failed.")

    /// Frames the progress total adds for assembling and publishing.
    var finishingWeight: Int { max(1, recipe.frameCount / 10) }

    public func run(_ recorder: JobRecorder) async -> RenderOutcome {
        let job = await recorder.job
        let lease = await runway.begin(
            RunwayRequest(title: "Rendering \(recipe.title)", subtitle: recipe.shape, wantsBackground: wantsBackground),
            onExpiration: { [stop] in stop.request(.interrupt(.expired)) }
        )
        let outcome = await body(job.id, recorder: recorder, lease: lease, durable: min(job.progress.completed, recipe.segmentCount))
        if case .succeeded = outcome { lease.finish(success: true) } else { lease.finish(success: false) }
        return outcome
    }

    private func body(_ id: JobID, recorder: JobRecorder, lease: any JobRunwayLease, durable: Int) async -> RenderOutcome {
        let pattern = FramePattern(recipe: recipe)
        let total = recipe.frameCount + finishingWeight
        var tally = PathTally()
        var repaired: [Int] = []
        let report: @Sendable (Int, RenderProgress.Step, RenderPath?) -> Void = { [onProgress, lease] done, step, path in
            lease.report(completed: Int64(done), total: Int64(total))
            onProgress(RenderProgress(job: id, framesDone: done, frameTotal: total, step: step, lastPath: path, runway: lease.mode))
        }
        do {
            try FileManager.default.createDirectory(at: workspace.workFolder(for: id), withIntermediateDirectories: true)
        } catch {
            return await stopped(.failed("The render's work folder could not be created."), recorder: recorder, id: id)
        }
        let durableFrames = durable == 0 ? 0 : recipe.frames(ofSegment: durable - 1).upperBound
        report(durableFrames, .rendering(segment: durable), nil)

        do throws(EncodeStop) {
            // Finished segments whose files are gone are encoded again; progress never moves back.
            for index in 0..<durable {
                guard await !segmentIsIntact(index, of: id) else { continue }
                let encoder = SegmentEncoder(
                    pattern: pattern, preferGPU: preferGPU, gpu: gpu, stop: stop,
                    onFrame: { _, path in report(durableFrames, .repairing(segment: index), path) }, pace: nil
                )
                tally.add(try await encoder.encode(segment: index, to: workspace.segment(index, of: id)))
                repaired.append(index)
            }

            let paceStart = ContinuousClock.now
            var framesThisRun = 0
            for index in durable..<recipe.segmentCount {
                await onStage(.segmentStarted(index))
                let encoder = SegmentEncoder(
                    pattern: pattern, preferGPU: preferGPU, gpu: gpu, stop: stop,
                    onFrame: { frame, path in report(frame + 1, .rendering(segment: index), path) },
                    pace: recipe.pacing == .realTime ? .init(start: paceStart, framesBefore: framesThisRun) : nil
                )
                tally.add(try await encoder.encode(segment: index, to: workspace.segment(index, of: id)))
                framesThisRun += recipe.frames(ofSegment: index).count
                await onStage(.segmentSaved(index))
                do {
                    try await recorder.advance(.checkpoint(completed: index + 1))
                } catch {
                    return await unrecordable(error, id: id)
                }
            }

            await onStage(.assembling)
            report(recipe.frameCount, .assembling, nil)
            if let request = stop.current { throw EncodeStop.requested(request) }
            let staged = workspace.assembled(for: id)
            let segments = (0..<recipe.segmentCount).map { workspace.segment($0, of: id) }
            try await SegmentAssembler(recipe: recipe, stop: stop).assemble(segments, to: staged)
            let facts: MovieFacts
            do { facts = try await SegmentAssembler.facts(of: staged) } catch { throw EncodeStop.failed("The assembled movie could not be read back.") }
            guard facts.frameCount == recipe.frameCount, facts.width == recipe.width, facts.height == recipe.height else {
                throw EncodeStop.failed("The assembled movie has \(facts.frameCount) frames at \(facts.width)×\(facts.height), not the recipe's.")
            }

            await onStage(.aboutToPublish)
            // The last point a stop is honored. After the rename the new movie is the output.
            if let request = stop.current { throw EncodeStop.requested(request) }
            report(recipe.frameCount, .publishing, nil)
            let published: AtomicPublication.Published
            do { published = try AtomicPublication.publish(staged, to: workspace.output(for: recipe)) } catch {
                throw EncodeStop.failed("The finished movie could not be published.")
            }
            await onStage(.published)
            report(total, .publishing, nil)

            let output: JobOutput
            do {
                output = try JobOutput(
                    name: recipe.outputName, byteCount: published.byteCount, sha256: published.digest.hex,
                    summary: "\(recipe.shape) · H.264 · \(recipe.frameCount) frames (\(tally.phrase))"
                )
            } catch {
                throw EncodeStop.failed("The published movie could not be described.")
            }
            do {
                try await recorder.advance(.succeed(output: output))
            } catch {
                return await unrecordable(error, id: id)
            }
            workspace.discardWork(of: id)
            let job = await recorder.job
            return .succeeded(job, RenderReport(output: output, facts: facts, tally: tally, repairedSegments: repaired, runway: lease.mode))
        } catch {
            return await stopped(error, recorder: recorder, id: id)
        }
    }

    /// Whether a finished segment's file is present and holds its frames.
    private func segmentIsIntact(_ index: Int, of id: JobID) async -> Bool {
        let url = workspace.segment(index, of: id)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
              let facts = try? await SegmentAssembler.facts(of: url)
        else { return false }
        return facts.frameCount == recipe.frames(ofSegment: index).count
    }

    /// Records why the run stopped, and cleans up what that kind of stop leaves behind.
    private func stopped(_ reason: EncodeStop, recorder: JobRecorder, id: JobID) async -> RenderOutcome {
        let transition: JobTransition
        switch reason {
        case .requested(.cancel):
            workspace.discardWork(of: id)
            transition = .cancel
        case .requested(.interrupt(let why)):
            workspace.discardPartials(of: id)
            transition = .interrupt(reason: why)
        case .outOfSpace:
            workspace.discardPartials(of: id)
            transition = .interrupt(reason: .outOfSpace)
        case .failed(let message):
            workspace.discardWork(of: id)
            transition = .fail(failure: (try? JobFailure(code: "render-failed", message: message)) ?? Self.genericFailure)
        }
        do {
            try await recorder.advance(transition)
        } catch {
            return await unrecordable(error, id: id)
        }
        let job = await recorder.job
        return switch job.phase {
        case .cancelled: .cancelled(job)
        case .interrupted(let why): .interrupted(job, why)
        case .failed(let failure): .failed(job, failure)
        case .running, .succeeded: .superseded(job.phase.name)
        }
    }

    private func unrecordable(_ error: JobError, id: JobID) async -> RenderOutcome {
        switch error {
        case .changedElsewhere(let phase):
            // Cancelled elsewhere or removed: this run's work has no job left to belong to.
            if phase == nil || phase == .cancelled || phase == .failed { workspace.discardWork(of: id) } else { workspace.discardPartials(of: id) }
            return .superseded(phase)
        case .unavailable, .refused:
            workspace.discardPartials(of: id)
            return .unrecorded(error)
        }
    }
}
#endif
