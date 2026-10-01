import Foundation
import LabDomain
import Synchronization

/// How long a running job may keep going, as the platform granted it.
///
/// A job always runs in the app's own process. What differs is what happens when the person
/// leaves it: on iPhone and iPad a job continues in the background only when the system accepted
/// a continued-processing request for it; otherwise it stays a foreground job and stops cleanly at
/// its next safe point. On the Mac the worker runs while the app runs.
public enum RunwayMode: Hashable, Sendable {
    /// iOS accepted a continued-processing request. The system shows the job's progress and may
    /// still end it early; the job then stops as `expired`, resumable.
    case continuedProcessing
    /// The job runs only while the app is in the foreground.
    case foregroundOnly(ForegroundOnlyReason)
    /// The Mac worker: it runs while Native Lab is open, with App Nap held off for it.
    case whileAppRuns

    public var summary: String {
        switch self {
        case .continuedProcessing:
            "Continues in the background: iOS accepted it and shows its progress. iOS can still end it early; it would stop and could resume."
        case .foregroundOnly(let reason):
            "Foreground only: \(reason.clause) If you leave, it stops at its next checkpoint and can resume."
        case .whileAppRuns:
            "Runs while Native Lab is open on this Mac. Quitting stops it, and it can resume on the next launch."
        }
    }
}

/// Why a job did not qualify for continued processing.
public enum ForegroundOnlyReason: String, Hashable, Sendable, CaseIterable {
    /// This platform has no continued processing.
    case notSupported = "not-supported"
    /// The person turned background continuation off for this job.
    case turnedOff = "turned-off"
    /// The app does not declare the task identifier, or the system does not permit it.
    case notPermitted = "not-permitted"
    /// The system could not run it now, for example under heavy load.
    case systemBusy = "system-busy"
    /// The system reported background work unavailable, as the simulator does.
    case unavailable
    /// The job was started or resumed while the app was not in the foreground.
    case notInForeground = "not-in-foreground"

    public var clause: String {
        switch self {
        case .notSupported: "this device has no continued background processing."
        case .turnedOff: "background continuation is turned off."
        case .notPermitted: "the system did not permit background continuation for this app."
        case .systemBusy: "the system could not run it in the background right now."
        case .unavailable: "background processing is unavailable here (the simulator reports this)."
        case .notInForeground: "it did not start from the app in the foreground."
        }
    }
}

/// What a job shows the system while it runs.
public struct RunwayRequest: Hashable, Sendable {
    public let title: String
    public let subtitle: String
    /// Whether the person allowed the job to continue in the background.
    public let wantsBackground: Bool

    public init(title: String, subtitle: String, wantsBackground: Bool) {
        self.title = title
        self.subtitle = subtitle
        self.wantsBackground = wantsBackground
    }
}

/// The time a running job holds. The worker reports progress to it and ends it exactly once.
public protocol JobRunwayLease: Sendable {
    var mode: RunwayMode { get }
    /// Fine progress for a system surface: `completed` of `total` work units.
    func report(completed: Int64, total: Int64)
    /// Ends the lease. `success` is false when the job stopped without its result.
    func finish(success: Bool)
}

/// Grants a job its runway. The host passes the one that fits its platform.
public protocol JobRunway: Sendable {
    /// Begins a lease. `onExpiration` runs, on any thread, if the system ends the time early.
    func begin(_ request: RunwayRequest, onExpiration: @escaping @Sendable () -> Void) async -> any JobRunwayLease
}

/// A runway with no background time: the job is a foreground job.
public struct ForegroundRunway: JobRunway {
    public let reason: ForegroundOnlyReason

    public init(reason: ForegroundOnlyReason = .notSupported) {
        self.reason = reason
    }

    public func begin(_ request: RunwayRequest, onExpiration: @escaping @Sendable () -> Void) async -> any JobRunwayLease {
        FixedLease(mode: .foregroundOnly(request.wantsBackground ? reason : .turnedOff))
    }
}

/// A lease that only reports its mode.
public struct FixedLease: JobRunwayLease {
    public let mode: RunwayMode

    public init(mode: RunwayMode) {
        self.mode = mode
    }

    public func report(completed: Int64, total: Int64) {}

    public func finish(success: Bool) {}
}

#if os(macOS)
/// The Mac worker's runway: it holds a user-initiated activity while the job runs, so App Nap does
/// not slow a job the person is waiting for. It ends when the job ends or the app quits.
public struct MacWorkerRunway: JobRunway {
    public init() {}

    public func begin(_ request: RunwayRequest, onExpiration: @escaping @Sendable () -> Void) async -> any JobRunwayLease {
        MacActivityLease(token: ActivityToken(ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated], reason: request.title
        )))
    }
}

/// `NSObjectProtocol` is not `Sendable`; the token is only ever handed back to `ProcessInfo`.
private final class ActivityToken: @unchecked Sendable {
    let value: any NSObjectProtocol

    init(_ value: any NSObjectProtocol) { self.value = value }
}

private final class MacActivityLease: JobRunwayLease, Sendable {
    private let token: Mutex<ActivityToken?>

    init(token: ActivityToken) { self.token = Mutex(token) }

    var mode: RunwayMode { .whileAppRuns }

    func report(completed: Int64, total: Int64) {}

    /// Ends the activity once; a second call does nothing.
    func finish(success: Bool) {
        guard let token = token.withLock({ value in defer { value = nil }; return value }) else { return }
        ProcessInfo.processInfo.endActivity(token.value)
    }
}
#endif
