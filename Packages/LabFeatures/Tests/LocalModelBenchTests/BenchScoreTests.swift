import Testing
@testable import LocalModelBench

/// Cold and warm stay apart, and a failed task cannot become a better score.
@Suite struct BenchScoreTests {
    @Test func coldAndWarmResultsCannotBeMerged() async throws {
        let cold = try await BenchFixtures.measured(.cold)
        let warm = try await BenchFixtures.measured(.warm)
        let coldScore = try cold.score()
        let warmScore = try warm.score()
        #expect(coldScore.medianLatencyNanoseconds == 31_000_000)
        #expect(warmScore.medianLatencyNanoseconds == 9_000_000)
        #expect(coldScore.thermal == .cold && warmScore.thermal == .warm)
        #expect(throws: BenchError.mixedThermal) {
            try BenchScore(reports: [cold, warm])
        }
        #expect(coldScore.medianLatencyNanoseconds == 31_000_000, "the cold score is unchanged")
    }

    @Test func aFailedTaskCannotImproveTheScore() async throws {
        let passed = try await BenchFixtures.measured(.cold)
        let passedScore = try passed.score()
        let failed = try await BenchFixtures.measured(.cold, scripts: [
            "slate-token": CaseScript(text: "WRONG", latencyNanoseconds: 1),
        ])
        #expect(failed.measurements.contains { $0.outcome == .failed && $0.latencyNanoseconds == 1 })
        #expect(throws: BenchError.failedTask) { try failed.score() }
        #expect(throws: BenchError.failedTask) { try BenchScore(reports: [passed, failed]) }
        #expect(passedScore.medianLatencyNanoseconds == 31_000_000)
        #expect(passedScore.medianLatencyNanoseconds > 1)
        #expect(failed.summary.contains("No score."))
    }

    @Test func downloadAndWarmupAreNotScores() async throws {
        let executor = FixtureExecutor()
        let download = try await executor.run(
            phase: .download, thermal: .cold, availableBytes: BenchFixtures.roomy, machine: BenchFixtures.machine
        )
        let warmup = try await executor.run(
            phase: .warmup, thermal: .warm, availableBytes: BenchFixtures.roomy, machine: BenchFixtures.machine
        )
        let secondDownload = try await executor.run(
            phase: .download, thermal: .cold, availableBytes: BenchFixtures.roomy, machine: BenchFixtures.machine
        )
        #expect(throws: BenchError.notMeasured) { try download.score() }
        #expect(throws: BenchError.notMeasured) { try warmup.score() }
        #expect(throws: BenchError.notMeasured) { try BenchScore(reports: [download, secondDownload]) }
        #expect(throws: BenchError.mixedThermal) { try BenchScore(reports: [download, warmup]) }
        #expect(download.phase == .download && warmup.phase == .warmup)
        #expect(download.measurements.allSatisfy { $0.phase == .download })
        #expect(warmup.measurements.allSatisfy { $0.phase == .warmup })
    }
}
