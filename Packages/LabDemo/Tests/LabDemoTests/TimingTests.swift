import Foundation
@testable import LabDemo
import LabDomain
import LabSupport
import Testing

/// CORE-009 steps 2 and criterion 4: measured intervals with declared timebases, and every
/// published performance claim links to a measured run.
@Suite struct TimingTests {
    @Test func stepIntervalsComeFromTheInjectedClock() async throws {
        // Each reading advances the manual clock 1 ms: the origin reads 0, then every step reads
        // its start and its end.
        let run = await DemoRunner.manual(step: .milliseconds(1)).run(try Showcase.script())
        #expect(run.result == .passed)
        for (index, step) in run.steps.enumerated() {
            #expect(step.timing?.start == .milliseconds(2 * index + 1))
            #expect(step.timing?.duration == .milliseconds(1))
        }
        #expect(run.totalDuration == .milliseconds(2 * run.steps.count - 1))
    }

    @Test func everyRunDeclaresItsTimebaseAndUnit() async throws {
        let script = try Showcase.script()
        let manual = try jsonObject(try await DemoRunner.manual().run(script).jsonText())
        let manualEnvironment = try #require(manual["environment"] as? [String: Any])
        #expect(manualEnvironment["timebase"] as? String == "manual-test-clock")
        #expect(manualEnvironment["unit"] as? String == "ns")
        #expect(manualEnvironment["measuresRealTime"] as? Bool == false)
        #expect((manualEnvironment["timebaseDeclaration"] as? String)?.contains("not measurements") == true)

        let continuous = try jsonObject(try await DemoRunner(store: .inMemory).run(script).jsonText())
        let continuousEnvironment = try #require(continuous["environment"] as? [String: Any])
        #expect(continuousEnvironment["timebase"] as? String == "swift-continuous-clock")
        #expect(continuousEnvironment["measuresRealTime"] as? Bool == true)
        let steps = try #require(continuous["steps"] as? [[String: Any]])
        #expect(steps.allSatisfy { ($0["durationNanoseconds"] as? Int).map { $0 >= 0 } == true })

        let suspending = await DemoRunner(store: .inMemory, clock: SuspendingIntervalClock()).run(script)
        #expect(suspending.environment.timebase == .suspending)
        #expect(suspending.steps.allSatisfy { $0.timing != nil })
    }

    @Test func aStepThatNeverStartedHasNoIntervalInTheRecord() async throws {
        let script = try smallScript([
            DemoStep(name("find-wrong"), try find("brass", expect: [])),
            DemoStep(name("find-never"), try find("coin", expect: [copperCoin])),
        ])
        let json = try jsonObject(try await DemoRunner.manual().run(script).jsonText())
        let steps = try #require(json["steps"] as? [[String: Any]])
        let never = try #require(steps.last)
        #expect(never["result"] as? String == "not-run")
        #expect(never["durationNanoseconds"] == nil && never["startNanoseconds"] == nil)
        #expect(json["totalNanoseconds"] == nil, "a run with an unrun step has no total")
    }

    @Test func aClaimNeedsARealTimeClock() async throws {
        let run = await DemoRunner.manual().run(try Showcase.script())
        #expect(throws: PerformanceClaimError.notMeasured(.manual)) { try PerformanceClaim(run: run) }
        #expect(throws: PerformanceClaimError.notMeasured(.manual)) { try PerformanceClaim(run: run, step: name("find-glass")) }
    }

    @Test func aClaimNeedsAStepOrRunThatPassed() async throws {
        let script = try smallScript([
            DemoStep(name("find-key"), try find("brass", expect: [brassKey])),
            DemoStep(name("find-wrong"), try find("brass", expect: [])),
            DemoStep(name("find-never"), try find("coin", expect: [copperCoin])),
        ])
        let run = await DemoRunner(store: .inMemory).run(script)
        #expect(run.result == .failed)
        let claim = try PerformanceClaim(run: run, step: name("find-key"))
        #expect(claim.runID == run.id && claim.timebase == .continuous && claim.sampleCount == 1)
        #expect(claim.duration == run.steps[2].timing?.duration)
        #expect(throws: PerformanceClaimError.stepDidNotPass(name("find-wrong"), .failed)) {
            try PerformanceClaim(run: run, step: name("find-wrong"))
        }
        #expect(throws: PerformanceClaimError.stepDidNotPass(name("find-never"), .notRun)) {
            try PerformanceClaim(run: run, step: name("find-never"))
        }
        #expect(throws: PerformanceClaimError.runDidNotPass(.failed)) { try PerformanceClaim(run: run) }
        #expect(throws: PerformanceClaimError.unknownStep(name("missing"))) { try PerformanceClaim(run: run, step: name("missing")) }
    }

    @Test func anExportRefusesAClaimWhoseRunIsNotInIt() async throws {
        let script = try Showcase.script()
        let measured = await DemoRunner(store: .inMemory).run(script)
        let other = await DemoRunner(store: .inMemory).run(script)
        let claim = try PerformanceClaim(run: measured, step: name("find-glass"))
        let exporter = EvidenceExporter(now: { fixedDate })

        #expect(throws: EvidenceExportError.claimWithoutRun(measured.id)) {
            try exporter.preview(EvidenceExportRequest(
                title: "Claim without its run", artifacts: [try .run(other)], claims: [claim], provenance: testProvenance
            ))
        }
        // A run refused in review does not count as exported either.
        let privateScript = try smallScript([DemoStep(name("find-key"), try find("brass", expect: [brassKey]))], tier: .userPrivate)
        let privateRun = await DemoRunner(store: .inMemory).run(privateScript)
        let privateClaim = try PerformanceClaim(run: privateRun)
        #expect(throws: EvidenceExportError.claimWithoutRun(privateRun.id)) {
            try exporter.preview(EvidenceExportRequest(
                title: "Claim on a refused run", artifacts: [try .run(privateRun)], claims: [privateClaim], provenance: testProvenance
            ))
        }

        let preview = try exporter.preview(EvidenceExportRequest(
            title: "Claim with its run", artifacts: [try .run(measured, at: "runs/measured.json")], claims: [claim],
            provenance: testProvenance
        ))
        let manifest = try jsonObject(preview.manifestText)
        let performance = try #require(manifest["performance"] as? [[String: Any]])
        #expect(performance.count == 1)
        #expect(performance[0]["run"] as? String == measured.id.rawValue.uuidString)
        #expect(performance[0]["runArtifact"] as? String == "runs/measured.json")
        #expect(performance[0]["step"] as? String == "find-glass")
        #expect(performance[0]["timebase"] as? String == "swift-continuous-clock")
        #expect(performance[0]["nanoseconds"] as? Int == Int(claim.duration.nanoseconds))
        #expect(preview.files.contains { $0.path == "runs/measured.json" })
        #expect(preview.summaryText.contains("step `find-glass` of run \(measured.id)"))
    }

    @Test func withoutClaimsTheSummaryPublishesNoNumber() async throws {
        let run = await DemoRunner(store: .inMemory).run(try Showcase.script())
        let preview = try EvidenceExporter(now: { fixedDate }).preview(EvidenceExportRequest(
            title: "No claims", artifacts: [try .run(run)], provenance: testProvenance
        ))
        #expect(preview.summaryText.contains("No performance claim."))
        #expect(!preview.summaryText.contains(" ms:"))
        let manifest = try jsonObject(preview.manifestText)
        #expect((manifest["performance"] as? [Any])?.isEmpty == true)
    }
}
