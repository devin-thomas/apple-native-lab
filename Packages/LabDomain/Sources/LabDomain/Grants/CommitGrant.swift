import Foundation

/// The time source for grant expiry. Grants live only in memory, so they use a monotonic clock
/// that keeps counting while the device sleeps and that changing the wall clock cannot move.
/// Inject a manual clock in tests.
public protocol GrantClock: Sendable {
    func now() -> ContinuousClock.Instant
}

public struct SystemGrantClock: GrantClock {
    public init() {}

    public func now() -> ContinuousClock.Instant { ContinuousClock.now }
}

/// Identifies one issued grant. It is a handle for revoking, never a bearer token: presenting
/// its value grants nothing, because the ledger checks the operation, not a string.
public struct GrantID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    init() { rawValue = UUID() }

    public var description: String { rawValue.uuidString }
}

/// What a grant lets its holder change.
public enum GrantTarget: Hashable, Sendable {
    /// One existing entity, or the one entity a creation creates.
    case entity(EntityReference)
    /// A new item in this collection, whatever its ID. This is how a person approves adding an
    /// import to a collection they chose.
    case newItem(in: CollectionID)
    /// The demo namespace as a whole, for Reset Demo.
    case demo

    /// The target an operation needs a grant for.
    public init(of operation: DomainOperation) {
        switch operation {
        case .createItem(let draft): self = .newItem(in: draft.collectionID)
        case .resetDemo: self = .demo
        default: self = operation.target.map(GrantTarget.entity) ?? .demo
        }
    }

    /// Whether an operation of this kind can ever act on this target.
    func fits(_ kind: OperationKind) -> Bool {
        switch (self, kind) {
        case (.newItem, .createItem), (.demo, .resetDemo): true
        case (.entity(.collection), .createCollection), (.entity(.collection), .updateCollection),
             (.entity(.collection), .archiveCollection), (.entity(.collection), .restoreCollection):
            true
        case (.entity(.item), .updateItem), (.entity(.item), .archiveItem), (.entity(.item), .restoreItem):
            true
        case (.entity(.session), .setSession):
            true
        case (.entity(.anchor), .placeAnchor), (.entity(.anchor), .moveAnchor), (.entity(.anchor), .removeAnchor):
            true
        default: false
        }
    }
}

/// A short-lived, scoped approval to commit, checked when the commit happens.
///
/// A grant names the adapter that may use it, the operation kinds it covers, the target, and an
/// expiry. It is created only by `GrantLedger.issue`, which host code calls in response to a
/// person's explicit action. It has no public initializer and is neither `Codable` nor
/// constructible from text, so nothing inside imported content, a deep link, a peer message, or
/// model output can become a grant. A grant only narrows: the service still applies the adapter
/// ceiling and the actor's permissions (ADR-011).
public struct CommitGrant: Hashable, Sendable, Identifiable {
    public let id: GrantID
    public let adapter: AdapterKind
    public let operations: Set<OperationKind>
    public let target: GrantTarget
    public let issuedAt: ContinuousClock.Instant
    public let expiresAt: ContinuousClock.Instant

    init(
        adapter: AdapterKind,
        operations: Set<OperationKind>,
        target: GrantTarget,
        issuedAt: ContinuousClock.Instant,
        expiresAt: ContinuousClock.Instant
    ) {
        id = GrantID()
        self.adapter = adapter
        self.operations = operations
        self.target = target
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    /// Whether this grant covers `operation` from `adapter`, ignoring time.
    public func covers(_ operation: DomainOperation, from adapter: AdapterKind) -> Bool {
        adapter == self.adapter && operations.contains(operation.kind) && target == GrantTarget(of: operation)
    }

    /// Whether the grant is valid at `now`. A clock reading before issue fails closed.
    public func isLive(at now: ContinuousClock.Instant) -> Bool {
        issuedAt <= now && now < expiresAt
    }
}

/// The result of checking a commit against the ledger.
public enum GrantCheck: Hashable, Sendable {
    case granted(GrantID)
    /// No grant was ever issued that covers this commit.
    case missing
    /// A grant covered this commit but is no longer valid.
    case expired
    /// Live grants exist, but none covers this adapter, operation, and target.
    case outOfScope

    public var isGranted: Bool {
        if case .granted = self { true } else { false }
    }
}

/// Why a grant was not issued.
public enum GrantError: Error, Hashable, Sendable {
    case noOperations
    /// The lifetime is zero, negative, or longer than the ledger allows.
    case lifetimeOutOfRange(maximum: Duration)
    /// The adapter can never commit this kind of operation, so a grant would be meaningless.
    /// Grants never widen an adapter ceiling (ADR-011).
    case exceedsAdapterCeiling(OperationKind)
    /// This kind of operation cannot act on the named target.
    case targetMismatch(OperationKind)

    var category: DiagnosticCategory {
        switch self {
        case .noOperations, .lifetimeOutOfRange, .targetMismatch: .invalidInput
        case .exceedsAdapterCeiling: .unauthorized
        }
    }
}
