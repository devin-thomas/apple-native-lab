@testable import AccessSuperpower
import Foundation
import LabDomain
import Testing

/// The chart's textual and audible reading, checked exactly against the original fixture
/// `Fixtures/access/archive-chart.json`, which is built only from the lab's demo seed.
@Suite struct ChartFixtureTests {
    let fixture: ChartFixture
    let seed: DemoSeed

    init() throws {
        fixture = try Fixtures.chart()
        seed = try Fixtures.demoSeed()
    }

    var practiced: ArchiveTally {
        ArchiveTally(seededGroups(seed, archiving: Set(fixture.practice.map { ItemID($0.id) })))
    }

    @Test func theFixtureIsVersionedAndNamesTheDemoSeed() {
        #expect(fixture.format == "native-lab-access-chart")
        #expect(fixture.formatVersion == 1)
        #expect(fixture.seed == "demo/seed.json")
    }

    /// The compiled practice set and the fixture's list are the same samples in the same order,
    /// and each is a demo seed sample in the collection the fixture says.
    @Test func thePracticeSetIsTheFixtureListOfDemoSamples() {
        #expect(PracticeSet.standard.sampleIDs == fixture.practice.map { ItemID($0.id) })
        for sample in fixture.practice {
            let item = seed.items.first { $0.id == ItemID(sample.id) }
            #expect(item?.title.value == sample.title, "\(sample.title) is in the demo seed")
            let collection = seed.collections.first { $0.id == item?.collectionID }
            #expect(collection?.title.value == sample.collection, "\(sample.title) is in \(sample.collection)")
        }
    }

    @Test func theChartReadsExactlyAsTheFixtureStates() {
        #expect(ChartSemantics(tally: practiced) == fixture.chart)
    }

    @Test func theValueAxisReadsEachValueAloud() {
        for (value, spoken) in fixture.spoken.valueAxis {
            #expect(ChartSemantics.valueDescription(Double(value)!) == spoken)
        }
    }

    /// What VoiceOver reads for each bar, and the Restore actions it offers, in chart order.
    @Test func eachBarReadsItsCollectionCountAndRestoreActions() {
        let tally = practiced
        let bars = tally.collections.map { collection in
            ChartFixture.Bar(
                label: collection.title,
                value: ChartSemantics.barValue(collection, in: tally),
                actions: collection.archived.map { "Restore \($0.title.value)" }
            )
        }
        #expect(bars == fixture.spoken.bars)
    }

    @Test func theTaskHasOneAnswerAndBothRestoresReadAsTheFixtureStates() throws {
        let tally = practiced
        #expect(AccessibleTask.question == fixture.task.question)
        #expect(tally.leaders.map(\.title) == fixture.task.answer)
        #expect(AccessibleTask.status(of: tally, after: nil) == .toDo)

        for (restore, completes) in [(fixture.task.finish, true), (fixture.task.miss, false)] {
            let outcome = try #require(AccessibleTask.judge(restoring: ItemID(restore.restore), in: tally))
            #expect(outcome.completesTask == completes)
            #expect(outcome.sentence == restore.outcome)
            let after = ArchiveTally(seededGroups(seed, archiving: Set(fixture.practice.map { ItemID($0.id) }).subtracting([ItemID(restore.restore)])))
            #expect(ChartSemantics.summary(of: after) == restore.summaryAfter)
            #expect(AccessibleTask.status(of: after, after: outcome) == (completes ? .done : .toDo))
        }
    }

    /// The declared fallback: the summary names every collection with its count, and the table
    /// lists exactly the samples the chart counts, so nothing depends on the chart or on audio.
    @Test func theSummaryAndTableCarryEveryValueTheChartShows() throws {
        let tally = practiced
        let chart = ChartSemantics(tally: tally)
        let points = try #require(chart.series.first?.points)
        #expect(points.count == tally.collections.count)
        for (point, collection) in zip(points, tally.collections) {
            #expect(point.category == collection.title)
            #expect(Int(point.value) == collection.archived.count, "the table lists what the bar counts")
            #expect(chart.summary.contains("\(collection.title) \(collection.archivedCount) of \(collection.total)"))
        }
        #expect(tally.totalArchived == fixture.practice.count)
    }
}
