import Foundation
import LabDomain
import LabJobs
@testable import RenderThatSurvives
import Synchronization
import Testing

/// LAB-032's acceptance criteria, run end to end with AVFoundation on the short fixture: every
/// render is a real H.264 movie in a temporary folder, and every job step goes through
/// `OperationService` with a receipt.
@Suite(.serialized) struct RenderRunTests {
    // MARK: Success

    @Test func aRenderPublishesACheckedMovieAndRecordsEveryStep() async throws {
        let bench = Bench()
        let (started, outcome) = try await bench.render()
        let report = try #require(outcome.report)
        #expect(report.facts == MovieFacts(frameCount: 48, width: 160, height: 90, duration: 2))
        #expect(report.tally.cpu == 48 && report.tally.gpu == 0 && report.repairedSegments.isEmpty)
        #expect(report.runway == .whileAppRuns)

        let job = try await bench.job(started.id)
        #expect(job.phase == .succeeded(output: report.output))
        #expect(job.progress.completed == 5 && job.progress.total == 5)
        let published = try AtomicPublication.digest(of: bench.workspace.output(for: Recipes.short))
        #expect(report.output.sha256 == published.digest.hex && report.output.byteCount == published.byteCount)
        #expect(report.output.summary == "2.0 s · 160×90 · 24 fps · H.264 · 48 frames (GPU 0, CPU 48)")

        #expect(bench.summaries == [
            "Started render job “Short color bars”.",
            "Saved render job “Short color bars” at 1 of 5.",
            "Saved render job “Short color bars” at 2 of 5.",
            "Saved render job “Short color bars” at 3 of 5.",
            "Saved render job “Short color bars” at 4 of 5.",
            "Finished render job “Short color bars” as “short-bars.mov”.",
        ])
        // Only the published movie remains: the work folder and every partial file are gone.
        #expect(bench.files() == ["Output/short-bars.mov"])
        #expect(bench.runway.finishes.withLock { $0 } == [true])
    }

    // MARK: Cancellation never replaces a good output

    @Test(arguments: [
        RenderStage.segmentStarted(0), .segmentSaved(1), .segmentStarted(3), .assembling, .aboutToPublish,
    ])
    func cancellingAtAnyPointKeepsTheGoodOutputByteForByte(_ stage: RenderStage) async throws {
        let bench = Bench()
        _ = try await bench.render()
        let good = try bench.outputBytes()

        bench.hooks.on(stage) { [studio = bench.studio] id in try? await studio.stop(id, .cancel) }
        let (job, outcome) = try await bench.render()
        guard case .cancelled(let cancelled) = outcome else {
            Issue.record("Expected a cancelled outcome at \(stage), got \(outcome)")
            return
        }
        #expect(cancelled.phase == .cancelled)
        #expect(try bench.outputBytes() == good, "the output changed after a cancel at \(stage)")
        #expect(!bench.workFolderExists(job.id))
        #expect(bench.files() == ["Output/short-bars.mov"])
        #expect(bench.summaries.last == "Cancelled render job “Short color bars”.")
    }

    @Test func aCancelledFirstRenderLeavesNoOutputAtAll() async throws {
        let bench = Bench()
        bench.hooks.on(.aboutToPublish) { [studio = bench.studio] id in try? await studio.stop(id, .cancel) }
        let (_, outcome) = try await bench.render()
        guard case .cancelled = outcome else { Issue.record("\(outcome)"); return }
        #expect(bench.files().isEmpty)
    }

    @Test func aStopRequestAfterThePublishPointIsNotHonored() async throws {
        let bench = Bench()
        bench.hooks.on(.published) { [studio = bench.studio] id in try? await studio.stop(id, .cancel) }
        let (_, outcome) = try await bench.render()
        #expect(outcome.report != nil)
        #expect(bench.files() == ["Output/short-bars.mov"])
    }

    // MARK: Expiration produces a resumable job

    @Test func anExpiredRunwayStopsAtACheckpointAndTheJobResumesToTheSameMovie() async throws {
        let bench = Bench(runway: .continuedProcessing)
        bench.hooks.on(.segmentStarted(2)) { [runway = bench.runway] _ in runway.expire() }
        let (job, outcome) = try await bench.render()
        guard case .interrupted(let stopped, .expired) = outcome else { Issue.record("\(outcome)"); return }
        #expect(stopped.progress.completed == 2)
        #expect(bench.summaries.last == "Stopped render job “Short color bars” at 2 of 5 because its time in the background ran out. It can resume.")
        // Finished segments stay; the partial one is gone; nothing is published.
        #expect(bench.files() == [
            "Work/\(job.id.rawValue.uuidString)/recipe.json",
            "Work/\(job.id.rawValue.uuidString)/segment-000.mov",
            "Work/\(job.id.rawValue.uuidString)/segment-001.mov",
        ])
        #expect(bench.runway.finishes.withLock { $0 } == [false])

        let resumed = try await bench.resume(job.id)
        let report = try #require(resumed.report)
        #expect(report.facts.frameCount == 48 && report.repairedSegments.isEmpty)
        #expect(bench.summaries.contains("Resumed render job “Short color bars” from 2 of 5."))
        #expect(try await bench.job(job.id).phase == .succeeded(output: report.output))
        #expect(bench.files() == ["Output/short-bars.mov"])
    }

    @Test func aResumedJobReEncodesASegmentWhoseFileIsGone() async throws {
        let bench = Bench()
        bench.hooks.on(.segmentStarted(3)) { [studio = bench.studio] id in try? await studio.stop(id, .interrupt(.paused)) }
        let (job, outcome) = try await bench.render()
        guard case .interrupted(_, .paused) = outcome else { Issue.record("\(outcome)"); return }
        try FileManager.default.removeItem(at: bench.workspace.segment(1, of: job.id))

        let report = try #require(try await bench.resume(job.id).report)
        #expect(report.repairedSegments == [1])
        #expect(report.facts.frameCount == 48)
    }

    @Test func aJobWhoseAppStoppedIsRecoveredAsInterruptedAndCanBeCancelled() async throws {
        let bench = Bench()
        // A worker that "crashed": the job is running in the store, with no worker in this process.
        let draft = try JobDraft(kind: .render, title: EntityTitle("Short color bars"), total: 5)
        let (recorder, _) = try await JobRecorder.start(draft, backend: bench.backend)
        try await recorder.advance(.checkpoint(completed: 1))
        let stray = bench.workspace.workFolder(for: JobID())
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)

        let receipts = try await bench.studio.recover()
        #expect(receipts.map(\.summary) == ["Stopped render job “Short color bars” at 1 of 5 because the app stopped while it ran. It can resume."])
        #expect(try await bench.job(draft.id).phase == .interrupted(reason: .appStopped))
        #expect(!FileManager.default.fileExists(atPath: stray.path(percentEncoded: false)))
        // No recipe was saved for this job, so it can be cancelled but not resumed.
        await #expect(throws: RenderRefusal.recipeMissing) { try await bench.studio.resume(draft.id, options: .init()) }
        try await bench.studio.stop(draft.id, .cancel)
        #expect(try await bench.job(draft.id).phase == .cancelled)
    }

    // MARK: The GPU is optional

    @Test func withoutAGPUEveryFrameTakesTheCPUPathAndTheMovieIsTheSame() async throws {
        let bench = Bench(gpu: .unavailable)
        let (_, outcome) = try await bench.render(options: .init(preferGPU: true))
        let report = try #require(outcome.report)
        #expect(report.tally.gpu == 0 && report.tally.cpu == 48 && report.tally.lastBlocker == .noDevice)
        #expect(report.facts.frameCount == 48)
    }

    @Test func aGPUThatMayNotBeUsedNowFallsBackPerFrame() async throws {
        let allowed = AllowedSwitch()
        let gpu = GPUAccess(painter: GPUFramePainter.systemDefault(), isAllowedNow: { allowed.value })
        let bench = Bench(gpu: gpu)
        // The app "goes to the background" halfway: from segment 2 the GPU may not be used.
        bench.hooks.on(.segmentStarted(2)) { _ in allowed.set(false) }
        let (_, outcome) = try await bench.render(options: .init(preferGPU: true))
        let report = try #require(outcome.report)
        #expect(report.tally.cpu >= 24)
        if gpu.painter != nil {
            #expect(report.tally.gpu == 24 && report.tally.lastBlocker == .notAllowedNow)
        }
        #expect(report.facts.frameCount == 48)
    }

    @Test(.enabled(if: GPUFramePainter.systemDefault() != nil, "needs a Metal device"))
    func withAGPUEveryFrameIsDrawnAndCheckedOnIt() async throws {
        let bench = Bench(gpu: .live())
        let (_, outcome) = try await bench.render(options: .init(preferGPU: true))
        let report = try #require(outcome.report)
        #expect(report.tally.gpu == 48 && report.tally.cpu == 0 && report.tally.gpuRedrawn == 0)
    }

    // MARK: Refusals and other writers

    @Test func tooLittleSpaceIsRefusedBeforeAJobExists() async throws {
        let bench = Bench(capacity: 10_000)
        await #expect(throws: RenderRefusal.destination(.insufficientSpace(needed: Recipes.short.requiredBytes, available: 10_000))) {
            try await bench.studio.start(Recipes.short, options: .init())
        }
        #expect(await bench.store.jobs().isEmpty)
        #expect(bench.summaries.isEmpty)
    }

    @Test func aSecondRenderOfTheSameOutputIsRefusedWhileOneRuns() async throws {
        let bench = Bench()
        bench.hooks.on(.segmentStarted(0)) { [studio = bench.studio] _ in
            await #expect(throws: RenderRefusal.alreadyRunning) { try await studio.start(Recipes.short, options: .init()) }
        }
        let (_, outcome) = try await bench.render()
        #expect(outcome.report != nil)
        #expect(await bench.store.jobs().count == 1)
    }

    @Test func aJobCancelledByAnotherWriterStopsWithoutPublishing() async throws {
        let bench = Bench()
        _ = try await bench.render()
        let good = try bench.outputBytes()
        bench.hooks.on(.segmentSaved(0)) { [backend = bench.backend] id in
            // Another window's recorder cancels the job directly in the store.
            if let job = try? await backend.job(id) { _ = try? await JobRecorder(job: job, backend: backend).advance(.cancel) }
        }
        let (job, outcome) = try await bench.render()
        #expect(outcome == .superseded(.cancelled))
        #expect(try bench.outputBytes() == good)
        #expect(!bench.workFolderExists(job.id))
    }

    @Test func resetDemoDuringARenderRemovesTheJobAndEveryFile() async throws {
        let bench = Bench()
        _ = try await bench.render()
        let seed = try DemoSeed(version: 1, collections: [CollectionDraft(title: EntityTitle("Swatches"))], items: [])
        bench.hooks.on(.segmentSaved(1)) { [service = bench.service] _ in
            _ = try? await service.perform(OperationRequest(id: RequestID(), operation: .resetDemo(seed: seed), actor: appUI))
        }
        let (_, outcome) = try await bench.render()
        #expect(outcome == .superseded(nil))
        // The host removes the experiment's files when it sees the reset's receipt.
        await bench.studio.removeEverything()
        #expect(await bench.store.jobs().isEmpty)
        #expect(bench.files().isEmpty)
    }

    @Test func leavingTheForegroundStopsOnlyJobsWithoutBackgroundTime() async throws {
        for mode in [RunwayMode.foregroundOnly(.unavailable), .continuedProcessing] {
            let bench = Bench(runway: mode)
            bench.hooks.on(.segmentStarted(1)) { [studio = bench.studio] _ in await studio.appWillLeaveForeground() }
            let (_, outcome) = try await bench.render()
            switch mode {
            case .foregroundOnly:
                guard case .interrupted(let job, .leftForeground) = outcome else { Issue.record("\(outcome)"); continue }
                #expect(job.progress.completed == 1)
            default:
                #expect(outcome.report != nil, "a job with continued processing keeps running")
            }
        }
    }
}

/// A flag a test flips from a stage hook.
final class AllowedSwitch: Sendable {
    private let state = Mutex(true)
    var value: Bool { state.withLock { $0 } }
    func set(_ value: Bool) { state.withLock { $0 = value } }
}
