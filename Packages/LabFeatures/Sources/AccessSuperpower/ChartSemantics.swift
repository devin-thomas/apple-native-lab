/// Everything the archive chart says, as plain values: its title and one-paragraph summary, its two
/// axes, and its one series. The visual bars, the VoiceOver labels, the Audio Graph descriptor, and
/// the table all come from this one value, so they cannot disagree.
///
/// It is `Codable` so an original fixture (`Fixtures/access/`) can state the exact expected reading
/// and a test can compare it field by field.
public struct ChartSemantics: Hashable, Sendable, Codable {
    public struct CategoryAxis: Hashable, Sendable, Codable {
        public let title: String
        /// The categories in display order, top to bottom.
        public let categories: [String]
    }

    public struct ValueAxis: Hashable, Sendable, Codable {
        public let title: String
        public let lowerBound: Double
        public let upperBound: Double
        public let gridlines: [Double]
    }

    public struct Point: Hashable, Sendable, Codable {
        public let category: String
        public let value: Double
        /// The point's own label, for example "3 of 4 archived".
        public let label: String
    }

    public struct Series: Hashable, Sendable, Codable {
        public let name: String
        public let points: [Point]
    }

    public let title: String
    public let summary: String
    public let categoryAxis: CategoryAxis
    public let valueAxis: ValueAxis
    public let series: [Series]

    public static let chartTitle = "Archived samples by collection"
    public static let seriesName = "Archived samples"

    public init(tally: ArchiveTally) {
        title = Self.chartTitle
        summary = Self.summary(of: tally)
        categoryAxis = CategoryAxis(title: "Collection", categories: tally.collections.map(\.title))
        let upper = max(tally.largestCollection, 1)
        valueAxis = ValueAxis(
            title: "Archived samples",
            lowerBound: 0,
            upperBound: Double(upper),
            gridlines: (0...upper).map(Double.init)
        )
        series = [Series(name: Self.seriesName, points: tally.collections.map { collection in
            Point(category: collection.title, value: Double(collection.archivedCount), label: Self.fraction(collection))
        })]
    }

    /// How the value axis reads a value aloud, for example "3 archived samples".
    public static func valueDescription(_ value: Double) -> String {
        let count = Int(value.rounded())
        return count == 1 ? "1 archived sample" : "\(count) archived samples"
    }

    /// What VoiceOver reads as one bar's value: the fraction, and whether it is the most.
    public static func barValue(_ collection: CollectionTally, in tally: ArchiveTally) -> String {
        let base = "\(collection.archivedCount) of \(collection.total) samples archived"
        guard tally.isLeader(collection) else { return base }
        return tally.leaders.count > 1 ? "\(base), tied for the most" : "\(base), the most"
    }

    /// The answer first, then every collection's count in display order. For example:
    /// "Mineral specimens has the most archived samples: 3 of 4. By collection: Pigment swatches
    /// 2 of 4, Mineral specimens 3 of 4, Paper stock 1 of 4."
    public static func summary(of tally: ArchiveTally) -> String {
        guard !tally.collections.isEmpty else { return "There are no demo collections." }
        let answer: String
        let leaders = tally.leaders
        if leaders.isEmpty {
            answer = "No samples are archived."
        } else if leaders.count == 1, let leader = leaders.first {
            answer = "\(leader.title) has the most archived samples: \(fraction(leader, archivedWord: false))."
        } else {
            answer = "\(leaders.map(\.title).spokenList) tie for the most archived samples, \(tally.mostArchived) each."
        }
        let counts = tally.collections.map { "\($0.title) \(fraction($0, archivedWord: false))" }.joined(separator: ", ")
        return "\(answer) By collection: \(counts)."
    }

    static func fraction(_ collection: CollectionTally, archivedWord: Bool = true) -> String {
        "\(collection.archivedCount) of \(collection.total)" + (archivedWord ? " archived" : "")
    }
}
