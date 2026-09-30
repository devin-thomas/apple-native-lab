/// The entry point a request arrives through. Every kind calls the same service.
public enum AdapterKind: String, Hashable, Sendable, Codable, CaseIterable {
    case appUI = "app-ui"
    case appIntent = "app-intent"
    case shareExtension = "share-extension"
    case authorizedPeer = "authorized-peer"
    case modelTool = "model-tool"

    /// The most this kind of adapter may ever do, whatever it is granted.
    ///
    /// Ceilings are fixed here, not injected, so no policy or grant can widen them. A model tool
    /// may read and propose but never commit (ADR-007). A share extension or peer may not commit a
    /// destructive change. Widening a ceiling needs a decision record.
    public var ceiling: Set<Permission> {
        switch self {
        case .appUI, .appIntent: [.read, .propose, .commit, .commitDestructive]
        case .shareExtension, .authorizedPeer: [.read, .propose, .commit]
        case .modelTool: [.read, .propose]
        }
    }
}

/// One kind of access to the domain.
public enum Permission: String, Hashable, Sendable, Codable, CaseIterable {
    case read
    /// Validate an operation against current state without committing it.
    case propose
    /// Commit a non-destructive operation.
    case commit
    /// Commit a destructive operation, such as an archive.
    case commitDestructive = "commit-destructive"
}

/// Who is asking, through which adapter, and what they have been granted.
///
/// The host assigns an adapter its scope when it composes that adapter. A scope is never decoded
/// from a payload, which is why `OperationRequest` is not `Codable`.
public struct ActorScope: Hashable, Sendable {
    public let adapter: AdapterKind
    public let grants: Set<Permission>

    public init(adapter: AdapterKind, grants: Set<Permission>) {
        self.adapter = adapter
        self.grants = grants
    }

    /// What this actor can actually do: its grants, limited by its adapter's ceiling.
    public var effectivePermissions: Set<Permission> { grants.intersection(adapter.ceiling) }
}

/// What a read asks for.
public enum ReadTarget: Hashable, Sendable {
    case collection(CollectionID)
    case item(ItemID)
    case items(ItemFilter)
    case session(SessionID)
    case receipt(RequestID)
    /// One job (LAB-032).
    case job(JobID)
    /// Every job of one kind, or of every kind when `nil`.
    case jobs(JobKind?)
}

/// One attempt to use the domain, as presented to the authorization policy.
public enum Access: Hashable, Sendable {
    case read(ReadTarget)
    case propose(DomainOperation)
    case commit(DomainOperation)

    public var requiredPermission: Permission {
        switch self {
        case .read: .read
        case .propose: .propose
        case .commit(let operation): operation.kind.commitPermission
        }
    }
}

public enum PolicyDecision: Hashable, Sendable {
    case allow
    case deny
}

/// An additional rule the service consults for every access attempt, including reads, proposals,
/// and replays of an already recorded request.
///
/// A policy can only narrow access. The service always enforces the adapter ceiling and the
/// actor's grants as well, so allowing something here never lets a model tool commit.
public protocol AuthorizationPolicy: Sendable {
    func decide(_ access: Access, for actor: ActorScope) -> PolicyDecision
}

/// Adds no rule beyond the adapter ceilings and grants the service always enforces.
public struct BaselineAuthorizationPolicy: AuthorizationPolicy {
    public init() {}

    public func decide(_ access: Access, for actor: ActorScope) -> PolicyDecision { .allow }
}

/// Why an access attempt was refused.
public struct AuthorizationDenial: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        /// The adapter kind can never hold the required permission.
        case outsideAdapterCeiling
        /// The actor was not granted the required permission.
        case notGranted
        /// The injected policy refused the attempt.
        case deniedByPolicy
    }

    public let adapter: AdapterKind
    public let required: Permission
    public let reason: Reason
}
