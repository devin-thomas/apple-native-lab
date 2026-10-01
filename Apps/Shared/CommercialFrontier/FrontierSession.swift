import CommercialFrontier
import LabDomain
import Observation

@MainActor @Observable
final class FrontierSession {
    private let desk = FrontierDesk()
    var snapshots: [FrontierCapabilityCase: FrontierSnapshot] = [:]
    var message: String?
    var busy = false

    func refresh(library: LabLibrary) async {
        do {
            var loaded: [FrontierCapabilityCase: FrontierSnapshot] = [:]
            for capability in FrontierCapabilityCase.allCases {
                loaded[capability] = try await desk.snapshot(capability, through: LibraryFrontierBackend(library: library))
            }
            snapshots = loaded
        } catch {
            snapshots = [:]
            message = "The saved probe could not be read."
        }
    }

    func perform(_ action: FrontierAction, capability: FrontierCapabilityCase, library: LabLibrary) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let receipt = try await desk.perform(action, for: capability,
                through: LibraryFrontierBackend(library: library), requestID: RequestID())
            message = "\(action.title). Receipt: \(receipt.operationID)."
            await refresh(library: library)
        } catch {
            await refresh(library: library)
            message = "The probe refused the change. Review the saved status."
        }
    }
}

struct LibraryFrontierBackend: FrontierBackend {
    let library: LabLibrary
    func item(_ id: ItemID) async throws -> LabItem? {
        let service = try await library.openedService()
        do { return try await service.item(id, as: LabDataService.appUI) }
        catch OperationError.notFound { return nil }
    }
    func collection(_ id: CollectionID) async throws -> LabCollection? {
        let service = try await library.openedService()
        do { return try await service.collection(id, as: LabDataService.appUI) }
        catch OperationError.notFound { return nil }
    }
    func perform(_ operation: DomainOperation, requestID: RequestID) async throws -> ActionReceipt {
        try await library.submit(operation, requestID: requestID, authority: .userAction, names: [:]).receipt
    }
}
