/// The content of a new collection. The caller chooses the ID, so a retry, an import, or a fixture
/// seed names the same entity every time.
public struct CollectionDraft: Hashable, Sendable, Codable {
    public let id: CollectionID
    public let title: EntityTitle

    public init(id: CollectionID = CollectionID(), title: EntityTitle) {
        self.id = id
        self.title = title
    }
}

/// The content of a new item in an existing collection.
public struct ItemDraft: Hashable, Sendable, Codable {
    public let id: ItemID
    public let collectionID: CollectionID
    public let title: EntityTitle
    public let note: ItemNote
    /// Metadata the new item keeps without this build interpreting it, such as the fields of an
    /// imported document that an item has no place for.
    public let extras: ItemExtras

    public init(
        id: ItemID = ItemID(),
        in collectionID: CollectionID,
        title: EntityTitle,
        note: ItemNote = .empty,
        extras: ItemExtras = .empty
    ) {
        self.id = id
        self.collectionID = collectionID
        self.title = title
        self.note = note
        self.extras = extras
    }

    private enum CodingKeys: String, CodingKey {
        case id, collectionID, title, note, extras
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(ItemID.self, forKey: .id),
            in: container.decode(CollectionID.self, forKey: .collectionID),
            title: container.decode(EntityTitle.self, forKey: .title),
            note: container.decode(ItemNote.self, forKey: .note),
            extras: container.decodeIfPresent(ItemExtras.self, forKey: .extras) ?? .empty
        )
    }

    /// `extras` is written only when there are any, so every receipt for a draft without them
    /// keeps the shape CORE-002 recorded.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(collectionID, forKey: .collectionID)
        try container.encode(title, forKey: .title)
        try container.encode(note, forKey: .note)
        if !extras.isEmpty { try container.encode(extras, forKey: .extras) }
    }
}

/// The fields an item update replaces. At least one field is present.
public struct ItemChanges: Hashable, Sendable, Codable {
    public let title: EntityTitle?
    public let note: ItemNote?

    public init(title: EntityTitle? = nil, note: ItemNote? = nil) throws(ValidationError) {
        guard title != nil || note != nil else { throw .emptyChanges }
        self.title = title
        self.note = note
    }

    init(uncheckedTitle title: EntityTitle?, note: ItemNote?) {
        self.title = title
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case note
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            title: container.decodeIfPresent(EntityTitle.self, forKey: .title),
            note: container.decodeIfPresent(ItemNote.self, forKey: .note)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(note, forKey: .note)
    }
}

/// Every state change the domain supports, with its validated payload.
///
/// An operation on an existing entity carries the revision the caller last saw. The type makes it
/// required, so no mutation can silently overwrite a newer state. Archiving is the domain's
/// reversible removal. The only deletion is Reset Demo's, and it reaches demo samples only.
public enum DomainOperation: Hashable, Sendable, Codable {
    case createCollection(draft: CollectionDraft)
    case updateCollection(id: CollectionID, expected: Revision, title: EntityTitle)
    case archiveCollection(id: CollectionID, expected: Revision)
    case restoreCollection(id: CollectionID, expected: Revision)
    case createItem(draft: ItemDraft)
    case updateItem(id: ItemID, expected: Revision, changes: ItemChanges)
    case archiveItem(id: ItemID, expected: Revision)
    case restoreItem(id: ItemID, expected: Revision)
    /// Makes the demo namespace match `seed`: every sample the seed names returns to its original
    /// content, and every other demo entity is removed. User data is never changed or removed.
    /// Destructive, so only an adapter allowed to commit destructive changes can reset (ADR-011).
    case resetDemo(seed: DemoSeed)
    /// Starts (`running: true`) or pauses a session (LAB-004 Surface Deck). `expected` is the
    /// revision the caller last saw, or `nil` when it saw a session that was never started. Not
    /// destructive: pausing hides nothing, and the undo is the opposite change.
    case setSession(id: SessionID, expected: Revision?, running: Bool)
    /// Records a new job, running, with none of its work done yet (LAB-032 Render That Survives).
    /// Not destructive and not undoable: stopping a job is a transition, not an inverse.
    case startJob(draft: JobDraft)
    /// Moves a job one step through its lifecycle (`JobTransition`) at the revision the caller
    /// last saw. Not destructive: cancelling or failing a job removes nothing from view. Never
    /// undoable, because a job's effects are work and files that a receipt cannot take back.
    case updateJob(id: JobID, expected: Revision, transition: JobTransition)

    public var kind: OperationKind {
        switch self {
        case .createCollection: .createCollection
        case .updateCollection: .updateCollection
        case .archiveCollection: .archiveCollection
        case .restoreCollection: .restoreCollection
        case .createItem: .createItem
        case .updateItem: .updateItem
        case .archiveItem: .archiveItem
        case .restoreItem: .restoreItem
        case .resetDemo: .resetDemo
        case .setSession: .setSession
        case .startJob: .startJob
        case .updateJob: .updateJob
        }
    }

    /// The one entity the operation creates or changes, or `nil` for Reset Demo, which acts on the
    /// whole demo namespace.
    public var target: EntityReference? {
        switch self {
        case .createCollection(let draft): .collection(draft.id)
        case .updateCollection(let id, _, _), .archiveCollection(let id, _), .restoreCollection(let id, _):
            .collection(id)
        case .createItem(let draft): .item(draft.id)
        case .updateItem(let id, _, _), .archiveItem(let id, _), .restoreItem(let id, _):
            .item(id)
        case .setSession(let id, _, _):
            .session(id)
        case .startJob(let draft):
            .job(draft.id)
        case .updateJob(let id, _, _):
            .job(id)
        case .resetDemo:
            nil
        }
    }

    /// The revision the caller expects the target to have, or `nil` for a creation or a reset.
    /// For a session, `nil` means the caller saw a session that was never started.
    public var expectedRevision: Revision? {
        switch self {
        case .createCollection, .createItem, .resetDemo, .startJob:
            nil
        case .updateCollection(_, let expected, _), .archiveCollection(_, let expected),
             .restoreCollection(_, let expected), .updateItem(_, let expected, _),
             .archiveItem(_, let expected), .restoreItem(_, let expected):
            expected
        case .setSession(_, let expected, _):
            expected
        case .updateJob(_, let expected, _):
            expected
        }
    }

    /// The same change aimed at another revision of its target.
    ///
    /// Use it after a conflict, once a person has decided the change still applies to the current
    /// state, and submit the result under a new request ID. A creation or a reset is returned
    /// unchanged.
    public func rebased(onto revision: Revision) -> DomainOperation {
        switch self {
        case .createCollection, .createItem, .resetDemo, .startJob: self
        case .updateCollection(let id, _, let title): .updateCollection(id: id, expected: revision, title: title)
        case .archiveCollection(let id, _): .archiveCollection(id: id, expected: revision)
        case .restoreCollection(let id, _): .restoreCollection(id: id, expected: revision)
        case .updateItem(let id, _, let changes): .updateItem(id: id, expected: revision, changes: changes)
        case .archiveItem(let id, _): .archiveItem(id: id, expected: revision)
        case .restoreItem(let id, _): .restoreItem(id: id, expected: revision)
        case .setSession(let id, _, let running): .setSession(id: id, expected: revision, running: running)
        case .updateJob(let id, _, let transition): .updateJob(id: id, expected: revision, transition: transition)
        }
    }
}

/// An operation without its payload, for policies, logs, and display.
public enum OperationKind: String, Hashable, Sendable, Codable, CaseIterable {
    case createCollection = "create-collection"
    case updateCollection = "update-collection"
    case archiveCollection = "archive-collection"
    case restoreCollection = "restore-collection"
    case createItem = "create-item"
    case updateItem = "update-item"
    case archiveItem = "archive-item"
    case restoreItem = "restore-item"
    case resetDemo = "reset-demo"
    case setSession = "set-session"
    case startJob = "start-job"
    case updateJob = "update-job"

    /// Whether the operation removes something from normal view. Destructive commits need their
    /// own permission, which no model tool can hold (ADR-007).
    public var isDestructive: Bool {
        switch self {
        case .archiveCollection, .archiveItem, .resetDemo: true
        case .createCollection, .updateCollection, .restoreCollection, .createItem, .updateItem, .restoreItem, .setSession,
             .startJob, .updateJob:
            false
        }
    }

    /// The permission needed to commit this kind of operation.
    public var commitPermission: Permission { isDestructive ? .commitDestructive : .commit }
}
