import Foundation
import LabDomain
import LabJobs

/// The job runtime's way into this host (LAB-032): reads and commits go through `LabLibrary` and
/// `LabDataService` as the app UI, so every job step leaves a receipt in the session's list. It
/// never holds the store.
///
/// A job step is part of work a person started with a button, and none is destructive, so no
/// grant is issued for it (ADR-013). A model tool could not take this path: its ceiling has no
/// commit (ADR-011).
struct LibraryJobBackend: JobBackend {
    let library: LabLibrary

    func job(_ id: JobID) async throws(JobError) -> LabJob {
        let service = try await openedService()
        do { return try await service.job(id, as: LabDataService.appUI) } catch { throw .refused(error) }
    }

    func jobs(of kind: JobKind) async throws(JobError) -> [LabJob] {
        let service = try await openedService()
        do { return try await service.jobs(kind: kind, as: LabDataService.appUI) } catch { throw .refused(error) }
    }

    func commit(_ operation: DomainOperation, requestID: RequestID) async throws(JobError) -> ActionReceipt {
        var names: [EntityReference: String] = [:]
        switch operation {
        case .startJob(let draft): names[.job(draft.id)] = draft.title.value
        case .updateJob(let id, _, _): names[.job(id)] = (try? await job(id))?.title.value
        default: break
        }
        do {
            return try await library.submit(operation, requestID: requestID, authority: .userAction, names: names).receipt
        } catch {
            switch error {
            case .unavailable(let reason): throw .unavailable(reason: reason)
            case .refused(let refusal): throw .refused(refusal)
            }
        }
    }

    private func openedService() async throws(JobError) -> LabDataService {
        do { return try await library.openedService() } catch {
            switch error {
            case .unavailable(let reason): throw .unavailable(reason: reason)
            case .refused(let refusal): throw .refused(refusal)
            }
        }
    }
}
