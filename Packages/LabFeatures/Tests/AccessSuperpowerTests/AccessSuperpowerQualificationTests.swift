@testable import AccessSuperpower
import Foundation
import LabDomain
import Testing

/// LAB-035-B criteria 1 and 3 and step 3, at the module level: every chart state reads fully in
/// words, the fallback carries the same numbers as the Audio Graph, and the task's operations
/// behave under denial, a late duplicate, and stale state. They add to the LAB-035-A suites.
/// Fixture path: the demo seed, and an in-memory store behind `OperationService` with
/// `GrantAuthorizationPolicy`.
@Suite struct AccessSuperpowerQualificationTests {
    static let quartz = ItemID(UUID(uuidString: "AF451890-CA80-4DE9-B18B-4007066C9177")!)
    static let agate = ItemID(UUID(uuidString: "D279FB0E-642E-463A-B3DA-299442A1C7CB")!)

    // MARK: Criterion 1: nothing depends on color

    /// Every one of the 4,096 ways the 12 demo samples can be archived: each bar's words give its
    /// count, its size, and whether it has the most; the summary gives every count and the
    /// answer; and the judgment of a restore agrees with the words. The chart's color only
    /// repeats what these words already say.
    @Test func everyArchiveStateReadsCompletelyInWords() throws {
        let seed = try Fixtures.demoSeed()
        let items = seed.items
        #expect(items.count == 12)
        var ties = 0
        for mask in 0..<(1 << items.count) {
            let archived = Set(items.indices.filter { mask & (1 << $0) != 0 }.map { items[$0].id })
            let tally = ArchiveTally(seededGroups(seed, archiving: archived))
            let summary = ChartSemantics.summary(of: tally)
            let leaders = tally.leaders
            if leaders.count > 1 { ties += 1 }
            for collection in tally.collections {
                let value = ChartSemantics.barValue(collection, in: tally)
                #expect(value.hasPrefix("\(collection.archivedCount) of \(collection.total) samples archived"), "\(mask)")
                let isLeader = leaders.contains { $0.id == collection.id }
                #expect(value.hasSuffix(", the most") == (isLeader && leaders.count == 1), "\(mask) \(collection.title)")
                #expect(value.hasSuffix(", tied for the most") == (isLeader && leaders.count > 1), "\(mask) \(collection.title)")
                #expect(summary.contains("\(collection.title) \(collection.archivedCount) of \(collection.total)"), "\(mask)")
                for sample in collection.archived {
                    #expect(AccessibleTask.judge(restoring: sample.id, in: tally)?.completesTask == isLeader, "\(mask)")
                }
            }
            switch leaders.count {
            case 0: #expect(summary.hasPrefix("No samples are archived."))
            case 1: #expect(summary.hasPrefix("\(leaders[0].title) has the most archived samples"))
            default: #expect(summary.hasPrefix("\(leaders.map(\.title).spokenList) tie for the most archived samples"))
            }
        }
        #expect(ties > 0, "ties were among the states read")
    }

    /// The task status, the bar standings, and the result sentences never share a word across
    /// meanings, so none of them needs its color to be told apart.
    @Test func statusesAndResultsAreToldApartByTheirWords() throws {
        let words = TaskStatus.allCases.map(\.title)
        #expect(words == ["Nothing Archived", "To Do", "Done"])
        #expect(Set(TaskStatus.allCases.map(\.symbol)).count == 3)
        let fixture = try Fixtures.chart()
        #expect(fixture.task.finish.outcome.hasPrefix("Task done:"))
        #expect(fixture.task.miss.outcome.hasPrefix("Task not done:"))
    }

    // MARK: Criterion 3: the fallback carries what the Audio Graph carries

    /// Without an Audio Graph, the summary and the table are the chart: the descriptor's series,
    /// category order, and value range can be rebuilt from the tally the list shows, for every
    /// way the practice samples can be archived.
    @Test func theTableAndSummaryCarryTheDescriptorsNumbersInEveryPracticeState() throws {
        let seed = try Fixtures.demoSeed()
        let practice = PracticeSet.standard.sampleIDs
        for mask in 0..<(1 << practice.count) {
            let archived = Set(practice.indices.filter { mask & (1 << $0) != 0 }.map { practice[$0] })
            let tally = ArchiveTally(seededGroups(seed, archiving: archived))
            let chart = ChartSemantics(tally: tally)
            let points = try #require(chart.series.first?.points)
            #expect(chart.categoryAxis.categories == tally.collections.map(\.title))
            #expect(points.map(\.value) == tally.collections.map { Double($0.archived.count) }, "\(mask)")
            #expect(chart.valueAxis.upperBound == Double(tally.collections.map(\.samples.count).max() ?? 0))
            #expect(chart.summary == ChartSemantics.summary(of: tally), "the descriptor's summary is the visible one")
            #expect(tally.totalArchived == archived.count)
        }
    }

    // MARK: Step 3: denial, duplicates, stale state

    /// Set Up Practice archives, a destructive change, so each archive needs the person's grant.
    /// Without it the service refuses and nothing changes. The task's restore is not destructive
    /// and needs none; the receipt's undo archives again, so it does.
    @Test func aPracticeArchiveWithoutTheGrantIsRefusedAndTheRestoreNeedsNone() async throws {
        let lab = try await TestLab.seeded()
        let operation = try #require(PracticeSet.standard.setUpOperations(in: try await lab.tally()).first)
        #expect(GrantRequirement.sensitiveCommits.requiresGrant(operation.kind, from: .appUI))
        await #expect(throws: OperationError.self) {
            try await lab.service.perform(OperationRequest(id: RequestID(), operation: operation, actor: TestLab.appUI))
        }
        #expect(try await lab.tally().totalArchived == 0, "nothing was archived")

        let archive = try await lab.perform(operation)
        let restore = try AccessibleTask.restoreOperation(for: Self.quartz, in: try await lab.tally())
        #expect(!GrantRequirement.sensitiveCommits.requiresGrant(restore.kind, from: .appUI))
        let restored = try await lab.service.perform(OperationRequest(id: RequestID(), operation: restore, actor: TestLab.appUI))
        #expect(restored.conflict == nil)
        let undo = try #require(restored.undo)
        #expect(undo.kind == .archiveItem && archive.undo?.kind == .restoreItem)
        #expect(GrantRequirement.sensitiveCommits.requiresGrant(undo.kind, from: .appUI))
    }

    /// A late retry of the task's restore, after its undo, returns the first receipt and restores
    /// nothing again: the undo stands.
    @Test func aLateRetryOfTheRestoreReturnsTheFirstReceiptAndLeavesTheUndoInPlace() async throws {
        let lab = try await TestLab.seeded()
        _ = try await PracticeRun.perform(PracticeSet.standard.setUpOperations(in: try await lab.tally())) { try await lab.perform($0) }
        let request = RequestID()
        let operation = try AccessibleTask.restoreOperation(for: Self.quartz, in: try await lab.tally())
        let first = try await lab.perform(operation, requestID: request)
        let undo = try await lab.perform(try #require(first.undo))
        #expect(undo.conflict == nil)

        let retry = try await lab.perform(operation, requestID: request)
        #expect(retry == first)
        let quartz = try #require(try await lab.tally().sample(Self.quartz)?.sample)
        #expect(quartz.isArchived && quartz.revision == Revision(rawValue: 4)!, "archived by the undo, never restored twice")
    }

    /// Set Up Practice read from a stale tally, after the person archived one of its samples
    /// elsewhere: that archive is a conflict receipt, the rest commit, and nothing is archived twice.
    @Test func aStalePracticeSetUpRecordsAConflictAndArchivesTheRest() async throws {
        let lab = try await TestLab.seeded()
        let stale = PracticeSet.standard.setUpOperations(in: try await lab.tally())
        _ = try await lab.perform(.archiveItem(id: Self.agate, expected: .initial))

        let run = try await PracticeRun.perform(stale) { try await lab.perform($0) }
        #expect(run.receipts.count == 6 && !run.wasCancelled)
        #expect(run.receipts.filter { $0.conflict != nil }.map(\.admitted.operation.target) == [.item(Self.agate)])
        let tally = try await lab.tally()
        #expect(tally.collections.map(\.archivedCount) == [2, 3, 1])
        #expect(tally.sample(Self.agate)?.sample.revision == Revision.initial.next(), "archived once")
        #expect(PracticeSet.standard.setUpOperations(in: tally).isEmpty)
    }

    /// Reset Practice from a stale tally, after the person restored one of the samples: that
    /// restore is a conflict receipt and the others commit.
    @Test func aStaleResetPracticeRecordsAConflictAndRestoresTheRest() async throws {
        let lab = try await TestLab.seeded()
        _ = try await PracticeRun.perform(PracticeSet.standard.setUpOperations(in: try await lab.tally())) { try await lab.perform($0) }
        let stale = PracticeSet.standard.resetOperations(in: try await lab.tally())
        _ = try await lab.perform(try AccessibleTask.restoreOperation(for: Self.quartz, in: try await lab.tally()))

        let run = try await PracticeRun.perform(stale) { try await lab.perform($0) }
        #expect(run.receipts.filter { $0.conflict != nil }.map(\.admitted.operation.target) == [.item(Self.quartz)])
        #expect(try await lab.tally().totalArchived == 0)
    }
}
