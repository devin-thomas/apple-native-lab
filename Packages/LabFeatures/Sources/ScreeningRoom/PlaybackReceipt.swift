import Foundation
import LabDomain

/// The answer to one playback command, kept under its request ID so a retry gets the same answer.
///
/// It mirrors the domain's `ActionReceipt`: which request, through which adapter, what happened,
/// the revisions before and after, a sentence, and the undo when one exists. Playback is live
/// session state, not a stored record, so these receipts stay with the session instead of the
/// store (docs/ARCHITECTURE.md, "live session transport").
public struct PlaybackReceipt: Hashable, Sendable, Codable, Identifiable {
    public enum Status: Hashable, Sendable, Codable {
        case applied
        /// The command asked for what was already true. Nothing changed.
        case unchanged
        /// The sender saw an older revision. Nothing changed; `current` is what it should look at.
        case conflict(expected: Revision, current: Revision)
    }

    public var id: RequestID { requestID }
    public let requestID: RequestID
    public let adapter: AdapterKind
    public let source: CommandSource
    public let command: PlaybackCommand
    public let expected: Revision?
    public let status: Status
    public let previous: Revision
    public let revision: Revision
    public let summary: String
    /// The command that reverses this one, when there is an exact reverse.
    public let undo: PlaybackCommand?

    public var didChange: Bool { status == .applied }

    /// Whether a retry with this content is the same request.
    func matches(_ request: PlaybackRequest) -> Bool {
        command == request.command && adapter == request.actor.adapter && expected == request.expected
    }
}
