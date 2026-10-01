import Foundation

/// The app's own index. It stores opted-in records only, and it never reads another app's index.
public actor AppSearchIndex {
    private var documents: [SearchRecordID: SearchDocument] = [:]
    private var pendingRemovals: [SearchRecordID] = []
    /// Fixture records a person removed. A reindex of the shelf leaves them out until a reset.
    private var suppressed: Set<SearchRecordID> = []
    /// How many lexical searches have run. A semantic retriever can read this to see that lexical
    /// search already happened.
    public private(set) var lexicalSearchCount = 0

    public init() {}

    public var isEmpty: Bool { documents.isEmpty }

    public func document(_ id: SearchRecordID) -> SearchDocument? { documents[id] }

    public func contains(_ id: SearchRecordID) -> Bool { documents[id] != nil }

    /// Opted-in records, ordered by folded title, then by ID.
    public func snapshot() -> [SearchDocument] {
        documents.values.sorted { lhs, rhs in
            let title = fold(lhs.title).compare(fold(rhs.title))
            if title != .orderedSame { return title == .orderedAscending }
            return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
        }
    }

    public func documents(outside ids: Set<SearchRecordID>) -> [SearchDocument] {
        snapshot().filter { !ids.contains($0.id) }
    }

    public func pendingRemovalIDs() -> [SearchRecordID] { pendingRemovals }

    public func clearPendingRemovals() { pendingRemovals.removeAll() }

    public func suppress(_ id: SearchRecordID) { suppressed.insert(id) }

    public func clearSuppressed() { suppressed.removeAll() }

    public func suppressedIDs() -> Set<SearchRecordID> { suppressed }

    /// Loads the shelf the first time the index is empty. A second caller, after the first has
    /// stored records, changes nothing.
    public func loadShelfIfEmpty() -> IndexAudit? {
        guard documents.isEmpty else { return nil }
        return apply(MessyCollection.corpus)
    }

    /// Replaces the index with the opted-in records in `corpus`. Records that are not opted in are
    /// counted and dropped. A repeated ID keeps the first copy.
    public func apply(_ corpus: [SearchDocument]) -> IndexAudit {
        var seen: Set<SearchRecordID> = []
        var next: [SearchRecordID: SearchDocument] = [:]
        var skippedNotOptedIn = 0
        var skippedDuplicate = 0
        for document in corpus {
            if !document.optedIn {
                skippedNotOptedIn += 1
                continue
            }
            if !seen.insert(document.id).inserted {
                skippedDuplicate += 1
                continue
            }
            next[document.id] = document
        }

        var indexed = 0
        var updated = 0
        var unchanged = 0
        for (id, document) in next {
            if let old = documents[id] {
                if old == document { unchanged += 1 } else { updated += 1 }
            } else {
                indexed += 1
            }
        }
        var removed = 0
        for id in documents.keys where next[id] == nil {
            removed += 1
            noteRemoved(id)
        }
        documents = next
        return IndexAudit(
            indexed: indexed,
            updated: updated,
            unchanged: unchanged,
            removed: removed,
            skippedNotOptedIn: skippedNotOptedIn,
            skippedDuplicate: skippedDuplicate
        )
    }

    /// Removes records that are present. An ID that was never indexed does not count as removed.
    public func delete(_ ids: [SearchRecordID]) -> Int {
        var removed = 0
        for id in ids {
            if documents.removeValue(forKey: id) != nil {
                removed += 1
                noteRemoved(id)
            }
        }
        return removed
    }

    /// Lexical search. Every token must occur, as a whole word, in the title or the body.
    /// Title matches rank above body matches. Ties break by folded title, then by ID.
    func lexicalHits(matching query: ValidatedQuery, limit: Int) -> [SearchHit] {
        lexicalSearchCount += 1
        let ranked = documents.values.compactMap { document -> (SearchDocument, Int)? in
            let score = score(document, tokens: query.tokens)
            guard score > 0 else { return nil }
            return (document, score)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            let title = fold(lhs.0.title).compare(fold(rhs.0.title))
            if title != .orderedSame { return title == .orderedAscending }
            return lhs.0.id.rawValue.uuidString < rhs.0.id.rawValue.uuidString
        }
        return Array(ranked.prefix(max(limit, 0))).enumerated().map { offset, pair in
            SearchHit(document: pair.0, rank: offset + 1, tokens: query.tokens)
        }
    }

    /// Hits for IDs the index actually holds, in the order given. An ID that is not indexed is
    /// dropped, so a retriever cannot introduce a record.
    func hits(keeping ids: [SearchRecordID], matching query: ValidatedQuery, limit: Int) -> [SearchHit] {
        var hits: [SearchHit] = []
        var seen: Set<SearchRecordID> = []
        for id in ids {
            guard hits.count < limit, seen.insert(id).inserted, let document = documents[id] else { continue }
            hits.append(SearchHit(document: document, rank: hits.count + 1, tokens: query.tokens))
        }
        return hits
    }

    private func score(_ document: SearchDocument, tokens: [String]) -> Int {
        let titleTokens = Set(tokenize(fold(document.title)))
        let bodyTokens = Set(tokenize(fold(document.body)))
        var score = 0
        for token in tokens {
            let inTitle = titleTokens.contains(token)
            let inBody = bodyTokens.contains(token)
            if !inTitle && !inBody { return 0 }
            if inTitle { score += 2 }
            if inBody { score += 1 }
        }
        return score
    }

    private func noteRemoved(_ id: SearchRecordID) {
        if !pendingRemovals.contains(id) { pendingRemovals.append(id) }
    }
}
