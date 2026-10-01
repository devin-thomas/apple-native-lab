import CryptoKit
import DocumentsEverywhere
import Foundation
import LabDomain
import LabStore
import LabSupport
import PortableObjects
import Testing
@testable import NativeLab

/// LAB-009-B complete browser interaction on a fresh host store. Calls the actual session and
/// library; no Files/Finder preview, UI gesture, or live provider is implied by this replay.
@MainActor
@Suite("Documents Everywhere host qualification", .serialized)
struct DocumentsEverywhereQualificationTests {
    @Test func browserAdoptionAndResetLeaveUserDataAndAuthorityIntact() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "DocumentsEverywhereQualification-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let started = Date()
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        let collection = CollectionID()
        _ = try await library.submit(
            .createCollection(draft: CollectionDraft(id: collection, title: EntityTitle("Sample documents"))),
            requestID: RequestID(), authority: .userAction, names: [:]
        )
        let staging = folder.appending(path: "staging")
        let session = DocumentsEverywhereSession(locateStaging: { staging })
        await session.open(library: library)
        #expect(session.phase == .ready)
        #expect(session.entries.count == 2)
        #expect(session.destinationID == collection)
        #expect(session.providerState == .disabled)
        #expect(session.requestProviderActivation() == .providerDisabled)

        let catalog = SampleCatalog.bundled
        let inputs = try catalog.samples.map { sample in
            let bytes = try catalog.data(for: sample.id)
            return "\(sample.filename)@sha256:" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        let store = try await SQLiteOperationStore(url: url)
        var adopted: [LabItem] = []
        for sample in catalog.samples {
            session.select(sample.id)
            #expect(session.preview == (try DocumentPreviewBuilder.preview(sample: sample.id)))
            await session.adoptSelected()
            guard case .adopted(let result) = session.outcome else {
                Issue.record("expected an adoption receipt")
                return
            }
            #expect(result.change == .created)
            #expect(result.receipt.status == .committed)
            #expect(result.receipt.admitted.adapter == .appUI)
            let item = try #require(result.item)
            #expect(item.namespace == .user)
            adopted.append(item)
            let receipts = library.receipts.count
            await session.adoptSelected()
            guard case .refused(let message) = session.outcome else {
                Issue.record("expected duplicate refusal")
                return
            }
            #expect(message.contains("already in the lab"))
            #expect(library.receipts.count == receipts)
        }
        #expect(await library.resetDemo() != nil)
        await session.refresh(library)
        for item in adopted {
            #expect(try await store.item(item.id) == item)
            let original = try LabDocument(decoding: catalog.data(for: ProviderItemID(rawValue:
                item.title.value == "Harbor note" ? "sample.harbor-note" : "sample.tide-card")))
            #expect(try ExportPreview(item: item, collection: await store.collection(collection)).object.data == original.encoded())
        }
        #expect(try await store.items(in: collection).count == 2)
        #expect(session.providerState == .disabled)
        session.select(ProviderItemID(rawValue: "sample.missing"))
        #expect(session.preview == nil)
        guard case .refused = session.outcome else {
            Issue.record("expected unknown sample refusal")
            return
        }

        #if os(iOS)
        let execution = try Execution(observing: .current)
        #expect(execution.path == .simulator)
        let name = "documents-everywhere-iphone-simulator-host.json"
        #else
        let execution = Execution.fixture
        let name = "documents-everywhere-mac-host.json"
        #endif
        let record = try EvidenceRecord(
            subject: "LAB-009", check: "Browser preview, adoption, duplicate refusal, and Reset Demo on a fresh host store",
            date: started, provenance: .current, execution: execution, inputs: inputs,
            steps: [
                "Start LabLibrary on a fresh SQLite store; create one user collection through its operation service",
                "Open DocumentsEverywhereSession; provider disabled; preview both bundled samples",
                "Adopt each sample through the session; inspect app-UI receipts; adopt again and observe refusal without another receipt",
                "Reset Demo; read the user items directly and compare exported documents to canonical original bytes",
                "Select an unknown sample; no preview and a visible refusal outcome",
            ],
            outcome: .passed(observed: "Both samples previewed with the provider disabled, committed once as user items with app-UI receipts, refused duplicate adoption without new receipts, and retained their items and canonical document bytes across Reset Demo. Unknown sample selection refused."),
            limitations: [
                "Hosted model replay: no rendered screen, gesture, assistive technology, file dialog, or Files/Finder Quick Look was driven.",
                "The Quick Look extension is not loaded by this check. Shared preview-builder behavior is not proof of a system preview.",
                "Provider remains disabled; no domain registration, external file edit, materialization, or real disconnect ran.",
                "No physical iPhone or iPad; supports implemented at most.",
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        Attachment.record(String(decoding: try encoder.encode(record), as: UTF8.self), named: name)
        #expect(record.supportedState == .implemented)
    }
}
