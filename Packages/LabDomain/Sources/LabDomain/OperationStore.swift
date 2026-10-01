/// Durable state behind `OperationService`.
///
/// Reads are plain queries. The only write is `apply(_:)`, which takes an `AuthorizedCommit`, and
/// only `OperationService` can create one. Code that holds a store still cannot change it without
/// passing authorization, validation, and idempotency.
///
/// An implementation must meet this contract (the in-memory store is the reference):
///
/// 1. `apply(_:)` is one atomic transaction. If it throws, or the process stops during it, nothing
///    it would have written is visible afterwards.
/// 2. Inside that transaction, in order: if a receipt is already recorded for
///    `commit.requestID`, write nothing and return `.duplicateRequest` with the recorded receipt.
///    Otherwise, if any precondition does not hold, write nothing and return
///    `.preconditionFailed`. Otherwise upsert every collection, then every item, then every
///    session, then every attention, then every job, then every anchor in the commit, remove every
///    entity in `commit.removals` in the order given, record `commit.receipt` under
///    `commit.requestID`, and return `.applied`.
/// 3. A recorded receipt is never changed or replaced. Request IDs are unique.
/// 4. Reads return the last applied state. `collections()` and `items(in:)` return archived
///    entities too, in any order.
/// 5. Namespaces are fixed. An upsert never changes a stored entity's namespace, an item always
///    has its collection's namespace, a session, a lab alert, and an anchor are always `demo`, a job
///    keeps the namespace it was created in, and a removal only ever deletes
///    a `demo` entity. A store
///    throws rather than break one of these rules, so a planning mistake cannot reach user data.
///    Rule 1 covers that throw too: nothing from the commit is written.
///
/// When several processes share one store, such as an app and its extensions in an App Group, each
/// runs its own service, so the checks in rule 2 must run inside the same write transaction that
/// writes, holding a lock that excludes other writers (for SQLite, `BEGIN IMMEDIATE`).
public protocol OperationStore: Sendable {
    /// Every collection, archived or not, in any order.
    func collections() async throws -> [LabCollection]
    func collection(_ id: CollectionID) async throws -> LabCollection?
    func item(_ id: ItemID) async throws -> LabItem?
    /// Every item, archived or not, in one collection or, when `collectionID` is `nil`, in all.
    func items(in collectionID: CollectionID?) async throws -> [LabItem]
    func receipt(for requestID: RequestID) async throws -> ActionReceipt?
    /// A stored session, or `nil` when it was never started (LAB-004).
    func session(_ id: SessionID) async throws -> LabSession?
    /// Every stored session, in any order.
    func sessions() async throws -> [LabSession]
    /// A stored lab alert, or `nil` when it was never scheduled (LAB-043).
    func attention(_ id: AttentionID) async throws -> LabAttention?
    /// Every stored lab alert, in any order. The table holds only lab-owned demo rows.
    func attentions() async throws -> [LabAttention]
    /// A stored job, or `nil` (LAB-032).
    func job(_ id: JobID) async throws -> LabJob?
    /// Every stored job, in any order.
    func jobs() async throws -> [LabJob]
    /// A stored lab-owned anchor, or `nil` (LAB-023).
    func anchor(_ id: AnchorID) async throws -> LabAnchor?
    /// Every stored anchor, in any order.
    func anchors() async throws -> [LabAnchor]
    func apply(_ commit: AuthorizedCommit) async throws -> CommitOutcome
}

/// A condition on the stored revision of one entity that must hold for a commit to apply.
public struct RevisionPrecondition: Hashable, Sendable {
    public let entity: EntityReference
    /// The revision the entity must have, or `nil` when it must not exist yet.
    public let expected: Revision?
}

/// One authorized, validated set of writes and the receipt that records them.
///
/// It has no public initializer and is not `Decodable`, so only `OperationService` can produce
/// one. A store reads its properties to persist them.
public struct AuthorizedCommit: Sendable {
    public let receipt: ActionReceipt
    public let preconditions: [RevisionPrecondition]
    public let collections: [LabCollection]
    public let items: [LabItem]
    /// Sessions to upsert (LAB-004). Always in the demo namespace.
    public let sessions: [LabSession]
    /// Lab alerts to upsert (LAB-043). Always in the demo namespace.
    public let attentions: [LabAttention]
    /// Jobs to upsert (LAB-032).
    public let jobs: [LabJob]
    /// Anchors to upsert (LAB-023). Always in the demo namespace.
    public let anchors: [LabAnchor]
    /// Entities to delete, items before collections, then jobs. Only Reset Demo, Cancel Lab Alerts,
    /// and an anchor removal remove anything, only demo entities, and every removal is also pinned
    /// by a precondition.
    public let removals: [EntityReference]

    init(
        receipt: ActionReceipt,
        preconditions: [RevisionPrecondition],
        collections: [LabCollection],
        items: [LabItem],
        sessions: [LabSession] = [],
        attentions: [LabAttention] = [],
        jobs: [LabJob] = [],
        anchors: [LabAnchor] = [],
        removals: [EntityReference]
    ) {
        self.receipt = receipt
        self.preconditions = preconditions
        self.collections = collections
        self.items = items
        self.sessions = sessions
        self.attentions = attentions
        self.jobs = jobs
        self.anchors = anchors
        self.removals = removals
    }

    public var requestID: RequestID { receipt.requestID }
}

public enum CommitOutcome: Hashable, Sendable {
    case applied
    /// A receipt was already recorded for the request ID. Nothing was written.
    case duplicateRequest(ActionReceipt)
    /// The stored revision did not match. Nothing was written.
    case preconditionFailed(RevisionPrecondition, actual: Revision?)
}

/// A commit would have moved an entity between namespaces, put an item in a collection of another
/// namespace, or removed an entity that is missing or user data. The store wrote nothing.
public struct NamespaceViolation: Error, Hashable, Sendable {
    public let entity: EntityReference

    public init(entity: EntityReference) { self.entity = entity }
}
