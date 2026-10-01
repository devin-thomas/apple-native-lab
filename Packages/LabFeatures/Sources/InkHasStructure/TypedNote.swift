import Foundation

/// A semantic text alternative to ink: the same place on the media, as words a person typed.
///
/// Typed notes complete the task when there is no Pencil and when assistive input is in use. They
/// ride with the document ID and stay editable alongside the strokes.
public struct TypedNote: Hashable, Sendable, Codable, Identifiable {
    public static let maximumLength = 500

    public let id: UUID
    public let anchor: AnnotationAnchor
    public let text: String

    public init(id: UUID = UUID(), anchor: AnnotationAnchor, text: String) throws(InkError) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw .invalidInput("A typed note needs some text.")
        }
        guard trimmed.count <= Self.maximumLength else {
            throw .invalidInput("A typed note may be at most \(Self.maximumLength) characters.")
        }
        guard !trimmed.contains(where: { $0.isNewline }) else {
            throw .invalidInput("A typed note is one line.")
        }
        self.id = id
        self.anchor = anchor
        self.text = trimmed
    }
}
