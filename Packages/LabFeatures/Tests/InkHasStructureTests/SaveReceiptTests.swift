@testable import InkHasStructure
import Foundation
import LabDomain
import Testing

@Suite struct SaveReceiptTests {
    @Test func savingCommitsThroughTheOperationServiceWithAReceipt() async throws {
        let lab = try await TestLab.seeded()
        let collectionID = try await lab.annotationsCollection()
        var document = SampleMedia.harborChart.openDocument()
        document = document.adding(try sampleStroke())
        document = document.adding(try TypedNote(anchor: try AnnotationAnchor(x: 0.4, y: 0.3), text: "High water mark"))

        let operation = try InkSave.createOperation(for: document, in: collectionID)
        #expect(operation.kind == .createItem)
        #expect(operation.target == .item(document.itemID))

        let receipt = try await lab.perform(operation)
        #expect(receipt.conflict == nil)
        #expect(receipt.admitted.adapter == .appUI)
        #expect(receipt.undo?.kind == .archiveItem)

        let item = try await lab.service.findItem(document.itemID, as: TestLab.appUI)
        #expect(item.title.value == "Annotation: Harbor Chart")
        #expect(item.note.value == "High water mark")
        #expect(!item.extras.isEmpty)
        #expect(item.extras.json.contains(InkDocument.format))
        #expect(item.extras.json.contains(document.documentID.uuidString))
    }

    @Test func emptyDocumentIsRefusedBeforeAnythingIsSubmitted() async throws {
        let lab = try await TestLab.seeded()
        let collectionID = try await lab.annotationsCollection()
        let document = SampleMedia.harborChart.openDocument()
        #expect(throws: InkError.self) {
            try InkSave.createOperation(for: document, in: collectionID)
        }
        let filter = try ItemFilter(collectionID: collectionID, includeArchived: true)
        let items = try await lab.service.findItems(filter, as: TestLab.appUI)
        #expect(items.isEmpty)
    }

    @Test func duplicateSaveOfTheSameDocumentIDIsRefused() async throws {
        let lab = try await TestLab.seeded()
        let collectionID = try await lab.annotationsCollection()
        var document = SampleMedia.harborChart.openDocument()
        document = document.adding(try sampleStroke())
        let first = try await lab.perform(try InkSave.createOperation(for: document, in: collectionID))
        #expect(first.conflict == nil)

        document = document.adding(try TypedNote(anchor: try AnnotationAnchor(x: 0.5, y: 0.5), text: "Second pass"))
        let again = try InkSave.createOperation(for: document, in: collectionID)
        await #expect(throws: OperationError.ruleViolation(.alreadyExists(.item(document.itemID)))) {
            try await lab.perform(again)
        }
        let item = try await lab.service.findItem(document.itemID, as: TestLab.appUI)
        #expect(item.note.value.contains("stroke"))
    }

    @Test func updatingTheNoteGoesThroughUpdateItem() async throws {
        let lab = try await TestLab.seeded()
        let collectionID = try await lab.annotationsCollection()
        var document = SampleMedia.harborChart.openDocument()
        document = document.adding(try sampleStroke())
        let created = try await lab.perform(try InkSave.createOperation(for: document, in: collectionID))
        #expect(created.conflict == nil)

        document = document.adding(try TypedNote(anchor: try AnnotationAnchor(x: 0.2, y: 0.2), text: "Pier edge"))
        let item = try await lab.service.findItem(document.itemID, as: TestLab.appUI)
        let update = try InkSave.updateNoteOperation(for: document, expected: item.revision)
        let receipt = try await lab.perform(update)
        #expect(receipt.conflict == nil)
        #expect(receipt.undo?.kind == .updateItem)
        let updated = try await lab.service.findItem(document.itemID, as: TestLab.appUI)
        #expect(updated.note.value == "Pier edge")
    }
}
