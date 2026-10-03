import Foundation
import LabDomain

/// One annotated object: editable ink and typed notes under a stable document ID.
///
/// The document is the native data. A flattened preview is produced separately and never replaces
/// this value. Undo restores a prior layer and note list; anchors stay relative, so a resize in
/// between does not break the restored marks.
public struct InkDocument: Hashable, Sendable, Codable {
    public static let format = "native-lab-ink-document"
    public static let schemaVersion = 1

    public let documentID: UUID
    public let mediaID: String
    public let mediaTitle: String
    public let size: DocumentSize
    public let layer: InkLayer
    public let notes: [TypedNote]
    /// Prior (layer, notes) pairs, oldest first. Undo pops the last entry.
    public let undoStack: [InkSnapshot]

    public struct InkSnapshot: Hashable, Sendable, Codable {
        public let layer: InkLayer
        public let notes: [TypedNote]

        public init(layer: InkLayer, notes: [TypedNote]) {
            self.layer = layer
            self.notes = notes
        }
    }

    public init(
        documentID: UUID = UUID(),
        mediaID: String,
        mediaTitle: String,
        size: DocumentSize,
        layer: InkLayer = .empty,
        notes: [TypedNote] = [],
        undoStack: [InkSnapshot] = []
    ) {
        self.documentID = documentID
        self.mediaID = mediaID
        self.mediaTitle = mediaTitle
        self.size = size
        self.layer = layer
        self.notes = notes
        self.undoStack = undoStack
    }

    public var itemID: ItemID { ItemID(rawValue: documentID) }

    public var canUndo: Bool { !undoStack.isEmpty }

    public var hasContent: Bool { !layer.isEmpty || !notes.isEmpty }

    /// Adds a stroke and records the prior state for undo.
    public func adding(_ stroke: InkStroke) -> InkDocument {
        replacing(layer: layer.appending(stroke), notes: notes)
    }

    /// Removes one stroke by ID and records the prior state for undo.
    public func erasing(strokeID: UUID) throws(InkError) -> InkDocument {
        guard layer.strokes.contains(where: { $0.id == strokeID }) else {
            throw .invalidInput("That stroke is not on this document.")
        }
        return replacing(layer: layer.removing(id: strokeID), notes: notes)
    }

    /// Adds a typed note and records the prior state for undo.
    public func adding(_ note: TypedNote) -> InkDocument {
        replacing(layer: layer, notes: notes + [note])
    }

    /// Removes one typed note by ID and records the prior state for undo.
    public func removing(noteID: UUID) throws(InkError) -> InkDocument {
        guard notes.contains(where: { $0.id == noteID }) else {
            throw .invalidInput("That note is not on this document.")
        }
        return replacing(layer: layer, notes: notes.filter { $0.id != noteID })
    }

    /// Restores the last snapshot. The current size is kept, so anchors still resolve after a resize.
    public func undone() throws(InkError) -> InkDocument {
        guard let prior = undoStack.last else { throw .nothingToUndo }
        return InkDocument(
            documentID: documentID,
            mediaID: mediaID,
            mediaTitle: mediaTitle,
            size: size,
            layer: prior.layer,
            notes: prior.notes,
            undoStack: Array(undoStack.dropLast())
        )
    }

    /// Changes the document's point size. Anchors are unchanged, so marks keep their relative place.
    public func resized(to size: DocumentSize) -> InkDocument {
        InkDocument(
            documentID: documentID,
            mediaID: mediaID,
            mediaTitle: mediaTitle,
            size: size,
            layer: layer,
            notes: notes,
            undoStack: undoStack
        )
    }

    private func replacing(layer: InkLayer, notes: [TypedNote]) -> InkDocument {
        let snapshot = InkSnapshot(layer: self.layer, notes: self.notes)
        return InkDocument(
            documentID: documentID,
            mediaID: mediaID,
            mediaTitle: mediaTitle,
            size: size,
            layer: layer,
            notes: notes,
            undoStack: undoStack + [snapshot]
        )
    }
}
