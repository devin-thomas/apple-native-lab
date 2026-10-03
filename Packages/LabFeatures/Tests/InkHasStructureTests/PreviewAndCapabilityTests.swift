@testable import InkHasStructure
import Testing

@Suite struct PreviewAndCapabilityTests {
    @Test func flattenedPreviewIsSeparateFromNativeData() throws {
        var document = SampleMedia.harborChart.openDocument()
        document = document.adding(try sampleStroke())
        document = document.adding(try TypedNote(anchor: try AnnotationAnchor(x: 0.1, y: 0.9), text: "Low tide"))
        let preview = try FlattenedPreview(document: document)
        #expect(preview.isFlattenedPreview)
        #expect(preview.strokeCount == 1)
        #expect(preview.noteCount == 1)
        #expect(preview.text.contains("Flattened preview (not editable ink)"))
        #expect(preview.text.contains("Low tide"))
        #expect(document.layer.strokes.count == 1, "exporting a preview must not clear ink")
        #expect(document.notes.count == 1)
    }

    @Test func nonPencilPathsCompleteTheTaskAndAbsentGesturesStayAbsent() throws {
        #expect(InkCapability.mac.canCompleteTask)
        #expect(!InkCapability.mac.pencilKitCanvasAvailable)
        #expect(InkCapability.mac.mouseOrTouchDrawingAvailable)
        #expect(InkCapability.mac.typedNotesAvailable)
        #expect(InkCapability.mac.unsupportedPencilGestures == InkCapability.defaultAbsentGestures)

        #expect(InkCapability.phone.pencilKitCanvasAvailable)
        #expect(InkCapability.phone.unsupportedPencilGestures.contains("pencil-squeeze"))

        #expect(InkCapability.typedNotesOnly.canCompleteTask)
        #expect(!InkCapability.typedNotesOnly.mouseOrTouchDrawingAvailable)
        #expect(InkCapability.mac.fallbackSummary == InkHasStructure.fallback)
    }

    @Test func fixtureMatchesBundledSampleMedia() throws {
        let fixture = try Fixtures.sampleMediaFile()
        #expect(fixture.media.id == SampleMedia.harborChart.id)
        #expect(fixture.media.title == SampleMedia.harborChart.title)
        #expect(fixture.media.width == SampleMedia.harborChart.width)
        #expect(fixture.media.height == SampleMedia.harborChart.height)
        #expect(fixture.task.fallback == InkHasStructure.fallback)
        #expect(fixture.absentPencilGestures == InkCapability.defaultAbsentGestures)
    }
}
