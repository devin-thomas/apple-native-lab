import Foundation
import LabDomain
import LabJobs
import RenderThatSurvives
import RespectfulAttention
import Testing
import UIKit
@testable import NativeLab

/// LAB-032 inside the built iPhone app, in a simulator: a render asks iOS for continued processing
/// through the app's real runway, and records what iOS answered; and a job with no background
/// time stops at a checkpoint when the app leaves the foreground. The lifecycle notifications are
/// posted by the test, which simulates leaving; it does not background the app. Each test uses a
/// fresh store, render folder, and defaults suite, never the app's own.
@MainActor
@Suite(.serialized) struct RenderSurvivesPhoneTests {
    let folder: URL
    let defaults: UserDefaults

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "RenderSurvivesPhoneTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defaults = try #require(UserDefaults(suiteName: "RenderSurvivesPhoneTests-\(UUID().uuidString)"))
    }

    private func connected() async throws -> (LabLibrary, RenderStudioModel) {
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let model = RenderStudioModel(defaults: defaults)
        model.connect(library, runway: ContinuedProcessingRunway(), workspace: RenderWorkspace(root: folder.appending(path: "Render")))
        try #require(await eventually { model.phase == .ready })
        return (library, model)
    }

    private func eventually(seconds: Int = 60, _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return await condition()
    }

    @Test func theAppDeclaresTheRenderTaskWildcard() throws {
        let permitted = try #require(Bundle.main.object(forInfoDictionaryKey: ContinuedProcessingRunway.infoKey) as? [String])
        #expect(permitted == ["\(try #require(ContinuedProcessingRunway.prefix)).*"])
    }

    /// The host can ask for Focus metadata during any render. The reported lifecycle crash
    /// trapped in this context's unsupported request.identifier expression, not in the worker.
    @Test func theHostsFocusContextCanBeReadWhileQualifyingRenders() throws {
        let allowed = LabAlertIdentity.notificationID(RespectfulAttention.offers[0].id)
        let context = LabFocusFilterIntent(includedIdentifiers: [allowed, "foreign.alert"]).appContext
        let predicate = try #require(context.notificationFilterPredicate)
        #expect(predicate.evaluate(with: allowed))
        #expect(!predicate.evaluate(with: "foreign.alert"))
        let empty = try #require(LabFocusFilterIntent(includedIdentifiers: []).appContext.notificationFilterPredicate)
        #expect(!empty.evaluate(with: allowed))
    }

    @Test func aRenderRecordsTheRunwayIOSGrantedAndPublishesTheMovie() async throws {
        let (_, model) = try await connected()
        model.selectedRecipeID = "short-bars"
        model.wantsBackground = true
        await model.start()
        let started = try #require(model.jobs.first)
        let outcome = try #require(await model.completion(of: started.id))
        try #require(outcome.report != nil)
        let job = try #require(model.jobs.first)
        let report = try #require(model.reports[job.id], "\(job.phase)")
        #expect(report.facts.frameCount == 48)
        // What iOS answered is the evidence; each answer is a supported path.
        print("LAB-032 runway in this simulator: \(report.runway)")
        switch report.runway {
        case .continuedProcessing, .foregroundOnly(.unavailable), .foregroundOnly(.notPermitted),
             .foregroundOnly(.systemBusy), .foregroundOnly(.notInForeground):
            break
        default:
            Issue.record("Unexpected runway \(report.runway)")
        }
    }

    @Test func leavingTheForegroundWithoutBackgroundTimeStopsAtACheckpoint() async throws {
        let (_, model) = try await connected()
        model.selectedRecipeID = "long-bars"
        model.wantsBackground = false
        await model.start()
        try #require(await eventually {
            await model.refresh()
            return (model.jobs.first?.progress.completed ?? 0) >= 1
        })
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: UIApplication.shared)
        let started = try #require(model.jobs.first)
        let outcome = try #require(await model.completion(of: started.id))
        try #require(outcome.job?.phase == .interrupted(reason: .leftForeground))
        let job = try #require(model.jobs.first)
        #expect(job.phase == .interrupted(reason: .leftForeground))
        #expect(job.progress.completed >= 1 && job.progress.completed < 9)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: UIApplication.shared)

        // Cancel may land while the worker is still ending after it recorded the stop; the
        // studio then cancels when the worker ends, so wait for the store to say so.
        await model.cancel(job)
        #expect(await eventually(seconds: 30) {
            await model.refresh()
            return model.jobs.first?.phase == .cancelled
        })
        #expect(!model.isLive(job))
    }
}
