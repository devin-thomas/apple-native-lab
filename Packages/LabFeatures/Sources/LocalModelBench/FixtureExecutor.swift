import Foundation

/// An answer substituted for one corpus case. The default answer is the case's own `expected`
/// text, at the scripted latency for its phase and thermal class.
public struct CaseScript: Sendable, Hashable {
    public var text: String
    public var latencyNanoseconds: Int64?

    public init(text: String, latencyNanoseconds: Int64? = nil) {
        self.text = text
        self.latencyNanoseconds = latencyNanoseconds
    }
}

/// Where the export says the numbers came from. Tests pass a fixed system string; the host
/// passes the current operating system.
public struct MachineStamp: Sendable, Hashable {
    public var operatingSystem: String

    public init(operatingSystem: String) {
        self.operatingSystem = operatingSystem
    }

    public static var current: MachineStamp {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return MachineStamp(operatingSystem: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
    }
}

/// The deterministic fixture executor. It checks the license and the memory budget, calls the
/// loader only after both pass, and marks every measurement as not inference.
public struct FixtureExecutor: Sendable {
    public var loader: @Sendable (LoadAdmission) async throws -> LoadedModel

    public init(loader: @escaping @Sendable (LoadAdmission) async throws -> LoadedModel = FixtureExecutor.allocateNothing) {
        self.loader = loader
    }

    /// The default loader. It does not allocate the model's declared budget.
    public static func allocateNothing(_ admission: LoadAdmission) async throws -> LoadedModel {
        _ = admission
        return LoadedModel(allocatedBytes: 0, inference: false)
    }

    /// Scripted latency for one case, in nanoseconds. Cold measured stays slower than warm measured.
    public static func scriptedLatency(phase: RunPhase, thermal: ThermalClass, index: Int) -> Int64 {
        let base: Int64
        switch (phase, thermal) {
        case (.download, _): base = 50_000_000
        case (.warmup, _): base = 20_000_000
        case (.measured, .cold): base = 30_000_000
        case (.measured, .warm): base = 8_000_000
        }
        return base + Int64(index) * 1_000_000
    }

    public func run(
        corpus: [BenchmarkCase] = EvaluationCorpus.cases,
        phase: RunPhase,
        thermal: ThermalClass,
        model: ModelDescriptor = .fixture,
        availableBytes: UInt64,
        scripts: [String: CaseScript] = [:],
        machine: MachineStamp
    ) async throws(BenchError) -> BenchReport {
        if Task.isCancelled { throw .cancelled }
        guard !corpus.isEmpty else { throw .emptyCorpus }
        var seen: Set<String> = []
        for item in corpus {
            guard seen.insert(item.id).inserted else { throw .invalidCase }
        }
        for (id, script) in scripts {
            guard seen.contains(id) else { throw .invalidCase }
            if let latency = script.latencyNanoseconds, latency < 0 { throw .invalidCase }
            guard !script.text.isEmpty else { throw .invalidCase }
        }
        let admission = try ModelGate.admit(model, availableBytes: availableBytes)
        if Task.isCancelled { throw .cancelled }
        let loaded: LoadedModel
        do {
            loaded = try await loader(admission)
        } catch let error as BenchError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .unavailable
        }
        guard !loaded.inference else { throw .notMeasured }
        if Task.isCancelled { throw .cancelled }

        var measurements: [RunMeasurement] = []
        for (index, item) in corpus.enumerated() {
            if Task.isCancelled { throw .cancelled }
            let script = scripts[item.id]
            let text = script?.text ?? item.expected
            let correct = text == item.expected
            let latency = script?.latencyNanoseconds ?? Self.scriptedLatency(phase: phase, thermal: thermal, index: index)
            measurements.append(RunMeasurement(
                caseID: item.id,
                phase: phase,
                thermal: thermal,
                outcome: correct ? .passed : .failed,
                correct: correct,
                latencyNanoseconds: latency,
                inference: false
            ))
        }
        return BenchReport(
            phase: phase,
            thermal: thermal,
            inference: false,
            model: model,
            availableBytes: availableBytes,
            allocatedBytes: loaded.allocatedBytes,
            machine: machine,
            measurements: measurements
        )
    }
}
