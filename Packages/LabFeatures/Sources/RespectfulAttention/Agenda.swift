import Foundation
import LabDomain

/// Identifiers this experiment owns on a system schedule. Anything else is left alone.
public enum LabAlertIdentity {
    public static let prefix = "lab-alert."

    public static func notificationID(_ id: AttentionID) -> String {
        prefix + id.rawValue.uuidString.lowercased()
    }

    public static func isLabOwned(_ identifier: String) -> Bool {
        guard identifier.lowercased().hasPrefix(prefix) else { return false }
        return UUID(uuidString: String(identifier.dropFirst(prefix.count))) != nil
    }
}

/// Which lab alerts a selected Focus may show. It filters lab content only.
///
/// Selecting a scope does not switch the system Focus and does not read or write any other app's
/// alerts. An identifier that is not lab-owned never matches.
public struct FocusScope: Hashable, Sendable {
    public let name: String
    public let included: Set<AttentionID>

    public init(name: String, included: Set<AttentionID>) {
        self.name = name
        self.included = included
    }

    public func visible(_ attentions: [LabAttention]) -> [LabAttention] {
        attentions.filter { included.contains($0.id) }
    }

    /// Lab-owned identifiers from `raw`, in order, dropping anything else.
    public static func labOwned(in raw: [String]) -> [String] {
        raw.filter(LabAlertIdentity.isLabOwned)
    }

    public func allowsNotification(_ identifier: String) -> Bool {
        guard LabAlertIdentity.isLabOwned(identifier),
              let id = UUID(uuidString: String(identifier.dropFirst(LabAlertIdentity.prefix.count)))
        else { return false }
        return included.contains(AttentionID(rawValue: id))
    }
}

/// One row of the in-app agenda, including a countdown from a supplied instant.
public struct AgendaTimer: Hashable, Sendable, Identifiable {
    public let id: AttentionID
    public let channel: AttentionChannel
    public let why: String
    public let when: String
    public let remainingSeconds: Int

    public var isElapsed: Bool { remainingSeconds <= 0 }

    public var remainingLabel: String {
        if remainingSeconds <= 0 { return "Due" }
        let minutes = remainingSeconds / 60
        if minutes < 1 { return "Under a minute" }
        if minutes == 1 { return "1 minute" }
        return "\(minutes) minutes"
    }
}

/// The foreground fallback: the agenda and its timers, with no system permission required.
public enum LabAgenda {
    public static func timers(
        _ attentions: [LabAttention],
        scope: FocusScope?,
        at now: Date,
        deviceZone: TimeZone
    ) -> [AgendaTimer] {
        let rows = scope?.visible(attentions) ?? attentions
        return rows.map { attention in
            let fire = attention.moment.instant(deviceZone: deviceZone)
            let remaining = Int(fire.timeIntervalSince(now).rounded())
            return AgendaTimer(
                id: attention.id,
                channel: attention.channel,
                why: attention.reason.value,
                when: attention.moment.label(deviceZone: deviceZone),
                remainingSeconds: remaining
            )
        }
        .sorted { $0.when < $1.when }
    }
}

/// What the system has said about alarms and reminders. A denial is sticky: `mayPrompt` stays false.
public enum SystemPermission: String, Hashable, Sendable, Codable {
    case notDetermined
    case denied
    case authorized
    case unavailable
}

public struct PromptGate: Hashable, Sendable, Codable {
    public var permission: SystemPermission
    public private(set) var prompts: Int

    public init(permission: SystemPermission, prompts: Int = 0) {
        self.permission = permission
        self.prompts = prompts
    }

    /// True only before the first prompt, and only while the system has not decided.
    public var mayPrompt: Bool { permission == .notDetermined && prompts == 0 }

    /// Asks `request` at most once. A denied or already-asked gate returns itself and does not call it.
    public func resolving(_ request: @Sendable () async -> SystemPermission) async -> PromptGate {
        guard mayPrompt else { return self }
        var next = self
        next.prompts += 1
        next.permission = await request()
        return next
    }
}

/// Where an alarm stands. A channel that is not an alarm is `.notAnAlarm` and is never sent to AlarmKit.
public enum AlarmState: String, Hashable, Sendable {
    case notAnAlarm
    case unavailable
    case needsConsent
    case denied
    case inAppOnly
    case scheduled
}

public enum AlarmRouting {
    public static func state(
        channel: AttentionChannel,
        routeAvailable: Bool,
        permission: SystemPermission,
        systemScheduled: Bool
    ) -> AlarmState {
        guard channel == .alarm else { return .notAnAlarm }
        if systemScheduled { return .scheduled }
        guard routeAvailable else { return .unavailable }
        switch permission {
        case .notDetermined: return .needsConsent
        case .denied: return .denied
        case .unavailable: return .unavailable
        case .authorized: return .inAppOnly
        }
    }
}

/// The system schedule. CoreLocal uses a client that never prompts and never writes.
/// A SystemSurfaces iPhone build supplies AlarmKit and UserNotifications behind the same methods.
public protocol SystemAttentionClient: Sendable {
    func permission() async -> SystemPermission
    func requestPermission() async -> SystemPermission
    /// Schedules one lab-owned alert. Call only after the person has allowed system alerts.
    func schedule(_ offer: AttentionOffer) async
    func cancel(labIDs: [AttentionID]) async
}

/// No system alerts. The in-app agenda still runs. `requestPermission` does not prompt.
public struct UnavailableAttentionSystem: SystemAttentionClient {
    public init() {}

    public func permission() async -> SystemPermission { .unavailable }
    public func requestPermission() async -> SystemPermission { .unavailable }
    public func schedule(_ offer: AttentionOffer) async {}
    public func cancel(labIDs: [AttentionID]) async {}
}

/// Splits a mixed pending list. Only lab-owned identifiers are removed.
public enum CancelLabAlerts {
    public static func selection(from pending: [String]) -> (remove: [String], keep: [String]) {
        var remove: [String] = []
        var keep: [String] = []
        for identifier in pending {
            if LabAlertIdentity.isLabOwned(identifier) {
                remove.append(identifier)
            } else {
                keep.append(identifier)
            }
        }
        return (remove, keep)
    }
}
