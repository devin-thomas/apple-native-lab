import Foundation

/// A peer's identity as the handshake carries it.
struct WireIdentity: Codable, Hashable, Sendable {
    let peerID: PeerID
    /// The raw Curve25519 signing public key, base64.
    let publicKey: String
    let name: String
}

/// The protocol a peer speaks: a name and the versions it can use.
public struct ProtocolOffer: Hashable, Sendable, Codable {
    public let name: String
    public let minimumVersion: Int
    public let maximumVersion: Int

    public init(name: String, versions: ClosedRange<Int>) {
        self.name = name
        minimumVersion = versions.lowerBound
        maximumVersion = versions.upperBound
    }

    public var versions: ClosedRange<Int> { minimumVersion...max(minimumVersion, maximumVersion) }

    var isValid: Bool {
        (1...64).contains(name.utf8.count) && minimumVersion >= 1 && maximumVersion >= minimumVersion && maximumVersion <= 1_000
    }

    /// The highest version both sides speak, or `nil`.
    public func negotiate(with other: ProtocolOffer) -> Int? {
        guard name == other.name else { return nil }
        let low = max(minimumVersion, other.minimumVersion)
        let high = min(maximumVersion, other.maximumVersion)
        return low <= high ? high : nil
    }

    public var versionsText: String {
        minimumVersion == maximumVersion ? "version \(minimumVersion)" : "versions \(minimumVersion)–\(maximumVersion)"
    }
}

/// How a joiner asks in.
enum JoinMode: String, Codable, Sendable {
    /// First contact: the pair must confirm a short code.
    case pair
    /// Both sides already pinned each other; signatures prove it.
    case resume
}

/// Why a handshake was refused. Every case is explained to both people; none leaks session data.
public enum RefusalReason: String, Codable, Hashable, Sendable, CaseIterable {
    case protocolMismatch = "protocol-mismatch"
    case versionUnsupported = "version-unsupported"
    case roleUnavailable = "role-unavailable"
    case pairingRequired = "pairing-required"
    case pairingClosed = "pairing-closed"
    case identityMismatch = "identity-mismatch"
    case codeMismatch = "code-mismatch"
    case notApproved = "not-approved"
    case tooManyAttempts = "too-many-attempts"
    case malformed
    case timedOut = "timed-out"

    public var explanation: String {
        switch self {
        case .protocolMismatch: "The other device runs a different experiment."
        case .versionUnsupported: "The two devices share no protocol version. Update the older one."
        case .roleUnavailable: "The conductor does not accept that role now."
        case .pairingRequired: "This device is not paired with the conductor. Pair it with a code first."
        case .pairingClosed: "The conductor is not pairing right now. Choose Pair a Device on the conductor first."
        case .identityMismatch: "The other device's identity is not the one this device paired with. Nothing was shared."
        case .codeMismatch: "The code did not match. Nothing was paired or shared."
        case .notApproved: "The person at the conductor did not allow this device."
        case .tooManyAttempts: "Too many pairing attempts. Wait a minute, then open pairing again."
        case .malformed: "The other device sent a message this build cannot read."
        case .timedOut: "The other device stopped answering."
        }
    }
}

/// The plaintext messages of a handshake, in the order they are sent.
///
/// Pairing: `hello` (joiner, with a commitment to its ephemeral key) → `challenge` (host) →
/// `reveal` (joiner) → both show or ask for the short code → `confirm` (joiner's signature) →
/// `accepted` (host's signature). Resuming: `hello` (with the ephemeral key) → `challenge` →
/// `confirm` → `accepted`. Either side may send `refusal` instead and close.
enum HandshakeMessage: Hashable, Sendable {
    struct Hello: Codable, Hashable, Sendable {
        let offer: ProtocolOffer
        let role: PeerRole
        let identity: WireIdentity
        let mode: JoinMode
        /// Pairing: SHA-256 of the ephemeral key and nonce, hex. Absent when resuming.
        let commitment: String?
        /// Resuming: the ephemeral key agreement key, base64. Absent when pairing.
        let ephemeralKey: String?
        /// Resuming: 32 random bytes, base64. Absent when pairing.
        let nonce: String?
    }

    struct Challenge: Codable, Hashable, Sendable {
        let version: Int
        let identity: WireIdentity
        let ephemeralKey: String
        let nonce: String
    }

    struct Reveal: Codable, Hashable, Sendable {
        let ephemeralKey: String
        let nonce: String
    }

    struct Signature: Codable, Hashable, Sendable {
        let signature: String
    }

    struct Refusal: Codable, Hashable, Sendable {
        let reason: RefusalReason
        /// The refusing side's protocol offer, so a version mismatch can say which versions it speaks.
        let offer: ProtocolOffer?
    }

    case hello(Hello)
    case challenge(Challenge)
    case reveal(Reveal)
    case confirm(Signature)
    case accepted(Signature)
    case refusal(Refusal)

    var type: String {
        switch self {
        case .hello: "hello"
        case .challenge: "challenge"
        case .reveal: "reveal"
        case .confirm: "confirm"
        case .accepted: "accepted"
        case .refusal: "refusal"
        }
    }

    // MARK: Wire form: {"type": "<type>", "body": {…}}

    private static let identityKeys: Set<String> = ["peerID", "publicKey", "name"]
    private static let offerKeys: Set<String> = ["name", "minimumVersion", "maximumVersion"]

    private static func allowedKeys(for type: String) -> [String: Set<String>]? {
        switch type {
        case "hello":
            ["": ["type", "body"], "body": ["offer", "role", "identity", "mode", "commitment", "ephemeralKey", "nonce"],
             "body.identity": identityKeys, "body.offer": offerKeys]
        case "challenge":
            ["": ["type", "body"], "body": ["version", "identity", "ephemeralKey", "nonce"], "body.identity": identityKeys]
        case "reveal":
            ["": ["type", "body"], "body": ["ephemeralKey", "nonce"]]
        case "confirm", "accepted":
            ["": ["type", "body"], "body": ["signature"]]
        case "refusal":
            ["": ["type", "body"], "body": ["reason", "offer"], "body.offer": offerKeys]
        default:
            nil
        }
    }

    private struct Envelope<Body: Codable>: Codable {
        let type: String
        let body: Body
    }

    private struct TypeOnly: Decodable {
        let type: String
    }

    /// The frame for this message, kind byte included.
    var frame: Data {
        let json: Data = switch self {
        case .hello(let body): WireJSON.encode(Envelope(type: type, body: body))
        case .challenge(let body): WireJSON.encode(Envelope(type: type, body: body))
        case .reveal(let body): WireJSON.encode(Envelope(type: type, body: body))
        case .confirm(let body), .accepted(let body): WireJSON.encode(Envelope(type: type, body: body))
        case .refusal(let body): WireJSON.encode(Envelope(type: type, body: body))
        }
        return Data([FrameCodec.Kind.handshake.rawValue]) + json
    }

    /// Reads one handshake frame, kind byte included.
    init(frame: Data) throws(HandshakeFailure) {
        guard frame.first == FrameCodec.Kind.handshake.rawValue else {
            throw .malformed("Expected a handshake message.")
        }
        let json = Data(frame.dropFirst())
        guard json.count <= FrameCodec.maximumHandshakeBytes,
              let peek = try? JSONDecoder().decode(TypeOnly.self, from: json),
              let keys = Self.allowedKeys(for: peek.type) else {
            throw .malformed("The handshake message is not one this build knows.")
        }
        func read<Body: Codable>(_ body: Body.Type) throws(HandshakeFailure) -> Body {
            do {
                return try WireJSON.decode(Envelope<Body>.self, from: json, maximumBytes: FrameCodec.maximumHandshakeBytes, allowedKeys: keys).body
            } catch {
                throw .malformed("The handshake message is not valid.")
            }
        }
        switch peek.type {
        case "hello": self = .hello(try read(Hello.self))
        case "challenge": self = .challenge(try read(Challenge.self))
        case "reveal": self = .reveal(try read(Reveal.self))
        case "confirm": self = .confirm(try read(Signature.self))
        case "accepted": self = .accepted(try read(Signature.self))
        default: self = .refusal(try read(Refusal.self))
        }
    }
}

/// Why a handshake did not complete. Nothing was pinned and no session data was sent.
public enum HandshakeFailure: Error, Hashable, Sendable {
    /// The other side refused.
    case refused(RefusalReason, theirOffer: ProtocolOffer?)
    /// This side refused, and told the other side why.
    case refusedLocally(RefusalReason)
    /// A message could not be read or did not verify.
    case malformed(String)
    /// The connection closed or failed mid-handshake.
    case disconnected
    case cryptography
    case cancelled

    public var explanation: String {
        switch self {
        case .refused(.versionUnsupported, let offer?):
            "The other device speaks \(offer.versionsText) of \(offer.name). \(RefusalReason.versionUnsupported.explanation)"
        case .refused(let reason, _), .refusedLocally(let reason):
            reason.explanation
        case .malformed(let detail):
            "\(detail) Nothing was paired or shared."
        case .disconnected:
            "The connection closed before pairing finished. Nothing was shared."
        case .cryptography:
            "A cryptographic check failed. Nothing was shared."
        case .cancelled:
            "Cancelled. Nothing was paired or shared."
        }
    }
}
