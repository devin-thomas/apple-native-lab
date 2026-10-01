/// Download, warm-up, and measured runs are different. Only a measured run can be scored.
public enum RunPhase: String, Codable, Hashable, Sendable, CaseIterable {
    case download
    case warmup
    case measured
}

/// When the run was taken. Cold and warm are not combined into one number.
public enum ThermalClass: String, Codable, Hashable, Sendable, CaseIterable {
    case cold
    case warm
}

public enum TaskOutcome: String, Codable, Hashable, Sendable {
    case passed
    case failed
}

/// One case in one phase. Latency is the fixture script's nanoseconds, not a hardware claim.
public struct RunMeasurement: Hashable, Sendable, Codable {
    public let caseID: String
    public let phase: RunPhase
    public let thermal: ThermalClass
    public let outcome: TaskOutcome
    public let correct: Bool
    public let latencyNanoseconds: Int64
    public let inference: Bool

    public init(
        caseID: String,
        phase: RunPhase,
        thermal: ThermalClass,
        outcome: TaskOutcome,
        correct: Bool,
        latencyNanoseconds: Int64,
        inference: Bool
    ) {
        self.caseID = caseID
        self.phase = phase
        self.thermal = thermal
        self.outcome = outcome
        self.correct = correct
        self.latencyNanoseconds = latencyNanoseconds
        self.inference = inference
    }
}

/// One score from measured runs of a single thermal class, every task passed.
///
/// The median is the lower median: after sorting, the element at index `(count - 1) / 2`.
/// A failed task is not dropped to make that number smaller. Cold and warm are not averaged.
public struct BenchScore: Hashable, Sendable, Codable {
    public let thermal: ThermalClass
    public let caseCount: Int
    public let medianLatencyNanoseconds: Int64
    /// Fixture script time, not a clock on the machine.
    public let timebase: String
    public let inference: Bool

    public static let fixtureTimebase = "fixture-script"

    /// Scores `reports` together only when every one is a passing measured run of the same
    /// thermal class. Otherwise it throws, and there is no number to publish.
    public init(reports: [BenchReport]) throws(BenchError) {
        guard let first = reports.first else { throw .emptyScore }
        guard reports.allSatisfy({ $0.thermal == first.thermal }) else { throw .mixedThermal }
        let measurements = reports.flatMap(\.measurements)
        guard reports.allSatisfy({ $0.phase == .measured }),
              measurements.allSatisfy({ $0.phase == .measured }) else { throw .notMeasured }
        guard reports.allSatisfy({ $0.thermal == first.thermal }),
              measurements.allSatisfy({ $0.thermal == first.thermal }) else { throw .mixedThermal }
        guard reports.allSatisfy({ !$0.inference }), measurements.allSatisfy({ !$0.inference }) else {
            throw .notMeasured
        }
        guard !measurements.isEmpty else { throw .emptyScore }
        guard measurements.allSatisfy({ $0.outcome == .passed && $0.correct }) else { throw .failedTask }
        let sorted = measurements.map(\.latencyNanoseconds).sorted()
        thermal = first.thermal
        caseCount = sorted.count
        medianLatencyNanoseconds = sorted[(sorted.count - 1) / 2]
        timebase = Self.fixtureTimebase
        inference = false
    }
}
