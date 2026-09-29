import Foundation
import LabDomain
@testable import LabStore
import Testing

/// CORE-003 acceptance: Reset Demo preserves a deliberately imported user record. Also pins the
/// repository's demo seed, which LAB-001 needs as 12 original samples with stable UUIDs.
@Suite struct ResetDemoTests {
    static let collectionIDs = [
        "A40194B3-5E91-4C5C-AE02-CF703BE23224",
        "A222A032-267A-4208-B1F9-F55D739D3C24",
        "E7EEE9BB-FA3B-41F1-805E-41BDB71B44A3",
    ]

    static let itemIDs = [
        "DB666EF1-F642-43F1-B415-895B6ECFF693", "9B97BF2F-4D0B-4197-9CA8-36489DF40455",
        "3A1711A8-E1DB-489E-8321-414266A8DF49", "C8E1904C-E8DC-40A0-93D3-53F6C0FFF95D",
        "AF451890-CA80-4DE9-B18B-4007066C9177", "D279FB0E-642E-463A-B3DA-299442A1C7CB",
        "0FCB968F-7FEC-452A-A67C-20773B9C7761", "C6468C0B-4BF6-48E8-AE5D-F5FC7A041097",
        "8223D442-4B96-4026-B686-99CCFA09F1E8", "6933AC83-9E61-4264-8EB8-0535B3C5E0F8",
        "6E2CED9D-B946-4188-8417-2E85C6A7268C", "E8E32999-AA3C-47C7-A530-2ABEE1EECC57",
    ]

    @Test func theRepositorySeedIsTwelveOriginalSamplesWithStableIDs() throws {
        let fixture = try DemoFixture(contentsOf: RepositoryFixtures.demoSeedURL)
        #expect(fixture.seed.version == 1)
        #expect(fixture.seed.collections.map(\.id.description) == Self.collectionIDs)
        #expect(fixture.seed.items.map(\.id.description) == Self.itemIDs)
        #expect(Set(fixture.seed.items.map(\.title)).count == 12)
        #expect(fixture.seed.items.allSatisfy { !$0.note.value.isEmpty })
        #expect(fixture.provenance.contains("Original synthetic sample data"))

        // Loading is deterministic, and the digest names the exact bytes, not just the content.
        #expect(try DemoFixture(contentsOf: RepositoryFixtures.demoSeedURL) == fixture)
        let data = try RepositoryFixtures.demoSeedData()
        let compact = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data))
        let recompacted = try DemoFixture(data: compact)
        #expect(recompacted.seed == fixture.seed)
        #expect(recompacted.sha256 != fixture.sha256)
    }

    @Test func resetDemoPreservesADeliberatelyImportedUserRecord() async throws {
        let directory = try TemporaryDirectory()
        let seed = try RepositoryFixtures.demoSeed()
        let inbox = CollectionID(rawValue: uuid(40))
        let record = ItemID(rawValue: uuid(41))
        let importMetadata = #"{"x-import":{"source":"share-extension","bytes":2048}}"#

        do {
            let store = try await SQLiteOperationStore(url: directory.storeURL)
            let service = OperationService(store: store)
            func perform(_ operation: DomainOperation, as actor: ActorScope = .appUI) async throws -> ActionReceipt {
                try await service.perform(OperationRequest(id: RequestID(), operation: operation, actor: actor))
            }

            // First run: the samples arrive through the same authorized operation as a reset.
            let firstRun = try await perform(.resetDemo(seed: seed))
            #expect(firstRun.changes.count == 15)

            // A person deliberately imports a record through the share extension, then edits it.
            _ = try await perform(.createCollection(draft: CollectionDraft(id: inbox, title: "Imported")), as: .shareExtension)
            let imported = try await perform(
                .createItem(draft: ItemDraft(id: record, in: inbox, title: "Imported record", note: "Brought in on purpose.")),
                as: .shareExtension
            )
            _ = try await perform(.updateItem(id: record, expected: .initial, changes: ItemChanges(note: "Brought in on purpose. Edited.")))
            // Metadata an importer adopts with the record (CORE-006), written directly here.
            try SQLiteDatabase(url: directory.storeURL).run(
                "UPDATE items SET extras = ?1 WHERE id = ?2", [.text(importMetadata), .text(record.description)]
            )

            // The person also changes the samples.
            _ = try await perform(.updateItem(id: seed.items[0].id, expected: .initial, changes: ItemChanges(title: "My amber")))
            _ = try await perform(.archiveItem(id: seed.items[4].id, expected: .initial))
            _ = try await perform(.updateCollection(id: seed.collections[2].id, expected: .initial, title: "My paper"))
            let userRows = try DatabaseDump(directory.storeURL).userRows

            // Content from outside the app cannot reset the demo.
            let refused = await #expect(throws: OperationError.self) { try await perform(.resetDemo(seed: seed), as: .shareExtension) }
            #expect(refused?.denial?.reason == .outsideAdapterCeiling)

            let reset = try await perform(.resetDemo(seed: seed))

            #expect(reset.status == .committed)
            #expect(Set(reset.affectedEntities) == [
                .item(seed.items[0].id), .item(seed.items[4].id), .collection(seed.collections[2].id),
            ])
            #expect(try DatabaseDump(directory.storeURL).userRows == userRows)
            #expect(try await service.findReceipt(for: imported.requestID, as: .appUI) == imported)
            try await Self.expectDemoMatches(seed, in: store)
        }

        // After a relaunch the record and its metadata are still exactly there.
        let reopened = try await SQLiteOperationStore(url: directory.storeURL)
        let kept = try #require(try await reopened.item(record))
        #expect(kept.namespace == .user && kept.revision == .r(2) && kept.note == "Brought in on purpose. Edited.")
        #expect(try SQLiteDatabase(url: directory.storeURL).strings("SELECT extras FROM items WHERE id = '\(record)'") == [importMetadata])
        try await Self.expectDemoMatches(seed, in: reopened)
    }

    @Test func theFileItselfRefusesToDeleteOrReassignUserRows() async throws {
        let directory = try TemporaryDirectory()
        let store = try await SQLiteOperationStore(url: directory.storeURL)
        let service = OperationService(store: store)
        let seed = try RepositoryFixtures.demoSeed()
        let inbox = CollectionID(rawValue: uuid(50))
        for operation in [
            DomainOperation.resetDemo(seed: seed),
            .createCollection(draft: CollectionDraft(id: inbox, title: "Imported")),
            .createItem(draft: ItemDraft(id: ItemID(rawValue: uuid(51)), in: inbox, title: "Imported record")),
        ] {
            _ = try await service.perform(OperationRequest(id: RequestID(), operation: operation, actor: .appUI))
        }
        let before = try DatabaseDump(directory.storeURL)
        let raw = try SQLiteDatabase(url: directory.storeURL)

        // Any writer of the file, not only this module, meets the schema's triggers.
        let attempts = [
            "DELETE FROM items WHERE namespace = 'user'",
            "DELETE FROM collections WHERE namespace = 'user'",
            "UPDATE items SET namespace = 'demo' WHERE namespace = 'user'",
            "UPDATE collections SET namespace = 'demo' WHERE namespace = 'user'",
            "INSERT INTO items (id, collection_id, title, note, is_archived, revision, namespace) VALUES ('\(uuid(52))', '\(seed.collections[0].id)', 'Mine', '', 0, 1, 'user')",
            "UPDATE items SET collection_id = '\(seed.collections[0].id)' WHERE id = '\(uuid(51))'",
            "UPDATE receipts SET body = '{}'",
            "DELETE FROM receipts",
        ]
        for sql in attempts {
            #expect(throws: SQLiteError.self, "\(sql)") { try raw.execute(sql) }
        }
        #expect(try DatabaseDump(directory.storeURL) == before)
    }

    static func expectDemoMatches(_ seed: DemoSeed, in store: SQLiteOperationStore) async throws {
        for draft in seed.collections {
            let collection = try #require(try await store.collection(draft.id))
            #expect(collection.title == draft.title && !collection.isArchived && collection.namespace == .demo)
        }
        for draft in seed.items {
            let item = try #require(try await store.item(draft.id))
            #expect(item.title == draft.title && item.note == draft.note && item.collectionID == draft.collectionID)
            #expect(!item.isArchived && item.namespace == .demo)
        }
        #expect(try await store.items(in: nil).filter { $0.namespace == .demo }.count == seed.items.count)
    }
}

extension DatabaseDump {
    /// The user namespace's rows, every column included.
    var userRows: [[String]] { (collections + items).filter { $0.last == "user" } }
}
