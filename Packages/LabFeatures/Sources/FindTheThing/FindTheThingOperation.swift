import Foundation
import LabDomain

/// Search, index, delete, and reindex for Find the Thing.
///
/// Lexical search always runs before an available semantic retriever. A retriever's ID is kept
/// only when the app index holds it. Deleting a lab item archives it through the backend, which
/// is the domain's authorization and receipt path, and the index drops the record only after that
/// archive is admitted. A cancelled call changes nothing.
public struct FindTheThingOperation: Sendable {
    public let index: AppSearchIndex
    private let backend: any FindTheThingBackend
    private let retriever: any SemanticRetriever
    private let donor: any AppIndexDonor

    public init(
        index: AppSearchIndex = AppSearchIndex(),
        backend: any FindTheThingBackend = UnavailableFindBackend(),
        retriever: any SemanticRetriever = UnavailableSemanticRetriever(),
        donor: any AppIndexDonor = IdleAppIndexDonor()
    ) {
        self.index = index
        self.backend = backend
        self.retriever = retriever
        self.donor = donor
    }

    /// The shelf, the first time this index is empty.
    public func loadShelfIfEmpty(as actor: ActorScope) async throws(FindTheThingError) -> IndexAudit? {
        try checkCancelled()
        try authorize(.reindex, actor: actor)
        return await index.loadShelfIfEmpty()
    }

    public func reindex(_ corpus: [SearchDocument], as actor: ActorScope) async throws(FindTheThingError) -> IndexAudit {
        try checkCancelled()
        try authorize(.reindex, actor: actor)
        return await index.apply(corpus)
    }

    /// Rebuilds the shelf. Fixture records a person has deleted stay out. Records that are not part
    /// of the shelf stay indexed.
    public func reindexShelf(as actor: ActorScope) async throws(FindTheThingError) -> IndexAudit {
        let suppressed = await index.suppressedIDs()
        let kept = await index.documents(outside: MessyCollection.ids)
        let shelf = MessyCollection.corpus.filter { !suppressed.contains($0.id) }
        return try await reindex(shelf + kept, as: actor)
    }

    /// Restores the fixture shelf and leaves every other indexed record in place.
    public func resetFixtures(as actor: ActorScope) async throws(FindTheThingError) -> IndexAudit {
        try checkCancelled()
        try authorize(.reindex, actor: actor)
        await index.clearSuppressed()
        let kept = await index.documents(outside: MessyCollection.ids)
        return await index.apply(MessyCollection.corpus + kept)
    }

    public func search(_ raw: String, as actor: ActorScope, limit: Int = 20) async throws(FindTheThingError) -> SearchOutcome {
        try checkCancelled()
        try authorize(.read, actor: actor)
        switch SearchText.validate(raw) {
        case .unsupported(let refusal):
            return .unsupported(refusal)
        case .query(let query):
            let lexical = await index.lexicalHits(matching: query, limit: limit)
            guard retriever.isAvailable else {
                return .answer(SearchAnswer(query: query.text, hits: lexical, method: .lexical))
            }
            try checkCancelled()
            let proposed = await retriever.retrieve(query.text, limit: limit)
            let known = await index.hits(keeping: proposed, matching: query, limit: limit)
            return .answer(SearchAnswer(query: query.text, hits: known, method: .semantic))
        }
    }

    /// Removes records from the app index.
    ///
    /// A lab item is archived first, through the backend. A conflict leaves the record indexed.
    /// An item that is already archived or already gone is dropped from the index, because the
    /// private data is already out of the lab. A record that is not a lab item is dropped after
    /// the same permission check, and it has no store receipt.
    public func delete(
        _ ids: [SearchRecordID],
        as actor: ActorScope,
        requestID: RequestID = RequestID()
    ) async throws(FindTheThingError) -> DeleteResult {
        try checkCancelled()
        try authorize(.delete, actor: actor)
        var receipts: [ActionReceipt] = []
        var removable: [SearchRecordID] = []
        var usedPrimaryRequest = false
        for id in ids {
            guard let document = await index.document(id) else { continue }
            try checkCancelled()
            if let binding = document.labItem {
                let archiveRequest = usedPrimaryRequest ? RequestID() : requestID
                usedPrimaryRequest = true
                do {
                    let receipt = try await backend.archiveItem(
                        id: binding.id,
                        expected: binding.revision,
                        actor: actor,
                        requestID: archiveRequest
                    )
                    if receipt.conflict != nil {
                        // Earlier archives already committed; drop those from the index. The
                        // conflicted record stays indexed.
                        let removed = await index.delete(removable)
                        return DeleteResult(removed: removed, receipts: receipts + [receipt])
                    }
                    receipts.append(receipt)
                } catch .alreadyArchived, .missingItem {
                    // The lab no longer holds this record. It still leaves the app index.
                }
            }
            if MessyCollection.ids.contains(id) { await index.suppress(id) }
            removable.append(id)
        }
        let removed = await index.delete(removable)
        return DeleteResult(removed: removed, receipts: receipts)
    }

    /// Sends the current index, and the IDs removed since the last donation, to the donor.
    /// This is a separate action from search. The idle donor does not touch a system index.
    public func donate(as actor: ActorScope) async throws(FindTheThingError) -> DonationReport {
        try checkCancelled()
        try authorize(.reindex, actor: actor)
        let present = await index.snapshot()
        let removed = await index.pendingRemovalIDs()
        let report = await donor.sync(present: present, removed: removed)
        if report.status != .failed {
            await index.clearPendingRemovals()
        }
        return report
    }

    private func checkCancelled() throws(FindTheThingError) {
        if Task.isCancelled { throw .cancelled }
    }

    private func authorize(_ access: IndexAccess, actor: ActorScope) throws(FindTheThingError) {
        let required = access.required
        if !actor.adapter.ceiling.contains(required) {
            throw .unauthorized(adapter: actor.adapter, required: required, reason: .outsideAdapterCeiling)
        }
        if !actor.grants.contains(required) {
            throw .unauthorized(adapter: actor.adapter, required: required, reason: .notGranted)
        }
    }
}

private enum IndexAccess {
    case read
    case reindex
    case delete

    var required: Permission {
        switch self {
        case .read: .read
        case .reindex: .commit
        case .delete: .commitDestructive
        }
    }
}
