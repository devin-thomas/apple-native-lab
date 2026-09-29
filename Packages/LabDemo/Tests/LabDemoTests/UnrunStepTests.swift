import Foundation
@testable import LabDemo
import LabDomain
import LabStore
import LabSupport
import Testing

/// CORE-009 criterion 2: an unrun step cannot acquire a passing badge.
@Suite struct UnrunStepTests {
    @Test func stepsAfterAFailureAreSkippedAndNotRun() async throws {
        let script = try smallScript([
            DemoStep(name("find-wrong"), try find("brass", expect: [copperCoin])),
            DemoStep(name("rename"), .perform(
                request: RequestID(rawValue: uuid(101)),
                operation: .domain(.updateItem(id: brassKey, expected: revision(1), changes: try ItemChanges(title: "Renamed")))
            )),
            DemoStep(name("find-after"), try find("renamed", expect: [brassKey])),
        ])
        let run = await DemoRunner.manual().run(script)
        checkStepInvariants(run)
        #expect(run.result == .failed)
        #expect(run.steps.map(\.result) == [.passed, .passed, .failed, .notRun, .notRun])
        #expect(run.steps.suffix(2).allSatisfy { $0.disposition == .skipped && $0.timing == nil && $0.receipt == nil })
        #expect(run.steps[2].outcome.detail.contains("expected"))
        #expect(run.outcome.summary.hasPrefix("Failed: "))
        // The skipped rename never reached the store.
        #expect(run.finalState?.items.first { $0.id == brassKey }?.title.value == "Brass key")
    }

    /// A destructive step with no declared approval is refused at the commit. The runner never
    /// supplies a grant the script did not declare.
    @Test func aDestructiveStepWithoutItsApprovalFailsAtTheCommit() async throws {
        let script = try smallScript([
            DemoStep(name("archive-key"), .perform(
                request: RequestID(rawValue: uuid(101)), operation: .domain(.archiveItem(id: brassKey, expected: revision(1)))
            )),
            DemoStep(name("find-after"), try find("brass", expect: [])),
        ])
        let run = await DemoRunner.manual().run(script)
        checkStepInvariants(run)
        #expect(run.steps.map(\.result) == [.passed, .passed, .failed, .notRun])
        #expect(run.steps[2].outcome.detail.contains("no live approval"))
        #expect(run.steps[2].receipt == nil)
        #expect(run.finalState?.items.first { $0.id == brassKey }?.isArchived == false)
    }

    @Test func withoutTheResetApprovalNothingIsCommitted() async throws {
        let script = try DemoScript(
            id: name("no-approval"), subject: "CORE-009", title: "No approval", dataTier: .publicFixture,
            provenance: "Test.", seed: try smallSeed(),
            steps: [DemoStep(name("reset"), .perform(request: RequestID(rawValue: uuid(100)), operation: .resetDemo))]
        )
        let run = await DemoRunner.manual().run(script)
        #expect(run.result == .failed)
        #expect(run.finalState?.collections.isEmpty == true && run.finalState?.items.isEmpty == true)
    }

    /// An approval never widens an adapter's ceiling: a share extension cannot be approved to
    /// reset the demo.
    @Test func anApprovalCannotWidenTheAdapter() async throws {
        let run = await DemoRunner.manual(adapter: .shareExtension).run(try Showcase.script())
        checkStepInvariants(run)
        #expect(run.steps[0].result == .failed)
        #expect(run.steps[0].outcome.detail.contains("outside the adapter's ceiling"))
        #expect(run.steps.dropFirst().allSatisfy { $0.result == .notRun })
        #expect(run.finalState?.items.isEmpty == true)
    }

    @Test func cancellingBeforeTheRunMarksEveryStepCancelled() async throws {
        let script = try Showcase.script()
        let run = await Task {
            cancelCurrentTask()
            return await DemoRunner.manual().run(script)
        }.value
        checkStepInvariants(run)
        #expect(run.result == .notRun)
        #expect(run.steps.allSatisfy { $0.disposition == .cancelled && $0.result == .notRun })
        #expect(run.finalState == nil)
    }

    @Test func cancellingMidRunLeavesTheRemainingStepsCancelled() async throws {
        let script = try Showcase.script()
        let seen = Collected<String>()
        let run = await Task {
            await DemoRunner.manual().run(script) { record in
                seen.append(record.id.rawValue)
                if record.id.rawValue == "find-glass" { cancelCurrentTask() }
            }
        }.value
        checkStepInvariants(run)
        let dispositions = run.steps.map(\.disposition)
        #expect(Array(dispositions.prefix(4)) == Array(repeating: .ran, count: 4))
        #expect(dispositions.dropFirst(4).allSatisfy { $0 == .cancelled })
        #expect(run.result == .notRun)
        #expect(run.outcome.summary.hasPrefix("Not run: "))
        #expect(seen.values == script.steps.map(\.id.rawValue), "the observer saw every step once, in order")
        // The rename never started, so the stored sample is unchanged.
        #expect(run.finalState?.items.first { $0.id == Showcase.seaGlass }?.revision == .initial)
    }

    @Test func aStoreThatCannotOpenBlocksEveryStep() async throws {
        let run = await DemoRunner.manual(store: unopenableStore).run(try Showcase.script())
        checkStepInvariants(run)
        #expect(run.result == .blocked)
        #expect(run.steps.allSatisfy { $0.disposition == .blocked && $0.result == .blocked })
        #expect(run.outcome.summary.hasPrefix("Blocked: "))
    }

    /// The runner refuses a store that already holds data, so a script's approvals can act only
    /// on the state it built itself.
    @Test func aStoreHoldingAPersonsDataIsRefused() async throws {
        let run = await DemoRunner.manual(store: try await storeWithUserData()).run(try Showcase.script())
        checkStepInvariants(run)
        #expect(run.result == .blocked)
        #expect(run.steps[0].outcome.detail.contains("not empty"))
    }

    @Test func theEvidenceRecordOfAnUnfinishedRunNeverPasses() async throws {
        let cancelled = await Task {
            cancelCurrentTask()
            return await DemoRunner.manual().run(try! Showcase.script())
        }.value
        let blocked = await DemoRunner.manual(store: unopenableStore).run(try Showcase.script())
        for run in [cancelled, blocked] {
            let record = try run.evidenceRecord(provenance: testProvenance)
            #expect(record.result == run.result)
            #expect(!record.result.isPassed)
            #expect(record.supportedState == nil)
            #expect(record.logRow.contains(run.result.title + " ("))
        }
    }
}
