import Foundation
import LabDomain

/// One finished run: a single phase and a single thermal class, with the environment that
/// produced it. Canonical JSON is stable for the same inputs.
public struct BenchReport: Hashable, Sendable, Codable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let experimentID: String
    public let corpusID: String
    public let corpusDigest: String
    public let phase: RunPhase
    public let thermal: ThermalClass
    public let inference: Bool
    public let executor: String
    public let timebase: String
    public let thermalSensor: String
    public let operatingSystem: String
    public let modelID: String
    public let license: String
    public let declaredMemoryBytes: UInt64
    public let availableBytes: UInt64
    public let allocatedBytes: UInt64
    public let measurements: [RunMeasurement]

    init(
        phase: RunPhase,
        thermal: ThermalClass,
        inference: Bool,
        model: ModelDescriptor,
        availableBytes: UInt64,
        allocatedBytes: UInt64,
        machine: MachineStamp,
        measurements: [RunMeasurement]
    ) {
        schemaVersion = Self.schemaVersion
        experimentID = LocalModelBench.experimentID
        corpusID = EvaluationCorpus.id
        corpusDigest = EvaluationCorpus.digest().hex
        self.phase = phase
        self.thermal = thermal
        self.inference = inference
        executor = "fixture"
        timebase = BenchScore.fixtureTimebase
        thermalSensor = "not-observed"
        operatingSystem = machine.operatingSystem
        modelID = model.id
        license = model.license.label
        declaredMemoryBytes = model.declaredMemoryBytes
        self.availableBytes = availableBytes
        self.allocatedBytes = allocatedBytes
        self.measurements = measurements
    }

    /// Sorted-key JSON. Two runs of the same inputs produce the same bytes.
    public func canonical() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// The score for this report alone. A failed task, a cold/warm mix, or a non-measured phase throws.
    public func score() throws(BenchError) -> BenchScore {
        try BenchScore(reports: [self])
    }
}

extension BenchReport {
    /// A short single-line summary for an item note. It never states a score when a task failed.
    public var summary: String {
        let failed = measurements.filter { $0.outcome != .passed }.count
        let passed = measurements.count - failed
        if failed > 0 {
            return "Fixture executor, not inference. \(phase.rawValue) \(thermal.rawValue): \(passed) passed, \(failed) failed. No score."
        }
        if phase == .measured, let score = try? score() {
            return "Fixture executor, not inference. \(phase.rawValue) \(thermal.rawValue): \(passed) passed, median \(score.medianLatencyNanoseconds) ns, fixture-script, not a hardware claim."
        }
        return "Fixture executor, not inference. \(phase.rawValue) \(thermal.rawValue): \(passed) passed. Not a measured score."
    }
}
