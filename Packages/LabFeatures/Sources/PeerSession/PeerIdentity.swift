import CryptoKit
import Foundation

/// A peer as others see it: a signing public key, the ID derived from it, and a display name.
///
/// The name is only a label. It is never a key or an authority: two peers may share a name, and a
/// peer is recognized by its key alone.
public struct PeerIdentity: Hashable, Sendable {
    public static let maximumNameLength = 64

    public let id: PeerID
    public let publicKey: Curve25519.Signing.PublicKey
    public let name: String

    public init(publicKey: Curve25519.Signing.PublicKey, name: String) {
        id = PeerID(publicKey: publicKey)
        self.publicKey = publicKey
        self.name = PeerIdentity.cleaned(name)
    }

    /// Reads the wire form. The ID must match the key, and the key must be a valid one.
    init(wire: WireIdentity) throws(HandshakeFailure) {
        guard let raw = Data(base64Encoded: wire.publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else {
            throw .malformed("The peer's public key is not valid.")
        }
        self.init(publicKey: key, name: wire.name)
        guard id == wire.peerID else { throw .malformed("The peer's ID does not match its key.") }
    }

    var wire: WireIdentity {
        WireIdentity(peerID: id, publicKey: publicKey.rawRepresentation.base64EncodedString(), name: name)
    }

    public static func == (lhs: PeerIdentity, rhs: PeerIdentity) -> Bool {
        lhs.publicKey.rawRepresentation == rhs.publicKey.rawRepresentation && lhs.name == rhs.name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
    }

    static func cleaned(_ name: String) -> String {
        let text = WireText.clean(name, limit: maximumNameLength)
        return text.isEmpty ? "Unnamed device" : text
    }
}

/// This device's own identity, with its private key.
///
/// It is created by the app, never derived from hardware, and can be replaced at any time, which
/// revokes every pairing that pinned the old key. It is not `Codable`: the private key never
/// enters a message, a log, or a snapshot.
public struct LocalIdentity: Sendable {
    private let privateKey: Curve25519.Signing.PrivateKey
    public let identity: PeerIdentity

    public init(name: String) {
        self.init(privateKey: Curve25519.Signing.PrivateKey(), name: name)
    }

    /// For a key the host keeps elsewhere, or a fixed test key.
    public init(privateKey: Curve25519.Signing.PrivateKey, name: String) {
        self.privateKey = privateKey
        identity = PeerIdentity(publicKey: privateKey.publicKey, name: name)
    }

    public var id: PeerID { identity.id }

    func sign(_ message: Data) throws(HandshakeFailure) -> Data {
        do { return try privateKey.signature(for: message) } catch { throw .cryptography }
    }
}

/// A peer this device paired with, and the roles it may take.
public struct PinnedPeer: Hashable, Sendable {
    public let identity: PeerIdentity
    /// The roles the person approved at pairing. A reconnect asking for another role must pair again.
    public let roles: Set<PeerRole>
    public let pinnedAt: Date

    public init(identity: PeerIdentity, roles: Set<PeerRole>, pinnedAt: Date) {
        self.identity = identity
        self.roles = roles
        self.pinnedAt = pinnedAt
    }
}

/// What a pin lookup found.
public enum PinCheck: Hashable, Sendable {
    /// Pinned with this exact key, and the role is allowed.
    case trusted(PinnedPeer)
    /// Never paired, or unpinned since.
    case unknown
    /// Pinned, but the key presented now is different. The peer is refused: it must be forgotten
    /// and paired again on purpose, never silently re-pinned.
    case keyChanged
    /// Pinned with this key, but not for the role it asks for now.
    case roleNotPaired
}

/// The peers this device trusts. Pins are added only by a completed pairing and removed only by a
/// person's Forget or a reset.
public protocol PeerTrustStore: Sendable {
    func pin(_ peer: PinnedPeer) async
    func check(_ identity: PeerIdentity, role: PeerRole) async -> PinCheck
    func pinned(_ id: PeerID) async -> PinnedPeer?
    func forget(_ id: PeerID) async
    func all() async -> [PinnedPeer]
}

/// Pins held in memory for the life of the process. A relaunch forgets every pairing, which is the
/// lab's reset; a host that keeps pairings across launches supplies its own store (for example,
/// one backed by the keychain).
public actor InMemoryTrustStore: PeerTrustStore {
    private var pins: [PeerID: PinnedPeer] = [:]

    public init() {}

    public func pin(_ peer: PinnedPeer) {
        if let existing = pins[peer.identity.id], existing.identity.publicKey.rawRepresentation == peer.identity.publicKey.rawRepresentation {
            pins[peer.identity.id] = PinnedPeer(identity: peer.identity, roles: existing.roles.union(peer.roles), pinnedAt: peer.pinnedAt)
        } else {
            pins[peer.identity.id] = peer
        }
    }

    public func check(_ identity: PeerIdentity, role: PeerRole) -> PinCheck {
        guard let pinned = pins[identity.id] else { return .unknown }
        guard pinned.identity.publicKey.rawRepresentation == identity.publicKey.rawRepresentation else { return .keyChanged }
        guard pinned.roles.contains(role) else { return .roleNotPaired }
        return .trusted(pinned)
    }

    public func pinned(_ id: PeerID) -> PinnedPeer? { pins[id] }

    public func forget(_ id: PeerID) {
        pins[id] = nil
    }

    public func all() -> [PinnedPeer] {
        pins.values.sorted { $0.identity.id < $1.identity.id }
    }
}
