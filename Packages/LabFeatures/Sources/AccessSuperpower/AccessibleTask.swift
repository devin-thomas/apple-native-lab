import LabDomain

/// The one task this experiment makes completable in four ways: find the demo collection with the
/// most archived samples, then restore one of its samples.
///
/// Every way ends in the same operation, `DomainOperation.restoreItem` at the revision the person
/// saw, committed through the operation service with its receipt. The answer is checked against the
/// tally from just before the restore, so a restore from another collection is still a real change
/// with a receipt, but it does not finish the task.
public enum AccessibleTask {
    public static let question = "Which demo collection has the most archived samples?"
    public static let instruction = "Restore one sample from that collection."

    /// The restore for one archived demo sample, at the revision the tally holds.
    public static func restoreOperation(for id: ItemID, in tally: ArchiveTally) throws(AccessTaskError) -> DomainOperation {
        guard let (sample, _) = tally.sample(id) else { throw .notFound }
        guard sample.isArchived else { throw .notArchived(sample.title.value) }
        return .restoreItem(id: sample.id, expected: sample.revision)
    }

    /// What restoring `id` would mean for the task, judged against `tally`, the state just before
    /// the restore. `nil` when the tally has no such archived sample.
    public static func judge(restoring id: ItemID, in tally: ArchiveTally) -> TaskOutcome? {
        guard let (sample, collection) = tally.sample(id), sample.isArchived else { return nil }
        return TaskOutcome(
            sampleID: sample.id,
            sampleTitle: sample.title.value,
            collectionID: collection.id,
            collectionTitle: collection.title,
            archivedInCollection: collection.archivedCount,
            leaderIDs: tally.leaders.map(\.id),
            leaders: tally.leaders.map(\.title),
            mostArchived: tally.mostArchived
        )
    }

    /// Where the task stands: done after a restore that finished it, otherwise whether there is
    /// anything archived to restore.
    public static func status(of tally: ArchiveTally, after outcome: TaskOutcome?) -> TaskStatus {
        if outcome?.completesTask == true { return .done }
        return tally.totalArchived == 0 ? .nothingArchived : .toDo
    }
}

/// Where the task stands. Each status is a word and a symbol, never a color alone.
public enum TaskStatus: String, Hashable, Sendable, CaseIterable {
    /// No demo sample is archived, so there is nothing to find. Practice data fixes that.
    case nothingArchived
    case toDo
    case done

    public var title: String {
        switch self {
        case .nothingArchived: "Nothing Archived"
        case .toDo: "To Do"
        case .done: "Done"
        }
    }

    public var symbol: String {
        switch self {
        case .nothingArchived: "tray"
        case .toDo: "circle.dashed"
        case .done: "checkmark.circle"
        }
    }
}

/// What one restore meant for the task, judged against the tally just before it.
public struct TaskOutcome: Hashable, Sendable {
    public let sampleID: ItemID
    public let sampleTitle: String
    public let collectionID: CollectionID
    public let collectionTitle: String
    /// How many samples the restored sample's collection had archived, including it.
    public let archivedInCollection: Int
    /// The collections that had the most archived samples, in display order, and their titles.
    public let leaderIDs: [CollectionID]
    public let leaders: [String]
    public let mostArchived: Int

    public var completesTask: Bool { leaderIDs.contains(collectionID) }

    /// One sentence for the result area and the announcement, for example "Task done: Mineral
    /// specimens had the most archived samples (3)."
    public var sentence: String {
        if completesTask {
            let standing = leaders.count > 1 ? "was tied for" : "had"
            return "Task done: \(collectionTitle) \(standing) the most archived samples (\(mostArchived))."
        }
        let own = archivedInCollection == 1 ? "1 archived sample" : "\(archivedInCollection) archived samples"
        let most = leaders.count > 1 ? "had the most (\(mostArchived) each)" : "had the most (\(mostArchived))"
        return "Task not done: \(collectionTitle) had \(own), and \(leaders.spokenList) \(most)."
    }
}

/// Why a restore was not submitted. Nothing is changed in any of these cases.
public enum AccessTaskError: Error, Hashable, Sendable {
    /// The sample is not a demo sample the tally holds: it was removed, or it is not demo data.
    case notFound
    /// The sample is not archived, so there is nothing to restore.
    case notArchived(String)

    public var message: String {
        switch self {
        case .notFound: "That sample is no longer in the demo. Nothing was changed."
        case .notArchived(let title): "“\(title)” is not archived, so there is nothing to restore. Nothing was changed."
        }
    }
}
