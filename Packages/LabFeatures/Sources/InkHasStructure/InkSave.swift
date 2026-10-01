import Foundation
import LabDomain

/// Builds the domain operation that saves an ink document into the lab library.
///
/// The document ID becomes the item ID. Editable ink rides in `extras` as a versioned entry; the
/// item note holds the typed notes as a short semantic summary. The commit goes through
/// `OperationService` as the app UI, with its receipt, the same path every other sensitive change
/// uses. Exporting a flattened preview never calls this.
public enum InkSave {
    public static let extrasKey = "inkDocument"
    public static let extrasVersion = 1

    /// Creates a new library item for a document that has never been saved. The item's extras hold
    /// the native ink; a flattened preview is not stored here.
    public static func createOperation(
        for document: InkDocument,
        in collectionID: CollectionID
    ) throws(InkError) -> DomainOperation {
        guard document.hasContent else {
            throw .invalidInput("Add a stroke or a typed note before saving.")
        }
        let title: EntityTitle
        let note: ItemNote
        let extras: ItemExtras
        do {
            title = try EntityTitle("Annotation: \(document.mediaTitle)")
            note = try ItemNote(noteText(for: document))
            extras = try ItemExtras(json: extrasJSON(for: document))
        } catch let error as InkError {
            throw error
        } catch is ValidationError {
            throw .invalidInput("The annotation title or note was refused.")
        } catch is ExtrasRejection {
            throw .invalidInput("The ink extras were refused.")
        } catch {
            throw .invalidInput("The annotation could not be prepared for saving.")
        }
        let draft = ItemDraft(id: document.itemID, in: collectionID, title: title, note: note, extras: extras)
        return .createItem(draft: draft)
    }

    /// Updates only the item note when the document was already saved (extras are immutable after
    /// creation). The live editable document stays in the experiment store.
    public static func updateNoteOperation(
        for document: InkDocument,
        expected: Revision
    ) throws(InkError) -> DomainOperation {
        let note: ItemNote
        do {
            note = try ItemNote(noteText(for: document))
        } catch {
            throw .invalidInput("The annotation note was refused.")
        }
        do {
            let changes = try ItemChanges(note: note)
            return .updateItem(id: document.itemID, expected: expected, changes: changes)
        } catch {
            throw .invalidInput("The annotation note had nothing to change.")
        }
    }

    /// Typed notes joined for the item note, or a short stroke summary when there are none.
    public static func noteText(for document: InkDocument) -> String {
        if !document.notes.isEmpty {
            return document.notes.map(\.text).joined(separator: "\n")
        }
        let count = document.layer.strokes.count
        return count == 1 ? "1 ink stroke on \(document.mediaTitle)." : "\(count) ink strokes on \(document.mediaTitle)."
    }

    /// The extras JSON object: one versioned `inkDocument` entry holding the native document
    /// without its undo stack (undo is session-local).
    public static func extrasJSON(for document: InkDocument) throws(InkError) -> String {
        let payload = SavedInk(
            format: InkDocument.format,
            schemaVersion: InkDocument.schemaVersion,
            documentID: document.documentID,
            mediaID: document.mediaID,
            mediaTitle: document.mediaTitle,
            size: document.size,
            layer: document.layer,
            notes: document.notes
        )
        let entry = ExtrasEntry(version: extrasVersion, document: payload)
        let root = ExtrasRoot(inkDocument: entry)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(root)
            guard let text = String(data: data, encoding: .utf8) else {
                throw InkError.invalidInput("Ink extras must be UTF-8.")
            }
            return text
        } catch let error as InkError {
            throw error
        } catch {
            throw .invalidInput("Ink extras could not be encoded.")
        }
    }

    private struct ExtrasRoot: Encodable {
        let inkDocument: ExtrasEntry
    }

    private struct ExtrasEntry: Encodable {
        let version: Int
        let document: SavedInk
    }

    private struct SavedInk: Encodable {
        let format: String
        let schemaVersion: Int
        let documentID: UUID
        let mediaID: String
        let mediaTitle: String
        let size: DocumentSize
        let layer: InkLayer
        let notes: [TypedNote]
    }
}
