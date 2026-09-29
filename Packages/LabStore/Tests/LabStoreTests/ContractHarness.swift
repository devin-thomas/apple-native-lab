import Foundation
import LabDomain
@testable import LabStore
import Testing

/// The store implementations the contract tests run against.
enum StoreKind: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case inMemory = "in-memory"
    case sqlite

    var testDescription: String { rawValue }
}

struct InjectedStoreFailure: Error {}

/// Wraps a store to count commits, fail one before it starts, or run another writer between the
/// service's read and its commit, the way LabDomain's own tests wrap the in-memory store.
actor ContractStore: OperationStore {
    let inner: any OperationStore
    private(set) var appliedCommits = 0
    private var failBeforeNextCommit = false
    private var beforeNextCommit: (@Sendable () async -> Void)?

    init(_ inner: any OperationStore) { self.inner = inner }

    func failBeforeNextCommitOnce() { failBeforeNextCommit = true }

    func runBeforeNextCommit(_ body: @escaping @Sendable () async -> Void) { beforeNextCommit = body }

    func collections() async throws -> [LabCollection] { try await inner.collections() }
    func collection(_ id: CollectionID) async throws -> LabCollection? { try await inner.collection(id) }
    func item(_ id: ItemID) async throws -> LabItem? { try await inner.item(id) }
    func items(in collectionID: CollectionID?) async throws -> [LabItem] { try await inner.items(in: collectionID) }
    func receipt(for requestID: RequestID) async throws -> ActionReceipt? { try await inner.receipt(for: requestID) }

    func apply(_ commit: AuthorizedCommit) async throws -> CommitOutcome {
        if let hook = beforeNextCommit {
            beforeNextCommit = nil
            await hook()
        }
        if failBeforeNextCommit {
            failBeforeNextCommit = false
            throw InjectedStoreFailure()
        }
        let outcome = try await inner.apply(commit)
        if outcome == .applied { appliedCommits += 1 }
        return outcome
    }
}

/// A service over one kind of store, with helpers that keep each contract test about its behavior.
struct ContractHarness {
    let kind: StoreKind
    let store: ContractStore
    let service: OperationService
    /// Set for SQLite: the directory holding the file, and the store's fault plan.
    let directory: TemporaryDirectory?
    let faults: FaultPlan?

    static func make(_ kind: StoreKind, operationIDs: SequentialOperationIDs? = nil) async throws -> ContractHarness {
        let inner: any OperationStore
        var directory: TemporaryDirectory?
        var faults: FaultPlan?
        switch kind {
        case .inMemory:
            inner = InMemoryOperationStore()
        case .sqlite:
            let folder = try TemporaryDirectory()
            let plan = FaultPlan()
            inner = try await SQLiteOperationStore.open(folder.storeURL, hook: plan.hook)
            directory = folder
            faults = plan
        }
        let store = ContractStore(inner)
        let service = if let operationIDs {
            OperationService(store: store, makeOperationID: { operationIDs.next() })
        } else {
            OperationService(store: store)
        }
        return ContractHarness(kind: kind, store: store, service: service, directory: directory, faults: faults)
    }

    /// A second service over the same data, as another process sharing the store would have. For
    /// SQLite it has its own connection to the file.
    func otherProcess() async throws -> OperationService {
        guard let directory else { return OperationService(store: store) }
        return OperationService(store: try await SQLiteOperationStore(url: directory.storeURL))
    }

    /// Makes the next commit fail. SQLite fails inside its transaction, after every write and the
    /// receipt insert and before `COMMIT`; the in-memory store fails before it starts.
    func failNextCommit() async {
        if let faults {
            faults.interrupt { $0 == .receiptRecorded }
        } else {
            await store.failBeforeNextCommitOnce()
        }
    }

    @discardableResult
    func perform(_ operation: DomainOperation, as actor: ActorScope = .appUI, id: RequestID = RequestID()) async throws -> ActionReceipt {
        try await service.perform(OperationRequest(id: id, operation: operation, actor: actor))
    }

    func makeCollection(_ title: EntityTitle = "Samples", id: CollectionID = CollectionID()) async throws -> LabCollection {
        try await perform(.createCollection(draft: CollectionDraft(id: id, title: title)))
        return try await collection(id)
    }

    func makeItem(_ title: EntityTitle = "Amber sample", in collection: LabCollection, id: ItemID = ItemID()) async throws -> LabItem {
        try await perform(.createItem(draft: ItemDraft(id: id, in: collection.id, title: title)))
        return try await item(id)
    }

    func item(_ id: ItemID) async throws -> LabItem { try await service.findItem(id, as: .appUI) }

    func collection(_ id: CollectionID) async throws -> LabCollection { try await service.findCollection(id, as: .appUI) }

    var appliedCommits: Int { get async { await store.appliedCommits } }

    /// Every entity, sorted by ID, read through the store protocol.
    func state() async throws -> ([LabCollection], [LabItem]) {
        let collections = try await store.collections().sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        let items = try await store.items(in: nil).sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        return (collections, items)
    }
}
