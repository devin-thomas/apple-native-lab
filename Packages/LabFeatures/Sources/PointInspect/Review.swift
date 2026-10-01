import Foundation
import LabDomain

/// What the operation service said about a record's operation, checked as the proposer.
public enum InspectionCheck: Hashable, Sendable {
    case accepted(OperationProposal)
    case refused(OperationError)
}

/// A record a person can review. Nothing is stored until `approve()` and a later commit.
public struct ReviewableInspection: Hashable, Sendable {
    public let observation: Observation
    /// The operation that was proposed. Approving it does not build another item ID.
    public let operation: DomainOperation
    public let serviceCheck: InspectionCheck

    public var isApprovable: Bool {
        guard observation.isApprovable, case .accepted(let proposal) = serviceCheck else { return false }
        return proposal.isReady && proposal.proposedBy == .modelTool && proposal.operation == operation
    }

    public var serviceSummary: String? {
        if case .accepted(let proposal) = serviceCheck { proposal.summary } else { nil }
    }

    /// A person's approval of exactly this operation, under a new request ID.
    ///
    /// Call it only from a control the person pressed after seeing the record. The request ID
    /// comes from nothing in the image or the barcode, so no payload can choose it.
    public func approve() throws(InspectFailure) -> ApprovedInspection {
        guard observation.isApprovable else { throw .invalidText(observation.titleIssue ?? "Fix the record before applying it.") }
        guard case .accepted(let proposal) = serviceCheck, proposal.isReady, proposal.operation == operation else {
            throw .invalidText("The lab did not accept this record. Nothing was saved.")
        }
        return ApprovedInspection(operation: operation, requestID: RequestID(), observation: observation)
    }
}

/// A record a person approved. Only `ReviewableInspection.approve()` creates one.
public struct ApprovedInspection: Hashable, Sendable {
    public let operation: DomainOperation
    public let requestID: RequestID
    public let observation: Observation

    init(operation: DomainOperation, requestID: RequestID, observation: Observation) {
        self.operation = operation
        self.requestID = requestID
        self.observation = observation
    }
}

/// What the experiment needs from the host.
///
/// Proposals run as `PointInspect.proposer`. Creating the collection and committing the item run
/// as the app UI, and only after a person presses Apply.
public protocol PointInspectBackend: Sendable {
    func collection(_ id: CollectionID) async throws(InspectFailure) -> LabCollection?
    func propose(_ operation: DomainOperation) async throws(InspectFailure) -> OperationProposal
    func createCollection(_ draft: CollectionDraft, requestID: RequestID) async throws(InspectFailure) -> ActionReceipt
    func commit(_ inspection: ApprovedInspection) async throws(InspectFailure) -> ActionReceipt
}

/// A backend directly over an `OperationService`, for tests. Commits use the app UI.
public struct ServicePointInspectBackend: PointInspectBackend {
    public static let committer = ActorScope(adapter: .appUI, grants: [.read, .propose, .commit])

    private let service: OperationService

    public init(service: OperationService) {
        self.service = service
    }

    public func collection(_ id: CollectionID) async throws(InspectFailure) -> LabCollection? {
        do {
            return try await service.findCollection(id, as: PointInspect.proposer)
        } catch .notFound {
            return nil
        } catch {
            throw .refused(error)
        }
    }

    public func propose(_ operation: DomainOperation) async throws(InspectFailure) -> OperationProposal {
        do {
            return try await service.propose(operation, as: PointInspect.proposer)
        } catch {
            throw .refused(error)
        }
    }

    public func createCollection(_ draft: CollectionDraft, requestID: RequestID) async throws(InspectFailure) -> ActionReceipt {
        let request = OperationRequest(
            id: requestID,
            operation: .createCollection(draft: draft),
            actor: Self.committer
        )
        do {
            return try await service.perform(request)
        } catch {
            throw .refused(error)
        }
    }

    public func commit(_ inspection: ApprovedInspection) async throws(InspectFailure) -> ActionReceipt {
        let request = OperationRequest(id: inspection.requestID, operation: inspection.operation, actor: Self.committer)
        do {
            return try await service.perform(request)
        } catch {
            throw .refused(error)
        }
    }
}
