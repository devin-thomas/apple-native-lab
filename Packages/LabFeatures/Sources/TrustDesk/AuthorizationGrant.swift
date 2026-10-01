import Foundation
import LabDomain
import Synchronization

/// What a desk grant allows. It is local authorization for one action in this app, not an
/// account session and not a passkey.
public enum DeskPurpose: String, Hashable, Sendable {
    case openSealedRecord
}

/// How the person authorized. Device owner is LocalAuthentication. Local confirmation is the
/// fallback when that is unavailable or fails, and it is labeled as such.
public enum AuthorizationMethod: String, Hashable, Sendable {
    case deviceOwner
    case localConfirmation
}

/// A short-lived approval to open the sealed record.
///
/// The ledger is the only thing that creates one. It is not `Codable`, so a note, a link, or a
/// passkey assertion cannot become a grant. It lives in memory and expires on a monotonic clock.
public struct AuthorizationGrant: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let identity: DeskIdentityID
    public let purpose: DeskPurpose
    public let method: AuthorizationMethod
    public let issuedAt: ContinuousClock.Instant
    public let expiresAt: ContinuousClock.Instant
    public let isRevoked: Bool

    fileprivate init(
        identity: DeskIdentityID,
        purpose: DeskPurpose,
        method: AuthorizationMethod,
        issuedAt: ContinuousClock.Instant,
        expiresAt: ContinuousClock.Instant
    ) {
        id = UUID()
        self.identity = identity
        self.purpose = purpose
        self.method = method
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        isRevoked = false
    }

    private init(copying grant: AuthorizationGrant, isRevoked: Bool) {
        id = grant.id
        identity = grant.identity
        purpose = grant.purpose
        method = grant.method
        issuedAt = grant.issuedAt
        expiresAt = grant.expiresAt
        self.isRevoked = isRevoked
    }

    fileprivate func revoked() -> AuthorizationGrant {
        AuthorizationGrant(copying: self, isRevoked: true)
    }

    /// Whether the grant still allows its purpose. A clock reading before issue fails closed,
    /// and the expiry instant itself is already too late.
    public func isLive(at now: ContinuousClock.Instant) -> Bool {
        !isRevoked && issuedAt <= now && now < expiresAt
    }
}

/// Issues, holds, and revokes desk grants. Grants are checked by the desk when the sealed
/// record is opened, not by presenting the grant's identifier.
public final class DeskGrantLedger: Sendable {
    public static let defaultLifetime = Duration.seconds(60)
    public static let maximumLifetime = Duration.seconds(300)

    private let clock: any GrantClock
    private let grants = Mutex<[UUID: AuthorizationGrant]>([:])

    public init(clock: any GrantClock = SystemGrantClock()) {
        self.clock = clock
    }

    @discardableResult
    public func issue(
        for identity: DeskIdentityID,
        purpose: DeskPurpose,
        method: AuthorizationMethod,
        lifetime: Duration = DeskGrantLedger.defaultLifetime
    ) throws(TrustDeskError) -> AuthorizationGrant {
        guard lifetime > .zero, lifetime <= Self.maximumLifetime else {
            throw .lifetimeOutOfRange
        }
        let now = clock.now()
        let grant = AuthorizationGrant(
            identity: identity, purpose: purpose, method: method, issuedAt: now, expiresAt: now + lifetime
        )
        grants.withLock { stored in
            stored = stored.filter { now < $0.value.expiresAt + Self.maximumLifetime }
            stored[grant.id] = grant
        }
        return grant
    }

    public func revoke(_ id: UUID) {
        grants.withLock { stored in
            guard let grant = stored[id] else { return }
            stored[id] = grant.revoked()
        }
    }

    public func revokeAll() {
        grants.withLock { stored in
            stored = stored.mapValues { $0.revoked() }
        }
    }

    public func grant(_ id: UUID) -> AuthorizationGrant? {
        grants.withLock { $0[id] }
    }

    /// The live grant for this identity and purpose, if there is one.
    public func liveGrant(for identity: DeskIdentityID, purpose: DeskPurpose) -> AuthorizationGrant? {
        let now = clock.now()
        return grants.withLock { stored in
            stored.values.first { $0.identity == identity && $0.purpose == purpose && $0.isLive(at: now) }
        }
    }

    /// Why no live grant exists, when the caller needs to tell expiry and revocation apart.
    public func refusal(for identity: DeskIdentityID, purpose: DeskPurpose) -> TrustDeskError {
        let now = clock.now()
        let matches = grants.withLock { stored in
            stored.values.filter { $0.identity == identity && $0.purpose == purpose }
        }
        if matches.contains(where: \.isRevoked) { return .grantRevoked }
        if matches.contains(where: { $0.expiresAt <= now || now < $0.issuedAt }) { return .grantExpired }
        return .noLiveGrant
    }
}

/// A clock a test can move. Production uses `SystemGrantClock`.
public final class ManualGrantClock: GrantClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: ContinuousClock.Instant

    public init(startingAt instant: ContinuousClock.Instant = ContinuousClock.now) {
        self.instant = instant
    }

    public func now() -> ContinuousClock.Instant {
        lock.lock()
        defer { lock.unlock() }
        return instant
    }

    public func advance(by duration: Duration) {
        lock.lock()
        defer { lock.unlock() }
        instant = instant.advanced(by: duration)
    }
}
