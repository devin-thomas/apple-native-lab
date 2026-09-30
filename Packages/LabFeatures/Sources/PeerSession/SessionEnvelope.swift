import Foundation

/// A command with the time its sender issued it, so a command that waited too long is refused
/// rather than applied to a later session.
public struct IssuedCommand<Command: WirePayload>: Codable, Hashable, Sendable {
    public let command: Command
    /// The sender's monotonic clock when the person acted.
    public let issuedAt: PeerInstant
    /// The conductor's epoch the person saw when they acted, or `nil` if they had seen none.
    public let issuedIn: SessionEpoch?

    public init(command: Command, issuedAt: PeerInstant, issuedIn: SessionEpoch?) {
        self.command = command
        self.issuedAt = issuedAt
        self.issuedIn = issuedIn
    }

    static var wireKeys: Set<String> { ["command", "issuedAt", "issuedIn"] }
}

/// The conductor's state at one revision.
public struct SnapshotBody<Snapshot: WirePayload>: Codable, Hashable, Sendable {
    public let revision: Int
    public let state: Snapshot

    static var wireKeys: Set<String> { ["revision", "state"] }
}

/// A sample, with the peer it came from. The conductor relays samples without changing them.
public struct SampleBody<Sample: WirePayload>: Codable, Hashable, Sendable {
    public let origin: PeerID
    public let sample: Sample
    /// The origin's own count of samples, so a relayed stream shows gaps from its source.
    public let streamSequence: UInt64

    static var wireKeys: Set<String> { ["origin", "sample", "streamSequence"] }
}

/// One clock probe: `sentAt` on the prober's clock; the answer adds the responder's receive and
/// send times on its own clock.
public struct ClockProbe: Codable, Hashable, Sendable {
    public let originatedAt: PeerInstant
    public let receivedAt: PeerInstant?
    public let answeredAt: PeerInstant?

    static let wireKeys: Set<String> = ["originatedAt", "receivedAt", "answeredAt"]
}

/// Why a peer asks for a snapshot.
public enum SnapshotReason: String, Codable, Hashable, Sendable {
    case joined
    case sequenceGap = "sequence-gap"
    case epochChanged = "epoch-changed"

    static let wireKeys: Set<String> = ["reason"]
}

/// Why a peer is leaving.
public enum GoodbyeReason: String, Codable, Hashable, Sendable {
    case leaving
    case sessionEnded = "session-ended"
    case forgotten

    static let wireKeys: Set<String> = ["reason"]
}

/// Everything a session sends after the handshake.
public enum SessionMessage<V: SessionVocabulary>: Hashable, Sendable {
    case command(IssuedCommand<V.Command>)
    case result(CommandResult)
    case snapshot(SnapshotBody<V.Snapshot>)
    case snapshotRequest(SnapshotReason)
    case sample(SampleBody<V.Sample>)
    case clockPing(ClockProbe)
    case clockPong(ClockProbe)
    case goodbye(GoodbyeReason)

    public var kind: String {
        switch self {
        case .command: "command"
        case .result: "result"
        case .snapshot: "snapshot"
        case .snapshotRequest: "snapshot-request"
        case .sample: "sample"
        case .clockPing: "clock-ping"
        case .clockPong: "clock-pong"
        case .goodbye: "goodbye"
        }
    }

    /// Commands, results, snapshots, and goodbyes are reliable; samples and clock probes are
    /// replaceable.
    public var channel: Channel {
        switch self {
        case .command, .result, .snapshot, .snapshotRequest, .goodbye: .reliable
        case .sample, .clockPing, .clockPong: .replaceable
        }
    }

    /// Keys allowed for each kind's payload, and for the objects nested in it.
    static func payloadKeys(for kind: String) -> [String: Set<String>]? {
        switch kind {
        case "command":
            ["payload": IssuedCommand<V.Command>.wireKeys, "payload.command": V.Command.wireKeys]
        case "result":
            ["payload": CommandResult.wireKeys]
        case "snapshot":
            ["payload": SnapshotBody<V.Snapshot>.wireKeys, "payload.state": V.Snapshot.wireKeys]
        case "snapshot-request":
            ["payload": SnapshotReason.wireKeys]
        case "sample":
            ["payload": SampleBody<V.Sample>.wireKeys, "payload.sample": V.Sample.wireKeys]
        case "clock-ping", "clock-pong":
            ["payload": ClockProbe.wireKeys]
        case "goodbye":
            ["payload": GoodbyeReason.wireKeys]
        default:
            nil
        }
    }

    var isValid: Bool {
        switch self {
        case .command(let issued): issued.command.isValid
        case .snapshot(let body): body.revision >= 0 && body.state.isValid
        case .sample(let body): body.sample.isValid
        case .result(let result): result.revision >= 0
        case .clockPing(let probe): probe.receivedAt == nil && probe.answeredAt == nil
        case .clockPong(let probe): probe.receivedAt != nil && probe.answeredAt != nil
        case .snapshotRequest, .goodbye: true
        }
    }
}

/// The protocol-v1 session envelope (docs/DATA_CONTRACTS.md, Live session envelope).
///
/// Every message after the handshake is one envelope, sealed by `SecureChannel`. The receiver
/// checks the version, session, epoch, sender, and role against the link it arrived on, never
/// trusting the envelope's own claims about who sent it.
public struct SessionEnvelope<V: SessionVocabulary>: Hashable, Sendable {
    public let protocolVersion: Int
    public let sessionID: LiveSessionID
    public let sessionEpoch: SessionEpoch
    public let messageID: MessageID
    public let senderPeerID: PeerID
    public let role: PeerRole
    /// This sender's count of envelopes on `message.channel`, from 1 on each link.
    public let sequence: UInt64
    /// The sender's monotonic clock when it sent the envelope.
    public let sentAt: PeerInstant
    /// For a command: the revision of the state its sender saw. `nil` for everything else.
    public let baseRevision: Int?
    public let message: SessionMessage<V>

    public var channel: Channel { message.channel }

    public init(
        protocolVersion: Int,
        sessionID: LiveSessionID,
        sessionEpoch: SessionEpoch,
        messageID: MessageID,
        senderPeerID: PeerID,
        role: PeerRole,
        sequence: UInt64,
        sentAt: PeerInstant,
        baseRevision: Int?,
        message: SessionMessage<V>
    ) {
        self.protocolVersion = protocolVersion
        self.sessionID = sessionID
        self.sessionEpoch = sessionEpoch
        self.messageID = messageID
        self.senderPeerID = senderPeerID
        self.role = role
        self.sequence = sequence
        self.sentAt = sentAt
        self.baseRevision = baseRevision
        self.message = message
    }

    // MARK: Wire form

    static var topLevelKeys: Set<String> {
        ["protocolVersion", "sessionID", "sessionEpoch", "messageID", "senderPeerID", "role", "channel",
         "sequence", "sentAt", "baseRevision", "kind", "payload"]
    }

    /// The envelope's JSON, which `SecureChannel` seals.
    public var json: Data {
        let header = Header(
            protocolVersion: protocolVersion, sessionID: sessionID, sessionEpoch: sessionEpoch, messageID: messageID,
            senderPeerID: senderPeerID, role: role, channel: channel, sequence: sequence, sentAt: sentAt,
            baseRevision: baseRevision, kind: message.kind
        )
        return switch message {
        case .command(let payload): WireJSON.encode(Wire(header: header, payload: payload))
        case .result(let payload): WireJSON.encode(Wire(header: header, payload: payload))
        case .snapshot(let payload): WireJSON.encode(Wire(header: header, payload: payload))
        case .snapshotRequest(let reason): WireJSON.encode(Wire(header: header, payload: Reason(reason: reason)))
        case .sample(let payload): WireJSON.encode(Wire(header: header, payload: payload))
        case .clockPing(let payload), .clockPong(let payload): WireJSON.encode(Wire(header: header, payload: payload))
        case .goodbye(let reason): WireJSON.encode(Wire(header: header, payload: Reason(reason: reason)))
        }
    }

    /// Reads an opened envelope's JSON, refusing anything outside the format.
    public init(json: Data) throws(WireDecodingError) {
        guard let peek = try? JSONDecoder().decode(KindOnly.self, from: json),
              var keys = SessionMessage<V>.payloadKeys(for: peek.kind) else {
            throw .invalidContent
        }
        keys[""] = Self.topLevelKeys
        func read<Payload: Codable>(_ type: Payload.Type) throws(WireDecodingError) -> Wire<Payload> {
            try WireJSON.decode(Wire<Payload>.self, from: json, maximumBytes: FrameCodec.maximumFrameBytes, allowedKeys: keys)
        }
        let header: Header
        let message: SessionMessage<V>
        switch peek.kind {
        case "command":
            let wire = try read(IssuedCommand<V.Command>.self)
            (header, message) = (wire.header, .command(wire.payload))
        case "result":
            let wire = try read(CommandResult.self)
            (header, message) = (wire.header, .result(wire.payload))
        case "snapshot":
            let wire = try read(SnapshotBody<V.Snapshot>.self)
            (header, message) = (wire.header, .snapshot(wire.payload))
        case "snapshot-request":
            let wire = try read(Reason<SnapshotReason>.self)
            (header, message) = (wire.header, .snapshotRequest(wire.payload.reason))
        case "sample":
            let wire = try read(SampleBody<V.Sample>.self)
            (header, message) = (wire.header, .sample(wire.payload))
        case "clock-ping":
            let wire = try read(ClockProbe.self)
            (header, message) = (wire.header, .clockPing(wire.payload))
        case "clock-pong":
            let wire = try read(ClockProbe.self)
            (header, message) = (wire.header, .clockPong(wire.payload))
        default:
            let wire = try read(Reason<GoodbyeReason>.self)
            (header, message) = (wire.header, .goodbye(wire.payload.reason))
        }
        guard header.kind == message.kind, header.channel == message.channel, message.isValid,
              header.sequence >= 1, header.protocolVersion >= 1,
              (header.baseRevision == nil) != (header.kind == "command"),
              (header.baseRevision ?? 0) >= 0 else {
            throw .invalidContent
        }
        self.init(
            protocolVersion: header.protocolVersion, sessionID: header.sessionID, sessionEpoch: header.sessionEpoch,
            messageID: header.messageID, senderPeerID: header.senderPeerID, role: header.role, sequence: header.sequence,
            sentAt: header.sentAt, baseRevision: header.baseRevision, message: message
        )
    }

    private struct KindOnly: Decodable {
        let kind: String
    }

    private struct Reason<Value: Codable & Hashable>: Codable {
        let reason: Value
    }

    private struct Header: Hashable {
        let protocolVersion: Int
        let sessionID: LiveSessionID
        let sessionEpoch: SessionEpoch
        let messageID: MessageID
        let senderPeerID: PeerID
        let role: PeerRole
        let channel: Channel
        let sequence: UInt64
        let sentAt: PeerInstant
        let baseRevision: Int?
        let kind: String
    }

    /// The flat wire object: the header's fields beside `payload`.
    private struct Wire<Payload: Codable>: Codable {
        let header: Header
        let payload: Payload

        init(header: Header, payload: Payload) {
            self.header = header
            self.payload = payload
        }

        enum CodingKeys: String, CodingKey {
            case protocolVersion, sessionID, sessionEpoch, messageID, senderPeerID, role, channel, sequence, sentAt
            case baseRevision, kind, payload
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            header = Header(
                protocolVersion: try c.decode(Int.self, forKey: .protocolVersion),
                sessionID: try c.decode(LiveSessionID.self, forKey: .sessionID),
                sessionEpoch: try c.decode(SessionEpoch.self, forKey: .sessionEpoch),
                messageID: try c.decode(MessageID.self, forKey: .messageID),
                senderPeerID: try c.decode(PeerID.self, forKey: .senderPeerID),
                role: try c.decode(PeerRole.self, forKey: .role),
                channel: try c.decode(Channel.self, forKey: .channel),
                sequence: try c.decode(UInt64.self, forKey: .sequence),
                sentAt: try c.decode(PeerInstant.self, forKey: .sentAt),
                baseRevision: try c.decodeIfPresent(Int.self, forKey: .baseRevision),
                kind: try c.decode(String.self, forKey: .kind)
            )
            payload = try c.decode(Payload.self, forKey: .payload)
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(header.protocolVersion, forKey: .protocolVersion)
            try c.encode(header.sessionID, forKey: .sessionID)
            try c.encode(header.sessionEpoch, forKey: .sessionEpoch)
            try c.encode(header.messageID, forKey: .messageID)
            try c.encode(header.senderPeerID, forKey: .senderPeerID)
            try c.encode(header.role, forKey: .role)
            try c.encode(header.channel, forKey: .channel)
            try c.encode(header.sequence, forKey: .sequence)
            try c.encode(header.sentAt, forKey: .sentAt)
            try c.encodeIfPresent(header.baseRevision, forKey: .baseRevision)
            try c.encode(header.kind, forKey: .kind)
            try c.encode(payload, forKey: .payload)
        }
    }
}
