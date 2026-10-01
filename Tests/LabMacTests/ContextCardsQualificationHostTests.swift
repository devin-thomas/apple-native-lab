import ActionAtlas
import ContextCards
import Foundation
import LabDomain
import LabStore
import LabSupport
import Testing
@testable import NativeLab

/// Fresh SQLite fixture replay through the host session and typed intent adapter. No system
/// snippet, Siri, or Shortcuts presentation participates in this check.
@MainActor
@Suite(.serialized) struct ContextCardsQualificationHostTests {
    @Test func theFallbackInteractionPreservesImportedDataAcrossReset() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ContextCardsQualification-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        ContextCardsHost.connect(library)
        defer { ContextCardsHost.link.publish(nil) }
        let actions = ContextCardsHost.link.actions(.appIntent)
        let collection = try await library.atlasActions.createCollection(title: "Qualification notes", request: request(1)).entity
        let store = try await SQLiteOperationStore(url: url)
        let ledger = GrantLedger()
        let service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
        let inbox = InMemoryStagingInbox()
        let input = "Original qualification note\nKeep this imported record."
        let staged = await inbox.stage(try StagingRecord.text(utf8: Array(input.utf8)))
        try ledger.issue(to: .shareExtension, for: [.createItem], on: ImportAdopter.grantTarget(into: collection.id))
        let imported = try await ImportAdopter(service: service, inbox: inbox, ledger: ledger).adopt(staged.id, into: collection.id)
        let userBefore = try await store.items(in: collection.id)
        let session = ContextCardsSession()
        await session.showPrimary()
        let amber = try #require(session.item)
        let before = library.receipts.count
        session.prepareDecision()
        session.cancelDecision()
        #expect(session.board.proposal == nil)
        #expect(library.receipts.count == before)
        session.prepareDecision()
        await session.showOther()
        #expect(session.board.decisionIsStale)
        await session.confirm(in: library, onReceipt: { _ in })
        #expect(session.messageIsFailure)
        #expect(library.receipts.count == before)
        #expect(try await actions.read(amber.id).isArchived == false)
        #expect(try await actions.read(ContextCards.replacementSampleID).isArchived == false)
        session.cancelDecision()
        await session.showPrimary()
        session.prepareDecision()
        await session.confirm(in: library, onReceipt: { _ in })
        #expect(session.item?.isArchived == true)
        #expect(!session.messageIsFailure)
        let uiReceipt = try #require(library.latestReceipt)
        #expect(uiReceipt.receipt.admitted.adapter == .appUI)
        #expect(uiReceipt.receipt.undo != nil)
        _ = try #require(await library.resetDemo())
        await session.showPrimary()
        #expect(session.item?.isArchived == false)
        #expect(try await store.items(in: collection.id) == userBefore)
        #expect(try await store.receipt(for: imported.receipt.requestID) == imported.receipt)

        let entity = try await actions.entity(for: try #require(session.item))
        let intent = SetAsideSampleIntent(item: entity, seenGeneration: nil)
        intent.requestID = request(2).id.description
        await #expect(throws: ContextCardsError.cancelled) {
            try await intent.run(with: ContextCardsHost.link) { _ in throw CancellationError() }
        }
        #expect(try await store.receipt(for: request(2).id) == nil)
        let first = try await intent.run(with: ContextCardsHost.link) { _ in }
        let second = try await intent.run(with: ContextCardsHost.link) { _ in }
        #expect(first.receipt == second.receipt)
        #expect(library.receipts.count(where: { $0.receipt.requestID == request(2).id }) == 1)
        #expect(first.receipt.admitted.adapter == .appIntent)
        #expect(first.dialog.contains("Context resolution is unavailable."))

        let seed = try Data(contentsOf: try #require(Bundle.main.url(forResource: "seed", withExtension: "json")))
        let record = try EvidenceRecord(
            subject: "LAB-002", check: "Context Cards clean-store fallback replay, cancellation, stale screen, duplicate intent, and reset beside imported data",
            date: Date(), provenance: .current, execution: .fixture,
            inputs: ["seed:app-bundle@sha256:\(ContentDigest.sha256(seed).hex)", "import:original-text@sha256:\(ContentDigest.sha256(Data(input.utf8)).hex)"],
            steps: ["ContextCardsQualificationHostTests.theFallbackInteractionPreservesImportedDataAcrossReset", "Fresh host SQLite store; import original text with a scoped share-extension grant", "Session: prepare/cancel, prepare/replace/refuse, prepare/confirm, Reset Demo", "Typed intent run(with:): decline, retry, duplicate same request"],
            outcome: .passed(observed: "Stale session refused with neither sample archived and no receipt. Confirmed app UI archive offered undo. Reset restored Amber and preserved imported item fields and its receipt. Declined intent had no receipt; retry and duplicate returned one identical app-intent receipt."),
            limitations: ["Fixture path in the sandboxed Mac host; no rendered UI or system dialog was driven.", "Intent confirmation is a stand-in. No Siri, Shortcuts app, physical device, or Siri-disabled system configuration ran.", "Package schema and card-equivalence checks are separate tests, not observations of system integration."]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        Attachment.record(String(decoding: try encoder.encode(record), as: UTF8.self), named: "LAB-002-context-cards-host-fallback.json")
    }

    private func request(_ index: Int) -> AtlasRequest {
        AtlasRequest(RequestID(rawValue: UUID(uuidString: String(format: "00000000-0002-4000-8000-%012d", index + 200))!))
    }
}
