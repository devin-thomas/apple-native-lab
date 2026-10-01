import ActionAtlas
import AppIntents
import LabDomain
import PointInspect
import SurfaceDeck

/// Includes Action Atlas's App Intents, entities, and queries in this app's App Intents metadata,
/// and Surface Deck's toggle and launch action (LAB-004). The intents live in package targets;
/// Xcode extracts them into the host.
struct NativeLabIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [ActionAtlasIntentsPackage.self, SurfaceDeckIntentsPackage.self, PointInspectIntentsPackage.self]
    }
}

/// Connects App Intents to this host's store.
enum ActionAtlasHost {
    /// Registers the library every App Intent and entity query uses. Call once at launch, before
    /// the system can run an intent. Intents then commit through the same `LabLibrary` and
    /// `LabDataService` as the app UI, and their receipts join this session's receipt list.
    @MainActor
    static func connect(_ library: LabLibrary) {
        AppDependencyManager.shared.add(dependency: ActionAtlasLink(backend: LibraryAtlasBackend(library: library)))
    }
}

/// Action Atlas's way into the host: every read and commit goes through `LabLibrary` and
/// `LabDataService`, under the adapter the entry point names. It never holds the store.
struct LibraryAtlasBackend: ActionAtlasBackend {
    let library: LabLibrary

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        authority: AtlasAuthority,
        names: [EntityReference: String]
    ) async throws(ActionAtlasError) -> ActionReceipt {
        do {
            return try await library.submit(
                operation, requestID: requestID, authority: CommitAuthority(authority), names: names
            ).receipt
        } catch {
            throw ActionAtlasError(error)
        }
    }

    func collection(_ id: CollectionID, via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> LabCollection {
        let service = try await openedService()
        do { return try await service.collection(id, as: Self.actor(entryPoint)) } catch { throw ActionAtlasError(error) }
    }

    func item(_ id: ItemID, via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> LabItem {
        let service = try await openedService()
        do { return try await service.item(id, as: Self.actor(entryPoint)) } catch { throw ActionAtlasError(error) }
    }

    func items(_ filter: ItemFilter, via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> [LabItem] {
        let service = try await openedService()
        do { return try await service.items(filter, as: Self.actor(entryPoint)) } catch { throw ActionAtlasError(error) }
    }

    func collections(via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> [LabCollection] {
        let service = try await openedService()
        do { return try await service.collections(as: Self.actor(entryPoint)) } catch { throw ActionAtlasError(error) }
    }

    private func openedService() async throws(ActionAtlasError) -> LabDataService {
        do { return try await library.openedService() } catch { throw ActionAtlasError(error) }
    }

    /// The actor each entry point reads as. Commits take theirs from the authority instead.
    static func actor(_ entryPoint: AtlasEntryPoint) -> ActorScope {
        switch entryPoint {
        case .appUI: LabDataService.appUI
        case .appIntent: LabDataService.appIntent
        }
    }
}

extension CommitAuthority {
    /// A control press in the action browser is a user action; an intent keeps its confirmation,
    /// if it has one, for the grant decision.
    init(_ authority: AtlasAuthority) {
        switch authority {
        case .appControl: self = .userAction
        case .intent(let confirmation): self = .intent(confirmation)
        }
    }
}

extension ActionAtlasError {
    init(_ failure: LabLibrary.SubmitFailure) {
        switch failure {
        case .unavailable(let reason): self = .unavailable(reason: reason)
        case .refused(let error): self.init(error)
        }
    }
}
