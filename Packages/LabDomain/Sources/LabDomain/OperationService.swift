/// The one path through which any adapter reads or changes domain state.
///
/// App UI, App Intents, the share extension, authorized peers, and model tools all call these
/// methods. Every call is authorized first, including reads, proposals, and replays. A mutation
/// then checks its request ID, validates against current state, and reaches the store as a single
/// `AuthorizedCommit` that records the change and its receipt together.
public actor OperationService {
    /// How many times a commit is re-planned when a concurrent writer invalidates it.
    static let maximumCommitAttempts = 3

    private let store: any OperationStore
    private let policy: any AuthorizationPolicy
    private let planner: OperationPlanner
    private let makeOperationID: @Sendable () -> OperationID

    /// - Parameters:
    ///   - policy: An additional rule consulted for every attempt. It can narrow access but never
    ///     widen an adapter ceiling or an actor's grants.
    ///   - makeOperationID: The source of receipt IDs. Inject a deterministic one in tests.
    public init(
        store: any OperationStore,
        policy: any AuthorizationPolicy = BaselineAuthorizationPolicy(),
        makeOperationID: @escaping @Sendable () -> OperationID = { OperationID() }
    ) {
        self.store = store
        self.policy = policy
        self.planner = OperationPlanner(store: store)
        self.makeOperationID = makeOperationID
    }

    // MARK: Mutations

    /// Commits one request, or returns the receipt already recorded for its request ID.
    ///
    /// A stale expected revision returns a `.conflict` receipt and changes nothing. That receipt is
    /// recorded too, so a retry of the same request gets the same answer.
    public func perform(_ request: OperationRequest) async throws(OperationError) -> ActionReceipt {
        try authorize(.commit(request.operation), for: request.actor)
        guard request.schemaVersion == OperationRequest.currentSchemaVersion else {
            throw .invalidPayload(.unsupportedSchemaVersion(request.schemaVersion))
        }
        let admitted = AdmittedRequest(request)
        for _ in 0..<Self.maximumCommitAttempts {
            if let recorded = try await recordedReceipt(for: request.id) {
                return try replay(recorded, for: admitted)
            }
            let plan: OperationPlan
            do {
                plan = try await planner.plan(request.operation)
            } catch {
                // Another attempt of this same request may have committed after the check above,
                // so its own effect now fails validation (a creation finds its entity existing).
                // The recorded receipt, not that refusal, is the answer to a retry.
                if let recorded = try await recordedReceipt(for: request.id) {
                    return try replay(recorded, for: admitted)
                }
                throw error
            }
            let receipt = ActionReceipt(
                operationID: makeOperationID(),
                requestID: request.id,
                admitted: admitted,
                status: plan.status,
                changes: plan.changes,
                removed: plan.removals,
                summary: plan.phrase.past,
                undo: plan.undo
            )
            let commit = AuthorizedCommit(
                receipt: receipt,
                preconditions: plan.preconditions,
                collections: plan.collections,
                items: plan.items,
                sessions: plan.sessions,
                jobs: plan.jobs,
                removals: plan.removals
            )
            let outcome: CommitOutcome
            do { outcome = try await store.apply(commit) } catch { throw .storeFailure(.commitFailed) }
            switch outcome {
            case .applied:
                return receipt
            case .duplicateRequest(let recorded):
                return try replay(recorded, for: admitted)
            case .preconditionFailed:
                // Another writer changed the state after it was read. Plan again from fresh state;
                // a stale expected revision now produces a conflict receipt instead of an overwrite.
                continue
            }
        }
        throw .storeFailure(.contention)
    }

    /// Validates an operation against current state without committing or recording anything.
    ///
    /// This is how a model tool contributes a change: it proposes, a person reviews, and an actor
    /// allowed to commit submits `proposal.operation` under a new request ID.
    public func propose(_ operation: DomainOperation, as actor: ActorScope) async throws(OperationError) -> OperationProposal {
        try authorize(.propose(operation), for: actor)
        let plan = try await planner.plan(operation)
        return OperationProposal(
            operation: operation,
            proposedBy: actor.adapter,
            summary: plan.phrase.imperative,
            conflict: plan.conflict
        )
    }

    // MARK: Reads

    public func findCollection(_ id: CollectionID, as actor: ActorScope) async throws(OperationError) -> LabCollection {
        try authorize(.read(.collection(id)), for: actor)
        guard let collection = try await read({ try await $0.collection(id) }) else {
            throw .notFound(.collection(id))
        }
        return collection
    }

    public func findItem(_ id: ItemID, as actor: ActorScope) async throws(OperationError) -> LabItem {
        try authorize(.read(.item(id)), for: actor)
        guard let item = try await read({ try await $0.item(id) }) else { throw .notFound(.item(id)) }
        return item
    }

    /// The items that match `filter`, ordered by title. Filtering by a missing collection is an
    /// error rather than an empty result.
    public func findItems(_ filter: ItemFilter, as actor: ActorScope) async throws(OperationError) -> [LabItem] {
        try authorize(.read(.items(filter)), for: actor)
        if let collectionID = filter.collectionID {
            guard try await read({ try await $0.collection(collectionID) }) != nil else {
                throw .notFound(.collection(collectionID))
            }
        }
        let candidates = try await read { try await $0.items(in: filter.collectionID) }
        return filter.select(from: candidates)
    }

    /// A session's current state, or `nil` when it was never started and so reads as paused
    /// (LAB-004 Surface Deck).
    public func findSession(_ id: SessionID, as actor: ActorScope) async throws(OperationError) -> LabSession? {
        try authorize(.read(.session(id)), for: actor)
        return try await read { try await $0.session(id) }
    }

    /// A job's current state (LAB-032). A job that was never started is not found.
    public func findJob(_ id: JobID, as actor: ActorScope) async throws(OperationError) -> LabJob {
        try authorize(.read(.job(id)), for: actor)
        guard let job = try await read({ try await $0.job(id) }) else { throw .notFound(.job(id)) }
        return job
    }

    /// Every job of one kind, or of every kind when `kind` is `nil`, in no particular order.
    public func findJobs(kind: JobKind?, as actor: ActorScope) async throws(OperationError) -> [LabJob] {
        try authorize(.read(.jobs(kind)), for: actor)
        let jobs = try await read { try await $0.jobs() }
        guard let kind else { return jobs }
        return jobs.filter { $0.jobKind == kind }
    }

    /// The receipt recorded for a request, or `nil` if that request was never admitted.
    public func findReceipt(for requestID: RequestID, as actor: ActorScope) async throws(OperationError) -> ActionReceipt? {
        try authorize(.read(.receipt(requestID)), for: actor)
        return try await recordedReceipt(for: requestID)
    }

    // MARK: Internals

    /// Consults the injected policy for every attempt, then applies the fixed adapter ceiling and
    /// the actor's grants. The first failing check names the reason.
    private func authorize(_ access: Access, for actor: ActorScope) throws(OperationError) {
        let decision = policy.decide(access, for: actor)
        let required = access.requiredPermission
        let reason: AuthorizationDenial.Reason? =
            if !actor.adapter.ceiling.contains(required) { .outsideAdapterCeiling }
            else if !actor.grants.contains(required) { .notGranted }
            else if decision == .deny { .deniedByPolicy }
            else { nil }
        if let reason {
            throw .unauthorized(AuthorizationDenial(adapter: actor.adapter, required: required, reason: reason))
        }
    }

    private func replay(_ recorded: ActionReceipt, for admitted: AdmittedRequest) throws(OperationError) -> ActionReceipt {
        guard recorded.admitted == admitted else { throw .requestIDReused(recorded.requestID) }
        return recorded
    }

    private func recordedReceipt(for requestID: RequestID) async throws(OperationError) -> ActionReceipt? {
        try await read { try await $0.receipt(for: requestID) }
    }

    private func read<Value: Sendable>(
        _ body: @Sendable (any OperationStore) async throws -> Value
    ) async throws(OperationError) -> Value {
        do { return try await body(store) } catch { throw .storeFailure(.readFailed) }
    }
}
