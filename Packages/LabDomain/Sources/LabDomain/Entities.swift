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

    public init(id: CollectionID, title: EntityTitle, isArchived: Bool = false, revision: Revision = .initial) {
        self.id = id
        self.title = title
        self.isArchived = isArchived
        self.revision = revision
    }

    public var reference: EntityReference { .collection(id) }

    /// The next revision with the given fields replaced.
    func revised(title: EntityTitle? = nil, isArchived: Bool? = nil) -> LabCollection {
        LabCollection(
            id: id,
            title: title ?? self.title,
            isArchived: isArchived ?? self.isArchived,
            revision: revision.next()
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

    public init(
        id: ItemID,
        collectionID: CollectionID,
        title: EntityTitle,
        note: ItemNote = .empty,
        isArchived: Bool = false,
        revision: Revision = .initial
    ) {
        self.id = id
        self.collectionID = collectionID
        self.title = title
        self.note = note
        self.isArchived = isArchived
        self.revision = revision
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
            revision: revision.next()
        )
    }
}
