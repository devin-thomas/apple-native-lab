import Foundation
import LabDomain
import LabSupport

/// Identifies one run. It is random, so two replays of one script never share it.
public struct DemoRunID: Hashable, Sendable, CustomStringConvertible, Encodable {
    public let rawValue: UUID

    init() { rawValue = UUID() }

    public var description: String { rawValue.uuidString }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// When a step ran, on the run's declared timebase.
public struct StepTiming: Hashable, Sendable {
    /// From the run's first clock reading to the step's start.
    public let start: Duration
    public let duration: Duration
}

/// How a step ended. Only `ran` can carry a passing result; the other three are never passed.
public enum StepDisposition: String, Hashable, Sendable, Codable {
    /// The step started and finished. Its result is `passed` or `failed`.
    case ran
    /// The step never started because an earlier step did not pass. Its result is `not-run`.
    case skipped
    /// The step never started because the run was cancelled. Its result is `not-run`.
    case cancelled
    /// The step never started because a prerequisite outside the script was missing, such as a
    /// store that could not be opened. Its result is `blocked`.
    case blocked
}

/// The grant an `approve` step obtained, described by its scope. The grant itself stays in the
/// run's in-memory ledger and is never recorded, exported, or reusable.
public struct ApprovalRecord: Hashable, Sendable, Encodable {
    public let approvedStep: DemoStepID
    public let adapter: AdapterKind
    public let operation: OperationKind
    /// `demo`, `collection <UUID>`, `item <UUID>`, or `new item in <collection UUID>`.
    public let target: String
    public let lifetimeSeconds: Int64

    init(approvedStep: DemoStepID, grant: CommitGrant, operation: OperationKind) {
        self.approvedStep = approvedStep
        adapter = grant.adapter
        self.operation = operation
        switch grant.target {
        case .demo: target = "demo"
        case .entity(let reference): target = reference.description
        case .newItem(let collection): target = "new item in \(collection)"
        }
        lifetimeSeconds = (grant.expiresAt - grant.issuedAt).components.seconds
    }
}

/// What one step did.
///
/// There is no public initializer and no decoder: only `DemoRunner` creates step records, and a
/// record whose result is `passed` always has a disposition of `ran` and a measured interval.
public struct DemoStepRecord: Equatable, Sendable {
    public let id: DemoStepID
    public let kind: String
    public let description: String
    public let disposition: StepDisposition
    public let outcome: RunOutcome
    /// `nil` for a step that never started.
    public let timing: StepTiming?
    public let request: RequestID?
    public let receipt: ActionReceipt?
    /// The item IDs a `find` step read, in order.
    public let found: [ItemID]?
    public let approval: ApprovalRecord?

    public var result: RunResult { outcome.result }

    /// A step that started and finished.
    init(
        ran step: DemoStep,
        passed: Bool,
        detail: String,
        timing: StepTiming,
        receipt: ActionReceipt? = nil,
        found: [ItemID]? = nil,
        approval: ApprovalRecord? = nil
    ) {
        id = step.id
        kind = step.action.kind
        description = step.description
        disposition = .ran
        outcome = passed ? .passed(observed: detail) : .failed(observed: detail)
        self.timing = timing
        if case .perform(let request, _) = step.action { self.request = request } else { request = nil }
        self.receipt = receipt
        self.found = found
        self.approval = approval
    }

    /// A step that never started. Its result follows from the disposition and is never passed.
    init(notStarted step: DemoStep, _ disposition: StepDisposition, reason: String) {
        precondition(disposition != .ran, "A step that ran records its own result.")
        id = step.id
        kind = step.action.kind
        description = step.description
        self.disposition = disposition
        outcome = disposition == .blocked ? .blocked(reason: reason) : .notRun(reason: reason)
        timing = nil
        if case .perform(let request, _) = step.action { self.request = request } else { request = nil }
        receipt = nil
        found = nil
        approval = nil
    }
}

/// Where a run happened, apart from the domain: which store and which clock.
public struct DemoEnvironment: Hashable, Sendable {
    /// Such as `sqlite (schema 2, temporary file)` or `in-memory`.
    public let store: String
    public let timebase: Timebase
}

/// Every collection and item in the store after the last step, ordered by ID.
public struct DemoState: Hashable, Sendable, Encodable {
    public let collections: [LabCollection]
    public let items: [LabItem]

    init(collections: [LabCollection], items: [LabItem]) {
        self.collections = collections.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        self.items = items.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
    }
}

/// One replay of a script: every step's record, the final state, and the environment.
///
/// It has no public initializer and no decoder, so a run in memory is always one that
/// `DemoRunner` executed in this process; a file cannot be read back as a passing run.
public struct DemoRun: Equatable, Sendable {
    public static let format = "native-lab-demo-run"
    public static let formatVersion = 1

    /// The fields of the run's JSON that legitimately differ between replays of one script, and
    /// that the replay comparison and `replayFingerprint` therefore leave out:
    ///
    /// - `runID`: random for every run.
    /// - `startedAt`: the wall-clock time the run started.
    /// - `environment`: which store and which clock ran it.
    /// - `totalNanoseconds`, `steps[].startNanoseconds`, `steps[].durationNanoseconds`: intervals
    ///   on the run's monotonic timebase.
    ///
    /// Everything else, including every receipt with its operation ID, every read, every
    /// approval's scope, and the final state, must be identical.
    public static let fieldsExcludedFromReplay = [
        "runID", "startedAt", "environment", "totalNanoseconds", "steps[].startNanoseconds", "steps[].durationNanoseconds",
    ]

    public let id: DemoRunID
    public let script: DemoScript
    public let adapter: AdapterKind
    public let environment: DemoEnvironment
    /// Wall-clock start, to the second.
    public let startedAt: Date
    public let steps: [DemoStepRecord]
    /// `nil` when the run never reached a store, or the store could not be read afterwards.
    public let finalState: DemoState?

    init(
        id: DemoRunID,
        script: DemoScript,
        adapter: AdapterKind,
        environment: DemoEnvironment,
        startedAt: Date,
        steps: [DemoStepRecord],
        finalState: DemoState?
    ) {
        self.id = id
        self.script = script
        self.adapter = adapter
        self.environment = environment
        self.startedAt = Date(timeIntervalSince1970: startedAt.timeIntervalSince1970.rounded(.down))
        self.steps = steps
        self.finalState = finalState
    }

    /// The worst step result: failed, then blocked, then not-run. Passed only when every step ran
    /// and passed.
    public var result: RunResult { RunResult.combining(steps.map(\.result)) }

    /// The run's result and what happened, leading with the result.
    public var outcome: RunOutcome {
        let passed = steps.filter { $0.result == .passed }.count
        var parts = ["\(passed) of \(steps.count) steps passed"]
        if let failed = steps.first(where: { $0.result == .failed }) {
            parts.append("step \(failed.id) failed: \(failed.outcome.detail)")
        }
        let blocked = steps.filter { $0.result == .blocked }
        if let first = blocked.first {
            parts.append("\(blocked.count) blocked: \(first.outcome.detail)")
        }
        let notRun = steps.filter { $0.result == .notRun }
        if let first = notRun.first {
            parts.append("\(notRun.count) not run: \(first.outcome.detail)")
        }
        return RunOutcome(result, detail: parts.joined(separator: "; ") + ".")
    }

    /// From the first step's start to the last step's end, when every step ran.
    public var totalDuration: Duration? {
        guard !steps.isEmpty, steps.allSatisfy({ $0.timing != nil }),
              let first = steps.first?.timing, let last = steps.last?.timing else { return nil }
        return last.start + last.duration - first.start
    }

    /// Everything a replay must reproduce: the run without `fieldsExcludedFromReplay`.
    public var domainResult: DemoDomainResult {
        DemoDomainResult(
            script: ScriptSummary(script),
            adapter: adapter,
            result: result,
            summary: outcome.summary,
            steps: steps.map(StepEncoding.init(domain:)),
            finalState: finalState
        )
    }

    /// The SHA-256 of `domainResult`'s canonical JSON. Two replays of one script on one build
    /// share it exactly when their domain results are identical.
    public var replayFingerprint: ContentDigest {
        // Every field is an ID, an enum, a number, or validated text, so encoding cannot fail.
        (try? Canonical.digest(domainResult)) ?? ContentDigest.sha256(Data())
    }

    /// The run as the JSON file an evidence export writes.
    public func jsonText() throws -> String {
        try Canonical.text(RunEncoding(self))
    }
}

/// A run without the fields that legitimately differ between replays.
public struct DemoDomainResult: Equatable, Sendable, Encodable {
    let script: ScriptSummary
    public let adapter: AdapterKind
    public let result: RunResult
    let summary: String
    let steps: [StepEncoding]
    public let finalState: DemoState?
}

// MARK: - Encoding

struct ScriptSummary: Equatable, Sendable, Encodable {
    let id: DemoName
    let subject: String
    let title: String
    let dataTier: DataTier
    let provenance: String
    let inputs: [DemoInput]
    let untested: [String]

    init(_ script: DemoScript) {
        id = script.id
        subject = script.subject
        title = script.title
        dataTier = script.dataTier
        provenance = script.provenance
        inputs = script.inputs
        untested = script.untested
    }
}

struct StepEncoding: Equatable, Sendable, Encodable {
    let id: DemoStepID
    let kind: String
    let description: String
    let disposition: StepDisposition
    let result: RunResult
    let detail: String
    let request: RequestID?
    let receipt: ActionReceipt?
    let found: [ItemID]?
    let approval: ApprovalRecord?
    let startNanoseconds: Int64?
    let durationNanoseconds: Int64?

    /// The step without its timing, for the replay comparison.
    init(domain record: DemoStepRecord) {
        self.init(record, includeTiming: false)
    }

    init(_ record: DemoStepRecord, includeTiming: Bool) {
        id = record.id
        kind = record.kind
        description = record.description
        disposition = record.disposition
        result = record.result
        detail = record.outcome.detail
        request = record.request
        receipt = record.receipt
        found = record.found
        approval = record.approval
        startNanoseconds = includeTiming ? record.timing?.start.nanoseconds : nil
        durationNanoseconds = includeTiming ? record.timing?.duration.nanoseconds : nil
    }
}

private struct EnvironmentEncoding: Encodable {
    let store: String
    let timebase: Timebase
    let timebaseDeclaration: String
    let measuresRealTime: Bool
    let unit = "ns"

    init(_ environment: DemoEnvironment) {
        store = environment.store
        timebase = environment.timebase
        timebaseDeclaration = environment.timebase.declaration
        measuresRealTime = environment.timebase.measuresRealTime
    }
}

private struct RunEncoding: Encodable {
    let format = DemoRun.format
    let formatVersion = DemoRun.formatVersion
    let runID: DemoRunID
    let startedAt: Date
    let environment: EnvironmentEncoding
    let totalNanoseconds: Int64?
    let script: ScriptSummary
    let adapter: AdapterKind
    let result: RunResult
    let summary: String
    let steps: [StepEncoding]
    let finalState: DemoState?
    let replayFingerprint: String
    let fieldsExcludedFromReplay = DemoRun.fieldsExcludedFromReplay

    init(_ run: DemoRun) {
        runID = run.id
        startedAt = run.startedAt
        environment = EnvironmentEncoding(run.environment)
        totalNanoseconds = run.totalDuration?.nanoseconds
        script = ScriptSummary(run.script)
        adapter = run.adapter
        result = run.result
        summary = run.outcome.summary
        steps = run.steps.map { StepEncoding($0, includeTiming: true) }
        finalState = run.finalState
        replayFingerprint = run.replayFingerprint.hex
    }
}
