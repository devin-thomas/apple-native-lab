import Foundation
import Testing
@testable import LocalModelBench

/// The fixture executor is the usable path, and it says it is not inference.
@Suite struct FixtureExecutorTests {
    @Test func theFixtureRunCompletesAndIsNotInference() async throws {
        let report = try await BenchFixtures.measured(.warm)
        #expect(report.inference == false)
        #expect(report.executor == "fixture")
        #expect(report.timebase == "fixture-script")
        #expect(report.thermalSensor == "not-observed")
        #expect(report.measurements.count == 4)
        #expect(report.measurements.allSatisfy { $0.inference == false && $0.outcome == .passed && $0.correct })
        #expect(report.corpusID == EvaluationCorpus.id)
        #expect(LocalModelBench.notInferenceLabel == "Deterministic fixture executor benchmarks the pipeline, marked as not inference.")
    }

    @Test func theSameInputsExportTheSameBytes() async throws {
        let first = try await BenchFixtures.measured(.cold)
        let second = try await BenchFixtures.measured(.cold)
        #expect(try first.canonical() == second.canonical())
        let decoded = try JSONDecoder().decode(BenchReport.self, from: first.canonical())
        #expect(decoded == first)
        #expect(decoded.operatingSystem == "fixture-os")
        #expect(decoded.corpusDigest == EvaluationCorpus.digest().hex)
    }

    @Test func anEmptyCorpusAndAnUnknownScriptRunNothing() async throws {
        let spy = LoadSpy()
        let executor = FixtureExecutor { await spy.load($0) }
        await #expect(throws: BenchError.emptyCorpus) {
            try await executor.run(
                corpus: [], phase: .measured, thermal: .cold, availableBytes: BenchFixtures.roomy, machine: BenchFixtures.machine
            )
        }
        await #expect(throws: BenchError.invalidCase) {
            try await executor.run(
                phase: .measured, thermal: .cold, availableBytes: BenchFixtures.roomy,
                scripts: ["missing": CaseScript(text: "x")], machine: BenchFixtures.machine
            )
        }
        #expect(throws: BenchError.invalidCase) {
            try BenchmarkCase(id: "", prompt: "A", expected: "A")
        }
        #expect(await spy.calls == 0)
    }

    @Test func theLiveRouteIsUnavailableAndTheFixtureStillRuns() async throws {
        #expect(throws: BenchError.liveModelUnavailable) { try LiveModelBench.run() }
        let report = try await BenchFixtures.measured(.cold)
        #expect(report.inference == false)
        #expect(try report.score().caseCount == 4)
    }

    @Test func cancellationBeforeTheLoaderAllocatesNothing() async throws {
        let spy = LoadSpy()
        let executor = FixtureExecutor { admission in
            try await Task.sleep(for: .seconds(30))
            return await spy.load(admission)
        }
        let task = Task {
            try await executor.run(
                phase: .measured, thermal: .cold, availableBytes: BenchFixtures.roomy, machine: BenchFixtures.machine
            )
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let result = await task.result
        #expect(throws: BenchError.cancelled) { try result.get() }
        #expect(await spy.calls == 0)
    }
}
