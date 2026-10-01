import ActionAtlas
import AppIntents
import Foundation
import LabDomain
import RespectfulAttention

/// Connects Respectful Attention's intents to this host's store (LAB-043).
enum AttentionHost {
    @MainActor
    static func connect(_ library: LabLibrary, model: AttentionModel = .shared) {
        model.connect(library)
        AppDependencyManager.shared.add(dependency: RespectfulAttentionLink(
            backend: LibraryAttentionBackend(library: library)
        ))
    }
}

/// Reads and commits through `LabLibrary`, under the adapter the entry point names.
struct LibraryAttentionBackend: AttentionBackend {
    let library: LabLibrary

    func attentions(via entryPoint: AttentionEntryPoint) async throws(AttentionError) -> [LabAttention] {
        let service: LabDataService
        do { service = try await library.openedService() } catch { throw .unavailable(error.message) }
        do { return try await service.attentions(as: scope(entryPoint)) }
        catch { throw .refused(error) }
    }

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        via entryPoint: AttentionEntryPoint,
        confirmation: AttentionConfirmation?
    ) async throws(AttentionError) -> ActionReceipt {
        let names = attentionNames(in: operation)
        let authority = authority(entryPoint, confirmation: confirmation, operation: operation)
        do {
            return try await library.submit(operation, requestID: requestID, authority: authority, names: names).receipt
        } catch {
            switch error {
            case .unavailable(let reason): throw .unavailable(reason)
            case .refused(let refused): throw .refused(refused)
            }
        }
    }

    private func scope(_ entryPoint: AttentionEntryPoint) -> ActorScope {
        switch entryPoint {
        case .appUI: LabDataService.appUI
        case .appIntent: LabDataService.appIntent
        }
    }

    private func authority(
        _ entryPoint: AttentionEntryPoint,
        confirmation: AttentionConfirmation?,
        operation: DomainOperation
    ) -> CommitAuthority {
        switch entryPoint {
        case .appUI:
            .userAction
        case .appIntent:
            .intent(confirmation.flatMap { $0.covers(operation) ? IntentConfirmation.confirmed(operation) : nil })
        }
    }

    private func attentionNames(in operation: DomainOperation) -> [EntityReference: String] {
        switch operation {
        case .scheduleAttention(_, let draft):
            [.attention(draft.id): draft.reason.value]
        case .restoreLabAlerts(let drafts):
            Dictionary(uniqueKeysWithValues: drafts.map { (.attention($0.id), $0.reason.value) })
        default:
            [:]
        }
    }
}

private extension LabLibrary.SubmitFailure {
    var message: String {
        switch self {
        case .unavailable(let reason): reason
        case .refused: "The lab store could not be read."
        }
    }
}
