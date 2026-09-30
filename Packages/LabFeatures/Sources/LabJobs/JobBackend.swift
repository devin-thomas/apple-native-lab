import Foundation
import LabDomain

/// What a job runtime needs from the host: job reads and commits through the host's own
/// `OperationService`, under the adapter the host chose.
///
/// The host implements this with the data service its views use, so a worker, a button, and a
/// launch-time recovery take one path to the store and every step leaves a receipt. Nothing here
/// holds the store.
public protocol JobBackend: Sendable {
    /// A job's current state. A job that is not stored is `.refused(.notFound)`.
    func job(_ id: JobID) async throws(JobError) -> LabJob
    /// Every stored job of one kind.
    func jobs(of kind: JobKind) async throws(JobError) -> [LabJob]
    /// Commits one request and returns its receipt. A retry with the same request ID returns the
    /// receipt already recorded.
    func commit(_ operation: DomainOperation, requestID: RequestID) async throws(JobError) -> ActionReceipt
}

/// Why a job step was not recorded.
public enum JobError: Error, Hashable, Sendable {
    /// The app's store cannot be used right now. The reason is a sentence for a person.
    case unavailable(reason: String)
    /// The operation service refused the request.
    case refused(OperationError)
    /// The job moved since this runtime last saw it: a person cancelled it elsewhere, or Reset
    /// Demo removed it (`nil`). The runtime must stop and not publish.
    case changedElsewhere(JobPhase.Name?)

    public var message: String {
        switch self {
        case .unavailable(let reason):
            reason
        case .refused(.unauthorized):
            "This entry point is not allowed to change the job. Nothing was changed."
        case .refused(.storeFailure):
            "Native Lab could not read or save its data. Try again."
        case .refused(.notFound), .changedElsewhere(nil):
            "The job no longer exists. Reset Demo may have removed it."
        case .refused:
            "The job could not take this step. Nothing was changed."
        case .changedElsewhere(let phase?):
            "The job changed elsewhere and is now \(phase.rawValue). This run stopped without publishing."
        }
    }
}

/// A backend over an `OperationService` the caller holds, under one actor: for tests, previews,
/// and hosts that compose the service directly.
public struct ServiceJobBackend: JobBackend {
    public let service: OperationService
    public let actor: ActorScope

    public init(service: OperationService, actor: ActorScope) {
        self.service = service
        self.actor = actor
    }

    public func job(_ id: JobID) async throws(JobError) -> LabJob {
        do { return try await service.findJob(id, as: actor) } catch { throw .refused(error) }
    }

    public func jobs(of kind: JobKind) async throws(JobError) -> [LabJob] {
        do { return try await service.findJobs(kind: kind, as: actor) } catch { throw .refused(error) }
    }

    public func commit(_ operation: DomainOperation, requestID: RequestID) async throws(JobError) -> ActionReceipt {
        do {
            return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
        } catch {
            throw .refused(error)
        }
    }
}
