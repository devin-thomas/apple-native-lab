import Foundation
import LabDomain
import Testing
@testable import WalletMoment

/// The repository's fixtures, read from the checkout.
enum Fixtures {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent() // WalletMomentTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LabFeatures
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository
        .appending(path: "Fixtures", directoryHint: .isDirectory)

    static var samplePass: URL { root.appending(path: "wallet/sample-event-pass.json") }
    static var hostileKey: URL { root.appending(path: "wallet/hostile-signing-key.json") }

    static func demoSeed() throws -> DemoSeed {
        struct File: Decodable {
            struct Collection: Decodable { let id: UUID; let title: String }
            struct Item: Decodable { let id: UUID; let collection: UUID; let title: String; let note: String }
            let seedVersion: Int
            let collections: [Collection]
            let items: [Item]
        }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: root.appending(path: "demo/seed.json")))
        return try DemoSeed(
            version: file.seedVersion,
            collections: try file.collections.map { CollectionDraft(id: CollectionID(rawValue: $0.id), title: try EntityTitle($0.title)) },
            items: try file.items.map {
                ItemDraft(id: ItemID(rawValue: $0.id), in: CollectionID(rawValue: $0.collection),
                          title: try EntityTitle($0.title), note: try ItemNote($0.note))
            }
        )
    }
}

/// An in-memory lab with the host's rules: `OperationService` over `GrantAuthorizationPolicy`.
struct TestLab {
    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    let store = InMemoryOperationStore()
    let ledger = GrantLedger()
    let service: OperationService

    init() {
        service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
    }

    static func seeded() async throws -> TestLab {
        let lab = TestLab()
        _ = try await lab.perform(.resetDemo(seed: Fixtures.demoSeed()))
        return lab
    }

    var backend: ServiceWalletBackend { ServiceWalletBackend(service: service, actor: Self.appUI) }

    func perform(_ operation: DomainOperation, requestID: RequestID = RequestID()) async throws -> ActionReceipt {
        var grant: GrantID?
        if GrantRequirement.sensitiveCommits.requiresGrant(operation.kind, from: .appUI) {
            grant = try ledger.issue(for: operation, to: .appUI, lifetime: .seconds(30)).id
        }
        defer { if let grant { ledger.revoke(grant) } }
        return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: Self.appUI))
    }

    func items(in collectionID: CollectionID) async throws -> [LabItem] {
        let filter = try ItemFilter(collectionID: collectionID, includeArchived: true, limit: ItemFilter.allowedLimits.upperBound)
        return try await service.findItems(filter, as: Self.appUI)
    }

    func allUserItems() async throws -> [LabItem] {
        let filter = try ItemFilter(includeArchived: true, limit: ItemFilter.allowedLimits.upperBound)
        return try await service.findItems(filter, as: Self.appUI).filter { $0.namespace == .user }
    }
}
