import LabDomain

/// Where an Action Atlas request arrived. The host maps it to an adapter kind (ADR-011).
public enum AtlasEntryPoint: String, Hashable, Sendable, CaseIterable {
    /// The in-app action browser, where a person presses a control.
    case appUI = "app-ui"
    /// An App Intent the system ran for Shortcuts, Siri, or Spotlight.
    case appIntent = "app-intent"

    public var adapter: AdapterKind {
        switch self {
        case .appUI: .appUI
        case .appIntent: .appIntent
        }
    }
}

/// Proof that a person confirmed one exact change in the system's confirmation for an App Intent.
///
/// Only `ActionAtlasActions` creates one, after the confirmation step it was given returns. It has
/// no public initializer and is not `Codable`, so nothing in a payload, a shortcut's stored value,
/// or model output can become one. The host issues an ADR-013 grant for an intent's destructive
/// commit only when it holds a confirmation that covers that commit.
public struct IntentConfirmation: Hashable, Sendable {
    /// The operation the person confirmed, including the revision it expects.
    public let operation: DomainOperation

    init(confirmed operation: DomainOperation) {
        self.operation = operation
    }

    /// A confirmation the host records after its own intent dialog has returned for this operation.
    /// The dialog has to return first. A payload cannot become one of these: there is no decoder.
    public static func confirmed(_ operation: DomainOperation) -> IntentConfirmation {
        IntentConfirmation(confirmed: operation)
    }

    /// Whether this confirmation is for exactly `operation`.
    public func covers(_ operation: DomainOperation) -> Bool {
        self.operation == operation
    }
}

/// Why a commit is being made, as the host needs to know it to decide on a grant.
public enum AtlasAuthority: Hashable, Sendable {
    /// A person pressed a control in the in-app action browser.
    case appControl
    /// An App Intent the system ran. It holds a confirmation only when the person confirmed this
    /// change in the system's dialog; an intent without one can never commit a destructive change.
    case intent(IntentConfirmation?)

    public var entryPoint: AtlasEntryPoint {
        switch self {
        case .appControl: .appUI
        case .intent: .appIntent
        }
    }
}

/// What Action Atlas needs from the host: reads and commits through the host's own
/// `OperationService`, under the adapter the entry point names.
///
/// The host implements this with the same data service its views use, so an App Intent and the
/// in-app action browser take one path to the store. Action Atlas never holds the store.
public protocol ActionAtlasBackend: Sendable {
    /// Commits one request and returns its receipt, or the receipt already recorded for its ID.
    /// `names` gives display titles for the entities involved, for the host's receipt inspector.
    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        authority: AtlasAuthority,
        names: [EntityReference: String]
    ) async throws(ActionAtlasError) -> ActionReceipt

    func collection(_ id: CollectionID, via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> LabCollection
    func item(_ id: ItemID, via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> LabItem
    func items(_ filter: ItemFilter, via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> [LabItem]
    /// Every collection, archived or not, in any order.
    func collections(via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> [LabCollection]
}

/// The handle App Intents and entity queries receive through `AppDependencyManager`.
///
/// The host registers one at launch. Until it does, intents use `unavailable`, which refuses
/// every request with a readable reason instead of failing silently.
public final class ActionAtlasLink: Sendable {
    public let backend: any ActionAtlasBackend

    public init(backend: any ActionAtlasBackend) {
        self.backend = backend
    }

    /// The actions an entry point may run.
    public func actions(_ entryPoint: AtlasEntryPoint) -> ActionAtlasActions {
        ActionAtlasActions(backend: backend, entryPoint: entryPoint)
    }

    /// Used when no host has connected its store.
    public static let unavailable = ActionAtlasLink(backend: UnavailableBackend(
        reason: "Native Lab has not opened its store for actions yet. Open Native Lab and try again."
    ))
}

/// A backend that refuses everything with one reason: the unavailable path.
public struct UnavailableBackend: ActionAtlasBackend {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public func commit(
        _ operation: DomainOperation, requestID: RequestID, authority: AtlasAuthority, names: [EntityReference: String]
    ) async throws(ActionAtlasError) -> ActionReceipt {
        throw .unavailable(reason: reason)
    }

    public func collection(_ id: CollectionID, via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> LabCollection {
        throw .unavailable(reason: reason)
    }

    public func item(_ id: ItemID, via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> LabItem {
        throw .unavailable(reason: reason)
    }

    public func items(_ filter: ItemFilter, via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> [LabItem] {
        throw .unavailable(reason: reason)
    }

    public func collections(via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> [LabCollection] {
        throw .unavailable(reason: reason)
    }
}
