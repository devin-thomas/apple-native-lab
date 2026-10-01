import Foundation
import LabDomain

public enum FrontierCapabilityCase: String, CaseIterable, Codable, Sendable, Identifiable {
    case pushToTalk, carPlay, screenTime
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .pushToTalk: "Push to Talk"
        case .carPlay: "CarPlay"
        case .screenTime: "Screen Time"
        }
    }
    public var gate: String {
        switch self {
        case .pushToTalk: "Live PTT needs the Push to Talk capability, audio transport and APNs. No background wake runs here."
        case .carPlay: "Live CarPlay needs Apple approval for an allowed category. This audio-category list is an in-app preview."
        case .screenTime: "Live Screen Time needs Family Controls configuration and individual authorization. No system restrictions are installed here."
        }
    }
    public var itemID: ItemID {
        let suffix: String
        switch self {
        case .pushToTalk: suffix = "01"
        case .carPlay: suffix = "02"
        case .screenTime: suffix = "03"
        }
        return ItemID(rawValue: UUID(uuidString: "04804804-1048-4048-8048-0480480480\(suffix)")!)
    }
}

public struct EntitlementEvidence: Sendable, Equatable {
    public let capability: FrontierCapabilityCase
    public let managedApproval: String = "Not supplied"
    public let liveAdapter: String = "Not run"
    public init(capability: FrontierCapabilityCase) { self.capability = capability }
}

public enum FrontierAction: String, CaseIterable, Sendable {
    case join, leave, connect, disconnect, authorizeSelf, restrictSample, revoke, reset
    public var title: String {
        switch self {
        case .join: "Join sample channel"
        case .leave: "Leave channel"
        case .connect: "Connect audio preview"
        case .disconnect: "Disconnect preview"
        case .authorizeSelf: "Authorize myself (simulated)"
        case .restrictSample: "Restrict sample (simulated)"
        case .revoke: "Revoke and clear restrictions"
        case .reset: "Reset probe"
        }
    }
}

public struct FrontierSnapshot: Codable, Equatable, Sendable {
    public var active = false
    public var restricted = false
    public init() {}
    public func applying(_ action: FrontierAction, to capability: FrontierCapabilityCase) throws -> Self {
        var next = self
        if action == .reset {
            guard active || restricted else { throw FrontierError.invalidTransition }
            return Self()
        }
        switch (capability, action) {
        case (.pushToTalk, .join), (.carPlay, .connect), (.screenTime, .authorizeSelf):
            guard !active else { throw FrontierError.invalidTransition }
            next.active = true
        case (.pushToTalk, .leave), (.carPlay, .disconnect):
            guard active else { throw FrontierError.invalidTransition }
            next.active = false
        case (.screenTime, .restrictSample):
            guard active && !restricted else { throw FrontierError.invalidTransition }
            next.restricted = true
        case (.screenTime, .revoke):
            guard active || restricted else { throw FrontierError.invalidTransition }
            next = Self()
        default: throw FrontierError.invalidTransition
        }
        return next
    }
}

public enum FrontierError: Error, Equatable {
    case invalidTransition, invalidRecord, conflict, busy, cancelled, sessionLimit, unavailable
}

public enum FrontierFixture {
    public static let collection = CollectionID(rawValue: UUID(uuidString: "04804804-1048-4048-8048-048048048040")!)
    public static let collectionRequest = RequestID(rawValue: UUID(uuidString: "04804804-1048-4048-8048-048048048041")!)
    public static let audioRows = ["Harbor tone — original fixture", "Quiet interval — original fixture"]
    public static let escape = "Revoke and clear restrictions always returns this simulation to unrestricted. For a future live individual-authorized demo, clear ManagedSettings and stop DeviceActivity monitoring before revoking authorization; authorization can also be revoked in Settings. Never shield this app or Settings."
}
