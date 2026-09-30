import LabDomain

/// What the operation service said about a proposal's operation, checked as the proposer.
public enum ServiceCheck: Hashable, Sendable {
    /// Blocked by validation before it reached the service.
    case notChecked
    /// The service validated it against current state without recording anything.
    case accepted(OperationProposal)
    /// The sample changed after it was read.
    case stale(RevisionConflict)
    case refused(OperationError)
}

/// A proposal a person can review: the validated fields and the service's check of its operation.
public struct ReviewableProposal: Hashable, Sendable {
    public let proposal: ExtractionProposal
    public let serviceCheck: ServiceCheck

    /// Whether a person may approve it now: nothing blocks it and the service accepted it as current.
    public var isApprovable: Bool {
        guard !proposal.isBlocked, case .accepted(let checked) = serviceCheck else { return false }
        return checked.isReady && checked.proposedBy == .modelTool
    }

    /// Every issue, including the service's, blocking ones first.
    public var issues: [ValidationIssue] {
        var all = proposal.issues
        switch serviceCheck {
        case .notChecked, .accepted: break
        case .stale(let conflict): all.append(.sampleChanged(conflict))
        case .refused(let error): all.append(.refusedByService(error))
        }
        return all.filter(\.isBlocking) + all.filter { !$0.isBlocking }
    }

    /// The service's one-line description of the change, such as “Update item “Cobalt swatch”.”
    public var serviceSummary: String? {
        if case .accepted(let checked) = serviceCheck { checked.summary } else { nil }
    }

    /// A person's approval of exactly this proposal's operation, under a new request ID.
    ///
    /// Call it only from an explicit control a person pressed after seeing the proposal and its
    /// diff. The request ID is new and derived from nothing in the note or the draft, so a retry
    /// of this approval is one commit, and no text can choose or reuse a request.
    public func approve() throws(ApprovalRefusal) -> ApprovedChange {
        guard !proposal.isBlocked, let operation = proposal.operation else {
            throw .blocked(proposal.blockingIssues)
        }
        switch serviceCheck {
        case .accepted(let checked) where checked.isReady && checked.operation == operation:
            return ApprovedChange(
                operation: operation,
                requestID: RequestID(),
                source: proposal.source,
                editedByPerson: proposal.editedByPerson
            )
        case .accepted, .stale: throw .stale
        case .notChecked, .refused: throw .notAccepted
        }
    }
}

public enum ApprovalRefusal: Error, Hashable, Sendable {
    case blocked([ValidationIssue])
    /// The sample changed after it was read.
    case stale
    /// The operation service has not accepted this proposal.
    case notAccepted

    public var message: String {
        switch self {
        case .blocked(let issues): issues.first?.message ?? "Fix the proposal before applying it."
        case .stale: "The sample changed after it was read. Read it again, then review the change."
        case .notAccepted: "The lab did not accept this change. Nothing was applied."
        }
    }
}

/// A change a person approved. Only `ReviewableProposal.approve()` creates one: it has no public
/// initializer and is not `Codable`, so no draft, note, or decoded payload can become one.
public struct ApprovedChange: Hashable, Sendable {
    public let operation: DomainOperation
    /// New for this approval. The commit uses it, so retrying the same approval commits once.
    public let requestID: RequestID
    public let source: ProposalSource
    public let editedByPerson: Bool

    init(operation: DomainOperation, requestID: RequestID, source: ProposalSource, editedByPerson: Bool) {
        self.operation = operation
        self.requestID = requestID
        self.source = source
        self.editedByPerson = editedByPerson
    }
}

/// Why the backend could not read, propose, or commit.
public enum IntelligenceError: Error, Hashable, Sendable {
    /// The lab store is not open. The reason is a sentence for a person.
    case unavailable(reason: String)
    case refused(OperationError)

    public var message: String {
        switch self {
        case .unavailable(let reason): reason
        case .refused(let error): ServiceRefusal.sentence(for: error)
        }
    }
}

/// What the experiment needs from the host. Reads and proposals run as `TypedIntelligence.proposer`,
/// the model-tool adapter; a commit runs as the app UI and needs an `ApprovedChange`.
///
/// Hosts implement it over their own `OperationService`, and never hand an extractor this value.
public protocol TypedIntelligenceBackend: Sendable {
    /// Items the proposer can read, archived ones excluded, in any order.
    func items(_ filter: ItemFilter) async throws(IntelligenceError) -> [LabItem]
    /// Validates an operation as the proposer. Records nothing.
    func propose(_ operation: DomainOperation) async throws(IntelligenceError) -> OperationProposal
    /// Commits a person's approved change as the app UI, under the approval's request ID.
    func commit(_ change: ApprovedChange) async throws(IntelligenceError) -> ActionReceipt
}

/// A backend directly over an `OperationService`, for tests and replays. It uses the proposer scope
/// for reads and proposals and the app-UI scope for commits.
public struct ServiceIntelligenceBackend: TypedIntelligenceBackend {
    /// The app UI's commit scope. An approved edit is never destructive, so no grant is needed.
    public static let committer = ActorScope(adapter: .appUI, grants: [.read, .propose, .commit])

    private let service: OperationService

    public init(service: OperationService) {
        self.service = service
    }

    public func items(_ filter: ItemFilter) async throws(IntelligenceError) -> [LabItem] {
        do { return try await service.findItems(filter, as: TypedIntelligence.proposer) } catch { throw .refused(error) }
    }

    public func propose(_ operation: DomainOperation) async throws(IntelligenceError) -> OperationProposal {
        do { return try await service.propose(operation, as: TypedIntelligence.proposer) } catch { throw .refused(error) }
    }

    public func commit(_ change: ApprovedChange) async throws(IntelligenceError) -> ActionReceipt {
        let request = OperationRequest(id: change.requestID, operation: change.operation, actor: Self.committer)
        do { return try await service.perform(request) } catch { throw .refused(error) }
    }
}
