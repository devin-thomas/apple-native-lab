import Foundation
import LabDomain
@testable import LabStore
import Testing

/// One way a demo seed file can be damaged, and the error that names it.
struct Corruption: Sendable, CustomTestStringConvertible {
    let name: String
    let expected: DemoFixtureError
    let bytes: @Sendable () throws -> Data

    var testDescription: String { name }

    /// Edits the repository's seed as a JSON object and serializes it again.
    static func editing(_ name: String, _ expected: DemoFixtureError, _ edit: @escaping @Sendable (inout [String: Any]) -> Void) -> Corruption {
        Corruption(name: name, expected: expected) {
            var object = try JSONSerialization.jsonObject(with: RepositoryFixtures.demoSeedData()) as! [String: Any]
            edit(&object)
            return try JSONSerialization.data(withJSONObject: object)
        }
    }

    static func editingItem(_ index: Int, _ name: String, _ expected: DemoFixtureError, _ edit: @escaping @Sendable (inout [String: Any]) -> Void) -> Corruption {
        editing(name, expected) { object in
            var items = object["items"] as! [[String: Any]]
            edit(&items[index])
            object["items"] = items
        }
    }
}

/// CORE-003 acceptance: a corrupt fixture import does not prevent the next valid one.
@Suite struct FixtureImportTests {
    static let amber = ItemID(rawValue: UUID(uuidString: "DB666EF1-F642-43F1-B415-895B6ECFF693")!)
    static let quartz = ItemID(rawValue: UUID(uuidString: "AF451890-CA80-4DE9-B18B-4007066C9177")!)
    static let stray = CollectionID(rawValue: uuid(404))

    static let corruptions: [Corruption] = [
        Corruption(name: "empty file", expected: .notJSON) { Data() },
        Corruption(name: "truncated file", expected: .notJSON) {
            let data = try RepositoryFixtures.demoSeedData()
            return data.prefix(data.count / 2)
        },
        Corruption(name: "not UTF-8", expected: .notJSON) { Data([0xFF, 0xFE, 0x7B, 0x00, 0xC3]) },
        Corruption(name: "a JSON array", expected: .unsupportedFormat) { Data("[1, 2, 3]".utf8) },
        Corruption(name: "oversized", expected: .tooLarge(limit: DemoFixture.maximumByteCount)) {
            Data(repeating: 0x20, count: DemoFixture.maximumByteCount + 1)
        },
        .editing("another format", .unsupportedFormat) { $0["format"] = "native-lab-document" },
        .editing("a future format version", .unsupportedFormatVersion(2)) { $0["formatVersion"] = 2 },
        .editing("no items field", .malformed(path: "items")) { $0["items"] = nil },
        .editing("a title of the wrong type", .malformed(path: "collections[0].title")) { object in
            var collections = object["collections"] as! [[String: Any]]
            collections[0]["title"] = 7
            object["collections"] = collections
        },
        .editing("a blank collection title", .invalidValue(path: "collections[1].title", .emptyTitle)) { object in
            var collections = object["collections"] as! [[String: Any]]
            collections[1]["title"] = "   "
            object["collections"] = collections
        },
        .editingItem(3, "a missing title", .malformed(path: "items[3].title")) { $0["title"] = nil },
        .editingItem(0, "a malformed UUID", .malformed(path: "items[0].id")) { $0["id"] = "not-a-uuid" },
        .editingItem(2, "an unknown field", .unknownField(path: "items[2].color")) { $0["color"] = "blue" },
        .editingItem(4, "a control character", .invalidValue(path: "items[4].note", .controlCharacter(in: .note))) {
            $0["note"] = "bell \u{07}"
        },
        .editingItem(1, "a duplicate ID", .invalidSeed(.duplicateID(amber.rawValue))) { $0["id"] = amber.description },
        .editingItem(4, "an item in a missing collection", .invalidSeed(.unknownCollection(item: quartz, collection: stray))) {
            $0["collection"] = stray.description
        },
        .editing("seed version 0", .invalidSeed(.unsupportedVersion(0))) { $0["seedVersion"] = 0 },
        .editing("no collections", .invalidSeed(.noCollections)) { object in
            object["collections"] = [Any]()
            object["items"] = [Any]()
        },
    ]

    /// A store with user data and an edited demo, and the valid fixture to import next.
    struct Scenario {
        let directory: TemporaryDirectory
        let faults: FaultPlan
        let store: SQLiteOperationStore
        let service: OperationService
        let valid: DemoFixture

        static func make() async throws -> Scenario {
            let directory = try TemporaryDirectory()
            let faults = FaultPlan()
            let store = try await SQLiteOperationStore.open(directory.storeURL, hook: faults.hook)
            let service = OperationService(store: store)
            let valid = try DemoFixture(contentsOf: RepositoryFixtures.demoSeedURL)
            let mine = CollectionID(rawValue: uuid(60))
            for operation in [
                DomainOperation.resetDemo(seed: valid.seed),
                .updateItem(id: FixtureImportTests.amber, expected: .initial, changes: try ItemChanges(title: "Edited amber")),
                .createCollection(draft: CollectionDraft(id: mine, title: "Mine")),
                .createItem(draft: ItemDraft(id: ItemID(rawValue: uuid(61)), in: mine, title: "Imported record")),
            ] {
                _ = try await service.perform(OperationRequest(id: RequestID(), operation: operation, actor: .appUI))
            }
            return Scenario(directory: directory, faults: faults, store: store, service: service, valid: valid)
        }

        func importFixture(_ fixture: DemoFixture, id: RequestID = RequestID()) async throws -> ActionReceipt {
            try await service.perform(OperationRequest(id: id, operation: .resetDemo(seed: fixture.seed), actor: .appUI))
        }

        func expectValidImportSucceeds() async throws {
            let receipt = try await importFixture(valid)
            #expect(receipt.status == .committed)
            #expect(try await store.item(FixtureImportTests.amber)?.title == "Amber swatch")
            #expect(try await store.items(in: nil).filter { $0.namespace == .demo }.count == 12)
            #expect(try await store.item(ItemID(rawValue: uuid(61)))?.namespace == .user)
        }
    }

    @Test(arguments: corruptions)
    func aCorruptFixtureIsRejectedBeforeAnyWriteAndTheNextValidOneLoads(_ corruption: Corruption) async throws {
        let scenario = try await Scenario.make()
        let before = try DatabaseDump(scenario.directory.storeURL)
        let bytes = try corruption.bytes()

        #expect(throws: corruption.expected) { try DemoFixture(data: bytes) }
        #expect(try DatabaseDump(scenario.directory.storeURL) == before)

        try await scenario.expectValidImportSucceeds()
    }

    @Test func anUnreadableFixtureIsReported() throws {
        let missing = RepositoryFixtures.root.appending(path: "demo/missing-seed.json")
        #expect(throws: DemoFixtureError.unreadable) { try DemoFixture(contentsOf: missing) }
    }

    @Test func aWellFormedFixtureThatNamesUserDataIsRefusedAndTheNextValidOneLoads() async throws {
        let scenario = try await Scenario.make()
        // A fixture that reuses the identifier of the person's own collection for a sample one.
        let seed = scenario.valid.seed
        let mine = CollectionID(rawValue: uuid(60))
        let clashing = try DemoSeed(
            version: 2,
            collections: [CollectionDraft(id: mine, title: "Sample shelf")],
            items: [ItemDraft(id: ItemID(rawValue: uuid(62)), in: mine, title: "Sample")]
        )
        let before = try DatabaseDump(scenario.directory.storeURL)
        let requestID = RequestID()

        await #expect(throws: OperationError.ruleViolation(.alreadyExists(.collection(mine)))) {
            try await scenario.service.perform(OperationRequest(id: requestID, operation: .resetDemo(seed: clashing), actor: .appUI))
        }
        #expect(try DatabaseDump(scenario.directory.storeURL) == before)
        #expect(try await scenario.store.receipt(for: requestID) == nil)
        #expect(seed.collections.allSatisfy { $0.id != mine })

        try await scenario.expectValidImportSucceeds()
    }

    @Test func anImportInterruptedMidCommitLeavesNothingAndTheNextOneLoads() async throws {
        let scenario = try await Scenario.make()
        let before = try DatabaseDump(scenario.directory.storeURL)
        let requestID = RequestID()
        scenario.faults.interrupt { if case .wrote = $0 { true } else { false } }

        await #expect(throws: OperationError.storeFailure(.commitFailed)) {
            try await scenario.importFixture(scenario.valid, id: requestID)
        }
        #expect(try DatabaseDump(scenario.directory.storeURL) == before)
        #expect(try await scenario.store.receipt(for: requestID) == nil)

        try await scenario.expectValidImportSucceeds()
    }
}
