/// Who owns an entity's lifecycle.
///
/// Everything a person creates or imports is `user` data. `demo` entities are the synthetic
/// samples from the bundled seed: only Reset Demo creates them, and Reset Demo only ever rewrites or
/// removes `demo` entities. An entity never changes namespace, and an item always has its
/// collection's namespace, so nothing a person adds can end up inside the demo.
public enum DataNamespace: String, Hashable, Sendable, Codable, CaseIterable {
    case user
    case demo
}

/// A small named group of items.
///
/// Named `LabCollection` rather than `Collection` so it never shadows the standard library's
/// `Collection` protocol in modules that import LabDomain.
public struct LabCollection: DomainEntity, Identifiable {
    public static let kind = EntityKind.collection

    public let id: CollectionID
    public let title: EntityTitle
    public let isArchived: Bool
    public let revision: Revision
    /// Whether a person owns the collection or it is a demo sample. It never changes.
    public let namespace: DataNamespace

    public init(
        id: CollectionID,
        title: EntityTitle,
        isArchived: Bool = false,
        revision: Revision = .initial,
        namespace: DataNamespace = .user
    ) {
        self.id = id
        self.title = title
        self.isArchived = isArchived
        self.revision = revision
        self.namespace = namespace
    }

    public var reference: EntityReference { .collection(id) }

    /// The next revision with the given fields replaced.
    func revised(title: EntityTitle? = nil, isArchived: Bool? = nil) -> LabCollection {
        LabCollection(
            id: id,
            title: title ?? self.title,
            isArchived: isArchived ?? self.isArchived,
            revision: revision.next(),
            namespace: namespace
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, isArchived, revision, namespace
    }

    /// A value encoded before namespaces existed has no `namespace` and decodes as user data, the
    /// reading under which Reset Demo can never remove it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(CollectionID.self, forKey: .id),
            title: container.decode(EntityTitle.self, forKey: .title),
            isArchived: container.decode(Bool.self, forKey: .isArchived),
            revision: container.decode(Revision.self, forKey: .revision),
            namespace: container.decodeIfPresent(DataNamespace.self, forKey: .namespace) ?? .user
        )
    }
}

/// One object in a collection.
public struct LabItem: DomainEntity, Identifiable {
    public static let kind = EntityKind.item

    public let id: ItemID
    public let collectionID: CollectionID
    public let title: EntityTitle
    public let note: ItemNote
    public let isArchived: Bool
    public let revision: Revision
    /// Always the namespace of the item's collection. It never changes.
    public let namespace: DataNamespace

    public init(
        id: ItemID,
        collectionID: CollectionID,
        title: EntityTitle,
        note: ItemNote = .empty,
        isArchived: Bool = false,
        revision: Revision = .initial,
        namespace: DataNamespace = .user
    ) {
        self.id = id
        self.collectionID = collectionID
        self.title = title
        self.note = note
        self.isArchived = isArchived
        self.revision = revision
        self.namespace = namespace
    }

    public var reference: EntityReference { .item(id) }

    /// The next revision with the given fields replaced.
    func revised(title: EntityTitle? = nil, note: ItemNote? = nil, isArchived: Bool? = nil) -> LabItem {
        LabItem(
            id: id,
            collectionID: collectionID,
            title: title ?? self.title,
            note: note ?? self.note,
            isArchived: isArchived ?? self.isArchived,
            revision: revision.next(),
            namespace: namespace
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, collectionID, title, note, isArchived, revision, namespace
    }

    /// A value encoded before namespaces existed has no `namespace` and decodes as user data.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(ItemID.self, forKey: .id),
            collectionID: container.decode(CollectionID.self, forKey: .collectionID),
            title: container.decode(EntityTitle.self, forKey: .title),
            note: container.decode(ItemNote.self, forKey: .note),
            isArchived: container.decode(Bool.self, forKey: .isArchived),
            revision: container.decode(Revision.self, forKey: .revision),
            namespace: container.decodeIfPresent(DataNamespace.self, forKey: .namespace) ?? .user
        )
    }
}
