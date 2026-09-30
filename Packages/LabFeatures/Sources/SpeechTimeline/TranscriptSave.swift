import Foundation
import LabDomain

/// Saving a transcript to one of the person's collections: one `createItem` through the operation
/// service, committed as the app UI with a receipt, like every other change in the lab.
///
/// The item's note holds the transcript's text. Its extras hold the whole export under
/// `speechTimeline`, so the saved item keeps every segment's media range, recognized text, and
/// source, and the audio reference. Provisional text is never saved.
public struct TranscriptSave: Hashable, Sendable {
    /// The extras key the export is kept under.
    public static let extrasKey = "speechTimeline"

    public let requestID: RequestID
    public let itemID: ItemID
    public let collectionID: CollectionID
    /// The timeline revision this save captures. A later correction needs a new save.
    public let revision: Int
    public let operation: DomainOperation
    /// Whether the note had to be shortened. The extras always hold every segment.
    public let noteWasShortened: Bool

    /// Builds the operation for `timeline`. Nothing is committed here.
    public static func prepare(
        _ timeline: TranscriptTimeline,
        audio: AudioReference,
        language: String,
        title: String,
        into collectionID: CollectionID,
        requestID: RequestID = RequestID(),
        itemID: ItemID = ItemID()
    ) throws(SpeechSaveError) -> TranscriptSave {
        guard !timeline.segments.isEmpty else { throw .nothingToSave }
        let entityTitle: EntityTitle
        do {
            entityTitle = try EntityTitle(String(title.prefix(EntityTitle.maximumLength)))
        } catch {
            throw .invalidTitle
        }
        var text = timeline.plainText
        let shortened = text.count > ItemNote.maximumLength
        if shortened { text = String(text.prefix(ItemNote.maximumLength - 1)) + "…" }
        let note: ItemNote
        let extras: ItemExtras
        do {
            note = try ItemNote(text)
            let export = try TimelineExport(timeline: timeline, audio: audio, language: language).encoded()
            guard let exportText = String(data: export, encoding: .utf8) else { throw SpeechSaveError.tooLargeToSave }
            extras = try ItemExtras(json: "{\"\(extrasKey)\":\(exportText)}")
        } catch let error as SpeechSaveError {
            throw error
        } catch is ExtrasRejection {
            throw .tooLargeToSave
        } catch {
            throw .tooLargeToSave
        }
        let draft = ItemDraft(id: itemID, in: collectionID, title: entityTitle, note: note, extras: extras)
        return TranscriptSave(
            requestID: requestID, itemID: itemID, collectionID: collectionID, revision: timeline.revision,
            operation: .createItem(draft: draft), noteWasShortened: shortened
        )
    }
}

/// Why a transcript was not saved. Nothing was stored.
public enum SpeechSaveError: Error, Hashable, Sendable {
    case nothingToSave
    case invalidTitle
    /// The export is larger than an item's extras can hold. Export it to a file instead.
    case tooLargeToSave
    /// The store cannot be used. The reason is a sentence for a person.
    case unavailable(String)
    case refused(OperationError)

    public var message: String {
        switch self {
        case .nothingToSave: "There are no finalized segments to save yet."
        case .invalidTitle: "The transcript needs a title of 1 to \(EntityTitle.maximumLength) characters."
        case .tooLargeToSave: "This timeline is too large to keep in the collection. Export it to a file instead."
        case .unavailable(let reason): reason
        case .refused(let error): "The lab refused the save (\(DiagnosticCategory(classifying: error).rawValue)). Nothing was stored."
        }
    }
}

/// How a host saves transcripts. The host's implementation commits through its operation service
/// as the app UI, so the receipt joins the session's receipt list.
public protocol SpeechTimelineBackend: Sendable {
    /// The person's collections that can take a new item.
    func destinations() async throws(SpeechSaveError) -> [LabCollection]
    /// Commits a prepared save, returning its receipt. A retry with the same request ID returns
    /// the same receipt and adds nothing.
    func commit(_ save: TranscriptSave) async throws(SpeechSaveError) -> ActionReceipt
}
