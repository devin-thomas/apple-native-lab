import Foundation
import LabDomain
import LabSupport

/// Whether two runs reproduced the same domain result.
public enum ReplayComparison: Equatable, Sendable {
    /// Every compared field matched. The shared fingerprint names the result.
    case identical(fingerprint: ContentDigest)
    /// What differed: `inputs`, `adapter`, `result`, `step <id>`, `steps` (a different count),
    /// or `final state`.
    case different([String])

    /// Compares everything except `DemoRun.fieldsExcludedFromReplay`.
    public init(_ first: DemoRun, _ second: DemoRun) {
        let a = first.domainResult
        let b = second.domainResult
        guard a != b else {
            self = .identical(fingerprint: first.replayFingerprint)
            return
        }
        var differences: [String] = []
        if a.script != b.script { differences.append("inputs") }
        if a.adapter != b.adapter { differences.append("adapter") }
        if a.result != b.result || a.summary != b.summary { differences.append("result") }
        if a.steps.count != b.steps.count {
            differences.append("steps")
        } else {
            for (left, right) in zip(a.steps, b.steps) where left != right {
                differences.append("step \(left.id)")
            }
        }
        if a.finalState != b.finalState { differences.append("final state") }
        self = .different(differences)
    }

    public var isIdentical: Bool {
        if case .identical = self { true } else { false }
    }
}

extension DemoRun {
    /// The fixed limitation of every replay: it exercises the domain through the service on
    /// deterministic fixtures, on whatever machine ran it.
    public static let fixtureLimitation = "Fixture path: the replay drives OperationService on original fixtures. It proves the domain contract on this build, not a device, a system surface, an entry point other than the runner's adapter, or a UI."

    /// An evidence record for this run (docs/EVIDENCE_TEMPLATE.md).
    ///
    /// The path is always `fixture`, so the record supports at most `implemented`. Its result is
    /// the run's worst step result, and its limitations list the script's untested areas and
    /// every step that did not pass.
    public func evidenceRecord(provenance: BuildProvenance, check: String? = nil) throws -> EvidenceRecord {
        var limitations = [Self.fixtureLimitation] + script.untested
        for step in steps where step.result != .passed {
            limitations.append("Step \(step.id) \(step.result.rawValue): \(step.outcome.detail)")
        }
        let observed = outcome.detail
            + " Replay fingerprint sha256:\(replayFingerprint.hex)."
            + " Adapter \(adapter.rawValue); store \(environment.store); timebase \(environment.timebase.rawValue)."
        return try EvidenceRecord(
            subject: script.subject,
            check: check ?? "Replay of demo script \(script.id)",
            date: startedAt,
            provenance: provenance,
            execution: .fixture,
            inputs: script.inputs.map(\.reference),
            steps: script.steps.map { "\($0.id): \($0.description)" },
            outcome: RunOutcome(result, detail: observed),
            limitations: limitations
        )
    }
}

/// Why a number cannot be published as a performance claim.
public enum PerformanceClaimError: Error, Hashable, Sendable {
    /// The run's clock was not a real-time clock, so its intervals are not measurements.
    case notMeasured(Timebase)
    case unknownStep(DemoStepID)
    /// The step did not pass. A failed or unrun step is never a performance result.
    case stepDidNotPass(DemoStepID, RunResult)
    /// The whole run did not pass, so its total time is not a performance result.
    case runDidNotPass(RunResult)
}

/// One duration that may be published, bound to the run that measured it.
///
/// It can be created only from a `DemoRun`, for a step that passed or a run that passed entirely,
/// on a real-time timebase. An evidence export refuses a claim whose run is not in the export,
/// so every published number links to the measured run it came from.
public struct PerformanceClaim: Hashable, Sendable {
    public let runID: DemoRunID
    public let scriptID: DemoName
    /// The measured step, or `nil` for the whole run.
    public let step: DemoStepID?
    public let duration: Duration
    public let timebase: Timebase
    /// Always 1: a claim is one measured interval, not an aggregate.
    public let sampleCount = 1

    public init(run: DemoRun, step: DemoStepID? = nil) throws(PerformanceClaimError) {
        guard run.environment.timebase.measuresRealTime else { throw .notMeasured(run.environment.timebase) }
        let measured: Duration
        if let step {
            guard let record = run.steps.first(where: { $0.id == step }) else { throw .unknownStep(step) }
            guard record.result == .passed, let timing = record.timing else { throw .stepDidNotPass(step, record.result) }
            measured = timing.duration
        } else {
            guard run.result == .passed, let total = run.totalDuration else { throw .runDidNotPass(run.result) }
            measured = total
        }
        runID = run.id
        scriptID = run.script.id
        self.step = step
        duration = measured
        timebase = run.environment.timebase
    }
}
