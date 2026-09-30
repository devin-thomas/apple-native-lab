import Foundation
import LabDomain
import LabSupport
import Testing
import TypedIntelligence
@testable import NativeLab

/// LAB-010 in the sandboxed Mac host: Typed Local Intelligence through `LibraryIntelligenceBackend`,
/// `LabLibrary`, and `LabDataService`, on a fresh SQLite store per test, never the app's real store.
/// The drafts here come from the sample parser and the manual editor, which need no model.
@MainActor
@Suite struct TypedIntelligenceHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "TypedIntelligenceHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func startedLibrary() async throws -> LabLibrary {
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        return library
    }

    private static let cobalt = ItemID(rawValue: UUID(uuidString: "9B97BF2F-4D0B-4197-9CA8-36489DF40455")!)

    private func item(_ id: ItemID, in library: LabLibrary) async throws -> LabItem {
        try await library.openedService().item(id, as: LabDataService.appUI)
    }

    @Test func theAppBundlesBothFixtureNotes() throws {
        for fixture in IntelligenceFixture.allCases {
            let note = try fixture.load(from: .main)
            #expect(note.origin == .fixture(fixture))
            #expect(!note.text.isEmpty)
        }
    }

    @Test func proposingRunsAsTheModelToolAndApplyingAsTheAppUI() async throws {
        let library = try await startedLibrary()
        let flow = TypedIntelligenceFlow(backend: LibraryIntelligenceBackend(library: library))
        let candidates = try await flow.candidates()
        #expect(candidates.count == 12, "the demo samples, and only them")
        let receiptsBefore = library.receipts.count
        let before = try await item(Self.cobalt, in: library)

        let note = try IntelligenceFixture.ambiguousNote.load(from: .main)
        let reviewable = try await flow.draft(note, with: SampleParser(), candidates: candidates).get()
        guard case .accepted(let checked) = reviewable.serviceCheck else { Issue.record("not accepted"); return }
        #expect(checked.proposedBy == .modelTool)
        #expect(reviewable.proposal.target?.id == Self.cobalt)
        // Drafted and checked, not approved: nothing stored, no receipt.
        #expect(library.receipts.count == receiptsBefore)
        #expect(try await item(Self.cobalt, in: library) == before)

        let approval = try reviewable.approve()
        let receipt = try await flow.commit(approval)
        #expect(receipt.admitted.adapter == .appUI)
        #expect(receipt.requestID == approval.requestID)
        #expect(receipt.conflict == nil)
        #expect(library.latestReceipt?.id == receipt.operationID, "the receipt joins the inspector's list")
        let after = try await item(Self.cobalt, in: library)
        #expect(after.title.value == "Cobalt (bleeds)")
        #expect(after.revision == before.revision.next())
    }

    /// The host has no commit path for the proposer: every commit authority maps to the app UI or
    /// an App Intent, and the proposer's scope can only propose through the host's service.
    @Test func theHostHasNoCommitPathForTheProposer() async throws {
        let authorities: [CommitAuthority] = [.userAction, .firstRunSeed, .intent(nil)]
        #expect(authorities.allSatisfy { $0.actor.adapter != .modelTool })
        #expect(TypedIntelligence.proposer.effectivePermissions == [.read, .propose])

        let library = try await startedLibrary()
        let service = try await library.openedService()
        let cobalt = try await item(Self.cobalt, in: library)
        let operation = DomainOperation.updateItem(id: cobalt.id, expected: cobalt.revision, changes: try ItemChanges(title: EntityTitle("Hijacked")))
        let proposal = try await service.propose(operation, as: TypedIntelligence.proposer)
        #expect(proposal.proposedBy == .modelTool)
        #expect(try await item(Self.cobalt, in: library) == cobalt)
    }

    @Test func theWorkbenchCompletesTheFallbackWithoutTheModel() async throws {
        let library = try await startedLibrary()
        let workbench = IntelligenceWorkbench(fixture: .injectedNote)
        await workbench.start(with: library)
        #expect(workbench.phase == .ready)
        #expect(workbench.note != nil)
        #expect(workbench.readiness != nil, "the probe ran")
        #expect(workbench.candidates.count == 12)

        workbench.draft(with: .sampleParser)
        try await waitUntil { workbench.phase == .reviewing }
        #expect(workbench.source == .sampleParser)
        #expect(workbench.review?.isApprovable == true)
        #expect(workbench.addedNote == "Kraft card: corners fray after a week in the drawer. Still takes pencil well.")

        // The person trims the added text; Apply waits for the edit to be checked.
        workbench.addedNote = "Corners fray after a week in the drawer."
        workbench.fieldsChanged()
        #expect(!workbench.canApply)
        try await waitUntil { !workbench.isRevising }
        #expect(workbench.review?.proposal.editedByPerson == true)
        #expect(workbench.canApply)

        await workbench.apply()
        let record = try #require(workbench.applied)
        #expect(record.receipt.admitted.adapter == .appUI)
        #expect(workbench.phase == .ready)
        let kraft = try #require(workbench.candidates.first { $0.title == "Kraft card" })
        #expect(kraft.note.hasSuffix("\nCorners fray after a week in the drawer."))
    }

    @Test func theManualEditorNeedsASampleBeforeItCanApply() async throws {
        let library = try await startedLibrary()
        let workbench = IntelligenceWorkbench(fixture: .ambiguousNote)
        await workbench.start(with: library)
        workbench.draft(with: .manualEditor)
        try await waitUntil { !workbench.isRevising && workbench.review != nil }
        #expect(workbench.review?.issues.contains(.noSampleChosen) == true)
        #expect(!workbench.canApply)
        let receipts = library.receipts.count
        workbench.discard()
        #expect(workbench.phase == .ready)
        #expect(library.receipts.count == receipts)
    }

    @Test func cancellingADraftLeavesNothingToReview() async throws {
        let library = try await startedLibrary()
        let workbench = IntelligenceWorkbench(fixture: .ambiguousNote)
        await workbench.start(with: library)
        workbench.draft(with: .sampleParser)
        workbench.cancelDraft()
        try await waitUntil { !workbench.isBusy }
        // Either the parser finished first or the cancellation did; a cancelled draft proposes nothing.
        if workbench.review == nil {
            #expect(workbench.message == ExtractionFailure.cancelled.message)
            #expect(workbench.phase == .ready)
        }
        #expect(library.receipts.isEmpty || library.receipts.allSatisfy { $0.receipt.admitted.operation.kind == .resetDemo })
    }

    /// The real on-device model inside the sandboxed app, through the same workbench the views
    /// use. Opt-in: `TEST_RUNNER_LAB_LIVE_MODEL=1 xcodebuild test …`. It needs an eligible Mac with
    /// Apple Intelligence on and the model ready; the probe decides, not the device name.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LAB_LIVE_MODEL"] == "1", "set TEST_RUNNER_LAB_LIVE_MODEL=1"))
    func theWorkbenchDraftsWithTheOnDeviceModelInTheSandboxedApp() async throws {
        let library = try await startedLibrary()
        let workbench = IntelligenceWorkbench(fixture: .ambiguousNote)
        await workbench.start(with: library)
        try #require(workbench.modelIsOffered, "the probe did not open the model route: \(workbench.readiness?.explanation ?? "")")
        let receipts = library.receipts.count
        workbench.draft(with: .onDeviceModel)
        #expect(workbench.drafting == .onDeviceModel)
        try await waitUntil(seconds: 60) { !workbench.isBusy }
        try #require(workbench.phase == .reviewing, "draft failed: \(workbench.message ?? "")")
        let review = try #require(workbench.review)
        #expect(workbench.source == .onDeviceModel)
        #expect(review.proposal.target != nil)
        #expect(library.receipts.count == receipts, "a draft writes nothing")
        if review.isApprovable {
            await workbench.apply()
            #expect(workbench.applied?.receipt.admitted.adapter == .appUI)
        }
    }

    private func waitUntil(seconds: Int = 4, _ condition: () -> Bool) async throws {
        for _ in 0..<(seconds * 50) {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("condition not met in \(seconds) seconds")
    }
}
