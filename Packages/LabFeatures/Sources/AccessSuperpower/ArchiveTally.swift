import LabDomain

/// One demo collection as the task sees it: every sample in it, and which of them are archived.
public struct CollectionTally: Hashable, Sendable, Identifiable {
    public let collection: LabCollection
    /// Every sample in the collection, in the order the host gave them.
    public let samples: [LabItem]

    public init(collection: LabCollection, samples: [LabItem]) {
        self.collection = collection
        self.samples = samples
    }

    public var id: CollectionID { collection.id }
    public var title: String { collection.title.value }
    public var total: Int { samples.count }
    /// The archived samples, in the order the host gave them.
    public var archived: [LabItem] { samples.filter(\.isArchived) }
    public var archivedCount: Int { samples.count(where: \.isArchived) }
}

/// How many samples each demo collection has archived, in the order the chart and table show them.
///
/// Built from what the operation service returned, so the chart, the table, the summary, and the
/// task's judgment all read the same numbers. Only the demo namespace is counted: the task is about
/// the lab's own samples, and a person's data never enters it.
public struct ArchiveTally: Hashable, Sendable {
    public let collections: [CollectionTally]

    /// - Parameter groups: collections with their items, in display order. Anything outside the
    ///   demo namespace is left out.
    public init(_ groups: [(collection: LabCollection, items: [LabItem])]) {
        collections = groups
            .filter { $0.collection.namespace == .demo }
            .map { CollectionTally(collection: $0.collection, samples: $0.items.filter { $0.namespace == .demo }) }
    }

    public var totalSamples: Int { collections.reduce(0) { $0 + $1.total } }
    public var totalArchived: Int { collections.reduce(0) { $0 + $1.archivedCount } }

    /// The highest archived count of any collection; 0 when nothing is archived.
    public var mostArchived: Int { collections.map(\.archivedCount).max() ?? 0 }

    /// The collections with the most archived samples, in display order. Several when they tie, and
    /// none when nothing is archived.
    public var leaders: [CollectionTally] {
        let most = mostArchived
        guard most > 0 else { return [] }
        return collections.filter { $0.archivedCount == most }
    }

    public func isLeader(_ collection: CollectionTally) -> Bool {
        leaders.contains { $0.id == collection.id }
    }

    /// The size of the largest collection, which sets the chart's value range.
    public var largestCollection: Int { collections.map(\.total).max() ?? 0 }

    /// One sample with the collection that holds it, or `nil` when the tally does not have it.
    public func sample(_ id: ItemID) -> (sample: LabItem, collection: CollectionTally)? {
        for collection in collections {
            if let sample = collection.samples.first(where: { $0.id == id }) { return (sample, collection) }
        }
        return nil
    }
}

extension [String] {
    /// "A", "A and B", or "A, B, and C", for sentences that name several collections.
    var spokenList: String {
        switch count {
        case 0: ""
        case 1: self[0]
        case 2: "\(self[0]) and \(self[1])"
        default: "\(dropLast().joined(separator: ", ")), and \(last!)"
        }
    }
}
