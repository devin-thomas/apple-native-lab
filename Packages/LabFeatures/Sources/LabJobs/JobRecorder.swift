import Foundation
import LabDomain

/// Records one job's lifecycle through a `JobBackend`, always at the revision it last saw.
///
/// A worker holds one recorder per job. Each step is one `updateJob` request, so it is authorized,
/// recorded with a receipt, and refused or answered with a conflict when the job moved elsewhere.
/// A conflict or a missing job becomes `JobError.changedElsewhere`, and the worker stops without
/// publishing. A step whose commit failed in the store is retried once under the same request ID,
/// so a commit that did land returns its recorded receipt instead of a second change.
public actor JobRecorder {
    /// The job's identity, which never changes.
    public nonisolated let id: JobID
    public private(set) var job: LabJob
    private let backend: any JobBackend

    /// Adopts a stored job, for example to resume it.
    public init(job: LabJob, backend: any JobBackend) {
        id = job.id
        self.job = job
        self.backend = backend
    }

    /// Records a new running job and returns its recorder.
    public static func start(
        _ draft: JobDraft,
        backend: any JobBackend,
        requestID: RequestID = RequestID()
    ) async throws(JobError) -> (recorder: JobRecorder, receipt: ActionReceipt) {
        let receipt = try await commitWithRetry(.startJob(draft: draft), requestID: requestID, backend: backend)
        let job = try await backend.job(draft.id)
        return (JobRecorder(job: job, backend: backend), receipt)
    }

    /// Records one lifecycle step and returns its receipt.
    @discardableResult
    public func advance(_ transition: JobTransition) async throws(JobError) -> ActionReceipt {
        let operation = DomainOperation.updateJob(id: job.id, expected: job.revision, transition: transition)
        let receipt: ActionReceipt
        do {
            receipt = try await Self.commitWithRetry(operation, requestID: RequestID(), backend: backend)
        } catch .refused(.notFound) {
            throw .changedElsewhere(nil)
        } catch .refused(.ruleViolation(.jobFinished)), .refused(.ruleViolation(.jobPhase)) {
            throw .changedElsewhere(try await currentPhase())
        }
        if receipt.conflict != nil {
            throw .changedElsewhere(try await currentPhase())
        }
        job = try await backend.job(job.id)
        return receipt
    }

    /// Reads the job again, for example after another adapter changed it.
    @discardableResult
    public func refresh() async throws(JobError) -> LabJob {
        job = try await backend.job(job.id)
        return job
    }

    private func currentPhase() async throws(JobError) -> JobPhase.Name? {
        do {
            job = try await backend.job(job.id)
            return job.phase.name
        } catch .refused(.notFound) {
            return nil
        }
    }

    private static func commitWithRetry(
        _ operation: DomainOperation,
        requestID: RequestID,
        backend: any JobBackend
    ) async throws(JobError) -> ActionReceipt {
        do {
            return try await backend.commit(operation, requestID: requestID)
        } catch .refused(.storeFailure(.commitFailed)) {
            // The commit may have landed before the failure was reported. The same request ID
            // returns that receipt, or commits once if it did not land.
            return try await backend.commit(operation, requestID: requestID)
        }
    }
}

/// Makes the stored truth match what is actually running after a launch.
public enum JobRecovery {
    /// Marks every running job of `kind` that no live worker owns as interrupted because the app
    /// stopped while it ran. Such a job was left `running` by a process that ended: a force-quit,
    /// a crash, or the system ending the app. Returns the receipts it recorded.
    ///
    /// A job that changed while this ran is left as it is.
    public static func reconcile(
        kind: JobKind,
        backend: any JobBackend,
        isLive: @Sendable (JobID) -> Bool
    ) async throws(JobError) -> [ActionReceipt] {
        var receipts: [ActionReceipt] = []
        let orphans = try await backend.jobs(of: kind)
            .filter { $0.phase == .running && !isLive($0.id) }
            .sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        for job in orphans {
            do {
                receipts.append(try await JobRecorder(job: job, backend: backend).advance(.interrupt(reason: .appStopped)))
            } catch .changedElsewhere {
                continue
            }
        }
        return receipts
    }
}
