#if canImport(Accessibility)
import Accessibility
@testable import AccessSuperpower
import Foundation
import LabDomain
import Testing

/// The Audio Graph descriptor built from the chart semantics: title, summary, axes, one series,
/// and every point, as `AXChartDescriptor` holds them.
@Suite struct ChartDescriptorTests {
    let fixture: ChartFixture
    let seed: DemoSeed

    init() throws {
        fixture = try Fixtures.chart()
        seed = try Fixtures.demoSeed()
    }

    private func tally(archiving ids: [UUID]) -> ArchiveTally {
        ArchiveTally(seededGroups(seed, archiving: Set(ids.map(ItemID.init))))
    }

    @Test func theDescriptorHasTheFixturesSeriesAndAxes() throws {
        let descriptor = ChartSemantics(tally: tally(archiving: fixture.practice.map(\.id))).makeChartDescriptor()
        try expect(descriptor, matches: fixture.chart)
    }

    /// SwiftUI keeps the descriptor it made first and asks for updates, so an update must bring
    /// every field to the new state; otherwise the Audio Graph plays a chart that is gone.
    @Test func anUpdateReplacesEveryFieldOfAnEarlierDescriptor() throws {
        let before = ChartSemantics(tally: tally(archiving: fixture.practice.map(\.id)))
        let after = ChartSemantics(tally: tally(archiving: [fixture.task.finish.restore]))
        let descriptor = before.makeChartDescriptor()
        after.update(descriptor)
        try expect(descriptor, matches: after)
        #expect(descriptor.summary?.hasPrefix("Mineral specimens has the most archived samples: 1 of 4.") == true)
    }

    @Test func aChartWithNothingArchivedStillDescribesEveryCollection() throws {
        let semantics = ChartSemantics(tally: tally(archiving: []))
        #expect(semantics.summary == "No samples are archived. By collection: Pigment swatches 0 of 4, Mineral specimens 0 of 4, Paper stock 0 of 4.")
        try expect(semantics.makeChartDescriptor(), matches: semantics)
    }

    private func expect(_ descriptor: AXChartDescriptor, matches semantics: ChartSemantics) throws {
        #expect(descriptor.title == semantics.title)
        #expect(descriptor.summary == semantics.summary)
        #expect(descriptor.contentDirection == .topToBottom, "bars run top to bottom in display order")

        let xAxis = try #require(descriptor.xAxis as? AXCategoricalDataAxisDescriptor, "the collection axis is categorical")
        #expect(xAxis.title == semantics.categoryAxis.title)
        #expect(xAxis.categoryOrder == semantics.categoryAxis.categories)

        let yAxis = try #require(descriptor.yAxis)
        #expect(yAxis.title == semantics.valueAxis.title)
        #expect(yAxis.range == semantics.valueAxis.lowerBound...semantics.valueAxis.upperBound)
        #expect(yAxis.gridlinePositions == semantics.valueAxis.gridlines)
        #expect(yAxis.valueDescriptionProvider(3) == "3 archived samples")
        #expect(yAxis.valueDescriptionProvider(1) == "1 archived sample")
        #expect(descriptor.additionalAxes.isEmpty)

        #expect(descriptor.series.count == semantics.series.count)
        for (series, expected) in zip(descriptor.series, semantics.series) {
            #expect(series.name == expected.name)
            #expect(!series.isContinuous, "collections are categories, not a line")
            #expect(series.dataPoints.count == expected.points.count)
            for (point, want) in zip(series.dataPoints, expected.points) {
                // `AXDataPointValue` refines `category` and `number` for Swift without an overlay
                // property, so they are read by key, as an assistive client reads them.
                #expect(point.xValue.value(forKey: "category") as? String == want.category)
                #expect(point.yValue?.value(forKey: "number") as? Double == want.value)
                #expect(point.label == want.label)
            }
        }
    }
}
#endif
