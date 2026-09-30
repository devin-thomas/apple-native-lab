import CryptoKit
import Foundation

/// A peer's identity on the wire: the first 16 bytes of the SHA-256 of its signing public key, as
/// 32 lowercase hex digits.
///
/// It is derived from the key, so a peer cannot claim another's ID without its private key. It is
/// app-generated and revocable, never a hardware serial number or an advertising identifier.
public struct PeerID: RawRepresentable, Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    /// `nil` unless `rawValue` is exactly 32 lowercase hex digits.
    public init?(rawValue: String) {
        guard rawValue.utf8.count == 32, rawValue.utf8.allSatisfy(Self.isLowercaseHex) else { return nil }
        self.rawValue = rawValue
    }

    /// The ID of the peer that holds the private half of `publicKey`.
    public init(publicKey: Curve25519.Signing.PublicKey) {
        let digest = SHA256.hash(data: publicKey.rawRepresentation)
        rawValue = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// The first eight digits in two groups, for people to compare, such as `4f2a 91c0`.
    public var shortForm: String {
        let digits = Array(rawValue.prefix(8))
        return String(digits[0..<4]) + " " + String(digits[4..<8])
    }

    public var description: String { rawValue }

    public static func < (lhs: PeerID, rhs: PeerID) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let id = PeerID(rawValue: try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "A peer ID is 32 lowercase hex digits.")
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func isLowercaseHex(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x61...0x66).contains(byte)
    }
}

/// One live session a conductor runs. It lasts as long as the conductor's session object; it is
/// not a stored entity (compare LabDomain's `SessionID`, which names a stored running-or-paused
/// flag).
public struct LiveSessionID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init() { rawValue = UUID() }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }
}

/// Which incarnation of a session a message belongs to. A conductor draws a new epoch each time it
/// starts, as after a reboot or relaunch, so anything sent under an earlier epoch is invalid:
/// its commands are refused and its samples and clock estimates are discarded.
public struct SessionEpoch: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// A random nonzero epoch.
    public static func random() -> SessionEpoch {
        SessionEpoch(rawValue: UInt32.random(in: 1...UInt32.max))
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UInt32.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { String(rawValue) }
}

/// Names one message. A replayed message ID gets its earlier answer instead of a second effect.
public struct MessageID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init() { rawValue = UUID() }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }
}

/// What a peer does in a session. The conductor is authoritative; every other role is checked on
/// the receiver, never trusted from the sender's claim alone: a peer's role is fixed when it is
/// paired and checked again when it reconnects.
public enum PeerRole: String, Hashable, Sendable, Codable, CaseIterable, Comparable {
    /// Holds the authoritative state, admits commands, and sends snapshots.
    case conductor
    /// Sends commands and samples.
    case controller
    /// Shows snapshots and relayed samples. It sends nothing that changes state.
    case display

    public var title: String {
        switch self {
        case .conductor: "Conductor"
        case .controller: "Controller"
        case .display: "Display"
        }
    }

    public static func < (lhs: PeerRole, rhs: PeerRole) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// A reading of one device's monotonic clock, in nanoseconds from an origin that device chose.
///
/// Two devices' readings cannot be compared directly; `ClockEstimate` relates them. The clock
/// keeps counting while the device sleeps, and changing the wall clock cannot move it.
public struct PeerInstant: RawRepresentable, Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: Int64

    public init(rawValue: Int64) { self.rawValue = rawValue }

    public init(nanoseconds: Int64) { rawValue = nanoseconds }

    public static func < (lhs: PeerInstant, rhs: PeerInstant) -> Bool { lhs.rawValue < rhs.rawValue }

    /// `self - other`, saturating instead of overflowing.
    public func since(_ other: PeerInstant) -> Duration {
        let (difference, overflow) = rawValue.subtractingReportingOverflow(other.rawValue)
        return .nanoseconds(overflow ? (other.rawValue > 0 ? Int64.min : Int64.max) : difference)
    }

    public func advanced(by duration: Duration) -> PeerInstant {
        let (sum, overflow) = rawValue.addingReportingOverflow(duration.wholeNanoseconds)
        return PeerInstant(rawValue: overflow ? (duration > .zero ? Int64.max : Int64.min) : sum)
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int64.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { "\(rawValue) ns" }
}

extension Duration {
    /// The whole nanoseconds in this duration, saturating at the bounds of `Int64`.
    public var wholeNanoseconds: Int64 {
        let (seconds, attoseconds) = components
        let (scaled, overflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        if overflow { return seconds > 0 ? Int64.max : Int64.min }
        let (sum, overflow2) = scaled.addingReportingOverflow(attoseconds / 1_000_000_000)
        if overflow2 { return seconds > 0 ? Int64.max : Int64.min }
        return sum
    }

    /// Milliseconds with one decimal, for people.
    public var millisecondsText: String {
        String(format: "%.1f ms", Double(wholeNanoseconds) / 1_000_000)
    }
}

/// A device's monotonic clock. Inject a manual clock in tests.
public protocol PeerClock: Sendable {
    func now() -> PeerInstant
}

/// The system's continuous clock, measured from when this value was created.
public struct SystemPeerClock: PeerClock {
    private let origin: ContinuousClock.Instant

    public init() { origin = ContinuousClock.now }

    public func now() -> PeerInstant {
        PeerInstant(nanoseconds: origin.duration(to: ContinuousClock.now).wholeNanoseconds)
    }
}
