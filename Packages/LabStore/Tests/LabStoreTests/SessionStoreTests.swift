import Foundation
import LabDomain
@testable import LabStore
import Testing

/// LAB-004 Surface Deck: the demo session is stored in the same SQLite file and transaction as its
/// receipt, survives reopening, is paused by Reset Demo, and cannot leave the demo namespace.
@Suite struct SessionStoreTests {
    static let session = SessionID(rawValue: uuid(40))

    private func perform(_ service: OperationService, _ operation: DomainOperation) async throws -> ActionReceipt {
        try await service.perform(OperationRequest(id: RequestID(), operation: operation, actor: .appUI))
    }

    @Test func aSessionAndItsReceiptSurviveReopeningTheFile() async throws {
        let directory = try TemporaryDirectory()
        let requestID = RequestID(rawValue: uuid(41))
        do {
            let store = try await SQLiteOperationStore(url: directory.storeURL)
            let service = OperationService(store: store)
            let started = try await service.perform(OperationRequest(
                id: requestID, operation: .setSession(id: Self.session, expected: nil, running: true), actor: .appUI
            ))
            #expect(started.changes.map(\.newRevision) == [.initial])
            _ = try await perform(service, .setSession(id: Self.session, expected: .initial, running: false))
        }
        let reopened = try await SQLiteOperationStore(url: directory.storeURL)
        #expect(try await reopened.session(Self.session) == LabSession(id: Self.session, isRunning: false, revision: .r(2)))
        #expect(try await reopened.sessions().count == 1)
        #expect(try await reopened.receipt(for: requestID)?.summary == "Started the demo session.")
    }

    @Test func anInterruptedSessionChangeLeavesTheOldStateAndNoReceipt() async throws {
        let directory = try TemporaryDirectory()
        let faults = FaultPlan()
        let store = try await SQLiteOperationStore.open(directory.storeURL, hook: faults.hook)
        let service = OperationService(store: store)
        _ = try await perform(service, .setSession(id: Self.session, expected: nil, running: true))

        let requestID = RequestID(rawValue: uuid(42))
        faults.interrupt { $0 == .receiptRecorded }
        await #expect(throws: OperationError.storeFailure(.commitFailed)) {
            try await service.perform(OperationRequest(
                id: requestID, operation: .setSession(id: Self.session, expected: .initial, running: false), actor: .appUI
            ))
        }
        #expect(try await store.session(Self.session)?.isRunning == true)
        #expect(try await store.session(Self.session)?.revision == .initial)
        #expect(try await store.receipt(for: requestID) == nil)
    }

    @Test func resetDemoPausesARunningSessionAtItsNextRevisionAndKeepsUserData() async throws {
        let directory = try TemporaryDirectory()
        let store = try await SQLiteOperationStore(url: directory.storeURL)
        let service = OperationService(store: store)
        let seed = try RepositoryFixtures.demoSeed()
        _ = try await perform(service, .resetDemo(seed: seed))
        let mine = CollectionID(rawValue: uuid(43))
        _ = try await perform(service, .createCollection(draft: CollectionDraft(id: mine, title: "Mine")))
        _ = try await perform(service, .setSession(id: Self.session, expected: nil, running: true))

        let reset = try await perform(service, .resetDemo(seed: seed))
        #expect(reset.changes.map(\.entity) == [.session(Self.session)])
        #expect(reset.changes.map(\.previousRevision) == [.initial])
        #expect(reset.changes.map(\.newRevision) == [.r(2)])
        #expect(reset.summary == "Reset the demo to its original 3 collections and 12 items: paused 1 session.")
        #expect(try await store.session(Self.session) == LabSession(id: Self.session, isRunning: false, revision: .r(2)))
        #expect(try await store.collection(mine)?.namespace == .user)

        // A paused session is already where a reset leaves it.
        let again = try await perform(service, .resetDemo(seed: seed))
        #expect(again.changes.isEmpty)
        #expect(try await store.session(Self.session)?.revision == .r(2))
    }

    @Test func version2FilesGainAnEmptySessionsTableAndKeepTheirRows() async throws {
        let directory = try TemporaryDirectory()
        do {
            let database = try SQLiteDatabase(url: directory.storeURL)
            try database.execute(StoreSchema.version1)
            try database.execute(StoreSchema.version2)
            try database.execute(
                "INSERT INTO collections (id, title, is_archived, revision, namespace) VALUES ('\(uuid(44).uuidString)', 'Kept', 0, 3, 'user')"
            )
            try database.execute("PRAGMA user_version = 2; PRAGMA application_id = \(StoreSchema.applicationID)")
        }
        let before = try DatabaseDump(directory.storeURL)

        let store = try await SQLiteOperationStore(url: directory.storeURL)
        #expect(try await store.sessions().isEmpty)
        #expect(try await store.attentions().isEmpty)
        #expect(try DatabaseDump(directory.storeURL) == before)
        let raw = try SQLiteDatabase(url: directory.storeURL)
        #expect(try raw.integer("PRAGMA user_version") == 4)
        #expect(try raw.strings("SELECT name FROM pragma_table_info('sessions')") == ["id", "is_running", "revision", "namespace", "extras"])
    }

    @Test func theSchemaKeepsSessionsInTheDemoNamespace() throws {
        let directory = try TemporaryDirectory()
        let database = try SQLiteDatabase(url: directory.storeURL)
        for migration in StoreSchema.migrations { try database.execute(migration.sql) }
        #expect(throws: SQLiteError.self) {
            try database.execute("INSERT INTO sessions (id, is_running, revision, namespace) VALUES ('\(uuid(45).uuidString)', 1, 1, 'user')")
        }
        #expect(throws: SQLiteError.self) {
            try database.execute("INSERT INTO sessions (id, is_running, revision) VALUES ('\(uuid(46).uuidString)', 2, 1)")
        }
    }
}
