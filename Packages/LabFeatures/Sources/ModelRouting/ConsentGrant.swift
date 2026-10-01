import Foundation

/// Explicit, short-lived consent to let a previewed cloud request leave the device.
///
/// Lab-owned (the experiment's `ConsentGrant`), not Apple's `CommitGrant`. Entering the
/// observatory does not grant this. A grant is bound to one preview's digest and expires; a
/// different outgoing field set needs a new grant.
public struct ConsentGrant: Hashable, Sendable, Identifiable {
    public let id: UUID
    /// Digest of the outgoing field preview this grant covers.
    public let previewDigest: String
    public let issuedAt: Date
    public let expiresAt: Date

    public init(
        id: UUID = UUID(),
        previewDigest: String,
        issuedAt: Date = Date(),
        lifetime: Duration = .seconds(120)
    ) {
        self.id = id
        self.previewDigest = previewDigest
        self.issuedAt = issuedAt
        expiresAt = issuedAt.addingTimeInterval(Double(lifetime.components.seconds))
    }

    public func isValid(for digest: String, at date: Date = Date()) -> Bool {
        previewDigest == digest && date < expiresAt && date >= issuedAt
    }
}

/// Why a cloud consent was refused. Nothing leaves the device in any of these cases.
public enum ConsentError: Error, Hashable, Sendable {
    case missing
    case expired
    case digestMismatch
    case cloudOff

    public var message: String {
        switch self {
        case .missing:
            "Cloud consent was not given. Nothing left this device."
        case .expired:
            "Cloud consent expired. Review the outgoing fields again. Nothing left this device."
        case .digestMismatch:
            "The outgoing fields changed after consent. Review them again. Nothing left this device."
        case .cloudOff:
            "Cloud is off. Nothing left this device."
        }
    }
}
