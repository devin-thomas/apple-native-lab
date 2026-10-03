import Foundation

/// In-memory working documents for this experiment. Reset Demo clears only these; the lab library
/// is left alone unless a person undoes a save receipt.
///
/// Edits (draw, erase, type, resize, undo) happen here. Saving builds a domain operation and the
/// host commits it through `OperationService`. A cancellation checked between edits leaves the
/// last stored document as it was.
public actor InkDocumentStore {
    private var documents: [UUID: InkDocument] = [:]

    public init() {}

    public func document(_ id: UUID) -> InkDocument? {
        documents[id]
    }

    public func allDocuments() -> [InkDocument] {
        documents.values.sorted { $0.mediaTitle < $1.mediaTitle }
    }

    /// Opens a blank document on the sample media, replacing any prior working copy with the same ID.
    @discardableResult
    public func open(_ media: SampleMedia, documentID: UUID = UUID()) -> InkDocument {
        let document = media.openDocument(documentID: documentID)
        documents[document.documentID] = document
        return document
    }

    public func put(_ document: InkDocument) {
        documents[document.documentID] = document
    }

    public func addStroke(_ stroke: InkStroke, to id: UUID) throws(InkError) -> InkDocument {
        let updated = try require(id).adding(stroke)
        documents[id] = updated
        return updated
    }

    public func eraseStroke(_ strokeID: UUID, from id: UUID) throws(InkError) -> InkDocument {
        let updated = try require(id).erasing(strokeID: strokeID)
        documents[id] = updated
        return updated
    }

    public func addNote(_ note: TypedNote, to id: UUID) throws(InkError) -> InkDocument {
        let updated = try require(id).adding(note)
        documents[id] = updated
        return updated
    }

    public func removeNote(_ noteID: UUID, from id: UUID) throws(InkError) -> InkDocument {
        let updated = try require(id).removing(noteID: noteID)
        documents[id] = updated
        return updated
    }

    public func undo(id: UUID) throws(InkError) -> InkDocument {
        let updated = try require(id).undone()
        documents[id] = updated
        return updated
    }

    public func resize(_ size: DocumentSize, id: UUID) throws(InkError) -> InkDocument {
        let updated = try require(id).resized(to: size)
        documents[id] = updated
        return updated
    }

    /// Removes only experiment-owned working documents.
    public func resetDemo() {
        documents.removeAll()
    }

    private func require(_ id: UUID) throws(InkError) -> InkDocument {
        guard let document = documents[id] else { throw .documentNotFound }
        return document
    }
}
