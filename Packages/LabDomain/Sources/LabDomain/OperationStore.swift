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
///    `.preconditionFailed`. Otherwise upsert every collection and item in the commit, record
///    `commit.receipt` under `commit.requestID`, and return `.applied`.
/// 3. A recorded receipt is never changed or replaced. Request IDs are unique.
/// 4. Reads return the last applied state. `items(in:)` returns archived items too, in any order.
public protocol OperationStore: Sendable {
    func collection(_ id: CollectionID) async throws -> LabCollection?
    func item(_ id: ItemID) async throws -> LabItem?
    /// Every item, archived or not, in one collection or, when `collectionID` is `nil`, in all.
    func items(in collectionID: CollectionID?) async throws -> [LabItem]
    func receipt(for requestID: RequestID) async throws -> ActionReceipt?
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

    init(
        receipt: ActionReceipt,
        preconditions: [RevisionPrecondition],
        collections: [LabCollection],
        items: [LabItem]
    ) {
        self.receipt = receipt
        self.preconditions = preconditions
        self.collections = collections
        self.items = items
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
