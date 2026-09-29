import Foundation
import Synchronization

/// Issues, holds, and checks short-lived commit grants.
///
/// Host code issues a grant when a person explicitly approves one change, such as tapping Add on
/// a reviewed import. The ledger lives in memory only: grants do not survive the process, cross
/// a process boundary, or come from a payload. `GrantAuthorizationPolicy` consults the ledger at
/// commit, inside `OperationService.perform`, so an approval that expired, was revoked, or names
/// another adapter, operation, or target fails closed.
public final class GrantLedger: Sendable {
    public static let defaultLifetime = Duration.seconds(60)
    public static let maximumLifetime = Duration.seconds(300)

    private let clock: any GrantClock
    private let grants = Mutex<[GrantID: CommitGrant]>([:])
    private let diagnostics: DiagnosticsLog?

    public init(clock: any GrantClock = SystemGrantClock(), diagnostics: DiagnosticsLog? = nil) {
        self.clock = clock
        self.diagnostics = diagnostics
    }

    /// Issues a grant for `adapter` to commit `operations` on `target` within `lifetime`.
    ///
    /// Refused when an operation is outside the adapter's ceiling, does not fit the target, or
    /// the lifetime is not between zero and `maximumLifetime`.
    @discardableResult
    public func issue(
        to adapter: AdapterKind,
        for operations: Set<OperationKind>,
        on target: GrantTarget,
        lifetime: Duration = GrantLedger.defaultLifetime
    ) throws(GrantError) -> CommitGrant {
        do {
            try Self.validate(adapter: adapter, operations: operations, target: target, lifetime: lifetime)
        } catch {
            diagnostics?.record("grant.issue", failure: error)
            throw error
        }
        let now = clock.now()
        let grant = CommitGrant(
            adapter: adapter, operations: operations, target: target, issuedAt: now, expiresAt: now + lifetime
        )
        grants.withLock { grants in
            // Forget grants that expired long ago, so the ledger stays small.
            grants = grants.filter { now < $0.value.expiresAt + Self.maximumLifetime }
            grants[grant.id] = grant
        }
        diagnostics?.record("grant.issue", outcome: .succeeded, counts: ["operations": operations.count])
        return grant
    }

    private static func validate(
        adapter: AdapterKind,
        operations: Set<OperationKind>,
        target: GrantTarget,
        lifetime: Duration
    ) throws(GrantError) {
        guard !operations.isEmpty else { throw .noOperations }
        guard lifetime > .zero, lifetime <= maximumLifetime else { throw .lifetimeOutOfRange(maximum: maximumLifetime) }
        for kind in operations.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard adapter.ceiling.contains(kind.commitPermission) else { throw .exceedsAdapterCeiling(kind) }
            guard target.fits(kind) else { throw .targetMismatch(kind) }
        }
    }

    /// Issues a grant for exactly this operation's kind and target.
    @discardableResult
    public func issue(
        for operation: DomainOperation,
        to adapter: AdapterKind,
        lifetime: Duration = GrantLedger.defaultLifetime
    ) throws(GrantError) -> CommitGrant {
        try issue(to: adapter, for: [operation.kind], on: GrantTarget(of: operation), lifetime: lifetime)
    }

    public func revoke(_ id: GrantID) {
        _ = grants.withLock { $0.removeValue(forKey: id) }
    }

    public func revokeAll() {
        grants.withLock { $0.removeAll() }
    }

    /// Grants that are valid now.
    public var liveGrants: [CommitGrant] {
        let now = clock.now()
        return grants.withLock { $0.values.filter { $0.isLive(at: now) } }
    }

    /// Whether a commit of `operation` from `adapter` is covered now.
    public func check(_ operation: DomainOperation, from adapter: AdapterKind) -> GrantCheck {
        let now = clock.now()
        return grants.withLock { grants in
            let covering = grants.values.filter { $0.covers(operation, from: adapter) }
            if let live = covering.first(where: { $0.isLive(at: now) }) { return .granted(live.id) }
            if !covering.isEmpty { return .expired }
            return grants.values.contains { $0.isLive(at: now) } ? .outOfScope : .missing
        }
    }
}
