/// A process-local `OperationStore` for tests, previews, and the reference behavior of the store
/// contract. Nothing survives the process.
public actor InMemoryOperationStore: OperationStore {
    private var collectionsByID: [CollectionID: LabCollection] = [:]
    private var itemsByID: [ItemID: LabItem] = [:]
    private var receiptsByRequest: [RequestID: ActionReceipt] = [:]

    public init() {}

    public func collection(_ id: CollectionID) -> LabCollection? { collectionsByID[id] }

    public func item(_ id: ItemID) -> LabItem? { itemsByID[id] }

    public func items(in collectionID: CollectionID?) -> [LabItem] {
        guard let collectionID else { return Array(itemsByID.values) }
        return itemsByID.values.filter { $0.collectionID == collectionID }
    }

    public func receipt(for requestID: RequestID) -> ActionReceipt? { receiptsByRequest[requestID] }

    /// Checks and writes without suspending, so the actor makes the whole commit atomic.
    public func apply(_ commit: AuthorizedCommit) -> CommitOutcome {
        if let recorded = receiptsByRequest[commit.requestID] {
            return .duplicateRequest(recorded)
        }
        for precondition in commit.preconditions {
            let actual = revision(of: precondition.entity)
            if actual != precondition.expected {
                return .preconditionFailed(precondition, actual: actual)
            }
        }
        for collection in commit.collections {
            collectionsByID[collection.id] = collection
        }
        for item in commit.items {
            itemsByID[item.id] = item
        }
        receiptsByRequest[commit.requestID] = commit.receipt
        return .applied
    }

    private func revision(of entity: EntityReference) -> Revision? {
        switch entity {
        case .collection(let id): collectionsByID[id]?.revision
        case .item(let id): itemsByID[id]?.revision
        }
    }
}
