import Foundation

#if os(iOS) || os(macOS)
import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers

/// The app index entity queries read. The host registers one at launch. Until it does, queries
/// read an empty index and return nothing.
public final class FindTheThingLink: Sendable {
    public let index: AppSearchIndex

    public init(index: AppSearchIndex) {
        self.index = index
    }

    public static let empty = FindTheThingLink(index: AppSearchIndex())
}

/// Lets a host include this experiment's indexed records in its App Intents metadata.
public struct FindTheThingIntentsPackage: AppIntentsPackage {}

/// One opted-in record as an indexed app entity.
///
/// Its identifier is the record's stable UUID. Building one from a record that is not opted in
/// fails, so a donation cannot add it. The entity is a snapshot for the app's own index. It does
/// not search other apps.
public struct FindRecordEntity: IndexedEntity, Equatable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Indexed Record")
    public static let defaultQuery = FindRecordQuery()

    public let id: UUID
    public let title: String
    public let body: String

    public init?(_ document: SearchDocument) {
        guard document.optedIn else { return nil }
        id = document.id.rawValue
        title = document.title
        body = document.body
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    public var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .plainText)
        set.title = title
        set.contentDescription = body
        return set
    }
}

enum IndexedRecordBuilder {
    static func entities(from documents: [SearchDocument]) -> [FindRecordEntity] {
        documents.compactMap(FindRecordEntity.init)
    }
}

/// Donates opted-in records to this app's index, and deletes only the record IDs it is given,
/// and only for this entity. It does not run a system-wide search.
public struct IndexedEntityDonor: AppIndexDonor {
    public init() {}

    public func sync(present: [SearchDocument], removed: [SearchRecordID]) async -> DonationReport {
        let entities = IndexedRecordBuilder.entities(from: present)
        guard !entities.isEmpty || !removed.isEmpty else {
            return DonationReport(indexed: 0, removed: 0, status: .donated)
        }
        let searchable = CSSearchableIndex.default()
        do {
            if !removed.isEmpty {
                try await searchable.deleteAppEntities(identifiedBy: removed.map(\.rawValue), ofType: FindRecordEntity.self)
            }
            if !entities.isEmpty {
                try await searchable.indexAppEntities(entities)
            }
            return DonationReport(indexed: entities.count, removed: removed.count, status: .donated)
        } catch {
            return DonationReport(indexed: 0, removed: 0, status: .failed)
        }
    }
}

/// Resolves indexed records from the app index only. Text uses the same lexical search as the
/// in-app fallback. An identifier the index does not hold is left out.
public struct FindRecordQuery: EntityStringQuery {
    @Dependency(default: FindTheThingLink.empty) private var link: FindTheThingLink

    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [FindRecordEntity] {
        var found: [FindRecordEntity] = []
        for identifier in identifiers {
            guard let document = await link.index.document(SearchRecordID(rawValue: identifier)),
                  let entity = FindRecordEntity(document) else { continue }
            found.append(entity)
        }
        return found
    }

    public func entities(matching string: String) async throws -> [FindRecordEntity] {
        guard case .query(let query) = SearchText.validate(string) else { return [] }
        let hits = await link.index.lexicalHits(matching: query, limit: 20)
        var found: [FindRecordEntity] = []
        for hit in hits {
            guard let document = await link.index.document(hit.documentID),
                  let entity = FindRecordEntity(document) else { continue }
            found.append(entity)
        }
        return found
    }

    public func suggestedEntities() async throws -> [FindRecordEntity] {
        IndexedRecordBuilder.entities(from: Array(await link.index.snapshot().prefix(10)))
    }
}
#endif

/// The donor a host uses when a person asks to update the app index. On Watch and Apple TV, where
/// this indexing API is unavailable, it is the idle donor.
public enum FindTheThingDonation {
    public static var live: any AppIndexDonor {
        #if os(iOS) || os(macOS)
        IndexedEntityDonor()
        #else
        IdleAppIndexDonor()
        #endif
    }
}
