/// Why a continuation could not be advertised, resumed, or imported.
///
/// Sentences name the outcome and never repeat text from the payload. A continuation is untrusted
/// data: echoing a field would reveal whatever a sender stuffed into it.
public enum PickUpError: Error, Hashable, Sendable {
    case cancelled
    /// The payload, link, or document is not a continuation this build understands.
    case invalidPayload
    /// The store could not be read or written. Nothing was changed.
    case unavailable
    /// The actor may not read this draft, or its access was revoked.
    case notAuthorized
    /// The draft is not in this lab, on the side that expected to advertise it.
    case missing
    /// The import has nowhere to go: no collection of the person's own is available.
    case destinationUnavailable
    /// The draft is longer than an item note, or the document exceeds its byte limit.
    case tooLarge

    public var sentence: String {
        switch self {
        case .cancelled: "Cancelled. Nothing was resumed."
        case .invalidPayload: "That continuation could not be read. Nothing was opened."
        case .unavailable: "The lab store could not be used. Nothing was resumed."
        case .notAuthorized: "Access to this draft was revoked. Its contents are not shown."
        case .missing: "This draft is not in the lab, so there is nothing to continue."
        case .destinationUnavailable: "Choose one of your own collections to hold the draft."
        case .tooLarge: "The draft is too long to store. Nothing was imported."
        }
    }
}
