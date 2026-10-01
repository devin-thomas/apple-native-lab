import Foundation
import LabDomain
import Synchronization

// The tests import LabDomain without @testable, so they exercise only what an adapter can reach.

// Test-only literal convenience for known-good fixture text. Because of it, `EntityTitle("…")`
// with a literal argument is a literal coercion here, not the validating initializer; validation
// tests call `title(_:)` and `note(_:)` below, which pass a `String` value.
extension EntityTitle: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        do { try self.init(value) } catch { fatalError("Invalid test title \(value): \(error)") }
    }
}

extension ItemNote: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        do { try self.init(value) } catch { fatalError("Invalid test note: \(error)") }
    }
}

/// Runs the validating initializer, as an adapter does with user input.
func title(_ raw: String) throws(ValidationError) -> EntityTitle { try EntityTitle(raw) }

/// Runs the validating initializer, as an adapter does with user input.
func note(_ raw: String) throws(ValidationError) -> ItemNote { try ItemNote(raw) }

extension ActorScope {
    /// An actor granted everything; its adapter ceiling still applies.
    static func granted(_ adapter: AdapterKind) -> ActorScope {
        ActorScope(adapter: adapter, grants: Set(Permission.allCases))
    }

    static let appUI = granted(.appUI)
    static let appIntent = granted(.appIntent)
    static let modelTool = granted(.modelTool)
}

extension Revision {
    static func r(_ value: Int) -> Revision { Revision(rawValue: value)! }
}

/// Deterministic identifiers: 00000000-0000-0000-0000-000000000001, …
func uuid(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
}

final class SequentialOperationIDs: Sendable {
    private let counter = Mutex(0)

    func next() -> OperationID {
        OperationID(rawValue: uuid(counter.withLock { value in
            value += 1
            return value
        }))
    }
}

/// An authorization policy that records every attempt it is asked about.
final class RecordingPolicy: AuthorizationPolicy {
    private let log = Mutex<[(AdapterKind, Access)]>([])
    private let decision: PolicyDecision

    init(decision: PolicyDecision = .allow) { self.decision = decision }

    func decide(_ access: Access, for actor: ActorScope) -> PolicyDecision {
        log.withLock { $0.append((actor.adapter, access)) }
        return decision
    }

    var attempts: [(adapter: AdapterKind, access: Access)] { log.withLock { $0.map { ($0.0, $0.1) } } }
}

struct InjectedStoreFailure: Error {}

/// Wraps a real store the way a second implementation would, to count commits, inject a failed
/// commit, or run another writer between the service's read and its commit.
actor SpyStore: OperationStore {
    let inner: any OperationStore
    private(set) var appliedCommits = 0
    private var failNextCommit = false
    private var beforeNextCommit: (@Sendable () async -> Void)?

    init(_ inner: any OperationStore = InMemoryOperationStore()) { self.inner = inner }

    func failNextCommitOnce() { failNextCommit = true }

    func runBeforeNextCommit(_ body: @escaping @Sendable () async -> Void) { beforeNextCommit = body }

    func collections() async throws -> [LabCollection] { try await inner.collections() }
    func collection(_ id: CollectionID) async throws -> LabCollection? { try await inner.collection(id) }
    func item(_ id: ItemID) async throws -> LabItem? { try await inner.item(id) }
    func items(in collectionID: CollectionID?) async throws -> [LabItem] { try await inner.items(in: collectionID) }
    func receipt(for requestID: RequestID) async throws -> ActionReceipt? { try await inner.receipt(for: requestID) }
    func session(_ id: SessionID) async throws -> LabSession? { try await inner.session(id) }
    func sessions() async throws -> [LabSession] { try await inner.sessions() }
    func attention(_ id: AttentionID) async throws -> LabAttention? { try await inner.attention(id) }
    func attentions() async throws -> [LabAttention] { try await inner.attentions() }
    func job(_ id: JobID) async throws -> LabJob? { try await inner.job(id) }
    func jobs() async throws -> [LabJob] { try await inner.jobs() }
    func anchor(_ id: AnchorID) async throws -> LabAnchor? { try await inner.anchor(id) }
    func anchors() async throws -> [LabAnchor] { try await inner.anchors() }

    func apply(_ commit: AuthorizedCommit) async throws -> CommitOutcome {
        if let hook = beforeNextCommit {
            beforeNextCommit = nil
            await hook()
        }
        if failNextCommit {
            failNextCommit = false
            throw InjectedStoreFailure()
        }
        let outcome = try await inner.apply(commit)
        if outcome == .applied { appliedCommits += 1 }
        return outcome
    }
}

/// A service over a spy store, with helpers that keep each test about its one behavior.
struct Harness {
    let store: SpyStore
    let service: OperationService

    init(
        store: SpyStore = SpyStore(),
        policy: any AuthorizationPolicy = BaselineAuthorizationPolicy(),
        operationIDs: SequentialOperationIDs? = nil
    ) {
        self.store = store
        if let operationIDs {
            service = OperationService(store: store, policy: policy, makeOperationID: { operationIDs.next() })
        } else {
            service = OperationService(store: store, policy: policy)
        }
    }

    @discardableResult
    func perform(
        _ operation: DomainOperation,
        as actor: ActorScope = .appUI,
        id: RequestID = RequestID()
    ) async throws -> ActionReceipt {
        try await service.perform(OperationRequest(id: id, operation: operation, actor: actor))
    }

    func makeCollection(_ title: EntityTitle = "Samples", id: CollectionID = CollectionID()) async throws -> LabCollection {
        try await perform(.createCollection(draft: CollectionDraft(id: id, title: title)))
        return try await service.findCollection(id, as: .appUI)
    }

    func makeItem(
        _ title: EntityTitle = "Amber sample",
        note: ItemNote = .empty,
        in collection: LabCollection,
        id: ItemID = ItemID()
    ) async throws -> LabItem {
        try await perform(.createItem(draft: ItemDraft(id: id, in: collection.id, title: title, note: note)))
        return try await service.findItem(id, as: .appUI)
    }

    func item(_ id: ItemID) async throws -> LabItem { try await service.findItem(id, as: .appUI) }

    func collection(_ id: CollectionID) async throws -> LabCollection { try await service.findCollection(id, as: .appUI) }

    var appliedCommits: Int { get async { await store.appliedCommits } }
}

extension OperationError {
    /// The denial, when this error is an authorization refusal.
    var denial: AuthorizationDenial? {
        if case .unauthorized(let denial) = self { denial } else { nil }
    }
}
