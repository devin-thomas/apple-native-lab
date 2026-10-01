import LabDomain

/// Where a workbench request arrived. The host maps it to an adapter kind (ADR-011).
public enum WorkbenchEntryPoint: String, Hashable, Sendable, CaseIterable {
    case appUI = "app-ui"
    case appIntent = "app-intent"

    public var adapter: AdapterKind {
        switch self {
        case .appUI: .appUI
        case .appIntent: .appIntent
        }
    }
}

/// Why a commit is being made, as the host needs it to decide on a grant.
public enum WorkbenchAuthority: Hashable, Sendable {
    case appControl
    /// Workbench intents are non-destructive in this build; confirmation stays nil. Destructive
    /// archive remains on Action Atlas, which carries `IntentConfirmation`.
    case intent

    public var entryPoint: WorkbenchEntryPoint {
        switch self {
        case .appControl: .appUI
        case .intent: .appIntent
        }
    }
}

/// What Shortcut Workbench needs from the host: reads and commits through `OperationService`.
public protocol WorkbenchBackend: Sendable {
    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        authority: WorkbenchAuthority,
        names: [EntityReference: String]
    ) async throws(WorkbenchError) -> ActionReceipt

    func item(_ id: ItemID, via entryPoint: WorkbenchEntryPoint) async throws(WorkbenchError) -> LabItem
    func items(_ filter: ItemFilter, via entryPoint: WorkbenchEntryPoint) async throws(WorkbenchError) -> [LabItem]
    func collection(_ id: CollectionID, via entryPoint: WorkbenchEntryPoint) async throws(WorkbenchError) -> LabCollection
    func collections(via entryPoint: WorkbenchEntryPoint) async throws(WorkbenchError) -> [LabCollection]
}

/// The handle App Intents receive through `AppDependencyManager`.
public final class WorkbenchLink: Sendable {
    public let backend: any WorkbenchBackend
    private let openWorkbench: @MainActor @Sendable () -> Void

    public init(backend: any WorkbenchBackend, openWorkbench: @escaping @MainActor @Sendable () -> Void = {}) {
        self.backend = backend
        self.openWorkbench = openWorkbench
    }

    public func actions(_ entryPoint: WorkbenchEntryPoint) -> WorkbenchActions {
        WorkbenchActions(backend: backend, entryPoint: entryPoint)
    }

    @MainActor
    public func open() {
        openWorkbench()
    }

    public static let unavailable = WorkbenchLink(
        backend: UnavailableWorkbenchBackend(
            reason: "Native Lab has not opened its store for the Shortcut Workbench yet. Open Native Lab and try again."
        ),
        openWorkbench: {}
    )
}

public struct UnavailableWorkbenchBackend: WorkbenchBackend {
    public let reason: String

    public init(reason: String) { self.reason = reason }

    public func commit(
        _ operation: DomainOperation, requestID: RequestID, authority: WorkbenchAuthority, names: [EntityReference: String]
    ) async throws(WorkbenchError) -> ActionReceipt {
        throw .unavailable(reason: reason)
    }

    public func item(_ id: ItemID, via entryPoint: WorkbenchEntryPoint) async throws(WorkbenchError) -> LabItem {
        throw .unavailable(reason: reason)
    }

    public func items(_ filter: ItemFilter, via entryPoint: WorkbenchEntryPoint) async throws(WorkbenchError) -> [LabItem] {
        throw .unavailable(reason: reason)
    }

    public func collection(_ id: CollectionID, via entryPoint: WorkbenchEntryPoint) async throws(WorkbenchError) -> LabCollection {
        throw .unavailable(reason: reason)
    }

    public func collections(via entryPoint: WorkbenchEntryPoint) async throws(WorkbenchError) -> [LabCollection] {
        throw .unavailable(reason: reason)
    }
}
