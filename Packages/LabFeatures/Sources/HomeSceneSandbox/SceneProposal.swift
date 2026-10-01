import Foundation

/// One home the sandbox can act on: simulated fictional home, or a live home when permitted.
public struct HomeSnapshot: Hashable, Sendable, Codable {
    public let id: UUID
    public let name: String
    public let accessories: [AccessorySnapshot]
    public let isSimulated: Bool

    public init(id: UUID, name: String, accessories: [AccessorySnapshot], isSimulated: Bool) {
        self.id = id
        self.name = name
        self.accessories = accessories
        self.isSimulated = isSimulated
    }

    public func accessory(_ id: AccessoryID) -> AccessorySnapshot? {
        accessories.first { $0.id == id }
    }

    public var lights: [AccessorySnapshot] { accessories.filter { $0.kind == .light } }
    public var excludedByDefault: [AccessorySnapshot] { accessories.filter(\.isExcludedByDefault) }
}

/// Whether the sandbox is on the fictional home or attempting a live HomeKit home.
public enum HomeRoute: String, Hashable, Sendable, Codable {
    /// Deterministic fictional home with no real accessories.
    case simulated
    /// Live HomeKit homes. Requires authorization; revoked permission leaves this route.
    case live
}

/// HomeKit authorization as the sandbox models it (mirrors `HMHomeManagerAuthorizationStatus`).
public enum HomePermission: String, Hashable, Sendable, Codable {
    /// The person has not chosen yet (`Determined` bit clear in HomeKit's options).
    case notDetermined
    /// Authorized to read homes.
    case authorized
    /// Explicitly denied.
    case denied
    /// Restricted by the system.
    case restricted

    public var allowsLiveMode: Bool { self == .authorized }

    public var explanation: String {
        switch self {
        case .notDetermined:
            "Home access has not been decided yet. The fictional home stays available."
        case .authorized:
            "Home access is authorized for live mode."
        case .denied:
            "Home access was denied. Live mode is stopped; the fictional home remains."
        case .restricted:
            "Home access is restricted. Live mode is stopped; the fictional home remains."
        }
    }
}

/// One proposed write for a selected accessory in a scene preview.
public struct ProposedAccessoryAction: Hashable, Sendable, Codable {
    public let accessory: AccessorySnapshot
    public let change: LightChange
    public let before: LightChange

    public init(accessory: AccessorySnapshot, change: LightChange, before: LightChange) {
        self.accessory = accessory
        self.change = change
        self.before = before
    }

    public var diffLine: String {
        "\(accessory.name): \(before.summary.isEmpty ? "—" : before.summary) → \(change.summary)"
    }
}

/// Why an accessory was left out of the selectable scene actions.
public struct ExcludedAccessory: Hashable, Sendable, Codable {
    public let accessory: AccessorySnapshot
    public let reason: String

    public init(accessory: AccessorySnapshot, reason: String) {
        self.accessory = accessory
        self.reason = reason
    }
}

/// Preview of a scene: selected light diffs, plus every default exclusion.
public struct SceneProposal: Hashable, Sendable, Codable {
    public let home: HomeSnapshot
    public let route: HomeRoute
    public let selected: [ProposedAccessoryAction]
    public let excluded: [ExcludedAccessory]

    public init(
        home: HomeSnapshot,
        route: HomeRoute,
        selected: [ProposedAccessoryAction],
        excluded: [ExcludedAccessory]
    ) {
        self.home = home
        self.route = route
        self.selected = selected
        self.excluded = excluded
    }

    public var isEmpty: Bool { selected.isEmpty }

    public var summary: String {
        if selected.isEmpty {
            return "No light changes selected. Locks, doors, alarms, and heating stay excluded."
        }
        let count = selected.count
        let noun = count == 1 ? "1 light change" : "\(count) light changes"
        return "Preview: \(noun) in \(home.name). \(excluded.count) accessories excluded by default."
    }
}

/// Result of applying one selected action.
public enum AccessoryOutcome: Hashable, Sendable, Codable {
    case succeeded(AccessoryID, String)
    case failed(AccessoryID, String)

    public var accessoryID: AccessoryID {
        switch self {
        case .succeeded(let id, _), .failed(let id, _): id
        }
    }

    public var didSucceed: Bool {
        if case .succeeded = self { true } else { false }
    }

    public var line: String {
        switch self {
        case .succeeded(_, let detail): detail
        case .failed(_, let detail): detail
        }
    }
}

/// Commit result for a scene: per-accessory outcomes and whether the whole scene succeeded.
public struct SceneCommitReport: Hashable, Sendable, Codable {
    public let proposal: SceneProposal
    public let outcomes: [AccessoryOutcome]
    /// True only when every selected action succeeded. A disconnected lamp keeps this false.
    public let sceneSucceeded: Bool
    public let explanation: String

    public init(proposal: SceneProposal, outcomes: [AccessoryOutcome]) {
        self.proposal = proposal
        self.outcomes = outcomes
        let selectedIDs = Set(proposal.selected.map(\.accessory.id))
        let relevant = outcomes.filter { selectedIDs.contains($0.accessoryID) }
        sceneSucceeded = !relevant.isEmpty && relevant.allSatisfy(\.didSucceed)
        if relevant.isEmpty {
            explanation = "Nothing was committed."
        } else if sceneSucceeded {
            explanation = "Scene succeeded: every selected light changed."
        } else {
            let failed = relevant.filter { !$0.didSucceed }.count
            let ok = relevant.filter(\.didSucceed).count
            explanation = "Scene did not succeed: \(ok) light(s) changed, \(failed) failed. A partial run is not a successful scene."
        }
    }
}
