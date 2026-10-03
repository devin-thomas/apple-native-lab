import Foundation

/// The original sample media this experiment annotates. Built only from the fixture; never from a
/// person's photos or private accounts.
public struct SampleMedia: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let width: Double
    public let height: Double

    public init(id: String, title: String, summary: String, width: Double, height: Double) throws(InkError) {
        guard !id.isEmpty, !title.isEmpty else {
            throw .invalidInput("Sample media needs an id and a title.")
        }
        _ = try DocumentSize(width: width, height: height)
        self.id = id
        self.title = title
        self.summary = summary
        self.width = width
        self.height = height
    }

    public var size: DocumentSize {
        // Validated in `init`.
        try! DocumentSize(width: width, height: height)
    }

    /// Opens a blank annotation document on this media.
    public func openDocument(documentID: UUID = UUID()) -> InkDocument {
        InkDocument(documentID: documentID, mediaID: id, mediaTitle: title, size: size)
    }

    /// The bundled harbor chart: a fictional tide grid, 320 × 240 points.
    public static let harborChart = try! SampleMedia(
        id: "harbor-chart",
        title: "Harbor Chart",
        summary: "A fictional tide grid for the sample pier. Annotate high-water marks or type a note.",
        width: 320,
        height: 240
    )
}
