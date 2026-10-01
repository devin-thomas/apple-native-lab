import Foundation
import LabDomain
import Synchronization

/// A request to stop a running worker, checked at its safe points.
///
/// A person's Cancel or Pause, the system ending background time, and the app leaving the
/// foreground all arrive here instead of killing the worker's task, so the worker stops between
/// two durable steps, removes only its partial file, and records why it stopped. A cancel always
/// wins over an interruption; the first interruption's reason is kept.
public final class JobStopSignal: Sendable {
    public enum Request: Hashable, Sendable {
        /// Stop, discard the work so far, and record the job as cancelled.
        case cancel
        /// Stop, keep durable progress, and record the job as interrupted for this reason.
        case interrupt(JobInterruption)
    }

    private let state = Mutex<Request?>(nil)

    public init() {}

    public var current: Request? { state.withLock { $0 } }

    public func request(_ request: Request) {
        state.withLock { current in
            switch (current, request) {
            case (nil, _), (.interrupt, .cancel): current = request
            case (.cancel, _), (.interrupt, .interrupt): break
            }
        }
    }
}
