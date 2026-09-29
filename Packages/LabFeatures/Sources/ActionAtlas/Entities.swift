import AppIntents
import Foundation
import LabDomain

/// A lab item as Shortcuts, Siri, and Spotlight see it: a snapshot at one revision.
///
/// Its identity is the item's stable UUID, so a renamed item still resolves. The snapshot is not
/// a guarantee: every change re-reads the item and commits against the revision here, so a stale
/// snapshot records a conflict instead of overwriting newer state. It grants no access; every
/// read and change goes through the operation service.
public struct LabItemEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Lab Item", numericFormat: "\(placeholder: .int) lab items"
    )
    public static let defaultQuery = LabItemQuery()

    public let id: UUID
    public let collectionID: UUID
    @Property(title: "Title") public var title: String
    @Property(title: "Note") public var note: String
    @Property(title: "Collection") public var collectionTitle: String
    @Property(title: "Archived") public var isArchived: Bool
    @Property(title: "Revision") public var revision: Int
    @Property(title: "Demo Sample") public var isDemoSample: Bool

    public init(_ item: LabItem, collectionTitle: String?) {
        id = item.id.rawValue
        collectionID = item.collectionID.rawValue
        title = item.title.value
        note = item.note.value
        self.collectionTitle = collectionTitle ?? ""
        isArchived = item.isArchived
        revision = item.revision.rawValue
        isDemoSample = item.namespace == .demo
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    /// Collection, then "Archived" or "Demo sample" when they apply.
    public var subtitle: String {
        [collectionTitle.isEmpty ? nil : collectionTitle, isArchived ? "Archived" : nil, isDemoSample ? "Demo sample" : nil]
            .compactMap(\.self).joined(separator: " · ")
    }

    public var itemID: ItemID { ItemID(rawValue: id) }

    /// The revision this snapshot saw. A value below 1 cannot come from the store.
    func expectedRevision() throws(ActionAtlasError) -> Revision {
        guard let revision = Revision(rawValue: revision) else { throw .missingItem(itemID) }
        return revision
    }
}

/// A collection as Shortcuts and Siri see it.
public struct LabCollectionEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Lab Collection", numericFormat: "\(placeholder: .int) lab collections"
    )
    public static let defaultQuery = LabCollectionQuery()

    public let id: UUID
    @Property(title: "Title") public var title: String
    @Property(title: "Archived") public var isArchived: Bool
    @Property(title: "Revision") public var revision: Int
    @Property(title: "Demo Collection") public var isDemo: Bool

    public init(_ collection: LabCollection) {
        id = collection.id.rawValue
        title = collection.title.value
        isArchived = collection.isArchived
        revision = collection.revision.rawValue
        isDemo = collection.namespace == .demo
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    public var subtitle: String {
        [isDemo ? "Demo · samples only" : "Yours", isArchived ? "Archived" : nil]
            .compactMap(\.self).joined(separator: " · ")
    }

    public var collectionID: CollectionID { CollectionID(rawValue: id) }
}

// MARK: - Entity queries

/// Resolves stored item references and text through the operation service as an App Intent.
///
/// An identifier that no longer exists is left out, which the system reports as a missing item.
/// Text that matches several items returns all of them, so the system asks which one was meant.
public struct LabItemQuery: EntityStringQuery {
    @Dependency(default: ActionAtlasLink.unavailable) private var atlas: ActionAtlasLink

    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [LabItemEntity] {
        try await ItemLookup(actions: atlas.actions(.appIntent)).entities(for: identifiers.map(ItemID.init(rawValue:)))
    }

    public func entities(matching string: String) async throws -> [LabItemEntity] {
        try await ItemLookup(actions: atlas.actions(.appIntent)).entities(matching: string)
    }

    public func suggestedEntities() async throws -> [LabItemEntity] {
        try await ItemLookup(actions: atlas.actions(.appIntent)).suggested()
    }
}

/// Resolves stored collection references and text, suggesting the person's own collections first.
public struct LabCollectionQuery: EntityStringQuery {
    @Dependency(default: ActionAtlasLink.unavailable) private var atlas: ActionAtlasLink

    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [LabCollectionEntity] {
        try await atlas.actions(.appIntent).collections(ids: identifiers.map(CollectionID.init(rawValue:)))
            .map(LabCollectionEntity.init)
    }

    public func entities(matching string: String) async throws -> [LabCollectionEntity] {
        try await CollectionLookup(actions: atlas.actions(.appIntent)).entities(matching: string, ownOnly: false)
    }

    public func suggestedEntities() async throws -> [LabCollectionEntity] {
        try await atlas.actions(.appIntent).collections().map(LabCollectionEntity.init)
    }
}

/// Offers only the person's own collections, for choosing where a new item goes.
public struct OwnCollectionOptions: DynamicOptionsProvider {
    @Dependency(default: ActionAtlasLink.unavailable) private var atlas: ActionAtlasLink

    public init() {}

    public func results() async throws -> [LabCollectionEntity] {
        try await atlas.actions(.appIntent).collectionsOfYourOwn().map(LabCollectionEntity.init)
    }
}

// MARK: - Lookups shared by queries and tests

/// The item lookups behind `LabItemQuery`, callable without the system.
struct ItemLookup: Sendable {
    static let suggestionLimit = 50
    let actions: ActionAtlasActions

    func entities(for ids: [ItemID]) async throws(ActionAtlasError) -> [LabItemEntity] {
        try await entities(actions.items(ids: ids))
    }

    /// Every item whose title or note matches, archived ones included, so Restore can find them.
    func entities(matching text: String) async throws(ActionAtlasError) -> [LabItemEntity] {
        try await entities(actions.findItems(text: text, includeArchived: true, limit: Self.suggestionLimit))
    }

    func suggested() async throws(ActionAtlasError) -> [LabItemEntity] {
        try await entities(actions.findItems(includeArchived: true, limit: Self.suggestionLimit))
    }

    func entities(_ items: [LabItem]) async throws(ActionAtlasError) -> [LabItemEntity] {
        let titles = try await actions.collectionTitles(for: items)
        return items.map { LabItemEntity($0, collectionTitle: titles[$0.collectionID]) }
    }
}

/// The collection lookups behind `LabCollectionQuery`, callable without the system.
struct CollectionLookup: Sendable {
    let actions: ActionAtlasActions

    /// Collections whose title contains `text`, ignoring case and diacritics.
    func entities(matching text: String, ownOnly: Bool) async throws(ActionAtlasError) -> [LabCollectionEntity] {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = ownOnly ? try await actions.collectionsOfYourOwn() : try await actions.collections()
        return candidates
            .filter { needle.isEmpty || $0.title.value.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .map(LabCollectionEntity.init)
    }
}
