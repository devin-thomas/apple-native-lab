import InkHasStructure
import LabDomain
import Observation
import SwiftUI

/// LAB-045's shared names.
enum InkHasStructureExperiment {
    static let id = InkHasStructure.experimentID
    static let title = InkHasStructure.title
    static let symbol = InkHasStructure.symbol
}

/// One person's working annotation session: editable ink in the experiment store, saves through
/// `LabLibrary.submit` as the app UI.
@MainActor
@Observable
final class InkSession {
    private(set) var document: InkDocument?
    private(set) var previewText: String?
    private(set) var message: String?
    private(set) var lastReceipt: ReceiptRecord?
    private(set) var isSaving = false
    var noteDraft = ""
    var tool: InkTool = .pen

    @ObservationIgnored private let store = InkDocumentStore()
    @ObservationIgnored private var saveRequest: RequestID?
    @ObservationIgnored private var annotationsCollectionID: CollectionID?
    @ObservationIgnored private var inProgressStroke: [CGPoint] = []

    #if os(iOS)
    var capability: InkCapability { .phone }
    #else
    var capability: InkCapability { .mac }
    #endif

    var canSave: Bool { document?.hasContent == true && !isSaving }
    var canUndo: Bool { document?.canUndo == true && !isSaving }

    /// Opens the sample harbor chart, replacing any prior working copy.
    func openSample() async {
        let opened = await store.open(SampleMedia.harborChart)
        document = opened
        previewText = nil
        message = "Annotate \(opened.mediaTitle). Ink stays editable; a flattened preview is separate."
        lastReceipt = nil
        noteDraft = ""
        inProgressStroke = []
    }

    func beginStroke(at point: CGPoint, in viewSize: CGSize) {
        guard document != nil, viewSize.width > 0, viewSize.height > 0 else { return }
        inProgressStroke = [point]
    }

    func continueStroke(to point: CGPoint) {
        guard !inProgressStroke.isEmpty else { return }
        inProgressStroke.append(point)
    }

    func endStroke(in viewSize: CGSize) async {
        guard var document, inProgressStroke.count >= 2, viewSize.width > 0, viewSize.height > 0 else {
            inProgressStroke = []
            return
        }
        do {
            let anchors = try inProgressStroke.map { point in
                try AnnotationAnchor(
                    x: min(1, max(0, Double(point.x / viewSize.width))),
                    y: min(1, max(0, Double(point.y / viewSize.height)))
                )
            }
            let stroke = try InkStroke(tool: tool, width: tool == .marker ? 0.04 : 0.02, points: anchors)
            document = document.adding(stroke)
            await store.put(document)
            self.document = document
            message = nil
        } catch {
            message = error.message
        }
        inProgressStroke = []
    }

    func eraseLastStroke() async {
        guard var document, let last = document.layer.strokes.last else {
            message = InkError.invalidInput("There is no stroke to erase.").message
            return
        }
        do {
            document = try document.erasing(strokeID: last.id)
            await store.put(document)
            self.document = document
            message = nil
        } catch {
            message = error.message
        }
    }

    func undo() async {
        guard let id = document?.documentID else { return }
        do {
            let updated = try await store.undo(id: id)
            document = updated
            message = nil
        } catch {
            message = error.message
        }
    }

    func addTypedNote() async {
        guard var document else { return }
        do {
            let note = try TypedNote(anchor: try AnnotationAnchor(x: 0.5, y: 0.12), text: noteDraft)
            document = document.adding(note)
            await store.put(document)
            self.document = document
            noteDraft = ""
            message = nil
        } catch {
            message = error.message
        }
    }

    func resize(scale: Double) async {
        guard let current = document else { return }
        do {
            let size = try DocumentSize(width: current.size.width * scale, height: current.size.height * scale)
            let updated = try await store.resize(size, id: current.documentID)
            document = updated
            message = "Document resized to \(Int(size.width))×\(Int(size.height)). Anchors kept their place."
        } catch {
            message = error.message
        }
    }

    func exportPreview() {
        guard let document else { return }
        do {
            let preview = try FlattenedPreview(document: document)
            previewText = preview.text
            message = "Flattened preview exported separately from the editable ink."
        } catch {
            message = error.message
        }
    }

    /// Saves through the operation service. Creates the Annotations collection on first save.
    @discardableResult
    func save(in library: LabLibrary) async -> ReceiptRecord? {
        guard let document, canSave else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let collectionID = try await annotationsCollection(in: library)
            let existing = library.item(document.itemID)
            let operation: DomainOperation
            if let existing {
                operation = try InkSave.updateNoteOperation(for: document, expected: existing.revision)
            } else {
                operation = try InkSave.createOperation(for: document, in: collectionID)
            }
            let requestID = saveRequest ?? RequestID()
            saveRequest = requestID
            let record = try await library.submit(operation, requestID: requestID, authority: .userAction, names: [
                .item(document.itemID): "Annotation: \(document.mediaTitle)",
            ])
            saveRequest = nil
            lastReceipt = record
            message = record.receipt.summary
            LabAnnouncement(receipt: ReceiptPresentation(record)).post()
            return record
        } catch let error as InkError {
            message = error.message
            LabAnnouncement(failure: error.message).post()
            return nil
        } catch {
            let sentence = Self.describe(error)
            message = sentence
            LabAnnouncement(failure: sentence).post()
            return nil
        }
    }

    /// Clears only this experiment's working documents.
    func resetDemo() async {
        await store.resetDemo()
        document = nil
        previewText = nil
        lastReceipt = nil
        noteDraft = ""
        message = "Reset the experiment's working ink. Library items and their receipts were left alone."
    }

    #if os(iOS)
    /// Replaces freehand strokes from a PencilKit drawing (any-input policy), keeping typed notes.
    /// PencilKit owns gesture undo for those strokes; the domain undo stack is unchanged here.
    func adoptPencilKitStrokes(_ strokes: [InkStroke]) async {
        guard let document else { return }
        let replaced = InkDocument(
            documentID: document.documentID,
            mediaID: document.mediaID,
            mediaTitle: document.mediaTitle,
            size: document.size,
            layer: InkLayer(strokes: strokes),
            notes: document.notes,
            undoStack: document.undoStack
        )
        await store.put(replaced)
        self.document = replaced
    }
    #endif

    static func describe(_ error: any Error) -> String {
        switch error {
        case let failure as LabLibrary.SubmitFailure:
            switch failure {
            case .unavailable(let reason): reason
            case .refused(let refusal): LibraryMessages.describe(refusal)
            }
        default:
            LibraryMessages.describe(error)
        }
    }

    private func annotationsCollection(in library: LabLibrary) async throws(InkError) -> CollectionID {
        if let annotationsCollectionID { return annotationsCollectionID }
        if let existing = library.collections.first(where: {
            $0.collection.namespace == .user && $0.collection.title.value == "Annotations"
        }) {
            annotationsCollectionID = existing.collection.id
            return existing.collection.id
        }
        let title: EntityTitle
        do {
            title = try EntityTitle("Annotations")
        } catch {
            throw .invalidInput("The Annotations collection title was refused.")
        }
        let draft = CollectionDraft(title: title)
        do {
            let record = try await library.submit(
                .createCollection(draft: draft),
                requestID: RequestID(),
                authority: .userAction,
                names: [.collection(draft.id): title.value]
            )
            if record.receipt.conflict != nil {
                throw InkError.saveFailed(record.receipt.summary)
            }
            annotationsCollectionID = draft.id
            return draft.id
        } catch let error as InkError {
            throw error
        } catch {
            throw .saveFailed(Self.describe(error))
        }
    }
}

extension LabLibrary {
    fileprivate func item(_ id: ItemID) -> LabItem? {
        collections.lazy.flatMap(\.items).first { $0.id == id }
    }
}
