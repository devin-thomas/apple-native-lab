import Foundation

/// Why a desktop operation stopped. Nothing is committed when one of these is thrown, except
/// `alreadyStored`, which means the note was already committed and the caller should keep that copy.
public enum DesktopPowerError: Error, Hashable, Sendable, CustomStringConvertible, LocalizedError {
    case emptyText
    case textTooLong(limit: Int)
    /// The text is not a note: it is not UTF-8, or it contains a control character a note cannot.
    case invalidText
    /// The text is not one of the allowlisted command tokens.
    case unknownCommand(String)
    /// The text looks like a shell command. It is refused before anything runs.
    case shellRefused
    case cancelled
    /// The lab store cannot be used. Nothing was written.
    case unavailable
    case notAuthorized
    /// A note with this identity is already in the lab.
    case alreadyStored
    case missingDocument
    /// A private note is not opened from a restored scene.
    case privateContentWithheld

    public var description: String {
        switch self {
        case .emptyText:
            "The note is empty, so nothing was imported."
        case .textTooLong(let limit):
            "The note is longer than \(limit) characters, so nothing was imported."
        case .invalidText:
            "The selection is not text this lab can keep, so nothing was imported."
        case .unknownCommand(let token):
            "“\(token)” is not an allowlisted desktop command, so nothing ran."
        case .shellRefused:
            "That text is not an allowlisted desktop command, so nothing ran."
        case .cancelled:
            "The import was cancelled. Nothing was imported."
        case .unavailable:
            "The lab store is unavailable, so nothing was imported."
        case .notAuthorized:
            "This entry point cannot change the lab, so nothing was imported."
        case .alreadyStored:
            "This note is already in the lab."
        case .missingDocument:
            "That note is not open in this lab."
        case .privateContentWithheld:
            "This private note stays closed until you open it."
        }
    }

    public var errorDescription: String? { description }
}
