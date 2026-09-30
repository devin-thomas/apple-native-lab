@testable import AccessSuperpower
import Foundation
import LabDomain
import Testing

/// Ties, an empty demo, and the words each status and alternative uses.
@Suite struct TallyTests {
    let seed: DemoSeed

    init() throws {
        seed = try Fixtures.demoSeed()
    }

    private func tally(archiving titles: [String]) -> ArchiveTally {
        let ids = seed.items.filter { titles.contains($0.title.value) }.map(\.id)
        return ArchiveTally(seededGroups(seed, archiving: Set(ids)))
    }

    @Test func aTieNamesEveryLeaderAndEitherFinishesTheTask() throws {
        let tally = tally(archiving: ["Cobalt swatch", "Ochre swatch", "Quartz point", "Pyrite cube", "Kraft card"])
        #expect(tally.leaders.map(\.title) == ["Pigment swatches", "Mineral specimens"])
        #expect(ChartSemantics.summary(of: tally).hasPrefix("Pigment swatches and Mineral specimens tie for the most archived samples, 2 each."))
        let mineral = try #require(tally.collections.first { $0.title == "Mineral specimens" })
        #expect(ChartSemantics.barValue(mineral, in: tally) == "2 of 4 samples archived, tied for the most")

        let mineralSample = try #require(mineral.archived.first)
        let finish = try #require(AccessibleTask.judge(restoring: mineralSample.id, in: tally))
        #expect(finish.completesTask)
        #expect(finish.sentence == "Task done: Mineral specimens was tied for the most archived samples (2).")
        let paper = try #require(tally.collections.last?.archived.first)
        let miss = try #require(AccessibleTask.judge(restoring: paper.id, in: tally))
        #expect(miss.sentence == "Task not done: Paper stock had 1 archived sample, and Pigment swatches and Mineral specimens had the most (2 each).")
    }

    @Test func nothingArchivedHasNoAnswerAndSaysSo() {
        let tally = tally(archiving: [])
        #expect(tally.leaders.isEmpty)
        #expect(tally.mostArchived == 0)
        #expect(AccessibleTask.status(of: tally, after: nil) == .nothingArchived)
        #expect(ChartSemantics(tally: tally).valueAxis.upperBound == 4)
    }

    @Test func anEmptyDemoStillHasASummaryAndAnAxis() {
        let empty = ArchiveTally([])
        let chart = ChartSemantics(tally: empty)
        #expect(chart.summary == "There are no demo collections.")
        #expect(chart.valueAxis.upperBound == 1, "a range, even with nothing to show")
        #expect(chart.series.first?.points.isEmpty == true)
    }

    @Test func everyStatusHasItsOwnWordAndSymbol() {
        #expect(Set(TaskStatus.allCases.map(\.title)).count == TaskStatus.allCases.count)
        #expect(Set(TaskStatus.allCases.map(\.symbol)).count == TaskStatus.allCases.count)
    }

    /// Each way to finish has its own words on both hosts, and each ends in a restore.
    @Test func everyAlternativeDescribesAPathToTheRestoreOnBothHosts() {
        for alternative in InteractionAlternative.allCases {
            for host in [InteractionAlternative.Host.mac, .phone] {
                let steps = alternative.steps(on: host)
                #expect(steps.localizedStandardContains("restore"), "\(alternative) on \(host)")
            }
        }
        #expect(InteractionAlternative.keyboard.steps(on: .mac).contains("Command-5"))
        #expect(InteractionAlternative.keyboard.steps(on: .mac).contains("Return"))
        #expect(Set(InteractionAlternative.allCases.map(\.symbol)).count == 4)
    }

    @Test func listsOfNamesReadAsASentence() {
        #expect([String]().spokenList == "")
        #expect(["A"].spokenList == "A")
        #expect(["A", "B"].spokenList == "A and B")
        #expect(["A", "B", "C"].spokenList == "A, B, and C")
    }
}
