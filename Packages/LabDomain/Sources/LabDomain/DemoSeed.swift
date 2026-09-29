import Foundation

/// The complete original content of the demo namespace, which Reset Demo restores.
///
/// A seed validates itself when it is created or decoded: it has a version of at least 1, names at
/// least one collection, uses every identifier once, puts every item in a collection it also
/// names, and holds at most `maximumEntityCount` entities. Its identifiers are stable, which is
/// what lets Reset Demo restore an edited sample instead of adding a second copy.
public struct DemoSeed: Hashable, Sendable, Codable {
    public static let maximumEntityCount = 200

    /// Increases whenever the seed's content changes.
    public let version: Int
    public let collections: [CollectionDraft]
    public let items: [ItemDraft]

    public init(version: Int, collections: [CollectionDraft], items: [ItemDraft]) throws(DemoSeedError) {
        guard version >= 1 else { throw .unsupportedVersion(version) }
        guard !collections.isEmpty else { throw .noCollections }
        let count = collections.count + items.count
        guard count <= Self.maximumEntityCount else { throw .tooManyEntities(limit: Self.maximumEntityCount) }
        var seen = Set<UUID>()
        for id in collections.map(\.id.rawValue) + items.map(\.id.rawValue) {
            guard seen.insert(id).inserted else { throw .duplicateID(id) }
        }
        let collectionIDs = Set(collections.map(\.id))
        for item in items where !collectionIDs.contains(item.collectionID) {
            throw .unknownCollection(item: item.id, collection: item.collectionID)
        }
        self.version = version
        self.collections = collections
        self.items = items
    }

    public var entityCount: Int { collections.count + items.count }

    private enum CodingKeys: String, CodingKey {
        case version
        case collections
        case items
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            version: container.decode(Int.self, forKey: .version),
            collections: container.decode([CollectionDraft].self, forKey: .collections),
            items: container.decode([ItemDraft].self, forKey: .items)
        )
    }
}

/// Why a demo seed was rejected. Nothing is stored for a rejected seed.
public enum DemoSeedError: Error, Hashable, Sendable {
    case unsupportedVersion(Int)
    case noCollections
    case tooManyEntities(limit: Int)
    /// The identifier appears more than once, for any two entities of either kind.
    case duplicateID(UUID)
    /// The item names a collection the seed does not contain.
    case unknownCollection(item: ItemID, collection: CollectionID)
}
