import Foundation
import Synchronization

/// Receives each event a `DiagnosticsLog` records, for example to write it to the system log.
public protocol DiagnosticSink: Sendable {
    func receive(_ event: DiagnosticEvent)
}

/// The one logging and diagnostics entry point for lab code.
///
/// Lab code does not call `print`, `NSLog`, `os_log`, or `Logger` directly (a test enforces
/// this outside this folder). It records a `DiagnosticEvent` here instead, and an event can hold
/// only fixed names, validated IDs, categories, durations, and counts. The safe thing is
/// therefore the only thing: there is no parameter that accepts a runtime string.
///
/// The log keeps the most recent events in memory, bounded by `capacity`, so a person can review
/// and export them (`exportPreview(_:)`), and it forwards every event to its sinks, such as
/// `OSLogDiagnosticSink`. Nothing is uploaded; there is no analytics or crash-reporting SDK.
public final class DiagnosticsLog: Sendable {
    public static let defaultCapacity = 500

    private struct State {
        var events: [DiagnosticEvent] = []
        var nextSequence = 1
    }

    public let capacity: Int
    private let state = Mutex(State())
    private let sinks: [any DiagnosticSink]
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - capacity: How many recent events to keep for review and export, at least 1.
    ///   - sinks: Where every event is also sent. Pass `[OSLogDiagnosticSink()]` in a host.
    ///   - now: The wall clock for event times. Inject a fixed one in tests.
    public init(
        capacity: Int = DiagnosticsLog.defaultCapacity,
        sinks: [any DiagnosticSink] = [],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.capacity = max(1, capacity)
        self.sinks = sinks
        self.now = now
    }

    /// Records one event.
    @discardableResult
    public func record(
        _ phase: DiagnosticName,
        outcome: DiagnosticOutcome,
        subject: DiagnosticSubject? = nil,
        category: DiagnosticCategory? = nil,
        duration: Duration? = nil,
        counts: [DiagnosticName: Int] = [:]
    ) -> DiagnosticEvent {
        let recordedAt = now()
        let event = state.withLock { state in
            let event = DiagnosticEvent(
                sequence: state.nextSequence,
                recordedAt: recordedAt,
                subject: subject,
                phase: phase,
                outcome: outcome,
                category: category,
                duration: duration,
                counts: counts
            )
            state.nextSequence += 1
            state.events.append(event)
            if state.events.count > capacity { state.events.removeFirst(state.events.count - capacity) }
            return event
        }
        for sink in sinks { sink.receive(event) }
        return event
    }

    /// Records a failed or rejected step. Only the error's category is kept, never its text.
    @discardableResult
    public func record(
        _ phase: DiagnosticName,
        failure error: any Error,
        subject: DiagnosticSubject? = nil,
        duration: Duration? = nil,
        counts: [DiagnosticName: Int] = [:]
    ) -> DiagnosticEvent {
        let category = DiagnosticCategory(classifying: error)
        return record(phase, outcome: category.outcome, subject: subject, category: category, duration: duration, counts: counts)
    }

    /// Runs `body`, then records its outcome and duration: `succeeded`, or the category of the
    /// error it threw. The error is rethrown unchanged.
    public func measure<Value, Failure: Error>(
        _ phase: DiagnosticName,
        subject: DiagnosticSubject? = nil,
        counts: [DiagnosticName: Int] = [:],
        _ body: () async throws(Failure) -> Value
    ) async throws(Failure) -> Value {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let value = try await body()
            record(phase, outcome: .succeeded, subject: subject, duration: clock.now - start, counts: counts)
            return value
        } catch {
            record(phase, failure: error, subject: subject, duration: clock.now - start, counts: counts)
            throw error
        }
    }

    /// The retained events, oldest first.
    public var events: [DiagnosticEvent] { state.withLock { $0.events } }

    /// Removes every retained event. Sinks keep what they already received; the system log
    /// applies its own retention.
    public func purge() {
        state.withLock { $0.events.removeAll() }
    }

    /// Exactly what an export with `selection` would contain. Show `preview.text` to the person
    /// before they choose a destination, then write `preview.data`.
    public func exportPreview(_ selection: DiagnosticExportSelection = .everything) -> DiagnosticExportPreview {
        DiagnosticExportPreview(events: events, selection: selection)
    }
}

/// Collects events in memory, for tests and for an in-app diagnostics view.
public final class CollectingDiagnosticSink: DiagnosticSink {
    private let received = Mutex<[DiagnosticEvent]>([])

    public init() {}

    public func receive(_ event: DiagnosticEvent) {
        received.withLock { $0.append(event) }
    }

    public var events: [DiagnosticEvent] { received.withLock { $0 } }
}
