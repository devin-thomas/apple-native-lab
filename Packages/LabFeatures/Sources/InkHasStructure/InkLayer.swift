import Foundation

/// The editable ink on one document: strokes only, never a flattened bitmap.
public struct InkLayer: Hashable, Sendable, Codable {
    public let strokes: [InkStroke]

    public static let empty = InkLayer(strokes: [])

    public init(strokes: [InkStroke]) {
        self.strokes = strokes
    }

    public var isEmpty: Bool { strokes.isEmpty }

    public func appending(_ stroke: InkStroke) -> InkLayer {
        InkLayer(strokes: strokes + [stroke])
    }

    public func removing(id: UUID) -> InkLayer {
        InkLayer(strokes: strokes.filter { $0.id != id })
    }
}
