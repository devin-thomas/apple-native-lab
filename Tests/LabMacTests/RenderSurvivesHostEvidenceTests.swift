import CryptoKit
import Foundation
import LabDomain
import LabJobs
import LabSupport
import RenderThatSurvives
import Testing
@testable import NativeLab

/// LAB-032-B step 1 with its evidence: the complete Render That Survives interaction in the
/// sandboxed Mac app, from clean state, through `RenderStudioModel`, `LabLibrary`, and a fresh
/// SQLite store, with the Mac worker's runway. Renders on the GPU and on the CPU; a long render
/// paused, carried across a relaunch of the model, resumed, and published; a second long render
/// cancelled with the published movie kept byte for byte; a job an earlier process left running;
/// and Reset Demo beside the person's own collection.
///
/// The long fixture is paced at playback speed, so this test takes about a minute.
///
/// The test attaches an `EvidenceRecord` of what it observed, with the toolchain read from this
/// app bundle. To keep it, run the test with a result bundle and export the attachment:
///
///     xcodebuild … -scheme LabMac-Core -only-testing:LabMacTests/RenderSurvivesHostEvidenceTests \
///       -resultBundlePath <bundle> LAB_SOURCE_REVISION=<sha> test
///     xcrun xcresulttool export attachments --path <bundle> --output-path <folder>
@MainActor
@Suite(.serialized) struct RenderSurvivesHostEvidenceTests {
    static let check = "Render That Survives in the Mac host: renders on the GPU and the CPU, a long render paused across a relaunch and resumed, a cancel that keeps the published movie, a job an earlier process left running, and Reset Demo beside the person's own data"

    /// SHA-256 of `Packages/LabFeatures/Sources/RenderThatSurvives/Resources/recipes.json`.
    static let recipesSHA256 = "b017a7501769525a64dcb6e0cd38efe1adb9f9a78c45de5e1aa4f887b9392738"

    @Test func theInteractionRunsInTheHostFromCleanState() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "RenderSurvivesHostEvidenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = try #require(UserDefaults(suiteName: "RenderSurvivesHostEvidenceTests-\(UUID().uuidString)"))
        let workspace = RenderWorkspace(root: folder.appending(path: "Render That Survives"))
        let started = Date()

        var observations: [String] = []
        var differences: [String] = []
        func check(_ same: Bool, _ what: String) {
            #expect(same, "\(what)")
            if same { observations.append(what) } else { differences.append(what) }
        }

        // The app's first run on a fresh store seeds the demo; the person has a collection.
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let own = CollectionID()
        _ = try await library.submit(
            .createCollection(draft: CollectionDraft(id: own, title: EntityTitle("Kiln notes"))),
            requestID: RequestID(), authority: .userAction, names: [:]
        )
        let model = try await Self.connected(library, defaults: defaults, workspace: workspace)
        check(model.jobs.isEmpty && workspace.outputNames().isEmpty, "a clean start has no jobs and no output")

        // 1. The short fixture on the GPU, then on the CPU.
        model.selectedRecipeID = "short-bars"
        model.preferGPU = true
        let gpuJob = try await Self.runToEnd(model)
        let gpuReport = try #require(model.reports[gpuJob.id])
        check(gpuReport.tally.gpu == 48 && gpuReport.tally.cpu == 0 && gpuReport.tally.gpuRedrawn == 0,
              "the GPU drew and checked all 48 frames")
        check(gpuReport.runway == .whileAppRuns && gpuReport.facts.frameCount == 48, "the Mac worker published 48 frames")
        check(model.output?.job?.id == gpuJob.id, "the published file's digest is the one the GPU job recorded")
        model.preferGPU = false
        let cpuJob = try await Self.runToEnd(model)
        let cpuReport = try #require(model.reports[cpuJob.id])
        check(cpuReport.tally.cpu == 48 && cpuReport.tally.gpu == 0 && cpuReport.tally.lastBlocker == .turnedOff,
              "with the GPU turned off the CPU drew all 48 frames")
        check(model.output?.job?.id == cpuJob.id && cpuReport.facts == gpuReport.facts,
              "the CPU movie replaced the GPU movie with the same frame count, size, and duration")
        let cpuDigest = try #require(model.output?.sha256)

        // 2. The long fixture: render it once, so a published movie exists.
        model.selectedRecipeID = "long-bars"
        model.preferGPU = true
        let firstLong = try await Self.runToEnd(model, seconds: 90)
        let longPublished = try #require(model.output)
        check(longPublished.job?.id == firstLong.id && model.reports[firstLong.id]?.facts.frameCount == 576,
              "the long fixture published 576 frames, recorded by its job")

        // 3. A second long render is paused after two checkpoints.
        let paused = try await Self.start(model)
        try #require(await Self.eventually(seconds: 60) { await Self.job(paused.id, in: model)?.progress.completed ?? 0 >= 2 })
        await model.pause(try #require(await Self.job(paused.id, in: model)))
        try #require(await Self.eventually { await Self.job(paused.id, in: model)?.phase.name == .interrupted })
        let stopped = try #require(await Self.job(paused.id, in: model))
        check(stopped.phase == .interrupted(reason: .paused) && stopped.progress.completed >= 2,
              "Pause stopped the long render at a checkpoint (\(stopped.progress.phrase))")
        check(model.output?.sha256 == longPublished.sha256, "the paused render left the published long movie alone")

        // 4. The app is relaunched: a new model over the same store and folder.
        let relaunched = try await Self.connected(library, defaults: defaults, workspace: workspace)
        let afterRelaunch = try #require(await Self.job(paused.id, in: relaunched))
        check(afterRelaunch == stopped, "after the relaunch the job reads exactly as it was stopped")
        relaunched.selectedRecipeID = "long-bars"
        await relaunched.resume(afterRelaunch)
        try #require(await Self.eventually(seconds: 90) { await Self.job(paused.id, in: relaunched)?.phase.isFinished ?? false })
        let resumed = try #require(await Self.job(paused.id, in: relaunched))
        let resumedReport = try #require(relaunched.reports[paused.id], "\(resumed.phase)")
        check(resumedReport.facts.frameCount == 576 && resumedReport.repairedSegments.isEmpty,
              "Resume continued from \(stopped.progress.phrase) to a checked 576-frame movie")
        await relaunched.refresh()
        let resumedOutput = try #require(relaunched.output)
        check(resumedOutput.job?.id == paused.id, "the resumed job's recorded digest is the published file's")

        // 5. A third long render is cancelled after a checkpoint; the published movie keeps its bytes.
        let cancelled = try await Self.start(relaunched)
        try #require(await Self.eventually(seconds: 60) { await Self.job(cancelled.id, in: relaunched)?.progress.completed ?? 0 >= 1 })
        await relaunched.cancel(try #require(await Self.job(cancelled.id, in: relaunched)))
        try #require(await Self.eventually { await Self.job(cancelled.id, in: relaunched)?.phase == .cancelled })
        await relaunched.refresh()
        check(relaunched.output?.sha256 == resumedOutput.sha256 && relaunched.output?.byteCount == resumedOutput.byteCount,
              "the cancel left the published long movie byte for byte")
        check(Self.workFolders(workspace).isEmpty && workspace.outputNames() == ["long-bars.mov", "short-bars.mov"],
              "only the two published movies remain; no work folder or partial file")

        // 6. A job an earlier process left running reads as stopped after the next connect.
        let service = try await library.openedService()
        let orphan = try JobDraft(kind: .render, title: EntityTitle("Short color bars"), total: 5)
        _ = try await service.perform(.startJob(draft: orphan), requestID: RequestID(), authority: .userAction)
        let third = try await Self.connected(library, defaults: defaults, workspace: workspace)
        check(try await service.job(orphan.id, as: LabDataService.appUI).phase == .interrupted(reason: .appStopped),
              "a job an earlier process left running reads as stopped (app-stopped)")
        await third.cancel(try #require(await Self.job(orphan.id, in: third)))

        // 7. Every step is an app-UI receipt with no undo.
        let receipts = third.receipts
        let operations = receipts.map { ReceiptPresentation($0).operation }
        check(receipts.allSatisfy { $0.receipt.admitted.adapter == .appUI && $0.receipt.undo == nil && $0.receipt.status == .committed },
              "all \(receipts.count) render receipts are committed by the app UI with no undo")
        // The job left by an earlier process was started outside this session's list.
        check(operations.filter { $0 == "Start Job" }.count == 5 && operations.filter { $0 == "Finish Job" }.count == 4,
              "this session started 5 jobs and finished 4")

        // 8. Reset Demo removes the demo jobs and the experiment's files, and not the person's collection.
        _ = await library.resetDemo()
        try #require(await Self.eventually { await third.refresh(); return third.jobs.isEmpty })
        try #require(await Self.eventually { !FileManager.default.fileExists(atPath: workspace.root.path(percentEncoded: false)) })
        let reset = try #require(library.receipts.first)
        check(reset.receipt.summary.hasSuffix("removed 6 jobs."), "Reset Demo removed the 6 demo jobs")
        check(try await service.collection(own, as: LabDataService.appUI).title.value == "Kiln notes",
              "the person's own collection is unchanged")

        let record = try EvidenceRecord(
            subject: "LAB-032",
            check: Self.check,
            date: started,
            provenance: .current,
            execution: .fixture,
            inputs: [
                "recipes:app-bundle (Packages/LabFeatures/Sources/RenderThatSurvives/Resources/recipes.json)@sha256:\(Self.recipesSHA256)",
                "short-bars:recipe 160x90, 24 fps, 48 frames in 4 segments, as fast as possible",
                "long-bars:recipe 320x180, 24 fps, 576 frames in 8 segments, paced at playback speed",
            ],
            steps: [
                "xcodebuild -scheme LabMac-Core -only-testing:LabMacTests/RenderSurvivesHostEvidenceTests test",
                "A fresh SQLite store in the app container, seeded by the host's first run; one collection of the person's own",
                "RenderStudioModel connected with MacWorkerRunway and a fresh render folder",
                "short-bars rendered with the GPU preferred, then with it turned off",
                "long-bars rendered to the end; a second long-bars paused after 2 checkpoints",
                "A new RenderStudioModel connected to the same store and folder (a relaunch); Resume to the end",
                "A third long-bars cancelled after a checkpoint",
                "A running job recorded as an earlier process would leave it; a new model connected; Cancel",
                "Reset Demo; the store and the folder read back",
            ],
            outcome: differences.isEmpty
                ? .passed(observed: "All \(observations.count) checks matched. " + observations.joined(separator: "; ") + ". The GPU and CPU short renders recorded different file digests for the same frames (the encoder's bytes are not repeatable); the last short digest was \(cpuDigest.prefix(16))….")
                : .failed(observed: "\(differences.count) of \(observations.count + differences.count) checks failed: " + differences.joined(separator: "; ") + "."),
            limitations: [
                "Fixture path: hosted tests in the sandboxed Mac app on the development Mac, on a fresh store in the app container. It supports implemented at most.",
                "The relaunch is a second RenderStudioModel over the same store and folder in one process; the app was not quit. The job left running by an earlier process was recorded directly, not by quitting the app mid-render.",
                "No window was shown and no person pressed a control: the test called the model's actions. No iPhone, iPad, or simulator ran in this check, so no continued-processing request was made.",
            ]
        )
        Attachment.record(try Self.json(record), named: "LAB-032-render-that-survives-host.json")
        #expect(record.result == .passed)
        #expect(record.provenance.xcodeBuild != "unknown" && record.provenance.sdkName.hasPrefix("macosx"))
        #expect(record.supportedState == .implemented)
    }

    // MARK: Helpers

    static func connected(_ library: LabLibrary, defaults: UserDefaults, workspace: RenderWorkspace) async throws -> RenderStudioModel {
        let model = RenderStudioModel(defaults: defaults)
        model.connect(library, runway: MacWorkerRunway(), workspace: workspace)
        try #require(await eventually { model.phase == .ready })
        await model.refresh()
        return model
    }

    /// Starts the selected recipe and returns its new job.
    static func start(_ model: RenderStudioModel) async throws -> LabJob {
        await model.refresh()
        let before = Set(model.jobs.map(\.id))
        await model.start()
        try #require(await eventually { await model.refresh(); return model.jobs.contains { !before.contains($0.id) } })
        return try #require(model.jobs.first { !before.contains($0.id) })
    }

    /// Starts the selected recipe and waits for its job to finish and its report to arrive.
    static func runToEnd(_ model: RenderStudioModel, seconds: Int = 30) async throws -> LabJob {
        let job = try await start(model)
        try #require(await eventually(seconds: seconds) { model.reports[job.id] != nil })
        await model.refresh()
        return try #require(model.jobs.first { $0.id == job.id })
    }

    static func job(_ id: JobID, in model: RenderStudioModel) async -> LabJob? {
        await model.refresh()
        return model.jobs.first { $0.id == id }
    }

    static func workFolders(_ workspace: RenderWorkspace) -> [String] {
        let work = workspace.root.appending(path: "Work", directoryHint: .isDirectory)
        return (try? FileManager.default.contentsOfDirectory(atPath: work.path(percentEncoded: false))) ?? []
    }

    static func eventually(seconds: Int = 30, _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return await condition()
    }

    private static func json(_ record: EvidenceRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return String(decoding: try encoder.encode(record), as: UTF8.self) + "\n"
    }
}
