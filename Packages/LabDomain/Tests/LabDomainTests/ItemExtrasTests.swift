import Foundation
import LabDomain
import Testing

/// An item's extras (LAB-008-A): validated when given, set by a creation, carried unchanged by
/// every later revision, and absent from every encoding that has none.
@Suite struct ItemExtrasTests {
    static let metadata = #"{"portableObject":{"version":1,"note":"null","document":{"kind":"collection-item","x":[0,0.0,"",null,false]}}}"#

    @Test func aJSONObjectIsKeptExactlyAsGiven() throws {
        let extras = try ItemExtras(json: Self.metadata)
        #expect(extras.json == Self.metadata)
        #expect(!extras.isEmpty && ItemExtras.empty.isEmpty)
        #expect(try ItemExtras(json: "  {\"a\": 1}\n").json == "  {\"a\": 1}\n")
    }

    @Test(arguments: [
        ("[]", ExtrasRejection.notAnObject),
        (#""text""#, .notAnObject),
        ("7", .notAnObject),
        ("{", .malformed),
        (#"{"a":1,"a":2}"#, .malformed),
        ("", .malformed),
        (String(repeating: "{\"a\":", count: 33) + "1" + String(repeating: "}", count: 33), .malformed),
    ])
    func anythingElseIsRefused(json: String, expected: ExtrasRejection) {
        #expect(throws: expected) { try ItemExtras(json: json) }
    }

    @Test func extrasHaveASizeLimit() throws {
        let padding = String(repeating: "x", count: ItemExtras.maximumBytes - 10)
        #expect(throws: ExtrasRejection.tooLarge(limit: ItemExtras.maximumBytes)) { try ItemExtras(json: #"{"p":"\#(padding)xxxxxxxx"}"#) }
        _ = try ItemExtras(json: #"{"p":"\#(padding)"}"#)
    }

    @Test func extrasNeverAppearInADescription() throws {
        let extras = try ItemExtras(json: #"{"secret":"do-not-log"}"#)
        #expect(!String(describing: extras).contains("do-not-log"))
        #expect(!String(reflecting: extras).contains("do-not-log"))
        let item = LabItem(id: ItemID(), collectionID: CollectionID(), title: "T", extras: extras)
        #expect(!String(reflecting: item).contains("do-not-log"))
    }

    @Test func aCreationSetsExtrasAndEveryLaterRevisionKeepsThem() async throws {
        let store = InMemoryOperationStore()
        let service = OperationService(store: store)
        let collection = CollectionDraft(title: "Imports")
        let extras = try ItemExtras(json: Self.metadata)
        let id = ItemID()
        func perform(_ operation: DomainOperation) async throws -> ActionReceipt {
            try await service.perform(OperationRequest(id: RequestID(), operation: operation, actor: .appUI))
        }
        _ = try await perform(.createCollection(draft: collection))
        let created = try await perform(.createItem(draft: ItemDraft(id: id, in: collection.id, title: "Imported", extras: extras)))
        #expect(try await service.findItem(id, as: .appUI).extras == extras)
        _ = try await perform(.updateItem(id: id, expected: .r(1), changes: ItemChanges(title: "Renamed")))
        _ = try await perform(.archiveItem(id: id, expected: .r(2)))
        _ = try await perform(.restoreItem(id: id, expected: .r(3)))
        let conflict = try await perform(.updateItem(id: id, expected: .r(1), changes: ItemChanges(note: "stale")))
        #expect(conflict.conflict != nil)
        let item = try await service.findItem(id, as: .appUI)
        #expect(item.revision == .r(4) && item.extras == extras)
        // The receipt records the extras the creation was asked for, and a retry must repeat them.
        guard case .createItem(let draft) = created.admitted.operation else {
            Issue.record("expected a creation")
            return
        }
        #expect(draft.extras == extras)
    }

    @Test func extrasAreEncodedOnlyWhenThereAreAny() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plain = ItemDraft(id: ItemID(rawValue: uuid(1)), in: CollectionID(rawValue: uuid(2)), title: "T")
        let plainJSON = String(decoding: try encoder.encode(plain), as: UTF8.self)
        #expect(!plainJSON.contains("extras"))
        #expect(plainJSON == #"{"collectionID":"00000000-0000-0000-0000-000000000002","id":"00000000-0000-0000-0000-000000000001","note":"","title":"T"}"#)

        let rich = ItemDraft(id: plain.id, in: plain.collectionID, title: "T", extras: try ItemExtras(json: Self.metadata))
        let richData = try encoder.encode(rich)
        #expect(try JSONDecoder().decode(ItemDraft.self, from: richData) == rich)

        let item = LabItem(id: plain.id, collectionID: plain.collectionID, title: "T")
        #expect(!String(decoding: try encoder.encode(item), as: UTF8.self).contains("extras"))
        let richItem = LabItem(id: plain.id, collectionID: plain.collectionID, title: "T", extras: rich.extras)
        #expect(try JSONDecoder().decode(LabItem.self, from: try encoder.encode(richItem)) == richItem)
    }

    @Test func decodingRefusesExtrasThatAreNotAnObject() {
        let forged = Data(#"{"collectionID":"00000000-0000-0000-0000-000000000002","id":"00000000-0000-0000-0000-000000000001","note":"","title":"T","extras":"[1]"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ItemDraft.self, from: forged) }
    }

    @Test func aRetryWithDifferentExtrasIsADifferentRequest() async throws {
        let service = OperationService(store: InMemoryOperationStore())
        let collection = CollectionDraft(title: "Imports")
        _ = try await service.perform(OperationRequest(id: RequestID(), operation: .createCollection(draft: collection), actor: .appUI))
        let request = RequestID()
        let id = ItemID()
        let first = ItemDraft(id: id, in: collection.id, title: "T", extras: try ItemExtras(json: #"{"a":1}"#))
        let second = ItemDraft(id: id, in: collection.id, title: "T", extras: try ItemExtras(json: #"{"a":2}"#))
        _ = try await service.perform(OperationRequest(id: request, operation: .createItem(draft: first), actor: .appUI))
        await #expect(throws: OperationError.requestIDReused(request)) {
            try await service.perform(OperationRequest(id: request, operation: .createItem(draft: second), actor: .appUI))
        }
    }
}
