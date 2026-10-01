import Foundation

/// A lossy, labeled rendering of the ink document that is never confused with the editable native
/// data. Exporting a preview leaves the document's strokes and notes untouched.
public struct FlattenedPreview: Hashable, Sendable {
    public let documentID: UUID
    public let mediaTitle: String
    public let width: Int
    public let height: Int
    public let strokeCount: Int
    public let noteCount: Int
    /// Plain-text rendering: one line per stroke or note, in document order.
    public let text: String
    /// True so a host can label the export as a flattened preview, not editable ink.
    public let isFlattenedPreview = true

    public init(document: InkDocument, scale: Double = 1) throws(InkError) {
        guard scale.isFinite, scale > 0, scale <= 4 else {
            throw .invalidInput("Preview scale must be between 0 and 4.")
        }
        documentID = document.documentID
        mediaTitle = document.mediaTitle
        width = Int((document.size.width * scale).rounded())
        height = Int((document.size.height * scale).rounded())
        strokeCount = document.layer.strokes.count
        noteCount = document.notes.count
        var lines: [String] = [
            "Flattened preview (not editable ink)",
            "Document: \(document.documentID.uuidString)",
            "Media: \(document.mediaTitle)",
            "Size: \(width)×\(height) at scale \(scale)",
        ]
        for (index, stroke) in document.layer.strokes.enumerated() {
            let first = stroke.points[0].point(in: document.size)
            let last = stroke.points[stroke.points.count - 1].point(in: document.size)
            lines.append(
                "Stroke \(index + 1): \(stroke.tool.title), \(stroke.points.count) points, from (\(Self.fmt(first.x)), \(Self.fmt(first.y))) to (\(Self.fmt(last.x)), \(Self.fmt(last.y)))"
            )
        }
        for (index, note) in document.notes.enumerated() {
            let point = note.anchor.point(in: document.size)
            lines.append("Note \(index + 1) at (\(Self.fmt(point.x)), \(Self.fmt(point.y))): \(note.text)")
        }
        if document.layer.isEmpty && document.notes.isEmpty {
            lines.append("No marks.")
        }
        text = lines.joined(separator: "\n")
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
