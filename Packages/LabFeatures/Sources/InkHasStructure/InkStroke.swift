import Foundation

/// One freehand mark on an ink layer, as editable data rather than pixels.
///
/// Points are anchors, so the stroke keeps its place when the document resizes. The tool is a
/// lab-owned label for the fallback mouse/touch path and for semantic alternatives; it is not a
/// PencilKit ink type.
public struct InkStroke: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let tool: InkTool
    /// Normalized stroke width relative to the shorter document side (for example 0.01).
    public let width: Double
    public let points: [AnnotationAnchor]

    public init(id: UUID = UUID(), tool: InkTool = .pen, width: Double, points: [AnnotationAnchor]) throws(InkError) {
        guard points.count >= 2 else {
            throw .invalidInput("A stroke needs at least two points.")
        }
        guard width.isFinite, width > 0, width <= 0.25 else {
            throw .invalidInput("A stroke width must be a positive fraction at most 0.25 of the short side.")
        }
        self.id = id
        self.tool = tool
        self.width = width
        self.points = points
    }
}

/// How a stroke was made. The host may map these to PencilKit tools when a canvas is present; the
/// domain never imports PencilKit.
public enum InkTool: String, Hashable, Sendable, Codable, CaseIterable {
    case pen
    case marker
    case pencil

    public var title: String {
        switch self {
        case .pen: "Pen"
        case .marker: "Marker"
        case .pencil: "Pencil"
        }
    }
}
