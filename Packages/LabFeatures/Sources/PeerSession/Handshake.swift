import CryptoKit
import Foundation

/// What the person at the host sees while a device pairs: who is asking, for which role, and the
/// code to read out.
public struct PairingRequest: Hashable, Sendable {
    public let peer: PeerIdentity
    public let role: PeerRole
    public let code: PairingCode
}

/// What the person at the joiner sees while pairing: which host asks for a code.
public struct CodePrompt: Hashable, Sendable {
    public let host: PeerIdentity
}

/// A completed handshake: a sealed channel to an authenticated peer.
public struct EstablishedLink: Sendable {
    public let connection: any PeerConnection
    public let local: PeerIdentity
    public let remote: PeerIdentity
    /// The role the joiner holds. On the joiner, its own role; on the host, the peer's.
    public let joinerRole: PeerRole
    public let version: Int
    /// Whether this handshake paired the peers, rather than resuming an earlier pairing.
    public let pairedNow: Bool
    let channel: SecureChannel
    let mailbox: FrameMailbox
}

/// The host's side of a handshake: the conductor accepting a controller or a display.
public struct HostHandshake: Sendable {
    public struct Configuration: Sendable {
        public var identity: LocalIdentity
        public var offer: ProtocolOffer
        public var trust: any PeerTrustStore
        /// How long to wait for each of the joiner's messages.
        public var stepTimeout: Duration

        public init(identity: LocalIdentity, offer: ProtocolOffer, trust: any PeerTrustStore, stepTimeout: Duration = .seconds(10)) {
            self.identity = identity
            self.offer = offer
            self.trust = trust
            self.stepTimeout = stepTimeout
        }
    }

    /// What the host lets in right now. The conductor answers from its own state.
    public struct Admission: Sendable {
        /// Whether a joiner may take this role now.
        public var acceptsRole: @Sendable (PeerRole) async -> Bool
        /// Whether pairing is open, and takes one attempt from its allowance. `false` refuses a
        /// pairing hello; a resume from a pinned peer does not need it.
        public var takePairingAttempt: @Sendable () async -> PairingAttemptDecision
        /// Shows the code and asks the person to allow the device. Must return `false` when its
        /// task is cancelled: the joiner gave up or the code did not match there.
        public var approve: @Sendable (PairingRequest) async -> Bool

        public init(
            acceptsRole: @escaping @Sendable (PeerRole) async -> Bool,
            takePairingAttempt: @escaping @Sendable () async -> PairingAttemptDecision,
            approve: @escaping @Sendable (PairingRequest) async -> Bool
        ) {
            self.acceptsRole = acceptsRole
            self.takePairingAttempt = takePairingAttempt
            self.approve = approve
        }
    }

    public let configuration: Configuration
    public let admission: Admission
    let now: @Sendable () -> Date

    public init(configuration: Configuration, admission: Admission, now: @escaping @Sendable () -> Date = Date.init) {
        self.configuration = configuration
        self.admission = admission
        self.now = now
    }

    /// Runs the host's side on a new connection. On failure the connection is closed and nothing
    /// was pinned or sent beyond the handshake.
    public func run(on connection: any PeerConnection) async throws(HandshakeFailure) -> EstablishedLink {
        let mailbox = FrameMailbox()
        await mailbox.start(connection)
        var exchange = HandshakeExchange(connection: connection, mailbox: mailbox, timeout: configuration.stepTimeout)
        do {
            return try await accept(&exchange)
        } catch {
            if case .refusedLocally(let reason) = error {
                await exchange.sendRefusal(.refusal(.init(reason: reason, offer: configuration.offer)))
            }
            connection.close()
            await mailbox.stop()
            throw error
        }
    }

    private func accept(_ exchange: inout HandshakeExchange) async throws(HandshakeFailure) -> EstablishedLink {
        guard case .hello(let hello) = try await exchange.receive() else { throw .refusedLocally(.malformed) }
        guard hello.offer.isValid, hello.offer.name == configuration.offer.name else { throw .refusedLocally(.protocolMismatch) }
        guard let version = configuration.offer.negotiate(with: hello.offer) else { throw .refusedLocally(.versionUnsupported) }
        guard hello.role != .conductor, await admission.acceptsRole(hello.role) else { throw .refusedLocally(.roleUnavailable) }
        let joiner: PeerIdentity
        do { joiner = try PeerIdentity(wire: hello.identity) } catch { throw .refusedLocally(.malformed) }

        let keys = EphemeralKeys()
        let local = configuration.identity
        let challenge = HandshakeMessage.challenge(.init(
            version: version, identity: local.identity.wire, ephemeralKey: keys.publicKeyText, nonce: keys.nonceText
        ))
        let joinerKey: Curve25519.KeyAgreement.PublicKey
        switch hello.mode {
        case .resume:
            // A peer this host never paired, or paired for another role, learns only that it
            // must pair. It receives no challenge, no identity, and no session data.
            guard case .trusted = await configuration.trust.check(joiner, role: hello.role) else {
                throw .refusedLocally(.pairingRequired)
            }
            guard hello.commitment == nil, let keyText = hello.ephemeralKey, let nonceText = hello.nonce else {
                throw .refusedLocally(.malformed)
            }
            do {
                joinerKey = try EphemeralKeys.publicKey(from: keyText)
                _ = try EphemeralKeys.nonce(from: nonceText)
            } catch { throw .refusedLocally(.malformed) }
            try await exchange.send(challenge)
        case .pair:
            switch await admission.takePairingAttempt() {
            case .allowed: break
            case .closed: throw .refusedLocally(.pairingClosed)
            case .exhausted: throw .refusedLocally(.tooManyAttempts)
            }
            guard let commitment = hello.commitment, hello.ephemeralKey == nil, hello.nonce == nil else {
                throw .refusedLocally(.malformed)
            }
            try await exchange.send(challenge)
            guard case .reveal(let reveal) = try await exchange.receive() else { throw .refusedLocally(.malformed) }
            let nonce: Data
            do {
                joinerKey = try EphemeralKeys.publicKey(from: reveal.ephemeralKey)
                nonce = try EphemeralKeys.nonce(from: reveal.nonce)
            } catch { throw .refusedLocally(.malformed) }
            guard EphemeralKeys.commitment(publicKey: joinerKey.rawRepresentation, nonce: nonce) == commitment else {
                throw .refusedLocally(.malformed)
            }
        }

        let transcript = exchange.transcript.digest
        let secret = try keys.sharedSecret(with: joinerKey)
        let confirmation: HandshakeMessage.Signature
        if hello.mode == .pair {
            let request = PairingRequest(peer: joiner, role: hello.role, code: PairingCode(transcript: transcript))
            confirmation = try await confirmPairing(request, exchange: &exchange)
        } else {
            guard case .confirm(let signature) = try await exchange.receive() else { throw .refusedLocally(.malformed) }
            confirmation = signature
        }
        guard let signature = Data(base64Encoded: confirmation.signature),
              joiner.publicKey.isValidSignature(signature, for: SignatureContext.joinerConfirm.message(transcript)) else {
            throw .refusedLocally(.identityMismatch)
        }
        if hello.mode == .pair {
            await configuration.trust.pin(PinnedPeer(identity: joiner, roles: [hello.role], pinnedAt: now()))
        }
        let accept = try local.sign(SignatureContext.hostAccept.message(transcript))
        try await exchange.send(.accepted(.init(signature: accept.base64EncodedString())))
        return EstablishedLink(
            connection: exchange.connection, local: local.identity, remote: joiner, joinerRole: hello.role,
            version: version, pairedNow: hello.mode == .pair,
            channel: SecureChannel(secret: secret, transcript: transcript, isHost: true), mailbox: exchange.mailbox
        )
    }

    /// Waits for both the person's Allow and the joiner's confirmation. The joiner confirms only
    /// after its person typed the matching code; if it refuses instead, the host's prompt is
    /// cancelled.
    private func confirmPairing(
        _ request: PairingRequest,
        exchange: inout HandshakeExchange
    ) async throws(HandshakeFailure) -> HandshakeMessage.Signature {
        enum Event: Sendable {
            case approval(Bool)
            case frame(Result<ReceivedHandshake, HandshakeFailure>)
        }
        let approve = admission.approve
        let mailbox = exchange.mailbox
        // The person may take a while to read the code; the joiner's confirmation may too.
        let patience = Duration.seconds(120)
        let outcome: (Bool?, ReceivedHandshake?)
        do {
            outcome = try await withThrowingTaskGroup(of: Event.self) { group in
                group.addTask { .approval(await approve(request)) }
                group.addTask {
                    do {
                        return .frame(.success(try await HandshakeExchange.read(from: mailbox, timeout: patience)))
                    } catch let failure as HandshakeFailure {
                        return .frame(.failure(failure))
                    }
                }
                var approval: Bool?
                var message: ReceivedHandshake?
                while approval == nil || message == nil, let event = try await group.next() {
                    switch event {
                    case .approval(let allowed):
                        approval = allowed
                        if !allowed { group.cancelAll(); return (false, message) }
                    case .frame(.success(let received)):
                        message = received
                        if case .confirm = received.message { continue }
                        group.cancelAll()
                        return (approval, received)
                    case .frame(.failure(let failure)):
                        group.cancelAll()
                        throw failure
                    }
                }
                return (approval, message)
            }
        } catch let failure as HandshakeFailure {
            throw failure
        } catch {
            throw .cancelled
        }
        if let message = outcome.1 { exchange.record(message) }
        switch (outcome.0, outcome.1?.message) {
        case (true, .confirm(let signature)?):
            return signature
        case (_, .refusal(let refusal)?):
            throw .refused(refusal.reason, theirOffer: refusal.offer)
        case (false, _):
            throw .refusedLocally(.notApproved)
        default:
            throw .refusedLocally(.malformed)
        }
    }
}

/// Whether the host takes a pairing attempt now.
public enum PairingAttemptDecision: Hashable, Sendable {
    case allowed
    /// No one opened pairing on the host.
    case closed
    /// Pairing is open but its allowance of attempts is spent.
    case exhausted
}

/// The joiner's side of a handshake: a controller or a display joining a conductor.
public struct JoinerHandshake: Sendable {
    public enum Mode: Sendable {
        /// First contact. `enterCode` asks the person for the code the host shows; `nil` cancels.
        case pair(enterCode: @Sendable (CodePrompt) async -> PairingCode?)
        /// Reconnect to a host this device pinned. Anything else is refused before any session data.
        case resume(host: PeerID)
    }

    public let identity: LocalIdentity
    public let offer: ProtocolOffer
    public let role: PeerRole
    public let trust: any PeerTrustStore
    public let stepTimeout: Duration
    let now: @Sendable () -> Date

    public init(
        identity: LocalIdentity,
        offer: ProtocolOffer,
        role: PeerRole,
        trust: any PeerTrustStore,
        stepTimeout: Duration = .seconds(10),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.identity = identity
        self.offer = offer
        self.role = role
        self.trust = trust
        self.stepTimeout = stepTimeout
        self.now = now
    }

    public func run(on connection: any PeerConnection, mode: Mode) async throws(HandshakeFailure) -> EstablishedLink {
        let mailbox = FrameMailbox()
        await mailbox.start(connection)
        var exchange = HandshakeExchange(connection: connection, mailbox: mailbox, timeout: stepTimeout)
        do {
            return try await join(&exchange, mode: mode)
        } catch {
            if case .refusedLocally(let reason) = error {
                await exchange.sendRefusal(.refusal(.init(reason: reason, offer: offer)))
            }
            connection.close()
            await mailbox.stop()
            throw error
        }
    }

    private func join(_ exchange: inout HandshakeExchange, mode: Mode) async throws(HandshakeFailure) -> EstablishedLink {
        let keys = EphemeralKeys()
        let hello: HandshakeMessage.Hello = switch mode {
        case .pair:
            .init(offer: offer, role: role, identity: identity.identity.wire, mode: .pair,
                  commitment: keys.commitment, ephemeralKey: nil, nonce: nil)
        case .resume:
            .init(offer: offer, role: role, identity: identity.identity.wire, mode: .resume,
                  commitment: nil, ephemeralKey: keys.publicKeyText, nonce: keys.nonceText)
        }
        try await exchange.send(.hello(hello))
        let challenge: HandshakeMessage.Challenge
        switch try await exchange.receive() {
        case .challenge(let received): challenge = received
        case .refusal(let refusal): throw .refused(refusal.reason, theirOffer: refusal.offer)
        default: throw .refusedLocally(.malformed)
        }
        guard offer.versions.contains(challenge.version) else { throw .refusedLocally(.versionUnsupported) }
        let host: PeerIdentity
        let hostKey: Curve25519.KeyAgreement.PublicKey
        do {
            host = try PeerIdentity(wire: challenge.identity)
            hostKey = try EphemeralKeys.publicKey(from: challenge.ephemeralKey)
            _ = try EphemeralKeys.nonce(from: challenge.nonce)
        } catch { throw .refusedLocally(.malformed) }

        switch mode {
        case .resume(let expected):
            guard host.id == expected, case .trusted = await trust.check(host, role: .conductor) else {
                throw .refusedLocally(.identityMismatch)
            }
        case .pair(let enterCode):
            try await exchange.send(.reveal(.init(ephemeralKey: keys.publicKeyText, nonce: keys.nonceText)))
            let code = PairingCode(transcript: exchange.transcript.digest)
            guard let typed = await enterCode(CodePrompt(host: host)) else {
                throw Task.isCancelled ? .cancelled : .refusedLocally(.notApproved)
            }
            guard typed == code else { throw .refusedLocally(.codeMismatch) }
        }

        let transcript = exchange.transcript.digest
        let secret = try keys.sharedSecret(with: hostKey)
        let signature = try identity.sign(SignatureContext.joinerConfirm.message(transcript))
        try await exchange.send(.confirm(.init(signature: signature.base64EncodedString())))
        // Pairing waits on the person at the host, who allows only after this side said the code
        // matched.
        let acceptance: HandshakeMessage
        if case .pair = mode {
            acceptance = try await exchange.receive(timeout: .seconds(120))
        } else {
            acceptance = try await exchange.receive()
        }
        switch acceptance {
        case .accepted(let accepted):
            guard let hostSignature = Data(base64Encoded: accepted.signature),
                  host.publicKey.isValidSignature(hostSignature, for: SignatureContext.hostAccept.message(transcript)) else {
                throw .refusedLocally(.identityMismatch)
            }
        case .refusal(let refusal):
            throw .refused(refusal.reason, theirOffer: refusal.offer)
        default:
            throw .refusedLocally(.malformed)
        }
        if case .pair = mode {
            await trust.pin(PinnedPeer(identity: host, roles: [.conductor], pinnedAt: now()))
        }
        return EstablishedLink(
            connection: exchange.connection, local: identity.identity, remote: host, joinerRole: role,
            version: challenge.version, pairedNow: { if case .pair = mode { true } else { false } }(),
            channel: SecureChannel(secret: secret, transcript: transcript, isHost: false), mailbox: exchange.mailbox
        )
    }
}

/// Sends and receives handshake frames, adding each to the transcript.
struct HandshakeExchange {
    let connection: any PeerConnection
    let mailbox: FrameMailbox
    let timeout: Duration
    private(set) var transcript = Transcript()

    init(connection: any PeerConnection, mailbox: FrameMailbox, timeout: Duration) {
        self.connection = connection
        self.mailbox = mailbox
        self.timeout = timeout
    }

    mutating func send(_ message: HandshakeMessage) async throws(HandshakeFailure) {
        let frame = message.frame
        transcript.append(frame)
        do {
            try await connection.send(frame)
        } catch {
            // The other side may have refused and closed while this side was busy, for example
            // while its person typed a code. Its refusal is still in the mailbox; report that.
            if let received = try? await Self.read(from: mailbox, timeout: .milliseconds(50)),
               case .refusal(let refusal) = received.message {
                throw .refused(refusal.reason, theirOffer: refusal.offer)
            }
            throw .disconnected
        }
    }

    /// Sends a refusal without adding it to the transcript, ignoring failure: the handshake is over.
    func sendRefusal(_ refusal: HandshakeMessage) async {
        try? await connection.send(refusal.frame)
    }

    mutating func receive(timeout: Duration? = nil) async throws(HandshakeFailure) -> HandshakeMessage {
        let received = try await Self.read(from: mailbox, timeout: timeout ?? self.timeout)
        record(received)
        return received.message
    }

    /// Adds a message read elsewhere (by `read`) to the transcript, as the bytes that arrived.
    mutating func record(_ received: ReceivedHandshake) {
        transcript.append(received.frame)
    }

    static func read(from mailbox: FrameMailbox, timeout: Duration) async throws(HandshakeFailure) -> ReceivedHandshake {
        let frame: Data?
        do {
            frame = try await mailbox.receive(within: timeout)
        } catch is MailboxTimeout {
            throw .refusedLocally(.timedOut)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .disconnected
        }
        guard let frame else { throw .disconnected }
        do {
            return ReceivedHandshake(message: try HandshakeMessage(frame: frame), frame: frame)
        } catch {
            throw .refusedLocally(.malformed)
        }
    }
}

/// A handshake message and the exact bytes it arrived as, which the transcript hashes.
struct ReceivedHandshake: Sendable {
    let message: HandshakeMessage
    let frame: Data
}
