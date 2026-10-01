import Foundation
import LabDomain
import PortableObjects
import Testing
@testable import DocumentsEverywhere

/// One lab for Documents Everywhere tests: in-memory store, importer, and sample catalog.
struct TestLab {
    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    let store = InMemoryOperationStore()
    let ledger = GrantLedger()
    let service: OperationService
    let importer: PortableObjectsImporter
    let adopter: SampleAdopter
    let catalog: SampleCatalog
    let stagingRoot: URL
    let inbox: CollectionID

    static func make(_ name: String = #function) async throws -> TestLab {
        try await TestLab(name: name)
    }

    private init(name: String) async throws {
        service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
        let backend = ServiceBackend(service: service, actor: Self.appUI)
        stagingRoot = FileManager.default.temporaryDirectory
            .appending(path: "DocumentsEverywhereTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        importer = try PortableObjectsImporter(backend: backend, stagingRoot: stagingRoot)
        catalog = .bundled
        adopter = SampleAdopter(importer: importer, catalog: catalog)

        inbox = CollectionID()
        let draft = CollectionDraft(id: inbox, title: try EntityTitle("Samples"))
        _ = try await service.perform(
            OperationRequest(id: RequestID(), operation: .createCollection(draft: draft), actor: Self.appUI)
        )
    }

    func snapshot() async -> Set<ItemID> {
        Set(await store.items(in: nil).map(\.id))
    }
}

enum Fixture {
    static let folder: URL = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/LAB-009", directoryHint: .isDirectory)

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: folder.appending(path: name))
    }
}
