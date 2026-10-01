import Foundation
import LabDomain
import LabJobs
@testable import RenderThatSurvives
import Synchronization
import Testing

// LAB-032-B: qualification of Render That Survives on its fixture path. Every render here is a
// real H.264 movie written by AVFoundation in a temporary folder, and every job step goes through
// `OperationService` with a receipt. Movies are compared by what their decoded frames show
// (`EncodedMovie`), because the encoder's bytes differ between runs; the published file is
// compared by its bytes.

/// Step 1: the complete fixture interaction, from a clean store and folder, twice.
@Suite(.serialized) struct RenderInteractionReplay {
    /// What one replay observed, compared between replays.
    struct Transcript: Hashable {
        var receipts: [String] = []
        var outcomes: [String] = []
        var samples: [String] = []
        var files: [[String]] = []
    }

    /// Render, render again, cancel a third render mid-run, pause and resume a fourth, recover a
    /// job an earlier process left running, then Reset Demo.
    func replay() async throws -> Transcript {
        let bench = Bench()
        var transcript = Transcript()
        func note(_ outcome: RenderOutcome) {
            let line = switch outcome {
            case .succeeded(let job, let report): "succeeded \(job.progress.phrase) \(report.facts.frameCount) frames"
            case .cancelled: "cancelled"
            case .interrupted(let job, let reason): "interrupted \(reason.rawValue) at \(job.progress.phrase)"
            case .failed(_, let failure): "failed \(failure.code)"
            case .superseded(let phase): "superseded \(phase?.rawValue ?? "removed")"
            case .unrecorded: "unrecorded"
            }
            transcript.outcomes.append(line)
            transcript.files.append(bench.files().map { $0.hasPrefix("Work/") ? "Work/…/" + $0.split(separator: "/").last! : $0 })
        }

        // 1. A first render publishes the movie.
        let (_, first) = try await bench.render()
        note(first)
        let published = try await bench.movie()
        #expect(published.frameCount == 48 && published.mismatchedFrames.isEmpty)
        transcript.samples.append(published.contentDigest)

        // 2. A second render replaces it with the same frames.
        let (_, second) = try await bench.render()
        note(second)
        transcript.samples.append(try await bench.movie().contentDigest)
        let good = try bench.outputBytes()

        // 3. A third render is cancelled after its second segment; the published file keeps its bytes.
        bench.hooks.on(.segmentSaved(1)) { [studio = bench.studio] id in try? await studio.stop(id, .cancel) }
        let (_, third) = try await bench.render()
        note(third)
        #expect(try bench.outputBytes() == good)

        // 4. A fourth is paused at its third segment and resumed to a movie with the same frames.
        bench.hooks.on(.segmentStarted(2)) { [studio = bench.studio] id in try? await studio.stop(id, .interrupt(.paused)) }
        let (paused, fourth) = try await bench.render()
        note(fourth)
        let resumed = try await bench.resume(paused.id)
        note(resumed)
        transcript.samples.append(try await bench.movie().contentDigest)

        // 5. A job an earlier process left running reads as stopped, and is cancelled.
        let draft = try JobDraft(kind: .render, title: EntityTitle("Short color bars"), total: 5)
        _ = try await JobRecorder.start(draft, backend: bench.backend)
        _ = try await bench.studio.recover()
        try await bench.studio.stop(draft.id, .cancel)

        // 6. Reset Demo removes the demo jobs; the host then removes the experiment's files.
        let seed = try DemoSeed(version: 1, collections: [CollectionDraft(title: EntityTitle("Swatches"))], items: [])
        let reset = try await bench.service.perform(OperationRequest(id: RequestID(), operation: .resetDemo(seed: seed), actor: appUI))
        await bench.studio.removeEverything()
        #expect(await bench.store.jobs().isEmpty)
        #expect(bench.files().isEmpty)

        transcript.receipts = bench.summaries + [reset.summary]
        return transcript
    }

    @Test func theInteractionReplaysFromCleanStateWithTheSameSteps() async throws {
        let first = try await replay()
        let second = try await replay()
        #expect(first == second)

        let outcomes: [String] = [
            "succeeded 5 of 5 48 frames", "succeeded 5 of 5 48 frames", "cancelled",
            "interrupted paused at 2 of 5", "succeeded 5 of 5 48 frames",
        ]
        #expect(first.outcomes == outcomes)
        let published = ["Output/short-bars.mov"]
        let stopped = published + ["Work/…/recipe.json", "Work/…/segment-000.mov", "Work/…/segment-001.mov"]
        let files: [[String]] = [published, published, published, stopped, published]
        #expect(first.files == files)
        // Every run, straight or resumed, shows the same frames.
        #expect(Set(first.samples).count == 1)
        // Two renders of 6 steps, a cancelled one of 4, a paused one and its resume of 4 each, the
        // recovered job's 3, and Reset Demo.
        let expectedCount: Int = 28
        #expect(first.receipts.count == expectedCount)
        let recovered: [String] = [
            "Started render job “Short color bars”.",
            "Stopped render job “Short color bars” at 0 of 5 because the app stopped while it ran. It can resume.",
            "Cancelled render job “Short color bars”.",
        ]
        #expect(Array(first.receipts.dropLast().suffix(3)) == recovered, "\(first.receipts)")
        // Reset Demo removes all five demo jobs.
        #expect(first.receipts.last!.hasSuffix("removed 5 jobs."), "\(first.receipts.last!)")
    }

    @Test func twoRendersOfOneRecipeShowTheSameFramesInDifferentBytes() async throws {
        let a = Bench()
        let b = Bench()
        _ = try await a.render()
        _ = try await b.render()
        let left = try await a.movie()
        let right = try await b.movie()
        #expect(left.frameCount == 48 && right.frameCount == 48)
        #expect(left.mismatchedFrames.isEmpty && right.mismatchedFrames.isEmpty)
        #expect(left.contentDigest == right.contentDigest)
        // Recorded, not required: the encoder's bytes are not repeatable, so a published digest
        // identifies one file, not one recipe.
        print("LAB-032-B two renders: \(left.byteCount) and \(right.byteCount) bytes, files \(left.fileDigest == right.fileDigest ? "identical" : "different")")
    }
}

/// Acceptance 1: cancellation never replaces a good output with a partial file.
@Suite(.serialized) struct CancellationQualification {
    @Test(arguments: shortRecipeStages)
    func aCancelAtEveryStageKeepsTheGoodOutputAndLeavesNothingElse(_ stage: RenderStage) async throws {
        let bench = Bench()
        _ = try await bench.render()
        let good = try bench.outputBytes()
        let receiptsBefore = bench.summaries.count

        bench.hooks.on(stage) { [studio = bench.studio] id in try? await studio.stop(id, .cancel) }
        let (job, outcome) = try await bench.render()
        guard case .cancelled = outcome else { Issue.record("\(stage): \(outcome)"); return }
        #expect(try bench.outputBytes() == good)
        #expect(bench.files() == ["Output/short-bars.mov"])
        #expect(try await bench.job(job.id).phase == .cancelled)
        // Start, the checkpoints before the stop, and one cancel: nothing after it.
        let after = Array(bench.summaries.dropFirst(receiptsBefore))
        #expect(after.first == "Started render job “Short color bars”.")
        #expect(after.last == "Cancelled render job “Short color bars”.")
        #expect(after.filter { $0.hasPrefix("Cancelled") }.count == 1)
        #expect(!after.contains { $0.hasPrefix("Finished") })
    }

    @Test func aCancelInTheMiddleOfASegmentRemovesThePartialFile() async throws {
        let bench = Bench()
        let recipe = Recipes.pacedPair
        _ = try await bench.render(recipe)
        let good = try bench.outputBytes(recipe)

        // Segment 0 takes a second at playback speed; the cancel lands about a third of the way in.
        let partialSeen = Mutex(false)
        bench.hooks.on(.segmentStarted(0)) { [studio = bench.studio, workspace = bench.workspace] id in
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                let partial = workspace.segment(0, of: id).deletingPathExtension().appendingPathExtension("partial.mov")
                partialSeen.withLock { $0 = FileManager.default.fileExists(atPath: partial.path(percentEncoded: false)) }
                try? await studio.stop(id, .cancel)
            }
        }
        let (job, outcome) = try await bench.render(recipe)
        guard case .cancelled(let cancelled) = outcome else { Issue.record("\(outcome)"); return }
        #expect(partialSeen.withLock { $0 }, "the cancel arrived while segment 0 was being written")
        #expect(cancelled.progress.completed == 0)
        #expect(try bench.outputBytes(recipe) == good)
        #expect(bench.files() == ["Output/paced-pair.mov"])
        #expect(!bench.workFolderExists(job.id))
    }

    @Test func aStopWhileSegmentsAreJoinedLeavesNoPartialMovie() async throws {
        let bench = Bench()
        bench.hooks.on(.assembling) { [studio = bench.studio] id in try? await studio.stop(id, .interrupt(.paused)) }
        let (job, outcome) = try await bench.render()
        guard case .interrupted(_, .paused) = outcome else { Issue.record("\(outcome)"); return }
        let segments = (0..<Recipes.short.segmentCount).map { bench.workspace.segment($0, of: job.id) }
        let staged = bench.workspace.assembled(for: job.id)

        // The assembler itself, with the stop already requested as the export begins.
        let signal = JobStopSignal()
        signal.request(.cancel)
        do {
            try await SegmentAssembler(recipe: Recipes.short, stop: signal).assemble(segments, to: staged)
            Issue.record("the join finished despite the stop")
        } catch {
            guard case .requested(.cancel) = error else { Issue.record("\(error)"); return }
        }
        #expect(!FileManager.default.fileExists(atPath: staged.path(percentEncoded: false)))
        // Without a stop the same segments join into the checked movie.
        try await SegmentAssembler(recipe: Recipes.short, stop: JobStopSignal()).assemble(segments, to: staged)
        #expect(try await SegmentAssembler.facts(of: staged).frameCount == 48)
    }

    @Test func cancellingAStoppedJobKeepsTheGoodOutputAndDiscardsItsSegments() async throws {
        let bench = Bench()
        _ = try await bench.render()
        let good = try bench.outputBytes()
        bench.hooks.on(.segmentStarted(3)) { [studio = bench.studio] id in try? await studio.stop(id, .interrupt(.paused)) }
        let (job, outcome) = try await bench.render()
        guard case .interrupted = outcome else { Issue.record("\(outcome)"); return }
        #expect(bench.workFolderExists(job.id))

        try await bench.studio.stop(job.id, .cancel)
        #expect(try await bench.job(job.id).phase == .cancelled)
        #expect(try bench.outputBytes() == good)
        #expect(bench.files() == ["Output/short-bars.mov"])
        // A cancelled job cannot resume, and cancelling it again is refused without a receipt.
        await #expect(throws: RenderRefusal.notResumable(.cancelled)) { try await bench.studio.resume(job.id, options: .init()) }
        let receipts = bench.summaries.count
        await #expect(throws: RenderRefusal.notResumable(.cancelled)) { try await bench.studio.stop(job.id, .cancel) }
        #expect(bench.summaries.count == receipts)
    }

    @Test func repeatedAndMixedStopRequestsRecordOneCancel() async throws {
        let bench = Bench()
        bench.hooks.on(.segmentStarted(1)) { [studio = bench.studio] id in
            try? await studio.stop(id, .interrupt(.paused))
            try? await studio.stop(id, .cancel)
            try? await studio.stop(id, .cancel)
            try? await studio.stop(id, .interrupt(.leftForeground))
        }
        let (_, outcome) = try await bench.render()
        guard case .cancelled = outcome else { Issue.record("\(outcome)"); return }
        #expect(bench.summaries.filter { $0.hasPrefix("Cancelled") }.count == 1)
        #expect(!bench.summaries.contains { $0.hasPrefix("Stopped") })
        #expect(bench.files().isEmpty)
    }

    @Test func aCancelThatArrivesAfterTheWorkerRecordedItsStopStillCancels() async throws {
        let bench = Bench()
        let hooked = HookedBackend(bench.backend)
        let studio = RenderStudio(
            backend: hooked, workspace: bench.workspace, destination: DestinationCheck(capacity: FixedCapacity(bytes: 1 << 34)),
            gpu: .unavailable, runway: bench.runway, onStage: { [hooks = bench.hooks] id, stage in await hooks.reached(id, stage) }
        )
        // The person presses Cancel just after the pause was recorded, while the worker is
        // still ending: the job reads stopped, and the worker no longer looks at its signal.
        bench.hooks.on(.segmentStarted(2)) { id in try? await studio.stop(id, .interrupt(.paused)) }
        hooked.afterCommit { operation in
            guard case .updateJob(let id, _, .interrupt) = operation else { return }
            #expect(studio.isLive(id))
            try? await studio.stop(id, .cancel)
        }
        let job = try await studio.start(Recipes.short, options: .init(preferGPU: false))
        let outcome = try #require(await studio.outcome(of: job.id))
        guard case .cancelled(let cancelled) = outcome else { Issue.record("\(outcome)"); return }
        #expect(cancelled.phase == .cancelled && cancelled.progress.completed == 2)
        #expect(try await bench.job(job.id).phase == .cancelled)
        #expect(bench.files().isEmpty)
        #expect(bench.summaries.suffix(2) == [
            "Stopped render job “Short color bars” at 2 of 5 because it was paused. It can resume.",
            "Cancelled render job “Short color bars”.",
        ])
    }

    @Test func aFailedPublishKeepsTheGoodOutputAndRecordsAClearFailure() async throws {
        let bench = Bench()
        _ = try await bench.render()
        let good = try bench.outputBytes()
        let output = bench.workspace.outputFolder.path(percentEncoded: false)
        // The output folder refuses the rename, as a folder that became read-only would.
        bench.hooks.on(.aboutToPublish) { _ in
            try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: output)
        }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: output) }
        let (job, outcome) = try await bench.render()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: output)
        guard case .failed(let failed, let failure) = outcome else { Issue.record("\(outcome)"); return }
        #expect(failure.code == "render-failed" && failure.message == "The finished movie could not be published.")
        #expect(failed.phase == .failed(failure: failure) && failed.progress.completed == 4)
        #expect(try bench.outputBytes() == good)
        #expect(!bench.workFolderExists(job.id))
        #expect(bench.summaries.last == "Render job “Short color bars” failed: The finished movie could not be published.")
        // A failed job is final: it can be neither resumed nor cancelled.
        await #expect(throws: RenderRefusal.notResumable(.failed)) { try await bench.studio.resume(job.id, options: .init()) }
        await #expect(throws: RenderRefusal.notResumable(.failed)) { try await bench.studio.stop(job.id, .cancel) }
    }
}

/// Acceptance 2: task expiration produces a resumable or clearly failed job.
@Suite(.serialized) struct ExpirationQualification {
    /// The number of segments durable after an expiration at each stage of the short recipe.
    static let expectedDurable: [RenderStage: Int] = [
        .segmentStarted(0): 0, .segmentSaved(0): 1, .segmentStarted(1): 1, .segmentSaved(1): 2,
        .segmentStarted(2): 2, .segmentSaved(2): 3, .segmentStarted(3): 3, .segmentSaved(3): 4,
        .assembling: 4, .aboutToPublish: 4,
    ]

    @Test(arguments: shortRecipeStages)
    func anExpirationAtEveryStageStopsResumablyAndResumesToTheSameFrames(_ stage: RenderStage) async throws {
        let reference = Bench()
        _ = try await reference.render()
        let expected = try await reference.movie()

        let bench = Bench(runway: .continuedProcessing)
        bench.hooks.on(stage) { [runway = bench.runway] _ in runway.expire() }
        let (job, outcome) = try await bench.render()
        guard case .interrupted(let stopped, .expired) = outcome else { Issue.record("\(stage): \(outcome)"); return }
        let durable = try #require(Self.expectedDurable[stage])
        #expect(stopped.progress.completed == durable, "\(stage)")
        #expect(bench.summaries.last == "Stopped render job “Short color bars” at \(durable) of 5 because its time in the background ran out. It can resume.")
        // Only finished segments and the saved recipe stay; nothing is published.
        let work = "Work/\(job.id.rawValue.uuidString)/"
        #expect(bench.files() == [work + "recipe.json"] + (0..<durable).map { work + String(format: "segment-%03d.mov", $0) })
        #expect(bench.runway.finishes.withLock { $0 } == [false])

        let resumed = try await bench.resume(job.id)
        let report = try #require(resumed.report, "\(resumed)")
        #expect(report.repairedSegments.isEmpty)
        let movie = try await bench.movie()
        #expect(movie.frameCount == 48 && movie.mismatchedFrames.isEmpty, "\(movie.mismatchedFrames)")
        #expect(movie.contentDigest == expected.contentDigest)
        #expect(bench.files() == ["Output/short-bars.mov"])
    }

    @Test func anExpirationAfterThePublishPointIsNotHonored() async throws {
        let bench = Bench(runway: .continuedProcessing)
        bench.hooks.on(.published) { [runway = bench.runway] _ in runway.expire() }
        let (job, outcome) = try await bench.render()
        #expect(outcome.report != nil)
        #expect(try await bench.job(job.id).phase.name == .succeeded)
        #expect(bench.runway.finishes.withLock { $0 } == [true])
    }

    @Test func repeatedExpirationsResumeEachTimeToOneMovie() async throws {
        let bench = Bench(runway: .continuedProcessing)
        bench.hooks.on(.segmentStarted(1)) { [runway = bench.runway] _ in runway.expire() }
        let (job, _) = try await bench.render()
        bench.hooks.on(.segmentStarted(3)) { [runway = bench.runway] _ in runway.expire() }
        guard case .interrupted(let second, .expired) = try await bench.resume(job.id) else { Issue.record("not expired"); return }
        #expect(second.progress.completed == 3)
        let report = try #require(try await bench.resume(job.id).report)
        #expect(report.facts.frameCount == 48)
        #expect(bench.summaries.filter { $0.contains("its time in the background ran out") } == [
            "Stopped render job “Short color bars” at 1 of 5 because its time in the background ran out. It can resume.",
            "Stopped render job “Short color bars” at 3 of 5 because its time in the background ran out. It can resume.",
        ])
        #expect(bench.summaries.filter { $0.hasPrefix("Resumed") } == [
            "Resumed render job “Short color bars” from 1 of 5.",
            "Resumed render job “Short color bars” from 3 of 5.",
        ])
    }

    @Test func anExpiredJobResumesAfterARelaunch() async throws {
        let bench = Bench(runway: .continuedProcessing)
        bench.hooks.on(.segmentSaved(1)) { [runway = bench.runway] _ in runway.expire() }
        let (job, _) = try await bench.render()

        // The app is launched again: recovery leaves the stopped job and its segments alone.
        let relaunched = bench.relaunched()
        #expect(try await relaunched.recover().isEmpty)
        #expect(try await bench.job(job.id).phase == .interrupted(reason: .expired))
        #expect(bench.workFolderExists(job.id))
        _ = try await relaunched.resume(job.id, options: .init(preferGPU: false))
        let report = try #require(await relaunched.outcome(of: job.id)?.report)
        #expect(report.facts.frameCount == 48 && report.repairedSegments.isEmpty)
    }

    @Test func anExpirationWhoseStopCouldNotBeRecordedIsRecoveredAsStopped() async throws {
        let bench = Bench(runway: .continuedProcessing)
        let switchable = SwitchableBackend(bench.backend)
        let studio = RenderStudio(
            backend: switchable, workspace: bench.workspace, destination: DestinationCheck(capacity: FixedCapacity(bytes: 1 << 34)),
            gpu: .unavailable, runway: bench.runway, onStage: { [hooks = bench.hooks] id, stage in await hooks.reached(id, stage) }
        )
        // The system ends the time, and the store is gone before the stop is written.
        bench.hooks.on(.segmentStarted(2)) { [runway = bench.runway] _ in
            switchable.close()
            runway.expire()
        }
        let job = try await studio.start(Recipes.short, options: .init(preferGPU: false))
        let outcome = try #require(await studio.outcome(of: job.id))
        guard case .unrecorded(.unavailable) = outcome else { Issue.record("\(outcome)"); return }
        // The store still says running, with the two checkpoints it did record.
        #expect(try await bench.job(job.id).phase == .running)
        #expect(try await bench.job(job.id).progress.completed == 2)

        // The next launch finds no worker and records the truth; the job resumes from there.
        switchable.reopen()
        let relaunched = bench.relaunched()
        #expect(try await relaunched.recover().map(\.summary) == [
            "Stopped render job “Short color bars” at 2 of 5 because the app stopped while it ran. It can resume.",
        ])
        _ = try await relaunched.resume(job.id, options: .init(preferGPU: false))
        #expect(await relaunched.outcome(of: job.id)?.report?.facts.frameCount == 48)
    }

    @Test func anExpiredJobWhoseSegmentWasDamagedRepairsItOnResume() async throws {
        let bench = Bench(runway: .continuedProcessing)
        bench.hooks.on(.segmentStarted(3)) { [runway = bench.runway] _ in runway.expire() }
        let (job, _) = try await bench.render()
        // A finished segment's file is overwritten with bytes that are not a movie.
        try Data(repeating: 0x5A, count: 4_096).write(to: bench.workspace.segment(1, of: job.id))
        let report = try #require(try await bench.resume(job.id).report)
        #expect(report.repairedSegments == [1])
        #expect(report.facts.frameCount == 48)
    }

    @Test func anExpiredJobWithoutItsRecipeIsClearlyRefusedAndCanBeCancelled() async throws {
        let bench = Bench(runway: .continuedProcessing)
        bench.hooks.on(.segmentStarted(2)) { [runway = bench.runway] _ in runway.expire() }
        let (job, _) = try await bench.render()
        try FileManager.default.removeItem(at: bench.workspace.workFolder(for: job.id).appending(path: "recipe.json"))
        await #expect(throws: RenderRefusal.recipeMissing) { try await bench.studio.resume(job.id, options: .init()) }
        #expect(RenderRefusal.recipeMissing.message == "This render's saved recipe is gone, so it cannot resume. Cancel it and start again.")
        #expect(try await bench.job(job.id).phase == .interrupted(reason: .expired))
        try await bench.studio.stop(job.id, .cancel)
        #expect(try await bench.job(job.id).phase == .cancelled)
        #expect(bench.files().isEmpty)
    }

    @Test func runningOutOfSpaceIsAResumableStopAndTheSystemsErrorsMapToIt() async throws {
        let bench = Bench()
        bench.hooks.on(.segmentStarted(1)) { [studio = bench.studio] id in try? await studio.stop(id, .interrupt(.outOfSpace)) }
        let (job, outcome) = try await bench.render()
        guard case .interrupted(_, .outOfSpace) = outcome else { Issue.record("\(outcome)"); return }
        #expect(bench.summaries.last == "Stopped render job “Short color bars” at 1 of 5 because the destination ran out of space. It can resume.")
        #expect(try await bench.resume(job.id).report != nil)

        // The mapping the encoder and the join use for the system's errors, directly and nested.
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        #expect(SegmentEncoder.isOutOfSpace(posix))
        #expect(SegmentEncoder.isOutOfSpace(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)))
        #expect(SegmentEncoder.isOutOfSpace(NSError(domain: "AVFoundationErrorDomain", code: -11807)))
        #expect(SegmentEncoder.isOutOfSpace(NSError(domain: "Other", code: 1, userInfo: [NSUnderlyingErrorKey: posix])))
        #expect(!SegmentEncoder.isOutOfSpace(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
    }
}

/// Acceptance 3: GPU-unavailable uses a supported lower-cost path.
@Suite(.serialized) struct GPUFallbackQualification {
    /// The frames of the CPU path, which every fallback must match.
    func cpuReference() async throws -> EncodedMovie {
        let bench = Bench(gpu: .unavailable)
        _ = try await bench.render(options: .init(preferGPU: false))
        return try await bench.movie()
    }

    @Test func everyReasonToSkipTheGPUDrawsTheSameFramesOnTheCPU() async throws {
        let reference = try await cpuReference()
        let cases: [(String, GPUAccess, Bool, GPUBlocker)] = [
            ("no device", .unavailable, true, .noDevice),
            ("turned off", GPUAccess(painter: MisdrawingPainter(), isAllowedNow: { true }), false, .turnedOff),
            ("not allowed now", GPUAccess(painter: MisdrawingPainter(), isAllowedNow: { false }), true, .notAllowedNow),
        ]
        for (name, gpu, prefer, blocker) in cases {
            let bench = Bench(gpu: gpu)
            let (_, outcome) = try await bench.render(options: .init(preferGPU: prefer))
            let report = try #require(outcome.report, "\(name)")
            #expect(report.tally.gpu == 0 && report.tally.cpu == 48 && report.tally.gpuRedrawn == 0, "\(name)")
            #expect(report.tally.lastBlocker == blocker, "\(name)")
            #expect(report.output.summary.hasSuffix("(GPU 0, CPU 48)"), "\(name)")
            #expect(try await bench.movie().contentDigest == reference.contentDigest, "\(name)")
        }
    }

    @Test func aGPUFrameThatFailsItsCheckIsDrawnAgainOnTheCPU() async throws {
        let reference = try await cpuReference()
        for painter in [MisdrawingPainter() as any FramePainter, FailingPainter()] {
            let bench = Bench(gpu: GPUAccess(painter: painter, isAllowedNow: { true }))
            let (_, outcome) = try await bench.render(options: .init(preferGPU: true))
            let report = try #require(outcome.report)
            #expect(report.tally.gpu == 0 && report.tally.gpuRedrawn == 48 && report.tally.cpu == 48, "\(type(of: painter))")
            #expect(try await bench.movie().contentDigest == reference.contentDigest, "\(type(of: painter))")
        }
    }

    @Test func theGPUComingAndGoingSwitchesPathsPerFrame() async throws {
        let allowed = AllowedSwitch()
        let bench = Bench(gpu: GPUAccess(painter: CPUFramePainterOnGPUPath(), isAllowedNow: { allowed.value }))
        bench.hooks.on(.segmentStarted(1)) { _ in allowed.set(false) }
        bench.hooks.on(.segmentStarted(3)) { _ in allowed.set(true) }
        let (_, outcome) = try await bench.render(options: .init(preferGPU: true))
        let report = try #require(outcome.report)
        #expect(report.tally.gpu == 24 && report.tally.cpu == 24 && report.tally.gpuRedrawn == 0)
        #expect(report.tally.lastBlocker == .notAllowedNow)
    }

    @Test(.enabled(if: GPUFramePainter.systemDefault() != nil, "needs a Metal device"))
    func theMetalPathAndTheCPUPathEncodeTheSameFrames() async throws {
        let reference = try await cpuReference()
        let bench = Bench(gpu: .live())
        let (_, outcome) = try await bench.render(options: .init(preferGPU: true))
        let report = try #require(outcome.report)
        #expect(report.tally.gpu == 48 && report.tally.gpuRedrawn == 0)
        #expect(try await bench.movie().contentDigest == reference.contentDigest)
    }
}

/// Step 3: denial, duplicates, stale state, and Reset Demo beside the person's own data.
@Suite(.serialized) struct RenderBoundaryQualification {
    @Test func entryPointsThatMayNotCommitStartNothing() async throws {
        let bench = Bench()
        for adapter in [AdapterKind.modelTool] {
            let backend = ServiceJobBackend(service: bench.service, actor: ActorScope(adapter: adapter, grants: Set(Permission.allCases)))
            let studio = RenderStudio(
                backend: backend, workspace: bench.workspace, destination: DestinationCheck(capacity: FixedCapacity(bytes: 1 << 34)),
                gpu: .unavailable, runway: bench.runway
            )
            do {
                _ = try await studio.start(Recipes.short, options: .init())
                Issue.record("\(adapter) started a render")
            } catch {
                guard case .job(.refused) = error else { Issue.record("\(adapter): \(error)"); continue }
            }
        }
        #expect(await bench.store.jobs().isEmpty)
        #expect(bench.files().isEmpty)
    }

    @Test func aRetriedStartWithTheSameRequestRecordsOneJob() async throws {
        let bench = Bench()
        let request = RequestID()
        let first = try await bench.studio.start(Recipes.short, options: .init(preferGPU: false), requestID: request)
        _ = await bench.studio.outcome(of: first.id)
        let receipts = bench.summaries.count
        // The same request ID again names a different job, so the service refuses the reuse.
        await #expect(throws: RenderRefusal.job(.refused(.requestIDReused(request)))) {
            try await bench.studio.start(Recipes.short, options: .init(preferGPU: false), requestID: request)
        }
        #expect(await bench.store.jobs().count == 1)
        #expect(bench.summaries.count == receipts)
        #expect(bench.files() == ["Output/short-bars.mov"])
    }

    @Test func twoResumesAtOnceRunOneWorker() async throws {
        let bench = Bench()
        bench.hooks.on(.segmentStarted(2)) { [studio = bench.studio] id in try? await studio.stop(id, .interrupt(.paused)) }
        let (job, _) = try await bench.render()
        async let first: Result<LabJob, RenderRefusal> = resume(bench.studio, job.id)
        async let second: Result<LabJob, RenderRefusal> = resume(bench.studio, job.id)
        let results = await [first, second]
        let refusals = results.compactMap { if case .failure(let refusal) = $0 { refusal } else { nil } }
        #expect(refusals.count == 1, "\(results)")
        if let refusal = refusals.first {
            // Which refusal depends on how far the first press got: its worker exists, its resume
            // is committed, or both presses read the stopped job and the second one's step conflicts.
            let expected: Set<RenderRefusal> = [.alreadyRunning, .notResumable(.running), .job(.changedElsewhere(.running))]
            #expect(expected.contains(refusal), "\(refusal)")
        }
        #expect(try #require(await bench.studio.outcome(of: job.id)).report != nil)
        #expect(bench.summaries.filter { $0.hasPrefix("Resumed") }.count == 1)
    }

    private func resume(_ studio: RenderStudio, _ id: JobID) async -> Result<LabJob, RenderRefusal> {
        do { return .success(try await studio.resume(id, options: .init(preferGPU: false))) } catch { return .failure(error) }
    }

    @Test func finishedJobsRefuseEveryChangeAndAPauseOfAStoppedJobDoesNothing() async throws {
        let bench = Bench()
        let (done, _) = try await bench.render()
        let good = try bench.outputBytes()
        let receipts = bench.summaries.count
        await #expect(throws: RenderRefusal.notResumable(.succeeded)) { try await bench.studio.resume(done.id, options: .init()) }
        await #expect(throws: RenderRefusal.notResumable(.succeeded)) { try await bench.studio.stop(done.id, .cancel) }
        try await bench.studio.stop(done.id, .interrupt(.paused))
        #expect(bench.summaries.count == receipts)
        #expect(try bench.outputBytes() == good)

        bench.hooks.on(.segmentStarted(1)) { [studio = bench.studio] id in try? await studio.stop(id, .interrupt(.paused)) }
        let (stopped, _) = try await bench.render()
        try await bench.studio.stop(stopped.id, .interrupt(.paused))
        #expect(try await bench.job(stopped.id).phase == .interrupted(reason: .paused))
        await #expect(throws: RenderRefusal.job(.refused(.notFound(.job(JobID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000032")!)))))) {
            try await bench.studio.stop(JobID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000032")!), .cancel)
        }
    }

    @Test func aStoppedJobCancelledElsewhereCannotBeResumedHere() async throws {
        let bench = Bench()
        bench.hooks.on(.segmentStarted(2)) { [studio = bench.studio] id in try? await studio.stop(id, .interrupt(.paused)) }
        let (job, _) = try await bench.render()
        // Another window, holding the job at the revision it last saw, cancels it.
        let stale = try await bench.job(job.id)
        _ = try await JobRecorder(job: stale, backend: bench.backend).advance(.cancel)
        await #expect(throws: RenderRefusal.notResumable(.cancelled)) { try await bench.studio.resume(job.id, options: .init()) }
        // A step at the stale revision gets a conflict receipt and changes nothing.
        let conflict = try await bench.backend.commit(.updateJob(id: job.id, expected: stale.revision, transition: .resume), requestID: RequestID())
        #expect(conflict.conflict != nil)
        #expect(try await bench.job(job.id).phase == .cancelled)
    }

    @Test func resetDemoRemovesDemoRendersAndLeavesThePersonsOwnDataAndOtherFiles() async throws {
        let bench = Bench()
        // The person's own collection, item, and a job of their own of another kind.
        let collection = CollectionDraft(title: try EntityTitle("Kiln notes"))
        _ = try await bench.service.perform(OperationRequest(id: RequestID(), operation: .createCollection(draft: collection), actor: appUI))
        let item = ItemDraft(in: collection.id, title: try EntityTitle("Glaze test"))
        _ = try await bench.service.perform(OperationRequest(id: RequestID(), operation: .createItem(draft: item), actor: appUI))
        let ownJob = try JobDraft(kind: JobKind(rawValue: "export")!, title: EntityTitle("My export"), total: nil, namespace: .user)
        _ = try await JobRecorder.start(ownJob, backend: bench.backend)
        // A file beside the experiment's folder, which is not the experiment's.
        let parent = bench.workspace.root.deletingLastPathComponent()
        let neighbour = parent.appending(path: "neighbour-\(UUID().uuidString).txt")
        try Data("not the lab's".utf8).write(to: neighbour)
        defer { try? FileManager.default.removeItem(at: neighbour) }

        _ = try await bench.render()
        bench.hooks.on(.segmentStarted(2)) { [studio = bench.studio] id in try? await studio.stop(id, .interrupt(.paused)) }
        _ = try await bench.render()

        let seed = try DemoSeed(version: 1, collections: [CollectionDraft(title: EntityTitle("Swatches"))], items: [])
        let reset = try await bench.service.perform(OperationRequest(id: RequestID(), operation: .resetDemo(seed: seed), actor: appUI))
        #expect(reset.summary.hasSuffix("removed 2 jobs."), "\(reset.summary)")
        await bench.studio.removeEverything()

        let jobs = await bench.store.jobs()
        #expect(jobs.map(\.id) == [ownJob.id])
        #expect(try await bench.service.findItem(item.id, as: appUI).title.value == "Glaze test")
        #expect(bench.files().isEmpty)
        #expect(try Data(contentsOf: neighbour) == Data("not the lab's".utf8))
    }

    @Test func recoveryKeepsStoppedJobsWorkAndSweepsOnlyOrphans() async throws {
        let bench = Bench()
        bench.hooks.on(.segmentStarted(2)) { [studio = bench.studio] id in try? await studio.stop(id, .interrupt(.paused)) }
        let (stopped, _) = try await bench.render()
        // Left behind by a process that ended: a work folder no job owns, and a partial output.
        let orphan = bench.workspace.workFolder(for: JobID())
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: orphan.appending(path: "segment-000.partial.mov"))
        try FileManager.default.createDirectory(at: bench.workspace.outputFolder, withIntermediateDirectories: true)
        try Data([4, 5]).write(to: bench.workspace.outputFolder.appending(path: "short-bars.partial.mov"))

        #expect(try await bench.relaunched().recover().isEmpty)
        let work = "Work/\(stopped.id.rawValue.uuidString)/"
        #expect(bench.files() == [work + "recipe.json", work + "segment-000.mov", work + "segment-001.mov"])
    }
}
