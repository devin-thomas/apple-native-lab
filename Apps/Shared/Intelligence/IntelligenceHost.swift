import LabDomain
import TypedIntelligence

/// Typed Local Intelligence's way into the host (LAB-010). Reads and proposals go through
/// `LabDataService` as `TypedIntelligence.proposer`, the model-tool adapter; a commit goes through
/// `LabLibrary.submit` as a user action, so it runs as the app UI and its receipt joins the session
/// list the inspector reads. It never holds the store, and no extractor ever receives it.
struct LibraryIntelligenceBackend: TypedIntelligenceBackend {
    let library: LabLibrary

    func items(_ filter: ItemFilter) async throws(IntelligenceError) -> [LabItem] {
        let service = try await openedService()
        do { return try await service.items(filter, as: TypedIntelligence.proposer) } catch { throw .refused(error) }
    }

    func propose(_ operation: DomainOperation) async throws(IntelligenceError) -> OperationProposal {
        let service = try await openedService()
        do { return try await service.propose(operation, as: TypedIntelligence.proposer) } catch { throw .refused(error) }
    }

    /// The person pressed Apply on this exact change. `.userAction` selects the app-UI actor, and
    /// an edit is never destructive, so no grant is issued.
    func commit(_ change: ApprovedChange) async throws(IntelligenceError) -> ActionReceipt {
        do {
            return try await library.submit(
                change.operation, requestID: change.requestID, authority: .userAction, names: [:]
            ).receipt
        } catch {
            throw IntelligenceError(error)
        }
    }

    private func openedService() async throws(IntelligenceError) -> LabDataService {
        do { return try await library.openedService() } catch { throw IntelligenceError(error) }
    }
}

extension IntelligenceError {
    init(_ failure: LabLibrary.SubmitFailure) {
        switch failure {
        case .unavailable(let reason): self = .unavailable(reason: reason)
        case .refused(let error): self = .refused(error)
        }
    }
}

/// The experiment's diagnostics: metadata-only events through the lab's one facade, to the system
/// log. Never the note, the prompt, the draft, or a sample's text.
enum IntelligenceDiagnostics {
    static let log = DiagnosticsLog(sinks: [OSLogDiagnosticSink()])
}
