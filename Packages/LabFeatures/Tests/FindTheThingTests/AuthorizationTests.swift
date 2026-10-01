import FindTheThing
import Foundation
import LabDomain
import Testing

/// Deletes of a lab item go through `OperationService`. A model tool can search and cannot delete,
/// reindex, or donate. A stale revision and an unavailable store leave the index as it was.
@Suite struct AuthorizationTests {
    private let word = "locktoken"

    @Test func aModelToolCanSearchAndCannotChangeTheIndex() async throws {
        let operation = try await loadedOperation()
        let answer = try #require(answer(try await operation.search("cedar", as: Actors.model)))
        #expect(answer.citations.count == 2)

        await #expect(throws: FindTheThingError.unauthorized(adapter: .modelTool, required: .commitDestructive, reason: .outsideAdapterCeiling)) {
            try await operation.delete([MessyCollection.lockerNote.id], as: Actors.model)
        }
        await #expect(throws: FindTheThingError.unauthorized(adapter: .modelTool, required: .commit, reason: .outsideAdapterCeiling)) {
            try await operation.reindex(MessyCollection.corpus, as: Actors.model)
        }
        await #expect(throws: FindTheThingError.unauthorized(adapter: .modelTool, required: .commit, reason: .outsideAdapterCeiling)) {
            try await operation.donate(as: Actors.model)
        }
        #expect(await operation.index.contains(MessyCollection.lockerNote.id))
    }

    @Test func aReaderCannotDelete() async throws {
        let operation = try await loadedOperation()
        await #expect(throws: FindTheThingError.unauthorized(adapter: .appUI, required: .commitDestructive, reason: .notGranted)) {
            try await operation.delete([MessyCollection.lockerNote.id], as: Actors.reader)
        }
        #expect(await operation.index.contains(MessyCollection.lockerNote.id))
    }

    @Test func archivingALabItemRemovesItFromTheIndexAndKeepsTheReceipt() async throws {
        let lab = TestLab()
        let item = try await lab.makeItem(note: "The private word is \(word).")
        let operation = FindTheThingOperation(backend: lab.backend())
        let document = item.document(body: "The private word is \(word).")
        _ = try await operation.reindex([document], as: Actors.app)
        let request = RequestID()

        let result = try await operation.delete([document.id], as: Actors.app, requestID: request)
        #expect(result.removed == 1)
        #expect(result.conflict == nil)
        let receipt = try #require(result.receipts.first)
        #expect(receipt.admitted.adapter == .appUI)
        #expect(receipt.admitted.operation.kind == .archiveItem)
        #expect(receipt.requestID == request)
        #expect(try await lab.service.findReceipt(for: request, as: Actors.app) == receipt)

        let stored = try await lab.service.findItem(item.id, as: Actors.app)
        #expect(stored.isArchived)
        #expect(stored.revision == Revision.initial.next())
        let answer = try #require(answer(try await operation.search(word, as: Actors.app)))
        #expect(answer.hits.isEmpty)
        #expect(answer.citations.isEmpty)

        let replay = try await lab.perform(.archiveItem(id: item.id, expected: .initial), requestID: request)
        #expect(replay == receipt)
        #expect(try await lab.service.findItem(item.id, as: Actors.app).revision == Revision.initial.next())

        let second = try await operation.delete([document.id], as: Actors.app, requestID: RequestID())
        #expect(second.removed == 0)
    }

    @Test func aStaleRevisionLeavesTheRecordIndexed() async throws {
        let lab = TestLab()
        let item = try await lab.makeItem(note: "The private word is \(word).")
        let operation = FindTheThingOperation(backend: lab.backend())
        _ = try await operation.reindex([item.document(body: "The private word is \(word).")], as: Actors.app)
        _ = try await lab.perform(.updateItem(
            id: item.id,
            expected: .initial,
            changes: try ItemChanges(note: try ItemNote("The private word is \(word) still."))
        ))

        let result = try await operation.delete([item.documentID], as: Actors.app)
        let conflict = try #require(result.conflict)
        #expect(conflict.expected == .initial)
        #expect(conflict.current == .initial.next())
        #expect(result.removed == 0)
        #expect(await operation.index.contains(item.documentID))
        let answer = try #require(answer(try await operation.search(word, as: Actors.app)))
        #expect(answer.citations.map(\.recordID) == [item.documentID])
        #expect(try await lab.service.findItem(item.id, as: Actors.app).isArchived == false)
    }

    @Test func anUnavailableStoreLeavesTheLabRecordIndexed() async throws {
        let item = ItemID()
        let document = SearchDocument(
            id: SearchRecordID(rawValue: item.rawValue),
            title: "Locker card",
            body: "The private word is \(word).",
            optedIn: true,
            isPrivate: true,
            labItem: LabItemBinding(id: item, revision: .initial)
        )
        let operation = FindTheThingOperation()
        _ = try await operation.reindex([document], as: Actors.app)
        await #expect(throws: FindTheThingError.self) {
            try await operation.delete([document.id], as: Actors.app)
        }
        #expect(await operation.index.contains(document.id))
    }

    @Test func anAlreadyArchivedItemIsDroppedFromTheIndex() async throws {
        let lab = TestLab()
        let item = try await lab.makeItem(note: "The private word is \(word).")
        _ = try await lab.perform(.archiveItem(id: item.id, expected: .initial))
        let operation = FindTheThingOperation(backend: lab.backend())
        _ = try await operation.reindex(
            [item.document(body: "The private word is \(word).", revision: Revision.initial.next())],
            as: Actors.app
        )

        let result = try await operation.delete([item.documentID], as: Actors.app)
        #expect(result.removed == 1)
        #expect(result.receipts.isEmpty)
        #expect(await operation.index.contains(item.documentID) == false)
        #expect(try await lab.service.findItem(item.id, as: Actors.app).revision == Revision.initial.next())
    }

    @Test func aCancelledDeleteArchivesNothing() async throws {
        let lab = TestLab()
        let item = try await lab.makeItem(note: "The private word is \(word).")
        let operation = FindTheThingOperation(backend: lab.backend())
        let document = item.document(body: "The private word is \(word).")
        _ = try await operation.reindex([document], as: Actors.app)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await operation.delete([document.id], as: Actors.app)
        }
        await #expect(throws: FindTheThingError.cancelled) { try await task.value }
        #expect(await operation.index.contains(document.id))
        #expect(try await lab.service.findItem(item.id, as: Actors.app).isArchived == false)
    }
}

private func answer(_ outcome: SearchOutcome) -> SearchAnswer? {
    guard case .answer(let answer) = outcome else { return nil }
    return answer
}

private struct StoredItem {
    let id: ItemID
    let collection: CollectionID
    var documentID: SearchRecordID { SearchRecordID(rawValue: id.rawValue) }

    func document(body: String, revision: Revision = .initial) -> SearchDocument {
        SearchDocument(
            id: documentID,
            title: "Locker card",
            body: body,
            optedIn: true,
            isPrivate: true,
            labItem: LabItemBinding(id: id, revision: revision)
        )
    }
}

extension TestLab {
    fileprivate func makeItem(note: String) async throws -> StoredItem {
        let collection = CollectionID()
        let item = ItemID()
        _ = try await perform(.createCollection(draft: CollectionDraft(
            id: collection, title: try EntityTitle("Shelf notes")
        )))
        _ = try await perform(.createItem(draft: ItemDraft(
            id: item, in: collection, title: try EntityTitle("Locker card"), note: try ItemNote(note)
        )))
        return StoredItem(id: item, collection: collection)
    }
}
