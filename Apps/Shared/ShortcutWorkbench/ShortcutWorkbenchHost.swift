import ActionAtlas
import AppIntents
import LabDomain
import ShortcutWorkbench

/// Connects Shortcut Workbench App Intents to this host's store and open action.
enum ShortcutWorkbenchHost {
    @MainActor
    static func connect(_ library: LabLibrary, model: ShortcutWorkbenchModel = .shared) {
        model.connect(library)
        AppDependencyManager.shared.add(dependency: WorkbenchLink(
            backend: LibraryWorkbenchBackend(library: library),
            openWorkbench: { model.requestOpen() }
        ))
    }
}

/// Workbench reads and commits through `LabLibrary` / `LabDataService`.
struct LibraryWorkbenchBackend: WorkbenchBackend {
    let library: LabLibrary

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        authority: WorkbenchAuthority,
        names: [EntityReference: String]
    ) async throws(WorkbenchError) -> ActionReceipt {
        do {
            return try await library.submit(
                operation,
                requestID: requestID,
                authority: CommitAuthority(authority),
                names: names
            ).receipt
        } catch {
            throw WorkbenchError(error)
        }
    }

    func item(_ id: ItemID, via entryPoint: WorkbenchEntryPoint) async throws(WorkbenchError) -> LabItem {
        let service = try await openedService()
        do { return try await service.item(id, as: Self.actor(entryPoint)) } catch { throw WorkbenchError(error) }
    }

    func items(_ filter: ItemFilter, via entryPoint: WorkbenchEntryPoint) async throws(WorkbenchError) -> [LabItem] {
        let service = try await openedService()
        do { return try await service.items(filter, as: Self.actor(entryPoint)) } catch { throw WorkbenchError(error) }
    }

    func collection(_ id: CollectionID, via entryPoint: WorkbenchEntryPoint) async throws(WorkbenchError) -> LabCollection {
        let service = try await openedService()
        do { return try await service.collection(id, as: Self.actor(entryPoint)) } catch { throw WorkbenchError(error) }
    }

    func collections(via entryPoint: WorkbenchEntryPoint) async throws(WorkbenchError) -> [LabCollection] {
        let service = try await openedService()
        do { return try await service.collections(as: Self.actor(entryPoint)) } catch { throw WorkbenchError(error) }
    }

    private func openedService() async throws(WorkbenchError) -> LabDataService {
        do { return try await library.openedService() } catch { throw WorkbenchError(error) }
    }

    static func actor(_ entryPoint: WorkbenchEntryPoint) -> ActorScope {
        switch entryPoint {
        case .appUI: LabDataService.appUI
        case .appIntent: LabDataService.appIntent
        }
    }
}

extension CommitAuthority {
    init(_ authority: WorkbenchAuthority) {
        switch authority {
        case .appControl: self = .userAction
        case .intent: self = .intent(nil)
        }
    }
}

extension WorkbenchError {
    init(_ failure: LabLibrary.SubmitFailure) {
        switch failure {
        case .unavailable(let reason): self = .unavailable(reason: reason)
        case .refused(let error): self.init(error)
        }
    }
}
