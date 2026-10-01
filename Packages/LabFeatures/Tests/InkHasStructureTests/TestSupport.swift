import Foundation
import InkHasStructure
import LabDomain

enum Fixtures {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent() // InkHasStructureTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LabFeatures
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository
        .appending(path: "Fixtures", directoryHint: .isDirectory)

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

    static func sampleMediaFile() throws -> SampleMediaFixture {
        try JSONDecoder().decode(SampleMediaFixture.self, from: Data(contentsOf: root.appending(path: "ink/sample-media.json")))
    }
}

struct SampleMediaFixture: Decodable {
    struct Media: Decodable {
        let id: String
        let title: String
        let summary: String
        let width: Double
        let height: Double
    }
    struct Task: Decodable {
        let instruction: String
        let fallback: String
    }

    let format: String
    let formatVersion: Int
    let media: Media
    let task: Task
    let absentPencilGestures: [String]
}

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

    func perform(_ operation: DomainOperation, requestID: RequestID = RequestID()) async throws -> ActionReceipt {
        var grant: GrantID?
        if GrantRequirement.sensitiveCommits.requiresGrant(operation.kind, from: .appUI) {
            grant = try ledger.issue(for: operation, to: .appUI, lifetime: .seconds(30)).id
        }
        defer { if let grant { ledger.revoke(grant) } }
        return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: Self.appUI))
    }

    /// A person-owned collection to hold saved annotations.
    func annotationsCollection() async throws -> CollectionID {
        let draft = CollectionDraft(title: try EntityTitle("Annotations"))
        _ = try await perform(.createCollection(draft: draft))
        return draft.id
    }
}

func sampleStroke(
    from: (Double, Double) = (0.2, 0.5),
    to: (Double, Double) = (0.8, 0.5),
    width: Double = 0.02
) throws -> InkStroke {
    try InkStroke(
        width: width,
        points: [
            try AnnotationAnchor(x: from.0, y: from.1),
            try AnnotationAnchor(x: to.0, y: to.1),
        ]
    )
}
