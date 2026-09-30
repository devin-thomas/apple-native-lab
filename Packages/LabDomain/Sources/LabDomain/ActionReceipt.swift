/// How one entity moved from one revision to the next.
public struct EntityChange: Hashable, Sendable, Codable {
    public let entity: EntityReference
    /// `nil` when the operation created the entity.
    public let previousRevision: Revision?
    public let newRevision: Revision
}

/// A request that named an older revision than the one stored. Nothing was changed.
public struct RevisionConflict: Hashable, Sendable, Codable {
    public let entity: EntityReference
    public let expected: Revision
    public let current: Revision
}

public enum ReceiptStatus: Hashable, Sendable, Codable {
    case committed
    /// The target changed after the caller last saw it. Inspect `current`, decide, and submit a
    /// rebased operation under a new request ID.
    case conflict(RevisionConflict)

    // Persisted as {"state": "committed"} or {"state": "conflict", "conflict": {…}}.
    private enum CodingKeys: String, CodingKey {
        case state
        case conflict
    }

    private enum State: String, Codable {
        case committed
        case conflict
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(State.self, forKey: .state) {
        case .committed: self = .committed
        case .conflict: self = .conflict(try container.decode(RevisionConflict.self, forKey: .conflict))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .committed:
            try container.encode(State.committed, forKey: .state)
        case .conflict(let conflict):
            try container.encode(State.conflict, forKey: .state)
            try container.encode(conflict, forKey: .conflict)
        }
    }
}

/// The immutable record of one admitted request and what it did.
///
/// The service stores it with the request ID in the same transaction as the change, and returns
/// the same value for every retry of that request.
public struct ActionReceipt: Hashable, Sendable, Codable, Identifiable {
    public let operationID: OperationID
    public let requestID: RequestID
    public let admitted: AdmittedRequest
    public let status: ReceiptStatus
    /// Every entity the operation created or changed, with its previous and new revision. Empty
    /// for a conflict.
    public let changes: [EntityChange]
    /// Every entity the operation deleted. Only Reset Demo and an anchor removal delete, and only
    /// demo entities.
    public let removed: [EntityReference]
    /// A short sentence for the person who made the request.
    public let summary: String
    /// The operation that reverses this one, pinned to the revision this one produced. `nil` when
    /// nothing changed or the change cannot be reversed.
    public let undo: DomainOperation?

    init(
        operationID: OperationID,
        requestID: RequestID,
        admitted: AdmittedRequest,
        status: ReceiptStatus,
        changes: [EntityChange],
        removed: [EntityReference],
        summary: String,
        undo: DomainOperation?
    ) {
        self.operationID = operationID
        self.requestID = requestID
        self.admitted = admitted
        self.status = status
        self.changes = changes
        self.removed = removed
        self.summary = summary
        self.undo = undo
    }

    public var id: OperationID { operationID }

    public var affectedEntities: [EntityReference] { changes.map(\.entity) + removed }

    public var conflict: RevisionConflict? {
        if case .conflict(let conflict) = status { conflict } else { nil }
    }

    // `removed` is written only when it is not empty, so every receipt without a removal keeps the
    // shape CORE-002 recorded, and a receipt recorded before the field existed still decodes.
    private enum CodingKeys: String, CodingKey {
        case operationID, requestID, admitted, status, changes, removed, summary, undo
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operationID = try container.decode(OperationID.self, forKey: .operationID)
        requestID = try container.decode(RequestID.self, forKey: .requestID)
        admitted = try container.decode(AdmittedRequest.self, forKey: .admitted)
        status = try container.decode(ReceiptStatus.self, forKey: .status)
        changes = try container.decode([EntityChange].self, forKey: .changes)
        removed = try container.decodeIfPresent([EntityReference].self, forKey: .removed) ?? []
        summary = try container.decode(String.self, forKey: .summary)
        undo = try container.decodeIfPresent(DomainOperation.self, forKey: .undo)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operationID, forKey: .operationID)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(admitted, forKey: .admitted)
        try container.encode(status, forKey: .status)
        try container.encode(changes, forKey: .changes)
        if !removed.isEmpty { try container.encode(removed, forKey: .removed) }
        try container.encode(summary, forKey: .summary)
        try container.encodeIfPresent(undo, forKey: .undo)
    }
}

/// A validated operation that has not been committed, such as a model tool's suggestion.
///
/// Nothing is stored. To apply it, an actor allowed to commit submits `operation` under its own
/// request ID; the expected revision inside it still guards against intervening changes.
public struct OperationProposal: Hashable, Sendable {
    public let operation: DomainOperation
    public let proposedBy: AdapterKind
    public let summary: String
    /// Set when the proposal was already out of date when it was made.
    public let conflict: RevisionConflict?

    public var isReady: Bool { conflict == nil }
}
