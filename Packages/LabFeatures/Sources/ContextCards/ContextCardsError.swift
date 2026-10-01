import ActionAtlas
import AppIntents
import Foundation
import LabDomain

/// Why a context-card decision did not complete. A stale screen and a schema mismatch change
/// nothing. Each case has a sentence a person can act on.
public enum ContextCardsError: Error, Hashable, Sendable {
    /// The claimed Apple schema does not match the sample, so nothing was associated.
    case schemaMismatch(String)
    /// The decision was for a sample that is no longer on screen.
    case staleVisibleContent(title: String)
    /// The Shortcut's request ID is not a UUID.
    case invalidRequestID
    /// Action Atlas refused the read or the set-aside.
    case action(ActionAtlasError)
    /// The decision was cancelled before anything was committed.
    case cancelled

    public var message: String {
        switch self {
        case .schemaMismatch(let reason):
            reason
        case .staleVisibleContent(let title):
            "“\(title)” is no longer the sample on screen, so it was not changed."
        case .invalidRequestID:
            "The request ID must be a UUID, such as one made by the Shortcuts action “UUID”. Nothing was changed."
        case .action(let error):
            error.message
        case .cancelled:
            "Cancelled. Nothing was changed."
        }
    }
}

extension ContextCardsError: LocalizedError, CustomLocalizedStringResourceConvertible {
    public var errorDescription: String? { message }
    public var localizedStringResource: LocalizedStringResource { "\(message)" }
}
