/// A process-local `OperationStore` for tests, previews, and the reference behavior of the store
/// contract. Nothing survives the process.
public actor InMemoryOperationStore: OperationStore {
    private var collectionsByID: [CollectionID: LabCollection] = [:]
    private var itemsByID: [ItemID: LabItem] = [:]
    private var sessionsByID: [SessionID: LabSession] = [:]
    private var receiptsByRequest: [RequestID: ActionReceipt] = [:]

    public init() {}

    public func collections() -> [LabCollection] { Array(collectionsByID.values) }

    public func collection(_ id: CollectionID) -> LabCollection? { collectionsByID[id] }

    public func item(_ id: ItemID) -> LabItem? { itemsByID[id] }

    public func items(in collectionID: CollectionID?) -> [LabItem] {
        guard let collectionID else { return Array(itemsByID.values) }
        return itemsByID.values.filter { $0.collectionID == collectionID }
    }

    public func receipt(for requestID: RequestID) -> ActionReceipt? { receiptsByRequest[requestID] }

    public func session(_ id: SessionID) -> LabSession? { sessionsByID[id] }

    public func sessions() -> [LabSession] { Array(sessionsByID.values) }

    /// Checks and writes without suspending, so the actor makes the whole commit atomic. Every
    /// check runs before the first write, so a throw leaves nothing written.
    public func apply(_ commit: AuthorizedCommit) throws(NamespaceViolation) -> CommitOutcome {
        if let recorded = receiptsByRequest[commit.requestID] {
            return .duplicateRequest(recorded)
        }
        for precondition in commit.preconditions {
            let actual = revision(of: precondition.entity)
            if actual != precondition.expected {
                return .preconditionFailed(precondition, actual: actual)
            }
        }
        try checkNamespaces(of: commit)
        for collection in commit.collections {
            collectionsByID[collection.id] = collection
        }
        for item in commit.items {
            // Like the SQLite store, a new item takes its extras and an existing one keeps its own.
            itemsByID[item.id] = itemsByID[item.id].map { stored in
                LabItem(
                    id: item.id, collectionID: item.collectionID, title: item.title, note: item.note,
                    isArchived: item.isArchived, revision: item.revision, namespace: item.namespace, extras: stored.extras
                )
            } ?? item
        }
        for session in commit.sessions {
            sessionsByID[session.id] = session
        }
        for removal in commit.removals {
            switch removal {
            case .collection(let id): collectionsByID[id] = nil
            case .item(let id): itemsByID[id] = nil
            case .session(let id): sessionsByID[id] = nil
            }
        }
        receiptsByRequest[commit.requestID] = commit.receipt
        return .applied
    }

    private func checkNamespaces(of commit: AuthorizedCommit) throws(NamespaceViolation) {
        var namespaceOfCollection = collectionsByID.mapValues(\.namespace)
        for collection in commit.collections {
            if let stored = namespaceOfCollection[collection.id], stored != collection.namespace {
                throw NamespaceViolation(entity: collection.reference)
            }
            namespaceOfCollection[collection.id] = collection.namespace
        }
        for item in commit.items {
            if let stored = itemsByID[item.id], stored.namespace != item.namespace {
                throw NamespaceViolation(entity: item.reference)
            }
            guard namespaceOfCollection[item.collectionID] == item.namespace else {
                throw NamespaceViolation(entity: item.reference)
            }
        }
        for removal in commit.removals where namespace(of: removal) != .demo {
            throw NamespaceViolation(entity: removal)
        }
    }

    private func namespace(of entity: EntityReference) -> DataNamespace? {
        switch entity {
        case .collection(let id): collectionsByID[id]?.namespace
        case .item(let id): itemsByID[id]?.namespace
        case .session(let id): sessionsByID[id]?.namespace
        }
    }

    private func revision(of entity: EntityReference) -> Revision? {
        switch entity {
        case .collection(let id): collectionsByID[id]?.revision
        case .item(let id): itemsByID[id]?.revision
        case .session(let id): sessionsByID[id]?.revision
        }
    }
}
