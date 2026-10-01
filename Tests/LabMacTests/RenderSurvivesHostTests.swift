import Foundation
import LabDomain
import LabJobs
import RenderThatSurvives
import Testing
@testable import NativeLab

/// LAB-032 in the sandboxed Mac host: a render started from the model runs as the Mac worker,
/// and every job step reaches the store through `LabLibrary`, `LabDataService`, and the one
/// `OperationService`, with receipts in the session's list. A job an earlier process left running
/// reads as stopped after launch, and Reset Demo removes the jobs and the experiment's files. Each
/// test uses a fresh store, render folder, and defaults suite, never the app's own.
@MainActor
@Suite(.serialized) struct RenderSurvivesHostTests {
    let folder: URL
    let defaults: UserDefaults

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "RenderSurvivesHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defaults = try #require(UserDefaults(suiteName: "RenderSurvivesHostTests-\(UUID().uuidString)"))
    }

    private var workspace: RenderWorkspace { RenderWorkspace(root: folder.appending(path: "Render That Survives")) }

    private func library() async throws -> LabLibrary {
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        return library
    }

    private func connected(_ library: LabLibrary) async throws -> RenderStudioModel {
        let model = RenderStudioModel(defaults: defaults)
        model.connect(library, runway: MacWorkerRunway(), workspace: workspace)
        try #require(await eventually { model.phase == .ready })
        return model
    }

    /// Waits up to 30 seconds for a condition that the app reaches asynchronously.
    private func eventually(_ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return await condition()
    }

    @Test func aRenderRunsAsTheMacWorkerWithEveryStepInTheReceiptList() async throws {
        let library = try await library()
        let model = try await connected(library)
        model.selectedRecipeID = "short-bars"
        model.preferGPU = true
        await model.start()
        try #require(await eventually {
            await model.refresh()
            return model.jobs.first.map { if case .succeeded = $0.phase { true } else { false } } ?? false
        })
        let job = try #require(model.jobs.first)
        guard case .succeeded(let output) = job.phase else { Issue.record("\(job.phase)"); return }

        // The published file is the one the job recorded, and nothing else is left behind.
        let published = try #require(model.output)
        #expect(published.sha256 == output.sha256 && published.job?.id == job.id)
        #expect(workspace.outputNames() == ["short-bars.mov"])

        let operations = model.receipts.reversed().map { ReceiptPresentation($0).operation }
        #expect(operations == ["Start Job", "Save Job Checkpoint", "Save Job Checkpoint", "Save Job Checkpoint", "Save Job Checkpoint", "Finish Job"])
        #expect(model.receipts.allSatisfy { $0.receipt.admitted.adapter == .appUI && $0.receipt.undo == nil })
        #expect(ReceiptPresentation(try #require(model.receipts.first)).noUndoReason?.hasPrefix("A job's steps have no undo") == true)
        let report = try #require(model.reports[job.id])
        #expect(report.runway == .whileAppRuns && report.facts.frameCount == 48)
        // The test host has a Metal device, so the GPU drew and checked every frame.
        #expect(report.tally.gpu + report.tally.cpu == 48)
    }

    @Test func aJobLeftRunningByAnEarlierProcessReadsAsStoppedAfterLaunch() async throws {
        let library = try await library()
        // An earlier process started a job and ended without recording anything more.
        let service = try await library.openedService()
        let draft = try JobDraft(kind: .render, title: EntityTitle("Short color bars"), total: 5)
        _ = try await service.perform(.startJob(draft: draft), requestID: RequestID(), authority: .userAction)

        let model = try await connected(library)
        await model.refresh()
        let job = try #require(model.jobs.first { $0.id == draft.id })
        #expect(job.phase == .interrupted(reason: .appStopped))
        #expect(model.lastMessage == "Stopped render job “Short color bars” at 0 of 5 because the app stopped while it ran. It can resume.")

        await model.cancel(job)
        #expect(try await service.job(draft.id, as: LabDataService.appUI).phase == .cancelled)
    }

    @Test func resetDemoRemovesTheJobsAndTheExperimentsFiles() async throws {
        let library = try await library()
        let model = try await connected(library)
        model.selectedRecipeID = "short-bars"
        await model.start()
        try #require(await eventually {
            await model.refresh()
            return model.output != nil
        })

        _ = await library.resetDemo()
        try #require(await eventually { model.jobs.isEmpty && !FileManager.default.fileExists(atPath: workspace.root.path(percentEncoded: false)) })
        let reset = try #require(library.receipts.first)
        #expect(reset.receipt.summary.hasSuffix("removed 1 job."))
        await model.refresh()
        #expect(model.output == nil)
    }

    @Test func theMacWindowHasARenderDestination() {
        #expect(SidebarDestination(storageKey: "render-survives") == .renderSurvives)
        #expect(SidebarDestination.renderSurvives.storageKey == "render-survives")
        #expect(SidebarDestination.renderSurvives.title == "Render That Survives")
    }
}
