import Foundation
import LabDomain
@testable import LabStore
import Testing

/// LAB-008-A: an item's extras reach the `extras` column when the item is created, exactly as
/// given, and nothing afterwards rewrites them: not an update, an archive, a restore, a reset, or
/// a relaunch. The in-memory store behaves the same.
@Suite struct ItemExtrasStoreTests {
    static let metadata = #"{"portableObject":{"document":{"kind":"collection-item","title-fr":"crème","n":0.0},"note":"absent","version":1}}"#

    @Test func extrasAreWrittenOnceAndKeptThroughEveryLaterCommit() async throws {
        let directory = try TemporaryDirectory()
        let seed = try RepositoryFixtures.demoSeed()
        let inbox = CollectionID(rawValue: uuid(60))
        let object = ItemID(rawValue: uuid(61))
        let plain = ItemID(rawValue: uuid(62))
        let extras = try ItemExtras(json: Self.metadata)

        do {
            let store = try await SQLiteOperationStore(url: directory.storeURL)
            let service = OperationService(store: store)
            func perform(_ operation: DomainOperation) async throws -> ActionReceipt {
                try await service.perform(OperationRequest(id: RequestID(), operation: operation, actor: .appUI))
            }
            _ = try await perform(.resetDemo(seed: seed))
            _ = try await perform(.createCollection(draft: CollectionDraft(id: inbox, title: "Imports")))
            _ = try await perform(.createItem(draft: ItemDraft(id: object, in: inbox, title: "Imported", extras: extras)))
            _ = try await perform(.createItem(draft: ItemDraft(id: plain, in: inbox, title: "Made here")))

            let raw = try SQLiteDatabase(url: directory.storeURL)
            #expect(try raw.strings("SELECT extras FROM items WHERE id = '\(object)'") == [Self.metadata])
            #expect(try raw.strings("SELECT extras FROM items WHERE id = '\(plain)'") == ["{}"])
            #expect(try await store.item(object)?.extras == extras)
            #expect(try await store.item(plain)?.extras == .empty)

            _ = try await perform(.updateItem(id: object, expected: .r(1), changes: ItemChanges(title: "Renamed", note: "Now with a note")))
            _ = try await perform(.archiveItem(id: object, expected: .r(2)))
            _ = try await perform(.restoreItem(id: object, expected: .r(3)))
            _ = try await perform(.resetDemo(seed: seed))
            #expect(try raw.strings("SELECT extras FROM items WHERE id = '\(object)'") == [Self.metadata])
        }

        let reopened = try await SQLiteOperationStore(url: directory.storeURL)
        let item = try #require(try await reopened.item(object))
        #expect(item.revision == .r(4) && item.title == "Renamed" && item.extras == extras)
        #expect(item.extras.json.utf8.elementsEqual(Self.metadata.utf8))
    }

    @Test func bothStoresAgreeOnExtras() async throws {
        let directory = try TemporaryDirectory()
        let stores: [any OperationStore] = [InMemoryOperationStore(), try await SQLiteOperationStore(url: directory.storeURL)]
        var results: [LabItem] = []
        for store in stores {
            let service = OperationService(store: store)
            func perform(_ operation: DomainOperation) async throws {
                _ = try await service.perform(OperationRequest(id: RequestID(), operation: operation, actor: .appUI))
            }
            let inbox = CollectionID(rawValue: uuid(70))
            let object = ItemID(rawValue: uuid(71))
            try await perform(.createCollection(draft: CollectionDraft(id: inbox, title: "Imports")))
            try await perform(.createItem(draft: ItemDraft(id: object, in: inbox, title: "Imported", extras: try ItemExtras(json: Self.metadata))))
            try await perform(.updateItem(id: object, expected: .r(1), changes: ItemChanges(note: "Edited")))
            results.append(try #require(try await store.item(object)))
        }
        #expect(results[0] == results[1])
        #expect(results[0].extras.json == Self.metadata)
    }
}
