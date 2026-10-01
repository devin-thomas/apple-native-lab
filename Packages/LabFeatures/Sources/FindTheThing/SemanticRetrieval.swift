import Foundation

/// Optional retrieval that runs only after lexical search.
///
/// It returns record IDs. The operation keeps an ID only when the app index holds that record, so
/// a retriever cannot add a record that was never opted in. The built-in retriever is unavailable,
/// which is the lexical fallback.
public protocol SemanticRetriever: Sendable {
    var isAvailable: Bool { get }
    func retrieve(_ query: String, limit: Int) async -> [SearchRecordID]
}

/// Semantic retrieval is not available. Search uses the lexical hits.
public struct UnavailableSemanticRetriever: SemanticRetriever {
    public init() {}

    public var isAvailable: Bool { false }

    public func retrieve(_ query: String, limit: Int) async -> [SearchRecordID] { [] }
}

/// What a donation of the app index reported. `notDonated` means this run did not touch a system index.
public struct DonationReport: Hashable, Sendable {
    public enum Status: String, Hashable, Sendable {
        case notDonated
        case donated
        case failed
    }

    public let indexed: Int
    public let removed: Int
    public let status: Status

    public init(indexed: Int, removed: Int, status: Status) {
        self.indexed = indexed
        self.removed = removed
        self.status = status
    }
}

/// Receives the records the app index holds and the IDs it has dropped since the last donation.
///
/// The idle donor records nothing outside the process. A host may supply a donor that updates the
/// app's own index of these records. A donor is not a search of other apps.
public protocol AppIndexDonor: Sendable {
    func sync(present: [SearchDocument], removed: [SearchRecordID]) async -> DonationReport
}

public struct IdleAppIndexDonor: AppIndexDonor {
    public init() {}

    public func sync(present: [SearchDocument], removed: [SearchRecordID]) async -> DonationReport {
        DonationReport(indexed: 0, removed: 0, status: .notDonated)
    }
}
