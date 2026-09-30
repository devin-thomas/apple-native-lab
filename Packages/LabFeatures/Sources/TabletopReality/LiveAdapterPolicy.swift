import Foundation
import LabDomain
import LabSupport

// MARK: - Which anchors are the lab's

/// One anchor in a live AR session, as the adapter reads it: its identifier and its name.
///
/// Detected planes and anything the system adds have no name, or a name the lab did not give.
public struct SessionAnchorRecord: Hashable, Sendable {
    public let identifier: UUID
    public let name: String?

    public init(identifier: UUID, name: String?) {
        self.identifier = identifier
        self.name = name
    }
}

/// Names the anchors the lab adds to an AR session, and picks only those for removal.
///
/// The adapter adds one anchor: the table's origin, where the person placed the table. Every
/// object hangs off it. A reset, Clear Table, or Start Fresh removes the anchors this names and
/// nothing else, so the planes ARKit detected, and anything another component added, stay.
public enum LabAnchorNames {
    public static let prefix = "nativelab.tabletop."
    public static let tableOrigin = prefix + "table-origin"

    public static func isLabOwned(_ name: String?) -> Bool {
        name?.hasPrefix(prefix) == true
    }

    /// The identifiers to remove: exactly the lab-owned anchors, in the order given.
    public static func removals(from anchors: [SessionAnchorRecord]) -> [UUID] {
        anchors.filter { isLabOwned($0.name) }.map(\.identifier)
    }
}

// MARK: - Saving the table map

/// ARKit's world-mapping status, as the adapter reads it.
public enum WorldMappingReading: String, Hashable, Sendable {
    case notAvailable
    case limited
    case extending
    case mapped
}

/// Whether the table's map may be saved now, and why not.
///
/// A saved map lets the next AR session find the same table again. It is the only mapping data
/// the lab keeps: ARKit's own world-map archive, on this device, in the app's container, never in
/// the lab store, a receipt, an export, or a backup. It is written only after the person reads
/// what it holds and confirms, every time.
public enum MappingDecision: Hashable, Sendable {
    /// The map can be saved once the person confirms.
    case ready
    /// Not now: the reason is a sentence for a person.
    case notYet(String)
    /// Never on this route.
    case unsupported(String)

    public var canSave: Bool { self == .ready }

    public var reason: String? {
        switch self {
        case .ready: nil
        case .notYet(let reason), .unsupported(let reason): reason
        }
    }
}

public enum MappingPolicy {
    /// What the person agrees to when saving a table map.
    public static let consentTitle = "Save a Map of This Table?"
    public static let consentMessage = """
        Native Lab will save ARKit's map of the area around this table so it can find the table \
        again next time. The map holds feature points and planes that describe the room's surfaces; \
        it holds no camera images. It stays on this device, is not backed up or exported, and is \
        deleted when you choose Forget Saved Map.
        """

    public static func decision(
        isLive: Bool,
        tracking: TrackingStatus,
        mapping: WorldMappingReading,
        hasTable: Bool
    ) -> MappingDecision {
        guard isLive else { return .unsupported("Only the live AR camera makes a map. The virtual table has nothing to save.") }
        guard hasTable else { return .notYet("Place the table first.") }
        guard tracking == .normal else { return .notYet("Wait until tracking is normal.") }
        switch mapping {
        case .mapped, .extending:
            return .ready
        case .limited, .notAvailable:
            return .notYet("Move slowly around the table until ARKit has mapped it.")
        }
    }
}

// MARK: - Which route runs

/// Where the tabletop runs: the live AR camera, or the virtual table.
public enum TabletopRoute: Hashable, Sendable {
    /// Every gate for world tracking is met. The person may start the AR camera.
    case live
    /// World tracking may run after an explicit Start AR Camera action asks for the camera.
    case afterPermission
    /// The virtual table is the route. The reason names the gate that decided it.
    case virtualOnly(reason: String)

    public var offersLiveStart: Bool {
        switch self {
        case .live, .afterPermission: true
        case .virtualOnly: false
        }
    }

    /// Chooses the route from the world-tracking capability report. The report is measured on
    /// this device and build; a product name or a platform is never enough.
    public init(report: CapabilityReport) {
        switch report.route {
        case .live:
            self = .live
        case .afterFeatureAction:
            self = .afterPermission
        case .fallback:
            let deciding = report.decidingGates.map(\.detail)
            let reason = deciding.isEmpty ? "World tracking is \(report.readiness.title.lowercased()) here." : deciding.joined(separator: " ")
            self = .virtualOnly(reason: reason)
        }
    }

    /// A sentence for the route card.
    public var summary: String {
        switch self {
        case .live:
            "This device reports AR world tracking and camera access. Start the AR camera to place the table on a real surface."
        case .afterPermission:
            "This device reports AR world tracking. Starting the AR camera asks for camera access first."
        case .virtualOnly(let reason):
            "The AR camera is not available here, so the table is virtual. \(reason)"
        }
    }

    /// The feature action a Start AR Camera press stages. Nothing asks for the camera before it.
    public static let startAction = FeatureAction(capability: .worldTracking, experimentID: TabletopExperiment.id, title: "Start AR Camera")
}

// MARK: - Running several commits

/// Runs a list of operations one commit at a time, stopping between commits when cancelled.
///
/// Clear Table and Set Out Starter Scene each make several commits, one receipt per object, so a
/// failure or a cancellation leaves every finished commit recorded and the rest unmade.
public enum SequentialRun {
    public static func perform(
        _ operations: [DomainOperation],
        commit: (DomainOperation) async throws(TabletopError) -> ActionReceipt
    ) async throws(TabletopError) -> [ActionReceipt] {
        var receipts: [ActionReceipt] = []
        for operation in operations {
            guard !Task.isCancelled else { throw .cancelled(completed: receipts.count) }
            receipts.append(try await commit(operation))
        }
        return receipts
    }
}
