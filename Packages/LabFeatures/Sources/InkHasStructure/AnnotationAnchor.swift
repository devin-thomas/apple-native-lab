/// A point on the annotated media, stored as fractions of the document's current size.
///
/// Anchors survive a resize: display code multiplies `x` by the new width and `y` by the new
/// height. Absolute pixel points are never persisted, so undoing a stroke after a resize still
/// lands on the same relative place on the media.
public struct AnnotationAnchor: Hashable, Sendable, Codable {
    /// Horizontal position in unit space: 0 is the leading edge, 1 is the trailing edge.
    public let x: Double
    /// Vertical position in unit space: 0 is the top edge, 1 is the bottom edge.
    public let y: Double

    public init(x: Double, y: Double) throws(InkError) {
        guard x.isFinite, y.isFinite else {
            throw .invalidInput("An anchor needs finite coordinates.")
        }
        guard (0...1).contains(x), (0...1).contains(y) else {
            throw .invalidInput("An anchor must stay inside the media (0…1 on each axis).")
        }
        self.x = x
        self.y = y
    }

    /// Builds an anchor from a point in the document's point space.
    public static func from(pointX: Double, pointY: Double, documentWidth: Double, documentHeight: Double) throws(InkError) -> AnnotationAnchor {
        guard documentWidth > 0, documentHeight > 0 else {
            throw .invalidInput("The document needs a positive size.")
        }
        return try AnnotationAnchor(x: pointX / documentWidth, y: pointY / documentHeight)
    }

    /// The point in the document's current point space.
    public func point(in size: DocumentSize) -> (x: Double, y: Double) {
        (x * size.width, y * size.height)
    }
}

/// The annotated media's size in points. Changing it remaps every anchor without rewriting strokes.
public struct DocumentSize: Hashable, Sendable, Codable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) throws(InkError) {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            throw .invalidInput("The document needs a positive, finite size.")
        }
        guard width <= Self.maximumSide, height <= Self.maximumSide else {
            throw .invalidInput("The document side may be at most \(Int(Self.maximumSide)) points.")
        }
        self.width = width
        self.height = height
    }

    public static let maximumSide: Double = 8_192
}
