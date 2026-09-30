import Foundation
import LabDomain
import Testing
@testable import PortableObjects

/// One lab for a test: an in-memory store behind `OperationService` with the host's
/// `GrantAuthorizationPolicy`, a user collection and a demo collection, and an importer whose
/// staging folder is a fresh temporary directory.
struct TestLab {
    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
    static let demoCollection = CollectionID(rawValue: UUID(uuidString: "0D3A0000-0000-4000-8000-000000000001")!)
    static let demoItem = ItemID(rawValue: UUID(uuidString: "0D3A0000-0000-4000-8000-000000000002")!)

    let store = InMemoryOperationStore()
    let ledger = GrantLedger()
    let service: OperationService
    let backend: ServiceBackend
    let importer: PortableObjectsImporter
    let stagingRoot: URL
    let inbox: CollectionID
    let shelf: CollectionID

    /// - Parameter name: A label for the temporary folder, so parallel tests never share one.
    static func make(_ name: String = #function) async throws -> TestLab {
        try await TestLab(name: name)
    }

    private init(name: String) async throws {
        service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
        backend = ServiceBackend(service: service, actor: Self.appUI)
        stagingRoot = FileManager.default.temporaryDirectory
            .appending(path: "PortableObjectsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        importer = try PortableObjectsImporter(backend: backend, stagingRoot: stagingRoot)

        let seed = try DemoSeed(
            version: 1,
            collections: [CollectionDraft(id: Self.demoCollection, title: EntityTitle("Swatches"))],
            items: [ItemDraft(id: Self.demoItem, in: Self.demoCollection, title: EntityTitle("Amber"), note: ItemNote("Warm."))]
        )
        let reset = DomainOperation.resetDemo(seed: seed)
        let grant = try ledger.issue(for: reset, to: .appUI)
        _ = try await service.perform(OperationRequest(id: RequestID(), operation: reset, actor: Self.appUI))
        ledger.revoke(grant.id)

        inbox = CollectionID()
        shelf = CollectionID()
        for (id, title) in [(inbox, "Imports"), (shelf, "Shelf")] {
            let draft = CollectionDraft(id: id, title: try EntityTitle(title))
            _ = try await service.perform(OperationRequest(id: RequestID(), operation: .createCollection(draft: draft), actor: Self.appUI))
        }
    }

    // MARK: Helpers

    /// Commits as the app UI. A destructive change gets a grant for exactly that operation, as the
    /// host issues one when a person presses the control (ADR-013).
    @discardableResult
    func perform(_ operation: DomainOperation) async throws -> ActionReceipt {
        var grant: GrantID?
        if operation.kind.isDestructive { grant = try ledger.issue(for: operation, to: .appUI, lifetime: .seconds(30)).id }
        defer { if let grant { ledger.revoke(grant) } }
        return try await service.perform(OperationRequest(id: RequestID(), operation: operation, actor: Self.appUI))
    }

    func item(_ id: ItemID) async -> LabItem? {
        await store.item(id)
    }

    /// Everything the store holds, for "nothing was written" checks.
    func snapshot() async -> Snapshot {
        Snapshot(
            items: Set(await store.items(in: nil)),
            collections: Set(await store.collections())
        )
    }

    struct Snapshot: Equatable {
        let items: Set<LabItem>
        let collections: Set<LabCollection>
    }

    func waitingImports() async -> [StagingID] {
        await importer.waitingImports()
    }

    /// Imports `data` into the inbox and returns the result.
    @discardableResult
    func importCreating(_ data: Data) async throws -> ImportResult {
        let review = try await importer.review(data: data)
        return try await importer.commit(review, into: inbox)
    }

    /// Exports an item as its canonical document bytes.
    func export(_ id: ItemID) async throws -> Data {
        let item = try #require(await store.item(id))
        let collection = await store.collection(item.collectionID)
        return try ExportPreview(item: item, collection: collection).object.data
    }
}

enum Fixture {
    static var sample: Data {
        get throws { try #require(PortableSample.data) }
    }

    static let sampleID = ItemID(rawValue: UUID(uuidString: "F1586771-0F15-4044-A372-5F9BC9968FDB")!)

    /// `Fixtures/LAB-008/` at the repository root, found from this source file.
    static let folder: URL = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/LAB-008", directoryHint: .isDirectory)

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: folder.appending(path: name))
    }

    /// A document built from the sample with `change` applied to its JSON object.
    static func edited(_ change: (inout [String: PortableValue]) -> Void) throws -> Data {
        let document = try LabDocument(decoding: sample)
        var root = document.root
        change(&root)
        return Data(PortableValue.object(root).canonicalText(topLevelOrder: LabDocument.schemaFields).utf8)
    }

    /// A minimal valid document, as text.
    static func minimal(id: UUID = UUID(), title: String = "Minimal", extra: String = "") -> Data {
        Data("""
        {"format":"native-lab-object","schemaVersion":1,"documentID":"\(id.uuidString)","kind":"collection-item","title":"\(title)"\(extra)}
        """.utf8)
    }
}

extension String {
    /// The UTF-8 bytes, for comparisons that must not treat canonically equivalent text as equal.
    var bytes: [UInt8] { Array(utf8) }
}
