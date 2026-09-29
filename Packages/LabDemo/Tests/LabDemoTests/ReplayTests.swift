import CryptoKit
import Foundation
@testable import LabDemo
import LabDomain
import LabStore
import LabSupport
import Testing

/// CORE-009 criterion 1: replaying a deterministic fixture produces the same domain result.
@Suite struct ReplayTests {
    @Test func theShowcaseLoadsWithTheHashesOfItsExactBytes() throws {
        let script = try Showcase.script()
        #expect(script.id.rawValue == "atlas-basics")
        #expect(script.subject == "CORE-009")
        #expect(script.dataTier == .publicFixture)
        #expect(script.steps.count == 11)
        #expect(script.seed.collections.count == 2 && script.seed.items.count == 5)
        func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        #expect(script.inputs.map(\.name) == ["script:atlas-basics", "seed:atlas-basics"])
        #expect(script.inputs[0].sha256.hex == hex(try Showcase.data("script.json")))
        #expect(script.inputs[1].sha256.hex == hex(try Showcase.data("seed.json")))
    }

    @Test func theShowcaseCreatesFindsUpdatesArchivesAndUndoesInTheDemoNamespace() async throws {
        let run = await DemoRunner.manual(store: .temporarySQLite).run(try Showcase.script())
        checkStepInvariants(run)
        #expect(run.result == .passed, "\(run.outcome.summary)")
        #expect(run.steps.allSatisfy { $0.disposition == .ran })

        let reset = try #require(run.steps.first { $0.id == name("reset") }?.receipt)
        #expect(reset.changes.count == 7)
        #expect(reset.changes.allSatisfy { $0.previousRevision == nil && $0.newRevision == .initial }, "Reset Demo created every sample")

        let byStep = Dictionary(uniqueKeysWithValues: run.steps.map { ($0.id.rawValue, $0) })
        #expect(byStep["list-shoreline"]?.found?.count == 3)
        #expect(byStep["find-glass"]?.found == [Showcase.seaGlass])
        #expect(byStep["find-frosted"]?.found == [Showcase.seaGlass])
        #expect(byStep["find-after-archive"]?.found == [])
        #expect(byStep["find-after-undo"]?.found == [Showcase.seaGlass])

        let archive = try #require(byStep["archive-glass"]?.receipt)
        let undo = try #require(byStep["undo-archive"]?.receipt)
        #expect(archive.undo == .restoreItem(id: Showcase.seaGlass, expected: revision(3)))
        #expect(undo.admitted.operation == archive.undo, "the undo step submitted the operation the archive receipt recorded")
        #expect(byStep["approve-reset"]?.approval?.target == "demo")
        #expect(byStep["approve-archive"]?.approval?.operation == .archiveItem)
        #expect(byStep["approve-archive"]?.approval?.lifetimeSeconds == 60)

        let state = try #require(run.finalState)
        #expect(state.collections.count == 2 && state.items.count == 5)
        #expect(state.collections.allSatisfy { $0.namespace == .demo } && state.items.allSatisfy { $0.namespace == .demo })
        let glass = try #require(state.items.first { $0.id == Showcase.seaGlass })
        #expect(glass.title.value == "Frosted sea glass")
        #expect(glass.revision == revision(4))
        #expect(!glass.isArchived)
    }

    @Test func replayingTheShowcaseReproducesReceiptsAndFinalState() async throws {
        let script = try Showcase.script()
        let first = await DemoRunner(store: .temporarySQLite).run(script)
        let second = await DemoRunner.manual(store: .temporarySQLite, step: .milliseconds(7)).run(script)
        checkStepInvariants(first)
        checkStepInvariants(second)
        #expect(first.result == .passed && second.result == .passed)

        #expect(ReplayComparison(first, second) == .identical(fingerprint: first.replayFingerprint))
        #expect(first.replayFingerprint == second.replayFingerprint)
        // The receipts, operation IDs included, and the final state are equal field for field.
        #expect(first.steps.map(\.receipt) == second.steps.map(\.receipt))
        #expect(first.steps.compactMap(\.receipt).count == 4)
        #expect(first.finalState == second.finalState)
        // The excluded fields really did differ, so the comparison had something to exclude.
        #expect(first.id != second.id)
        #expect(first.environment.timebase != second.environment.timebase)
    }

    @Test func theSQLiteAndInMemoryStoresReplayToTheSameResult() async throws {
        let script = try Showcase.script()
        let sqlite = await DemoRunner.manual(store: .temporarySQLite).run(script)
        let memory = await DemoRunner.manual(store: .inMemory).run(script)
        #expect(sqlite.environment.store.hasPrefix("sqlite"))
        #expect(memory.environment.store == "in-memory")
        #expect(ReplayComparison(sqlite, memory).isIdentical)
    }

    /// The comparison excludes exactly the named fields: strip them from both runs' JSON and the
    /// rest is identical, while each named field actually differs.
    @Test func onlyTheNamedFieldsDifferBetweenReplays() async throws {
        let script = try Showcase.script()
        let first = await DemoRunner.manual(store: .temporarySQLite, step: .milliseconds(1), wallClock: fixedDate).run(script)
        let second = await DemoRunner(store: .inMemory, wallClock: { fixedDate.addingTimeInterval(3_600) }).run(script)
        let a = try jsonObject(try first.jsonText())
        let b = try jsonObject(try second.jsonText())

        #expect(DemoRun.fieldsExcludedFromReplay == [
            "runID", "startedAt", "environment", "totalNanoseconds", "steps[].startNanoseconds", "steps[].durationNanoseconds",
        ])
        for field in ["runID", "startedAt", "environment", "totalNanoseconds"] {
            #expect(!NSDictionary(dictionary: [field: a[field] as Any]).isEqual(to: [field: b[field] as Any]), "\(field) differs")
        }
        let strippedA = removing(DemoRun.fieldsExcludedFromReplay, from: a)
        let strippedB = removing(DemoRun.fieldsExcludedFromReplay, from: b)
        #expect(NSDictionary(dictionary: strippedA).isEqual(to: strippedB))
        #expect(a["replayFingerprint"] as? String == b["replayFingerprint"] as? String)
    }

    /// The comparison is not trivially equal: a changed input shows up in the inputs, the steps it
    /// touches, and the final state.
    @Test func aChangedSeedChangesTheDomainResult() async throws {
        let original = try smallScript([DemoStep(name("find-key"), try find("brass", expect: [brassKey]))])
        let changed = try smallScript(
            [DemoStep(name("find-key"), try find("brass", expect: [brassKey]))],
            seed: try smallSeed(note: "A different note.")
        )
        let first = await DemoRunner.manual().run(original)
        let second = await DemoRunner.manual().run(changed)
        #expect(first.result == .passed && second.result == .passed)
        guard case .different(let differences) = ReplayComparison(first, second) else {
            Issue.record("A changed seed must not replay as identical")
            return
        }
        #expect(differences.contains("inputs"))
        #expect(differences.contains("step reset"))
        #expect(differences.contains("final state"))
        #expect(first.replayFingerprint != second.replayFingerprint)
    }

    @Test func receiptIDsAreDerivedFromTheInputsNotRandom() async throws {
        let script = try Showcase.script()
        let first = await DemoRunner.manual().run(script)
        let second = await DemoRunner.manual().run(script)
        let ids = first.steps.compactMap(\.receipt?.operationID)
        #expect(ids.count == 4 && Set(ids).count == 4)
        #expect(ids == second.steps.compactMap(\.receipt?.operationID))
    }
}
