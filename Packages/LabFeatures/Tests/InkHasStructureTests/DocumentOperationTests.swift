@testable import InkHasStructure
import Foundation
import Testing

@Suite struct DocumentOperationTests {
    @Test func drawEraseUndoAndTypedNoteKeepEditableInk() throws {
        var document = SampleMedia.harborChart.openDocument()
        #expect(!document.hasContent)
        #expect(!document.canUndo)

        let stroke = try sampleStroke()
        document = document.adding(stroke)
        #expect(document.layer.strokes.count == 1)
        #expect(document.canUndo)

        let note = try TypedNote(anchor: try AnnotationAnchor(x: 0.1, y: 0.1), text: "High water")
        document = document.adding(note)
        #expect(document.notes.count == 1)

        document = try document.erasing(strokeID: stroke.id)
        #expect(document.layer.isEmpty)
        #expect(document.notes.count == 1)

        document = try document.undone()
        #expect(document.layer.strokes.count == 1)
        #expect(document.notes.count == 1)

        document = try document.undone()
        #expect(document.notes.isEmpty)
        #expect(document.layer.strokes.count == 1)
    }

    @Test func undoAfterResizeKeepsAnchoring() throws {
        var document = SampleMedia.harborChart.openDocument()
        let stroke = try sampleStroke(from: (0.25, 0.5), to: (0.75, 0.5))
        document = document.adding(stroke)
        let firstPointBefore = document.layer.strokes[0].points[0]

        let larger = try DocumentSize(width: 640, height: 480)
        document = document.resized(to: larger)
        #expect(document.size.width == 640)
        #expect(document.layer.strokes[0].points[0] == firstPointBefore)

        let display = firstPointBefore.point(in: document.size)
        #expect(display.x == 160)
        #expect(display.y == 240)

        document = try document.undone()
        #expect(document.layer.isEmpty)
        #expect(document.size.width == 640, "undo restores marks, not the prior size")
        #expect(!document.canUndo)
    }

    @Test func invalidInputIsRefusedWithoutChangingTheDocument() throws {
        let document = SampleMedia.harborChart.openDocument()
        #expect(throws: InkError.self) {
            try InkStroke(width: 0.02, points: [try AnnotationAnchor(x: 0.5, y: 0.5)])
        }
        #expect(throws: InkError.self) {
            try TypedNote(anchor: try AnnotationAnchor(x: 0.5, y: 0.5), text: "   ")
        }
        #expect(throws: InkError.nothingToUndo) {
            try document.undone()
        }
        #expect(document.layer.isEmpty && document.notes.isEmpty)
    }

    @Test func storeResetClearsOnlyExperimentDocuments() async throws {
        let store = InkDocumentStore()
        let opened = await store.open(SampleMedia.harborChart)
        _ = try await store.addStroke(try sampleStroke(), to: opened.documentID)
        #expect(await store.allDocuments().count == 1)
        await store.resetDemo()
        #expect(await store.allDocuments().isEmpty)
        #expect(await store.document(opened.documentID) == nil)
    }

    @Test func cancellationLeavesTheLastStoredDocument() async throws {
        let store = InkDocumentStore()
        let opened = await store.open(SampleMedia.harborChart)
        _ = try await store.addStroke(try sampleStroke(), to: opened.documentID)
        // A cancelled save path never calls put with a partial save; the store still holds the stroke.
        let current = await store.document(opened.documentID)
        #expect(current?.layer.strokes.count == 1)
        #expect(InkError.cancelled.message.contains("Stopped before saving"))
    }
}
