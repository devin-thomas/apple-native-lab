import Foundation

/// One entry of a link's wire log: what crossed the transport, as sealed bytes, and what it was.
public struct WireRecord: Hashable, Sendable, Identifiable {
    public enum Direction: String, Hashable, Sendable {
        case sent
        case received
    }

    public let id: UInt64
    public let direction: Direction
    public let peer: PeerID
    public let kind: String
    public let channel: Channel
    public let sequence: UInt64
    /// The sealed frame's size, which is the same on every transport for the same envelope.
    public let frameBytes: Int
    /// The envelope's plaintext JSON. Only this process's own log sees it.
    public let plaintext: Data
}

/// Why a received frame was not delivered to the session.
public enum LinkRejection: Hashable, Sendable {
    /// It failed authentication, or reused a counter. The link is closed: the bytes were altered,
    /// replayed, or not from the paired peer.
    case unauthenticated
    /// It opened, but is not a valid envelope for this vocabulary.
    case malformed(WireDecodingError)
    /// Its header claims another sender, role, or protocol version than the link was paired for.
    case impersonation
}

/// A sealed, authenticated link to one peer, carrying `SessionEnvelope`s.
///
/// It numbers each channel separately, seals every envelope, and checks every received one against
/// the identity and role the handshake established. It does not interpret messages; `Conductor`
/// and `Client` do.
public actor PeerLink<V: SessionVocabulary> {
    public nonisolated let local: PeerIdentity
    public nonisolated let remote: PeerIdentity
    public nonisolated let localRole: PeerRole
    public nonisolated let remoteRole: PeerRole
    public nonisolated let version: Int
    public nonisolated let pairedNow: Bool
    public nonisolated let remoteLabel: String

    private let connection: any PeerConnection
    private let mailbox: FrameMailbox
    private var channel: SecureChannel
    private let clock: any PeerClock
    private let makeMessageID: @Sendable () -> MessageID
    private let record: (@Sendable (WireRecord) -> Void)?
    private var nextSequence: [Channel: UInt64] = [.reliable: 1, .replaceable: 1]
    private var recordCounter: UInt64 = 0
    public private(set) var rejections: [LinkRejection] = []
    public private(set) var isClosed = false

    /// - Parameters:
    ///   - isHost: whether this side accepted the handshake (the conductor) rather than joined.
    ///   - record: sees every envelope sent and received, for the wire log.
    public init(
        _ link: EstablishedLink,
        isHost: Bool,
        clock: any PeerClock,
        makeMessageID: @escaping @Sendable () -> MessageID = { MessageID() },
        record: (@Sendable (WireRecord) -> Void)? = nil
    ) {
        local = link.local
        remote = link.remote
        localRole = isHost ? .conductor : link.joinerRole
        remoteRole = isHost ? link.joinerRole : .conductor
        version = link.version
        pairedNow = link.pairedNow
        remoteLabel = link.connection.remoteLabel
        connection = link.connection
        mailbox = link.mailbox
        channel = link.channel
        self.clock = clock
        self.makeMessageID = makeMessageID
        self.record = record
    }

    /// Seals and sends one message. Returns the envelope as sent.
    @discardableResult
    public func send(
        _ message: SessionMessage<V>,
        session: LiveSessionID,
        epoch: SessionEpoch,
        baseRevision: Int? = nil,
        messageID: MessageID? = nil
    ) async throws(TransportError) -> SessionEnvelope<V> {
        guard !isClosed else { throw .closed }
        let sequence = nextSequence[message.channel, default: 1]
        nextSequence[message.channel] = sequence + 1
        let envelope = SessionEnvelope<V>(
            protocolVersion: version, sessionID: session, sessionEpoch: epoch, messageID: messageID ?? makeMessageID(),
            senderPeerID: local.id, role: localRole, sequence: sequence, sentAt: clock.now(),
            baseRevision: baseRevision, message: message
        )
        let plaintext = envelope.json
        let frame: Data
        do { frame = try channel.seal(plaintext) } catch { throw .failed("The envelope could not be sealed.") }
        log(.sent, envelope, plaintext: plaintext, frameBytes: frame.count)
        do {
            try await connection.send(frame)
        } catch {
            close()
            throw error
        }
        return envelope
    }

    /// The next valid envelope, or `nil` when the link has closed.
    ///
    /// Frames that open but are not valid envelopes are recorded in `rejections` and skipped. A
    /// frame that fails authentication closes the link.
    public func receive() async -> SessionEnvelope<V>? {
        while !isClosed {
            let frame: Data?
            do { frame = try await mailbox.receive() } catch { frame = nil }
            guard let frame else {
                close()
                return nil
            }
            let plaintext: Data
            do {
                plaintext = try channel.open(frame)
            } catch {
                rejections.append(.unauthenticated)
                close()
                return nil
            }
            let envelope: SessionEnvelope<V>
            do {
                envelope = try SessionEnvelope<V>(json: plaintext)
            } catch {
                rejections.append(.malformed(error))
                continue
            }
            guard envelope.senderPeerID == remote.id, envelope.role == remoteRole, envelope.protocolVersion == version else {
                rejections.append(.impersonation)
                continue
            }
            log(.received, envelope, plaintext: plaintext, frameBytes: frame.count)
            return envelope
        }
        return nil
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        connection.close()
        Task { await mailbox.stop() }
    }

    private func log(_ direction: WireRecord.Direction, _ envelope: SessionEnvelope<V>, plaintext: Data, frameBytes: Int) {
        guard let record else { return }
        recordCounter += 1
        record(WireRecord(
            id: recordCounter, direction: direction, peer: remote.id, kind: envelope.message.kind,
            channel: envelope.channel, sequence: envelope.sequence, frameBytes: frameBytes, plaintext: plaintext
        ))
    }
}
