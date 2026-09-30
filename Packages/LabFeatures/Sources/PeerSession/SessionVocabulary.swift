import Foundation

/// A typed payload an experiment sends inside a session envelope.
///
/// Payloads are data only: never code, method names, file paths, or command lines. The receiver
/// decodes one into this type and calls `isValid`, so a payload that decodes but carries an
/// out-of-range number or an oversized string is refused like a malformed one.
public protocol WirePayload: Codable, Hashable, Sendable {
    /// The keys the payload's JSON object may have. Anything else is refused as an unknown field.
    static var wireKeys: Set<String> { get }
    /// Whether the decoded content is within the experiment's bounds.
    var isValid: Bool { get }
}

/// What one experiment's session speaks: its protocol name and versions, and its three payload
/// types. The session layer is generic over this, so later experiments reuse pairing, the sealed
/// channel, clock estimates, sequencing, and presence by declaring their own vocabulary.
public protocol SessionVocabulary: Sendable {
    /// A request to change the conductor's state. Reliable: queued, acknowledged, never dropped
    /// silently, and either admitted, reconciled, or refused.
    associatedtype Command: WirePayload
    /// A high-frequency reading. Replaceable: only the newest matters, and a stale one is dropped.
    associatedtype Sample: WirePayload
    /// The conductor's whole authoritative state, sent after every admitted change and whenever a
    /// peer must resynchronize.
    associatedtype Snapshot: WirePayload

    static var offer: ProtocolOffer { get }
    /// The roles that may send `command`. The conductor checks this for every command it receives.
    static func rolesAllowed(toSend command: Command) -> Set<PeerRole>
    /// The roles whose samples the conductor accepts and relays.
    static var sampleSenders: Set<PeerRole> { get }
    /// The roles the conductor relays samples to.
    static var sampleReceivers: Set<PeerRole> { get }
}

/// Which queue a message travels in.
public enum Channel: String, Codable, Hashable, Sendable, CaseIterable {
    /// Commands, their results, snapshots, and goodbyes. In order; a gap means continuity was lost.
    case reliable
    /// Samples and clock probes. Only the newest matters; a gap is counted and a stale one dropped.
    case replaceable
}

/// How the conductor answered a command.
public enum CommandDisposition: String, Codable, Hashable, Sendable, CaseIterable {
    /// Received and waiting, for example for a person at the conductor to allow it.
    case received
    /// Admitted and applied; the result names the new revision.
    case applied
    /// Admitted, but it changed nothing (the state was already so).
    case unchanged
    /// Based on an older revision than the current one. Nothing changed; a snapshot follows so the
    /// sender can see the current state and decide again.
    case stale
    /// Older than the session allows, measured with the clock estimate. Nothing changed.
    case expired
    /// Sent under an earlier session epoch, before the conductor restarted. Nothing changed.
    case wrongEpoch = "wrong-epoch"
    /// Sequence continuity was lost. Nothing changed; a snapshot follows, and the sender may send
    /// again once it has it.
    case needsSnapshot = "needs-snapshot"
    /// The sender's role may not send this command.
    case notAllowed = "not-allowed"
    /// The conductor, or the person there, refused it.
    case refused
    /// The payload was outside the vocabulary's bounds.
    case invalid

    /// Whether the command's life is over.
    public var isFinal: Bool { self != .received }

    /// Whether the conductor's state changed.
    public var changedState: Bool { self == .applied }
}

/// The conductor's answer to one command. A replayed command ID gets the same answer again.
public struct CommandResult: Codable, Hashable, Sendable {
    public static let maximumSummaryLength = 200

    public let commandID: MessageID
    public let disposition: CommandDisposition
    /// The revision after the command, or the current one when nothing changed.
    public let revision: Int
    /// A sentence for people, written by the conductor. Never the sender's own text.
    public let summary: String

    public init(commandID: MessageID, disposition: CommandDisposition, revision: Int, summary: String) {
        self.commandID = commandID
        self.disposition = disposition
        self.revision = revision
        self.summary = WireText.clean(summary, limit: Self.maximumSummaryLength)
    }

    static let wireKeys: Set<String> = ["commandID", "disposition", "revision", "summary"]

    private enum CodingKeys: String, CodingKey {
        case commandID, disposition, revision, summary
    }

    /// A received summary is cleaned like one written here, so it cannot carry control characters.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            commandID: try container.decode(MessageID.self, forKey: .commandID),
            disposition: try container.decode(CommandDisposition.self, forKey: .disposition),
            revision: try container.decode(Int.self, forKey: .revision),
            summary: try container.decode(String.self, forKey: .summary)
        )
    }
}
