import Foundation
import LabDomain
@testable import LabStore
import Testing

/// LAB-023 Tabletop Reality: lab-owned anchors are stored in the same SQLite file and transaction
/// as their receipts, survive reopening, are removed by Reset Demo, and cannot leave the demo
/// namespace or hold an out-of-reach pose.
@Suite struct AnchorStoreTests {
    static let anchor = AnchorID(rawValue: uuid(60))

    private static func draft(x: Int = 120, z: Int = -80, yaw: Int = 90) throws -> AnchorDraft {
        AnchorDraft(id: anchor, fixture: try FixtureKey("windmill"), title: "Windmill", pose: try AnchorPose(x: x, z: z, yaw: yaw))
    }

    private func perform(_ service: OperationService, _ operation: DomainOperation) async throws -> ActionReceipt {
        try await service.perform(OperationRequest(id: RequestID(), operation: operation, actor: .appUI))
    }

    @Test func anAnchorAndItsReceiptsSurviveReopeningTheFile() async throws {
        let directory = try TemporaryDirectory()
        let placedID = RequestID(rawValue: uuid(61))
        do {
            let store = try await SQLiteOperationStore(url: directory.storeURL)
            let service = OperationService(store: store)
            let placed = try await service.perform(OperationRequest(
                id: placedID, operation: .placeAnchor(draft: try Self.draft()), actor: .appUI
            ))
            #expect(placed.summary == "Placed “Windmill”.")
            _ = try await perform(service, .moveAnchor(id: Self.anchor, expected: .initial, pose: try AnchorPose(x: -40, y: 5, z: 300, yaw: 270)))
        }
        let reopened = try await SQLiteOperationStore(url: directory.storeURL)
        let stored = try #require(try await reopened.anchor(Self.anchor))
        #expect(stored.pose == (try AnchorPose(x: -40, y: 5, z: 300, yaw: 270)))
        #expect(stored.revision == .r(2))
        #expect(stored.fixture.value == "windmill" && stored.title.value == "Windmill")
        #expect(try await reopened.anchors().count == 1)
        #expect(try await reopened.receipt(for: placedID)?.undo == .removeAnchor(id: Self.anchor, expected: .initial))
    }

    @Test func removingAnAnchorDeletesItsRowAndItsUndoPlacesItAgain() async throws {
        let directory = try TemporaryDirectory()
        let store = try await SQLiteOperationStore(url: directory.storeURL)
        let service = OperationService(store: store)
        _ = try await perform(service, .placeAnchor(draft: try Self.draft()))

        let removed = try await perform(service, .removeAnchor(id: Self.anchor, expected: .initial))
        #expect(removed.removed == [.anchor(Self.anchor)])
        #expect(try await store.anchor(Self.anchor) == nil)

        let undo = try #require(removed.undo)
        _ = try await perform(service, undo)
        #expect(try await store.anchor(Self.anchor)?.pose == (try Self.draft()).pose)
    }

    @Test func anInterruptedMoveLeavesTheOldPoseAndNoReceipt() async throws {
        let directory = try TemporaryDirectory()
        let faults = FaultPlan()
        let store = try await SQLiteOperationStore.open(directory.storeURL, hook: faults.hook)
        let service = OperationService(store: store)
        _ = try await perform(service, .placeAnchor(draft: try Self.draft()))

        let requestID = RequestID(rawValue: uuid(62))
        faults.interrupt { $0 == .receiptRecorded }
        await #expect(throws: OperationError.storeFailure(.commitFailed)) {
            try await service.perform(OperationRequest(
                id: requestID, operation: .moveAnchor(id: Self.anchor, expected: .initial, pose: try AnchorPose(x: 0, z: 0)), actor: .appUI
            ))
        }
        #expect(try await store.anchor(Self.anchor)?.pose == (try Self.draft()).pose)
        #expect(try await store.anchor(Self.anchor)?.revision == .initial)
        #expect(try await store.receipt(for: requestID) == nil)
    }

    @Test func resetDemoRemovesEveryAnchorAndKeepsUserData() async throws {
        let directory = try TemporaryDirectory()
        let store = try await SQLiteOperationStore(url: directory.storeURL)
        let service = OperationService(store: store)
        let seed = try RepositoryFixtures.demoSeed()
        _ = try await perform(service, .resetDemo(seed: seed))
        let mine = CollectionID(rawValue: uuid(63))
        _ = try await perform(service, .createCollection(draft: CollectionDraft(id: mine, title: "Mine")))
        _ = try await perform(service, .placeAnchor(draft: try Self.draft()))

        let reset = try await perform(service, .resetDemo(seed: seed))
        #expect(reset.removed == [.anchor(Self.anchor)])
        #expect(reset.summary == "Reset the demo to its original 3 collections and 12 items: cleared 1 placed object.")
        #expect(try await store.anchors().isEmpty)
        #expect(try await store.collection(mine)?.namespace == .user)
    }

    @Test func version5FilesGainAnEmptyAnchorsTableAndKeepTheirRows() async throws {
        let directory = try TemporaryDirectory()
        do {
            let database = try SQLiteDatabase(url: directory.storeURL)
            try database.execute(StoreSchema.version1)
            try database.execute(StoreSchema.version2)
            try database.execute(StoreSchema.version3)
            try database.execute(StoreSchema.version4)
            try database.execute(StoreSchema.version5)
            try database.execute(
                "INSERT INTO collections (id, title, is_archived, revision, namespace) VALUES ('\(uuid(64).uuidString)', 'Kept', 0, 2, 'user')"
            )
            try database.execute("PRAGMA user_version = 5; PRAGMA application_id = \(StoreSchema.applicationID)")
        }
        let before = try DatabaseDump(directory.storeURL)

        let store = try await SQLiteOperationStore(url: directory.storeURL)
        #expect(try await store.anchors().isEmpty)
        #expect(try DatabaseDump(directory.storeURL) == before)
        let raw = try SQLiteDatabase(url: directory.storeURL)
        #expect(try raw.integer("PRAGMA user_version") == 6)
        #expect(try raw.strings("SELECT name FROM pragma_table_info('anchors')") == [
            "id", "fixture", "title", "x_mm", "y_mm", "z_mm", "yaw_degrees", "revision", "namespace", "extras",
        ])
    }

    @Test func theSchemaKeepsAnchorsInTheDemoNamespaceAndWithinReach() throws {
        let directory = try TemporaryDirectory()
        let database = try SQLiteDatabase(url: directory.storeURL)
        for migration in StoreSchema.migrations { try database.execute(migration.sql) }
        let columns = "id, fixture, title, x_mm, y_mm, z_mm, yaw_degrees, revision"
        #expect(throws: SQLiteError.self) {
            try database.execute("INSERT INTO anchors (\(columns), namespace) VALUES ('\(uuid(65).uuidString)', 'lamp', 'Lamp', 0, 0, 0, 0, 1, 'user')")
        }
        #expect(throws: SQLiteError.self) {
            try database.execute("INSERT INTO anchors (\(columns)) VALUES ('\(uuid(66).uuidString)', 'lamp', 'Lamp', 5001, 0, 0, 0, 1)")
        }
        #expect(throws: SQLiteError.self) {
            try database.execute("INSERT INTO anchors (\(columns)) VALUES ('\(uuid(67).uuidString)', 'lamp', 'Lamp', 0, 0, 0, 360, 1)")
        }
    }
}
