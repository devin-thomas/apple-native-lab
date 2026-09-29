import Foundation
import LabDomain
@testable import LabStore
import Testing

/// A store file as the released version 1 schema wrote it, built from frozen SQL rather than from
/// the store's own migration code, so the test would catch a change to a released step.
enum ReleasedVersion1 {
    /// Version 1 exactly as released. Never edit this to follow a later change.
    static let schema = """
        CREATE TABLE collections (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            title TEXT NOT NULL,
            is_archived INTEGER NOT NULL CHECK (is_archived IN (0, 1)),
            revision INTEGER NOT NULL CHECK (revision >= 1),
            extras TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(extras))
        ) STRICT;

        CREATE TABLE items (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            collection_id TEXT NOT NULL REFERENCES collections (id),
            title TEXT NOT NULL,
            note TEXT NOT NULL,
            is_archived INTEGER NOT NULL CHECK (is_archived IN (0, 1)),
            revision INTEGER NOT NULL CHECK (revision >= 1),
            extras TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(extras))
        ) STRICT;

        CREATE INDEX items_by_collection ON items (collection_id);

        CREATE TABLE receipts (
            request_id TEXT PRIMARY KEY NOT NULL CHECK (length(request_id) = 36),
            operation_id TEXT NOT NULL UNIQUE,
            body TEXT NOT NULL CHECK (json_valid(body))
        ) STRICT;

        CREATE TRIGGER receipts_are_immutable BEFORE UPDATE ON receipts
        BEGIN SELECT RAISE(ABORT, 'lab-receipt: a recorded receipt never changes'); END;

        CREATE TRIGGER receipts_are_kept BEFORE DELETE ON receipts
        BEGIN SELECT RAISE(ABORT, 'lab-receipt: a recorded receipt never changes'); END;
        """

    static let notebook = CollectionID(rawValue: uuid(1))
    static let oldShelf = CollectionID(rawValue: uuid(2))
    static let tideTable = ItemID(rawValue: uuid(11))
    static let pressedLeaf = ItemID(rawValue: uuid(12))
    static let postcard = ItemID(rawValue: uuid(13))
    static let recordedRequest = RequestID(rawValue: uuid(21))

    /// Metadata version 1 stored but did not interpret, including nesting, numbers, null, and
    /// non-ASCII text.
    static let notebookExtras = #"{"x-origin":"import","palette":{"hue":37.5,"tags":["warm","ámbar"]},"legacy":null}"#
    static let tideTableExtras = #"{"x-source":"share-extension","size":{"value":12,"unit":"cm"}}"#
    static let postcardExtras = #"{"emoji":"🪨","x-empty":""}"#

    /// A receipt body as version 1 recorded it, with a field this build does not know.
    static let receiptBody = #"""
        {"admitted":{"adapter":"app-ui","operation":{"createCollection":{"draft":{"id":"00000000-0000-0000-0000-000000000001","title":"Field notebook"}}},"schemaVersion":1},"changes":[{"entity":{"id":"00000000-0000-0000-0000-000000000001","kind":"collection"},"newRevision":1}],"operationID":"00000000-0000-0000-0000-000000000031","requestID":"00000000-0000-0000-0000-000000000021","status":{"state":"committed"},"summary":"Created collection “Field notebook”.","undo":{"archiveCollection":{"expected":1,"id":"00000000-0000-0000-0000-000000000001"}},"x-recorder":"version-1"}
        """#

    static func makeFile(at url: URL, userVersion: Int = 1) throws {
        let database = try SQLiteDatabase(url: url)
        try database.execute("PRAGMA journal_mode = WAL")
        try database.execute(schema)
        try database.execute("PRAGMA user_version = \(userVersion); PRAGMA application_id = 1279345235")
        try database.run(
            "INSERT INTO collections (id, title, is_archived, revision, extras) VALUES (?1, ?2, ?3, ?4, ?5)",
            [.text(notebook.description), .text("Field notebook"), .integer(0), .integer(3), .text(notebookExtras)]
        )
        try database.run(
            "INSERT INTO collections (id, title, is_archived, revision) VALUES (?1, ?2, ?3, ?4)",
            [.text(oldShelf.description), .text("Old shelf"), .integer(1), .integer(2)]
        )
        let items: [(ItemID, CollectionID, String, String, Int, Int, String?)] = [
            (tideTable, notebook, "Tide table", "Line one\nLine two", 0, 5, tideTableExtras),
            (pressedLeaf, notebook, "Pressed leaf", "", 1, 2, nil),
            (postcard, oldShelf, "Émigré postcard", "ünïcödé ✓", 0, 1, postcardExtras),
        ]
        for (id, collection, title, note, archived, revision, extras) in items {
            try database.run(
                "INSERT INTO items (id, collection_id, title, note, is_archived, revision, extras) VALUES (?1, ?2, ?3, ?4, ?5, ?6, coalesce(?7, '{}'))",
                [.text(id.description), .text(collection.description), .text(title), .text(note), .integer(archived), .integer(revision)]
                    + (extras.map { [.text($0)] } ?? [])
            )
        }
        try database.run(
            "INSERT INTO receipts (request_id, operation_id, body) VALUES (?1, ?2, ?3)",
            [.text(recordedRequest.description), .text(uuid(31).uuidString), .text(receiptBody)]
        )
    }
}

/// CORE-003 acceptance: a released schema migration preserves stable IDs and unknown supported
/// metadata.
@Suite struct MigrationTests {
    @Test func aReleasedVersion1FileMigratesKeepingIDsAndUnknownMetadata() async throws {
        let directory = try TemporaryDirectory()
        try ReleasedVersion1.makeFile(at: directory.storeURL)
        let before = try DatabaseDump(directory.storeURL)
        let bodiesBefore = try SQLiteDatabase(url: directory.storeURL).strings("SELECT body FROM receipts ORDER BY request_id")

        let store = try await SQLiteOperationStore(url: directory.storeURL)

        let raw = try SQLiteDatabase(url: directory.storeURL)
        #expect(try raw.integer("PRAGMA user_version") == SQLiteOperationStore.schemaVersion)
        let after = try DatabaseDump(directory.storeURL)
        // Every column of every row is unchanged, with the new namespace column appended as user.
        #expect(after.collections == before.collections.map { $0 + ["user"] })
        #expect(after.items == before.items.map { $0 + ["user"] })
        #expect(after.receiptRequests == before.receiptRequests)
        #expect(try raw.strings("SELECT extras FROM items WHERE id = '\(ReleasedVersion1.tideTable)'") == [ReleasedVersion1.tideTableExtras])
        #expect(try raw.strings("SELECT body FROM receipts ORDER BY request_id") == bodiesBefore)

        let tideTable = try #require(try await store.item(ReleasedVersion1.tideTable))
        #expect(tideTable.namespace == .user)
        #expect(tideTable.revision == .r(5))
        #expect(tideTable.note == "Line one\nLine two")
        #expect(try await store.item(ReleasedVersion1.postcard)?.title == "Émigré postcard")
        #expect(try await store.collection(ReleasedVersion1.oldShelf)?.isArchived == true)

        let receipt = try #require(try await store.receipt(for: ReleasedVersion1.recordedRequest))
        #expect(receipt.status == .committed)
        #expect(receipt.removed.isEmpty)
        #expect(receipt.affectedEntities == [.collection(ReleasedVersion1.notebook)])
    }

    @Test func migratedRecordsKeepTheirMetadataThroughLaterWritesAndResets() async throws {
        let directory = try TemporaryDirectory()
        try ReleasedVersion1.makeFile(at: directory.storeURL)
        let store = try await SQLiteOperationStore(url: directory.storeURL)
        let service = OperationService(store: store)

        let edit = try await service.perform(OperationRequest(
            id: RequestID(),
            operation: .updateItem(id: ReleasedVersion1.tideTable, expected: .r(5), changes: ItemChanges(title: "Tide table, edited")),
            actor: .appUI
        ))
        #expect(edit.status == .committed)
        let beforeReset = try DatabaseDump(directory.storeURL)
        let reset = try await service.perform(OperationRequest(
            id: RequestID(), operation: .resetDemo(seed: RepositoryFixtures.demoSeed()), actor: .appUI
        ))
        #expect(reset.status == .committed)

        let raw = try SQLiteDatabase(url: directory.storeURL)
        #expect(try raw.strings("SELECT extras FROM items WHERE id = '\(ReleasedVersion1.tideTable)'") == [ReleasedVersion1.tideTableExtras])
        #expect(try raw.strings("SELECT extras FROM collections WHERE id = '\(ReleasedVersion1.notebook)'") == [ReleasedVersion1.notebookExtras])
        #expect(try await store.item(ReleasedVersion1.tideTable)?.revision == .r(6))
        // The reset added the demo and left every migrated row exactly as it was.
        let afterReset = try DatabaseDump(directory.storeURL)
        #expect(afterReset.items.filter { $0.last == "user" } == beforeReset.items)
        #expect(afterReset.collections.filter { $0.last == "user" } == beforeReset.collections)
    }

    @Test func aMigratedFileHasExactlyTheSchemaOfANewFile() async throws {
        let migrated = try TemporaryDirectory()
        try ReleasedVersion1.makeFile(at: migrated.storeURL)
        _ = try await SQLiteOperationStore(url: migrated.storeURL)
        let created = try TemporaryDirectory()
        _ = try await SQLiteOperationStore(url: created.storeURL)

        let query = "SELECT type || ' ' || name || ': ' || coalesce(sql, '') FROM sqlite_schema ORDER BY name"
        let migratedSchema = try SQLiteDatabase(url: migrated.storeURL).strings(query)
        #expect(migratedSchema == (try SQLiteDatabase(url: created.storeURL).strings(query)))
        #expect(migratedSchema.contains { $0.hasPrefix("trigger user_items_are_never_deleted") })
    }

    @Test func anInterruptedMigrationLeavesTheFileAtVersion1() async throws {
        let directory = try TemporaryDirectory()
        try ReleasedVersion1.makeFile(at: directory.storeURL)
        let before = try DatabaseDump(directory.storeURL)
        let faults = FaultPlan()
        faults.interrupt { $0 == .migrationWritten(version: 2) }

        await #expect(throws: StoreError.interrupted) { try await SQLiteOperationStore.open(directory.storeURL, hook: faults.hook) }

        let raw = try SQLiteDatabase(url: directory.storeURL)
        #expect(try raw.integer("PRAGMA user_version") == 1)
        #expect(try !raw.strings("SELECT name FROM pragma_table_info('items')").contains("namespace"))
        #expect(try DatabaseDump(directory.storeURL) == before)

        let store = try await SQLiteOperationStore(url: directory.storeURL)
        #expect(try await store.item(ReleasedVersion1.tideTable)?.namespace == .user)
    }

    @Test func aFileFromANewerBuildIsRefusedAndLeftUnchanged() async throws {
        let directory = try TemporaryDirectory()
        try ReleasedVersion1.makeFile(at: directory.storeURL, userVersion: 3)
        let bytes = try Data(contentsOf: directory.storeURL)

        await #expect(throws: StoreError.newerSchema(found: 3, supported: 2)) {
            try await SQLiteOperationStore(url: directory.storeURL)
        }
        #expect(try Data(contentsOf: directory.storeURL) == bytes)
    }

    @Test func aFileThatIsNotThisStoresIsRefusedAndLeftUnchanged() async throws {
        let directory = try TemporaryDirectory()
        let foreign = directory.file("foreign.sqlite")
        try SQLiteDatabase(url: foreign).execute("CREATE TABLE notes (body TEXT)")
        let foreignBytes = try Data(contentsOf: foreign)
        await #expect(throws: StoreError.notALabStore) { try await SQLiteOperationStore(url: foreign) }
        #expect(try Data(contentsOf: foreign) == foreignBytes)

        let text = directory.file("notes.txt")
        let textBytes = Data(String(repeating: "Not a database. ", count: 64).utf8)
        try textBytes.write(to: text)
        await #expect(throws: StoreError.notALabStore) { try await SQLiteOperationStore(url: text) }
        #expect(try Data(contentsOf: text) == textBytes)
    }

    @Test func aNewFileIsCreatedAtTheCurrentVersionWithDurableSettings() async throws {
        let directory = try TemporaryDirectory()
        let store = try await SQLiteOperationStore(url: directory.storeURL)
        #expect(try await store.collections().isEmpty)

        let raw = try SQLiteDatabase(url: directory.storeURL)
        #expect(try raw.integer("PRAGMA user_version") == 2)
        #expect(try raw.integer("PRAGMA application_id") == 0x4C41_4253)
        #expect(try raw.strings("PRAGMA journal_mode") == ["wal"])
    }
}
