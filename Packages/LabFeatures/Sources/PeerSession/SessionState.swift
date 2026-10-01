import Foundation

/// One line of a session's event log, for people. Written by this device, never copied from a
/// peer's text.
public struct SessionEvent: Hashable, Sendable, Identifiable {
    public enum Severity: String, Hashable, Sendable {
        case info
        /// Something was refused, lost, or went stale, and the session handled it.
        case notice
        /// A link failed or a peer misbehaved.
        case problem
    }

    public let id: UInt64
    public let at: PeerInstant
    public let severity: Severity
    public let text: String
}

/// A bounded event log.
struct EventLog: Sendable {
    static let capacity = 60
    private(set) var events: [SessionEvent] = []
    private var counter: UInt64 = 0

    mutating func add(_ text: String, at instant: PeerInstant, _ severity: SessionEvent.Severity = .info) {
        counter += 1
        events.append(SessionEvent(id: counter, at: instant, severity: severity, text: text))
        if events.count > Self.capacity { events.removeFirst(events.count - Self.capacity) }
    }
}

/// Counts from one direction of one link.
public struct LinkCounters: Hashable, Sendable {
    /// Reliable envelopes that arrived out of sequence: continuity was lost.
    public var reliableGaps = 0
    /// Replaceable envelopes that never arrived, counted from gaps in their sequence.
    public var replaceableMissing: UInt64 = 0
    /// Replaceable envelopes dropped because a newer one had already arrived.
    public var staleDropped = 0
    /// Received frames refused as unauthenticated, malformed, or impersonating.
    public var refusedFrames = 0

    public init() {}
}

/// How one peer looks from the conductor.
public struct PeerStatus: Hashable, Sendable, Identifiable {
    public var id: PeerID { identity.id }
    public let identity: PeerIdentity
    public let role: PeerRole
    public let presence: Presence
    /// How long since anything was heard from the peer.
    public let silence: Duration
    public let clock: ClockEstimate?
    public let counters: LinkCounters
    /// Links after the first one.
    public let reconnections: Int
    public let admittedCommands: Int
    public let refusedCommands: Int
    /// Whether the peer has the current snapshot and may have commands admitted.
    public let isSynchronized: Bool
}

/// A command that waits for the person at the conductor.
public struct PendingCommand<Command: WirePayload>: Hashable, Sendable, Identifiable {
    public var id: MessageID { commandID }
    public let commandID: MessageID
    public let command: Command
    public let from: PeerIdentity
    public let role: PeerRole
    public let receivedAt: PeerInstant
    public let expiresAt: PeerInstant
}

/// Whether the conductor accepts new pairings.
public struct PairingWindow: Hashable, Sendable {
    public let closesAt: PeerInstant
    public let attemptsLeft: Int
}

/// Everything the conductor's views show. A value: the conductor publishes a new one after each
/// change, and a view never reaches into the conductor.
public struct ConductorState<V: SessionVocabulary>: Sendable {
    public let identity: PeerIdentity
    public let sessionID: LiveSessionID
    public let epoch: SessionEpoch
    public let revision: Int
    public let snapshot: V.Snapshot
    public let peers: [PeerStatus]
    public let pending: [PendingCommand<V.Command>]
    public let pairing: PairingWindow?
    /// The pairing the person must allow or deny, with the code to read out.
    public let pairingRequest: PairingRequest?
    public let events: [SessionEvent]
    public let now: PeerInstant
}

/// The joiner's connection, as its views show it.
public enum ClientPhase: Hashable, Sendable {
    case idle
    /// Handshaking. While pairing, `ClientState.codePrompt` asks for the code.
    case connecting
    /// Joined, waiting for the conductor's snapshot before sending anything.
    case synchronizing
    case live
    /// Connected, but the conductor has been silent past the stale threshold.
    case stale
    case disconnected(reason: String)

    public var title: String {
        switch self {
        case .idle: "Not connected"
        case .connecting: "Connecting"
        case .synchronizing: "Synchronizing"
        case .live: "Live"
        case .stale: "Stale"
        case .disconnected: "Disconnected"
        }
    }
}

/// One command's life on the device that sent it.
public enum CommandStage: Hashable, Sendable {
    /// Waiting to be sent: not connected, or not yet synchronized.
    case queued
    /// Sent; no answer yet.
    case sent(attempts: Int)
    /// The conductor has it and is waiting, for example for its person to allow it.
    case received(CommandResult)
    /// The conductor's final answer.
    case finished(CommandResult)
    /// Never sent: it waited longer than a command may live. Nothing changed.
    case expiredBeforeSending
    /// Never sent: too many commands were already waiting.
    case queueFull
    /// The conductor forgot this device before answering. It is never sent again, not even after
    /// pairing anew; a command that was sent may or may not have been applied.
    case withdrawn

    public var isFinal: Bool {
        switch self {
        case .queued, .sent, .received: false
        case .finished, .expiredBeforeSending, .queueFull, .withdrawn: true
        }
    }
}

public struct TrackedCommand<Command: WirePayload>: Hashable, Sendable, Identifiable {
    public let id: MessageID
    public let command: Command
    /// The revision the person saw when they acted.
    public let baseRevision: Int
    public let issuedAt: PeerInstant
    public let issuedIn: SessionEpoch?
    public var stage: CommandStage
}

/// Everything the joiner's views show.
public struct ClientState<V: SessionVocabulary>: Sendable {
    public let identity: PeerIdentity
    public let role: PeerRole
    public let phase: ClientPhase
    public let host: PeerIdentity?
    public let codePrompt: CodePrompt?
    public let sessionID: LiveSessionID?
    public let epoch: SessionEpoch?
    public let revision: Int?
    public let snapshot: V.Snapshot?
    /// How long since anything was heard from the conductor.
    public let silence: Duration?
    public let commands: [TrackedCommand<V.Command>]
    /// The newest sample from each origin, as relayed by the conductor.
    public let samples: [PeerID: SampleBody<V.Sample>]
    public let clock: ClockEstimate?
    public let counters: LinkCounters
    public let reconnections: Int
    public let events: [SessionEvent]
    public let now: PeerInstant
}
