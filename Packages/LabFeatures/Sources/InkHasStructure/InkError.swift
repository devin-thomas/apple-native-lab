/// Why an ink operation was refused. Nothing in the document or the lab changes in these cases.
public enum InkError: Error, Hashable, Sendable {
    /// The document ID is not one this store holds.
    case documentNotFound
    /// There is nothing left to undo.
    case nothingToUndo
    /// A stroke, note, or size was refused before any change.
    case invalidInput(String)
    /// The working document was cancelled before a commit finished.
    case cancelled
    /// PencilKit (or another live drawing surface) is not available on this host; the mouse/touch
    /// and typed-note path still works.
    case drawingSurfaceUnavailable
    /// The lab refused the save (authorization, store, or validation).
    case saveFailed(String)

    public var message: String {
        switch self {
        case .documentNotFound:
            "That annotation document is gone. Nothing was changed."
        case .nothingToUndo:
            "Nothing to undo."
        case .invalidInput(let detail):
            "\(detail) Nothing was changed."
        case .cancelled:
            "Stopped before saving. Nothing new was committed."
        case .drawingSurfaceUnavailable:
            "The PencilKit canvas is not on this host. Draw with the pointer or touch, or type a note."
        case .saveFailed(let detail):
            detail
        }
    }
}
