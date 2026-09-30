#if canImport(Accessibility)
import Accessibility

/// The Audio Graph route: the chart as an `AXChartDescriptor` ([S29], [S30]).
///
/// Installed SDK (Xcode 27.0, macOS and iOS 27.0): `AXChartDescriptor`, `AXCategoricalDataAxisDescriptor`,
/// `AXNumericDataAxisDescriptor`, `AXDataSeriesDescriptor`, and `AXDataPoint` are declared
/// macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, so they are always present above the lab's 26.0
/// floor. A build without the Accessibility module compiles this out, and the hosts keep the
/// summary and the table.
extension ChartSemantics {
    public func makeChartDescriptor() -> AXChartDescriptor {
        let descriptor = AXChartDescriptor(
            title: title,
            summary: summary,
            xAxis: makeCategoryAxis(),
            yAxis: makeValueAxis(),
            additionalAxes: [],
            series: makeSeries()
        )
        descriptor.contentDirection = .topToBottom
        return descriptor
    }

    /// Brings an existing descriptor up to date, so VoiceOver never plays a chart the screen no
    /// longer shows.
    public func update(_ descriptor: AXChartDescriptor) {
        descriptor.title = title
        descriptor.summary = summary
        descriptor.xAxis = makeCategoryAxis()
        descriptor.yAxis = makeValueAxis()
        descriptor.additionalAxes = []
        descriptor.series = makeSeries()
        descriptor.contentDirection = .topToBottom
    }

    private func makeCategoryAxis() -> AXCategoricalDataAxisDescriptor {
        AXCategoricalDataAxisDescriptor(title: categoryAxis.title, categoryOrder: categoryAxis.categories)
    }

    private func makeValueAxis() -> AXNumericDataAxisDescriptor {
        AXNumericDataAxisDescriptor(
            title: valueAxis.title,
            range: valueAxis.lowerBound...valueAxis.upperBound,
            gridlinePositions: valueAxis.gridlines,
            valueDescriptionProvider: ChartSemantics.valueDescription
        )
    }

    private func makeSeries() -> [AXDataSeriesDescriptor] {
        series.map { series in
            AXDataSeriesDescriptor(name: series.name, isContinuous: false, dataPoints: series.points.map { point in
                AXDataPoint(x: point.category, y: point.value, label: point.label)
            })
        }
    }
}
#endif
