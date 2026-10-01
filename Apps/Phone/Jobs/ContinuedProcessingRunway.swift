#if os(iOS)
import BackgroundTasks
import Foundation
import LabJobs
import Synchronization
import UIKit

/// The iPhone and iPad runway (LAB-032): continued processing when the job qualifies, and a
/// foreground job otherwise.
///
/// A job qualifies only when the person allowed background continuation, the app is in the
/// foreground (the request is made on behalf of the foreground app), the app declares the task
/// identifier's wildcard in `BGTaskSchedulerPermittedIdentifiers`, and the system accepts the
/// request right now (`strategy = .fail`: never queued for later). Each attempt registers a new
/// identifier under that wildcard, because an identifier may be registered only once. The system
/// shows the job's progress and may end it early; the lease then reports expiration and the job
/// stops as `expired`, resumable. The render never asks for background GPU, so this lab needs no
/// entitlement; in the background its frames take the CPU path.
struct ContinuedProcessingRunway: JobRunway {
    static let infoKey = "BGTaskSchedulerPermittedIdentifiers"

    /// `<bundle identifier>.render`, the prefix the Info.plist permits with `.*`.
    static var prefix: String? { Bundle.main.bundleIdentifier.map { "\($0).render" } }

    func begin(_ request: RunwayRequest, onExpiration: @escaping @Sendable () -> Void) async -> any JobRunwayLease {
        guard request.wantsBackground else { return FixedLease(mode: .foregroundOnly(.turnedOff)) }
        guard await UIApplication.shared.applicationState == .active else { return FixedLease(mode: .foregroundOnly(.notInForeground)) }
        guard let prefix = Self.prefix,
              let permitted = Bundle.main.object(forInfoDictionaryKey: Self.infoKey) as? [String],
              permitted.contains("\(prefix).*")
        else { return FixedLease(mode: .foregroundOnly(.notPermitted)) }

        let identifier = "\(prefix).\(UUID().uuidString)"
        let lease = ContinuedLease()
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            task.expirationHandler = {
                onExpiration()
            }
            lease.attach(TaskBox(task))
        }
        guard registered else { return FixedLease(mode: .foregroundOnly(.notPermitted)) }

        let submission = BGContinuedProcessingTaskRequest(identifier: identifier, title: request.title, subtitle: request.subtitle)
        submission.strategy = .fail
        do {
            #if LAB_SDK_27
            if #available(iOS 27.0, *) {
                try await BGTaskScheduler.shared.submitTaskRequest(submission)
            } else {
                try BGTaskScheduler.shared.submit(submission)
            }
            #else
            try BGTaskScheduler.shared.submit(submission)
            #endif
        } catch {
            return FixedLease(mode: .foregroundOnly(Self.reason(for: error)))
        }
        return lease
    }

    static func reason(for error: any Error) -> ForegroundOnlyReason {
        guard let error = error as? BGTaskScheduler.Error else { return .unavailable }
        return switch error.code {
        case .notPermitted: .notPermitted
        case .immediateRunIneligible, .tooManyPendingTaskRequests: .systemBusy
        case .unavailable: .unavailable
        @unknown default: .unavailable
        }
    }
}

/// `BGContinuedProcessingTask` is not `Sendable`; the box only hands it to the lease's lock.
private final class TaskBox: @unchecked Sendable {
    let task: BGContinuedProcessingTask

    init(_ task: BGContinuedProcessingTask) { self.task = task }
}

/// A lease whose system task may arrive after the worker began. Progress and the ending are kept
/// until it does, and the task is completed exactly once.
private final class ContinuedLease: JobRunwayLease {
    private struct State {
        var task: TaskBox?
        var completed: Int64 = 0
        var total: Int64 = 1
        var ended: Bool?
    }

    private let state = Mutex(State())

    var mode: RunwayMode { .continuedProcessing }

    func attach(_ box: TaskBox) {
        let pending = state.withLock { state -> (Int64, Int64, Bool?) in
            state.task = box
            return (state.completed, state.total, state.ended)
        }
        box.task.progress.totalUnitCount = pending.1
        box.task.progress.completedUnitCount = pending.0
        if let success = pending.2 { box.task.setTaskCompleted(success: success) }
    }

    func report(completed: Int64, total: Int64) {
        let box = state.withLock { state -> TaskBox? in
            state.completed = completed
            state.total = total
            return state.task
        }
        guard let box else { return }
        box.task.progress.totalUnitCount = total
        box.task.progress.completedUnitCount = completed
    }

    func finish(success: Bool) {
        let box = state.withLock { state -> TaskBox? in
            guard state.ended == nil else { return nil }
            state.ended = success
            return state.task
        }
        box?.task.setTaskCompleted(success: success)
    }
}
#endif
