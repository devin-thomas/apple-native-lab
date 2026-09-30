import AccessSuperpower
import Foundation
import LabDomain

/// The repository's fixtures, read from the checkout: the app's demo seed and this experiment's
/// chart fixture.
enum Fixtures {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent() // AccessSuperpowerTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LabFeatures
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository
        .appending(path: "Fixtures", directoryHint: .isDirectory)

    /// `Fixtures/demo/seed.json`, the seed the app commits on its first run.
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

    /// `Fixtures/access/archive-chart.json`.
    static func chart() throws -> ChartFixture {
        try JSONDecoder().decode(ChartFixture.self, from: Data(contentsOf: root.appending(path: "access/archive-chart.json")))
    }
}

/// The chart fixture: the practice set, and the exact reading of the chart it produces.
struct ChartFixture: Decodable {
    struct PracticeSample: Decodable { let id: UUID; let title: String; let collection: String }
    struct Bar: Decodable, Equatable { let label: String; let value: String; let actions: [String] }
    struct Spoken: Decodable { let valueAxis: [String: String]; let bars: [Bar] }
    struct Restore: Decodable { let restore: UUID; let outcome: String; let summaryAfter: String }
    struct Task: Decodable { let question: String; let answer: [String]; let finish: Restore; let miss: Restore }

    let format: String
    let formatVersion: Int
    let seed: String
    let practice: [PracticeSample]
    let chart: ChartSemantics
    let spoken: Spoken
    let task: Task
}

/// The demo seed as the host holds it after a first run: every sample at revision 1, each
/// collection's items ordered by title, as `LabDataService.demoContents` returns them.
func seededGroups(_ seed: DemoSeed, archiving archived: Set<ItemID> = []) -> [(collection: LabCollection, items: [LabItem])] {
    seed.collections.map { draft in
        let collection = LabCollection(id: draft.id, title: draft.title, namespace: .demo)
        let items = seed.items.filter { $0.collectionID == draft.id }.map { item in
            LabItem(id: item.id, collectionID: item.collectionID, title: item.title, note: item.note,
                    isArchived: archived.contains(item.id),
                    revision: archived.contains(item.id) ? Revision.initial.next() : .initial, namespace: .demo)
        }
        return (collection, items.sorted { $0.title.value.compare($1.title.value, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedAscending })
    }
}

/// An in-memory lab with the host's rules: `OperationService` over `GrantAuthorizationPolicy`, and a
/// grant issued only for a person's control press, as `LabDataService` issues one.
struct TestLab {
    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    let store = InMemoryOperationStore()
    let ledger = GrantLedger()
    let service: OperationService

    init() {
        service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
    }

    /// A lab holding `Fixtures/demo/seed.json` in its demo namespace.
    static func seeded() async throws -> TestLab {
        let lab = TestLab()
        _ = try await lab.perform(.resetDemo(seed: Fixtures.demoSeed()))
        return lab
    }

    /// Commits one operation as a control press in the app.
    func perform(_ operation: DomainOperation, requestID: RequestID = RequestID()) async throws -> ActionReceipt {
        var grant: GrantID?
        if GrantRequirement.sensitiveCommits.requiresGrant(operation.kind, from: .appUI) {
            grant = try ledger.issue(for: operation, to: .appUI, lifetime: .seconds(30)).id
        }
        defer { if let grant { ledger.revoke(grant) } }
        return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: Self.appUI))
    }

    /// The demo namespace as the host reads it: through the service, items ordered by title.
    func tally() async throws -> ArchiveTally {
        var groups: [(collection: LabCollection, items: [LabItem])] = []
        let seed = try Fixtures.demoSeed()
        for draft in seed.collections {
            let collection = try await service.findCollection(draft.id, as: Self.appUI)
            let filter = try ItemFilter(collectionID: draft.id, includeArchived: true, limit: ItemFilter.allowedLimits.upperBound)
            let items = try await service.findItems(filter, as: Self.appUI)
            groups.append((collection, items))
        }
        return ArchiveTally(groups)
    }
}

extension ItemID {
    init(_ uuid: UUID) { self.init(rawValue: uuid) }
}
