/// Which commits need a live grant.
public struct GrantRequirement: Sendable {
    private let rule: @Sendable (OperationKind, AdapterKind) -> Bool

    public init(_ rule: @escaping @Sendable (OperationKind, AdapterKind) -> Bool) {
        self.rule = rule
    }

    public func requiresGrant(_ kind: OperationKind, from adapter: AdapterKind) -> Bool {
        rule(kind, adapter)
    }

    /// Every destructive commit, from any adapter, and every commit whose content arrived from
    /// outside the app: through the share extension or from an authorized peer.
    public static let sensitiveCommits = GrantRequirement { kind, adapter in
        kind.isDestructive || adapter == .shareExtension || adapter == .authorizedPeer
    }

    /// Every commit from every adapter.
    public static let everyCommit = GrantRequirement { _, _ in true }
}

/// An `AuthorizationPolicy` that requires a live, matching grant for sensitive commits.
///
/// `OperationService` consults its policy for every attempt, at the moment of the commit, and
/// always applies the adapter ceiling and the actor's permissions as well. This policy can
/// therefore only narrow access: a grant never lets an adapter do what its ceiling forbids
/// (ADR-011). A commit that needs a grant fails closed when the grant is missing, expired,
/// revoked, or for another adapter, operation, or target. Reads and proposals need no grant.
public struct GrantAuthorizationPolicy: AuthorizationPolicy {
    private let ledger: GrantLedger
    private let requirement: GrantRequirement
    private let base: any AuthorizationPolicy
    private let diagnostics: DiagnosticsLog?

    /// - Parameters:
    ///   - base: A further policy that must also allow the attempt.
    public init(
        ledger: GrantLedger,
        requirement: GrantRequirement = .sensitiveCommits,
        narrowing base: any AuthorizationPolicy = BaselineAuthorizationPolicy(),
        diagnostics: DiagnosticsLog? = nil
    ) {
        self.ledger = ledger
        self.requirement = requirement
        self.base = base
        self.diagnostics = diagnostics
    }

    public func decide(_ access: Access, for actor: ActorScope) -> PolicyDecision {
        guard base.decide(access, for: actor) == .allow else { return .deny }
        guard case .commit(let operation) = access, requirement.requiresGrant(operation.kind, from: actor.adapter) else {
            return .allow
        }
        let check = ledger.check(operation, from: actor.adapter)
        switch check {
        case .granted:
            return .allow
        case .missing:
            diagnostics?.record("grant.check", outcome: .rejected, category: .grantMissing)
        case .expired:
            diagnostics?.record("grant.check", outcome: .rejected, category: .grantExpired)
        case .outOfScope:
            diagnostics?.record("grant.check", outcome: .rejected, category: .grantOutOfScope)
        }
        return .deny
    }
}
