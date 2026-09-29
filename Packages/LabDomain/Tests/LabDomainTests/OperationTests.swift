import Foundation
import LabDomain
import Testing

@Suite struct CreateAndFindTests {
    @Test func creatingReturnsACommittedReceiptWithABoundedUndo() async throws {
        let lab = Harness()
        let collectionID = CollectionID(rawValue: uuid(1))
        let itemID = ItemID(rawValue: uuid(2))
        let requestID = RequestID(rawValue: uuid(3))

        try await lab.perform(.createCollection(draft: CollectionDraft(id: collectionID, title: "Samples")))
        let receipt = try await lab.perform(
            .createItem(draft: ItemDraft(id: itemID, in: collectionID, title: "Amber sample", note: "Original fixture")),
            id: requestID
        )

        #expect(receipt.status == .committed)
        #expect(receipt.requestID == requestID)
        #expect(receipt.admitted.adapter == .appUI)
        #expect(receipt.affectedEntities == [.item(itemID)])
        #expect(receipt.changes.first?.previousRevision == nil)
        #expect(receipt.changes.first?.newRevision == .initial)
        #expect(receipt.summary == "Created item “Amber sample” in “Samples”.")
        #expect(receipt.undo == .archiveItem(id: itemID, expected: .initial))

        let stored = try await lab.item(itemID)
        #expect(stored.collectionID == collectionID)
        #expect(stored.note == "Original fixture")
        #expect(stored.revision == .initial)
        #expect(!stored.isArchived)
    }

    @Test func aDuplicateEntityIDIsRefused() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        await #expect(throws: OperationError.ruleViolation(.alreadyExists(.item(item.id)))) {
            try await lab.perform(.createItem(draft: ItemDraft(id: item.id, in: samples.id, title: "Other")))
        }
        await #expect(throws: OperationError.ruleViolation(.alreadyExists(.collection(samples.id)))) {
            try await lab.perform(.createCollection(draft: CollectionDraft(id: samples.id, title: "Other")))
        }
    }

    @Test func findItemsMatchesTextAndHidesArchivedByDefault() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let other = try await lab.makeCollection("Other shelf")
        let amber = try await lab.makeItem("Ámber sample", in: samples)
        _ = try await lab.makeItem("Cobalt sample", note: "Pairs with amber", in: samples)
        let archived = try await lab.makeItem("Amber offcut", in: samples)
        _ = try await lab.makeItem("Amber elsewhere", in: other)
        try await lab.perform(.archiveItem(id: archived.id, expected: archived.revision))

        let visible = try await lab.service.findItems(ItemFilter(collectionID: samples.id, text: "AMBER"), as: .appUI)
        #expect(visible.map(\.title.value) == ["Ámber sample", "Cobalt sample"])
        #expect(visible.first?.id == amber.id)

        let everything = try await lab.service.findItems(
            ItemFilter(collectionID: samples.id, text: "amber", includeArchived: true), as: .appUI
        )
        #expect(everything.map(\.title.value) == ["Amber offcut", "Ámber sample", "Cobalt sample"])

        let firstOnly = try await lab.service.findItems(ItemFilter(text: "amber", limit: 1), as: .appUI)
        #expect(firstOnly.map(\.title.value) == ["Amber elsewhere"])
    }
}

@Suite struct UpdateAndArchiveTests {
    @Test func updatingAdvancesTheRevisionAndUndoRestoresThePreviousContent() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem("Amber sample", note: "First note", in: samples)

        let receipt = try await lab.perform(
            .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "Amber study", note: "Second note"))
        )
        #expect(receipt.status == .committed)
        #expect(receipt.changes.map(\.previousRevision) == [.initial])
        #expect(receipt.changes.map(\.newRevision) == [.r(2)])
        #expect(receipt.summary == "Renamed item “Amber sample” to “Amber study” and updated its note.")
        #expect(receipt.undo == .updateItem(
            id: item.id, expected: .r(2), changes: try ItemChanges(title: "Amber sample", note: "First note")
        ))

        let undo = try #require(receipt.undo)
        let undone = try await lab.perform(undo)
        let restored = try await lab.item(item.id)
        #expect(undone.status == .committed)
        #expect(restored.title == "Amber sample")
        #expect(restored.note == "First note")
        #expect(restored.revision == .r(3))
    }

    @Test func undoOnlyRevertsFieldsThatActuallyChanged() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem("Amber sample", note: "Keep me", in: samples)
        let receipt = try await lab.perform(
            .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "Amber sample", note: "New note"))
        )
        #expect(receipt.summary == "Updated the note of item “Amber sample”.")
        #expect(receipt.undo == .updateItem(id: item.id, expected: .r(2), changes: try ItemChanges(note: "Keep me")))
    }

    @Test func anUpdateThatChangesNothingIsRefused() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem("Amber sample", in: samples)
        await #expect(throws: OperationError.ruleViolation(.noChanges(.item(item.id)))) {
            try await lab.perform(.updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "Amber sample")))
        }
        #expect(try await lab.item(item.id).revision == .initial)
    }

    @Test func archiveAndRestoreAreEachOthersUndo() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)

        let archived = try await lab.perform(.archiveItem(id: item.id, expected: .initial))
        #expect(archived.summary == "Archived item “Amber sample”.")
        #expect(archived.undo == .restoreItem(id: item.id, expected: .r(2)))
        #expect(try await lab.item(item.id).isArchived)

        let restored = try await lab.perform(try #require(archived.undo))
        #expect(restored.undo == .archiveItem(id: item.id, expected: .r(3)))
        #expect(try await !lab.item(item.id).isArchived)
    }

    @Test func archiveRulesAreExplicit() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        try await lab.perform(.archiveItem(id: item.id, expected: .initial))

        await #expect(throws: OperationError.ruleViolation(.alreadyArchived(.item(item.id)))) {
            try await lab.perform(.archiveItem(id: item.id, expected: .r(2)))
        }
        await #expect(throws: OperationError.ruleViolation(.archived(.item(item.id)))) {
            try await lab.perform(.updateItem(id: item.id, expected: .r(2), changes: ItemChanges(title: "Edited")))
        }
        await #expect(throws: OperationError.ruleViolation(.notArchived(.collection(samples.id)))) {
            try await lab.perform(.restoreCollection(id: samples.id, expected: .initial))
        }
    }

    @Test func anArchivedCollectionAcceptsNoNewItems() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let receipt = try await lab.perform(.archiveCollection(id: samples.id, expected: .initial))
        #expect(receipt.undo == .restoreCollection(id: samples.id, expected: .r(2)))
        await #expect(throws: OperationError.ruleViolation(.collectionArchived(samples.id))) {
            try await lab.perform(.createItem(draft: ItemDraft(in: samples.id, title: "Late arrival")))
        }
        await #expect(throws: OperationError.ruleViolation(.archived(.collection(samples.id)))) {
            try await lab.perform(.updateCollection(id: samples.id, expected: .r(2), title: "Renamed"))
        }
    }

    @Test func renamingACollectionKeepsItsIdentity() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection("Samples")
        let receipt = try await lab.perform(.updateCollection(id: samples.id, expected: .initial, title: "Field samples"))
        #expect(receipt.summary == "Renamed collection “Samples” to “Field samples”.")
        #expect(receipt.undo == .updateCollection(id: samples.id, expected: .r(2), title: "Samples"))
        #expect(try await lab.collection(samples.id).title == "Field samples")
    }
}

@Suite struct MissingEntityTests {
    let missingItem = ItemID(rawValue: uuid(404))
    let missingCollection = CollectionID(rawValue: uuid(405))

    @Test func findingAMissingEntityIsARecoverableError() async throws {
        let lab = Harness()
        await #expect(throws: OperationError.notFound(.item(missingItem))) {
            try await lab.service.findItem(missingItem, as: .appUI)
        }
        await #expect(throws: OperationError.notFound(.collection(missingCollection))) {
            try await lab.service.findCollection(missingCollection, as: .appUI)
        }
        await #expect(throws: OperationError.notFound(.collection(missingCollection))) {
            try await lab.service.findItems(ItemFilter(collectionID: missingCollection), as: .appUI)
        }
        #expect(try await lab.service.findReceipt(for: RequestID(), as: .appUI) == nil)
    }

    @Test func changingAMissingEntityIsRefusedAndRecordsNothing() async throws {
        let lab = Harness()
        let requestID = RequestID()
        await #expect(throws: OperationError.notFound(.item(missingItem))) {
            try await lab.perform(
                .updateItem(id: missingItem, expected: .initial, changes: ItemChanges(title: "Ghost")), id: requestID
            )
        }
        await #expect(throws: OperationError.notFound(.item(missingItem))) {
            try await lab.perform(.archiveItem(id: missingItem, expected: .initial))
        }
        await #expect(throws: OperationError.notFound(.collection(missingCollection))) {
            try await lab.perform(.archiveCollection(id: missingCollection, expected: .initial))
        }
        await #expect(throws: OperationError.notFound(.collection(missingCollection))) {
            try await lab.perform(.createItem(draft: ItemDraft(in: missingCollection, title: "Orphan")))
        }
        #expect(await lab.appliedCommits == 0)
        #expect(try await lab.service.findReceipt(for: requestID, as: .appUI) == nil)
    }
}

@Suite struct ReceiptTests {
    @Test func receiptsRoundTripThroughJSON() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        let committed = try await lab.perform(.updateItem(id: item.id, expected: .initial, changes: ItemChanges(note: "Edited")))
        let conflict = try await lab.perform(.archiveItem(id: item.id, expected: .initial))

        for receipt in [committed, conflict] {
            let decoded = try JSONDecoder().decode(ActionReceipt.self, from: JSONEncoder().encode(receipt))
            #expect(decoded == receipt)
        }

        // The persisted status shape is part of the store contract (CORE-003).
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(String(decoding: try encoder.encode(committed.status), as: UTF8.self) == #"{"state":"committed"}"#)
        let conflictJSON = String(decoding: try encoder.encode(conflict.status), as: UTF8.self)
        #expect(conflictJSON == #"{"conflict":{"current":2,"entity":{"id":"\#(item.id)","kind":"item"},"expected":1},"state":"conflict"}"#)
    }

    @Test func receiptIDsComeFromTheInjectedSource() async throws {
        let lab = Harness(operationIDs: SequentialOperationIDs())
        let first = try await lab.perform(.createCollection(draft: CollectionDraft(title: "Samples")))
        let second = try await lab.perform(.createCollection(draft: CollectionDraft(title: "Others")))
        #expect(first.operationID == OperationID(rawValue: uuid(1)))
        #expect(second.operationID == OperationID(rawValue: uuid(2)))
        #expect(first.id == first.operationID)
    }
}
