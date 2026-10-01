import Foundation
import LabDomain

/// LAB-006's shared names: the experiment's ID in the catalog and its title.
public enum FindTheThing {
    public static let id = "LAB-006"
    public static let title = "Find the Thing"
    public static let symbol = "magnifyingglass"
}

/// A stable identifier for one searchable record.
///
/// It is a UUID, never a title or a list position. When the record is a lab item, this is that
/// item's ID, so the citation and the item are the same record.
public struct SearchRecordID: Hashable, Sendable, Codable, RawRepresentable, CustomStringConvertible, Identifiable {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var id: UUID { rawValue }
    public var description: String { rawValue.uuidString }
}

/// An in-app link to one indexed record.
///
/// The URL is a stable name the lab uses inside the app. This build does not register it as a
/// system URL type, and it is not a claim that another app, or Spotlight across the Mac, can open it.
public struct SearchDeepLink: Hashable, Sendable, Codable {
    public let recordID: SearchRecordID

    public init(recordID: SearchRecordID) {
        self.recordID = recordID
    }

    public var url: URL {
        URL(string: "nativelab://find/\(recordID.rawValue.uuidString)")!
    }
}

/// The lab item a record stands for, at the revision the index last saw.
public struct LabItemBinding: Hashable, Sendable, Codable {
    public let id: ItemID
    public let revision: Revision

    public init(id: ItemID, revision: Revision) {
        self.id = id
        self.revision = revision
    }
}

/// One record the shelf may offer to the app index.
///
/// `optedIn` is the person's choice. A record that is not opted in is never stored, never donated,
/// and never returned as a hit. `isPrivate` marks a record the person can remove from the index
/// with an explicit delete; it does not by itself put the record into the index.
public struct SearchDocument: Hashable, Sendable, Codable, Identifiable {
    public let id: SearchRecordID
    public let title: String
    public let body: String
    public let revision: Int
    public let optedIn: Bool
    public let isPrivate: Bool
    public let labItem: LabItemBinding?

    public init(
        id: SearchRecordID,
        title: String,
        body: String,
        revision: Int = 1,
        optedIn: Bool,
        isPrivate: Bool = false,
        labItem: LabItemBinding? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.revision = revision
        self.optedIn = optedIn
        self.isPrivate = isPrivate
        self.labItem = labItem
    }

    public var deepLink: SearchDeepLink { SearchDeepLink(recordID: id) }
}

/// One match. The same shape whether the match came from lexical search or from semantic retrieval.
public struct SearchHit: Hashable, Sendable, Codable, Identifiable {
    public let documentID: SearchRecordID
    public let title: String
    public let snippet: String
    public let deepLink: SearchDeepLink
    /// 1 for the first hit. Order is the order the search returned.
    public let rank: Int

    public var id: SearchRecordID { documentID }

    init(document: SearchDocument, rank: Int, tokens: [String]) {
        documentID = document.id
        title = document.title
        snippet = Self.snippet(of: document, tokens: tokens)
        deepLink = document.deepLink
        self.rank = rank
    }

    private static func snippet(of document: SearchDocument, tokens: [String]) -> String {
        let source = document.body.isEmpty ? document.title : document.body
        for token in tokens {
            if let range = source.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) {
                return String(source[range.lowerBound...].prefix(80))
            }
        }
        return String(source.prefix(80))
    }
}

/// A record that informed an answer. It always names a hit's ID and that hit's deep link.
public struct EvidencePointer: Hashable, Sendable, Codable, Identifiable {
    public let recordID: SearchRecordID
    public let title: String
    public let deepLink: SearchDeepLink

    public var id: SearchRecordID { recordID }

    public init(recordID: SearchRecordID, title: String, deepLink: SearchDeepLink) {
        self.recordID = recordID
        self.title = title
        self.deepLink = deepLink
    }
}

/// Which search produced the hits. Lexical is the fallback and the path that always runs first.
public enum RetrievalMethod: String, Hashable, Sendable, Codable {
    case lexical
    case semantic
}

/// An answer whose citations are the hits, and nothing else.
public struct SearchAnswer: Hashable, Sendable, Codable {
    public let query: String
    public let prose: String
    public let citations: [EvidencePointer]
    public let hits: [SearchHit]
    public let method: RetrievalMethod

    public init(query: String, hits: [SearchHit], method: RetrievalMethod) {
        self.query = query
        self.hits = hits
        self.method = method
        citations = hits.map { EvidencePointer(recordID: $0.documentID, title: $0.title, deepLink: $0.deepLink) }
        if hits.isEmpty {
            prose = "No records match."
        } else {
            let cited = hits.map { "\($0.title) (\($0.documentID.rawValue.uuidString))" }.joined(separator: "; ")
            let noun = hits.count == 1 ? "record" : "records"
            prose = "\(hits.count) \(noun): \(cited)."
        }
    }
}

/// A query this build will not answer. It carries no hits and no citations.
public struct SearchRefusal: Hashable, Sendable, Codable {
    public let reason: String

    public init(reason: String) { self.reason = reason }
}

public enum SearchOutcome: Hashable, Sendable {
    case answer(SearchAnswer)
    case unsupported(SearchRefusal)
}

/// Counts from one index or reindex. Every record that was not opted in is counted and not stored.
public struct IndexAudit: Hashable, Sendable, Codable {
    public let indexed: Int
    public let updated: Int
    public let unchanged: Int
    public let removed: Int
    public let skippedNotOptedIn: Int
    public let skippedDuplicate: Int

    public init(
        indexed: Int,
        updated: Int,
        unchanged: Int,
        removed: Int,
        skippedNotOptedIn: Int,
        skippedDuplicate: Int
    ) {
        self.indexed = indexed
        self.updated = updated
        self.unchanged = unchanged
        self.removed = removed
        self.skippedNotOptedIn = skippedNotOptedIn
        self.skippedDuplicate = skippedDuplicate
    }

    public var sentence: String {
        "Indexed \(indexed), updated \(updated), unchanged \(unchanged), removed \(removed), skipped \(skippedNotOptedIn) not opted in."
    }
}

/// What a delete did. A conflict receipt means the index was left as it was.
public struct DeleteResult: Hashable, Sendable {
    public let removed: Int
    public let receipts: [ActionReceipt]

    public init(removed: Int, receipts: [ActionReceipt]) {
        self.removed = removed
        self.receipts = receipts
    }

    public var conflict: RevisionConflict? { receipts.first?.conflict }
}
