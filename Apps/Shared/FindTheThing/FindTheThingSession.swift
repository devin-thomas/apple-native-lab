import FindTheThing
import LabDomain
import Observation

/// The shelf, the latest answer, and the explicit index actions for one presentation of LAB-006.
///
/// Every window and the iPhone page share `FindTheThingHost.index`, which is the app index. Search
/// reads it. Delete, reindex, reset, and donation are separate actions; opening the page only
/// loads the shelf into that index the first time it is empty.
@MainActor
@Observable
final class FindTheThingSession {
    private static let actor = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    let operation: FindTheThingOperation
    var query = ""
    private(set) var outcome: SearchOutcome?
    private(set) var auditLine: String?
    private(set) var donationLine: String?
    private(set) var failure: String?
    private(set) var indexedIDs: Set<SearchRecordID> = []
    private(set) var isWorking = false
    var selectedID: SearchRecordID?

    init(operation: FindTheThingOperation) {
        self.operation = operation
    }

    convenience init() {
        self.init(operation: FindTheThingOperation(
            index: FindTheThingHost.index,
            donor: FindTheThingDonation.live
        ))
    }

    var selectedRecord: SearchDocument? {
        MessyCollection.corpus.first { $0.id == selectedID }
    }

    func prepare() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if let audit = try await operation.loadShelfIfEmpty(as: Self.actor) {
                auditLine = audit.sentence
            }
            failure = nil
        } catch {
            failure = error.message
        }
        await refreshIDs()
    }

    func search() async {
        await run { () async throws(FindTheThingError) in
            let outcome = try await operation.search(query, as: Self.actor)
            self.outcome = outcome
            if case .answer(let answer) = outcome {
                selectedID = answer.hits.first?.documentID ?? selectedID
            }
        }
    }

    func deletePrivateNote() async {
        guard indexedIDs.contains(MessyCollection.lockerNote.id) else { return }
        await run { () async throws(FindTheThingError) in
            let result = try await operation.delete([MessyCollection.lockerNote.id], as: Self.actor)
            auditLine = "Removed \(result.removed) from the app index."
            outcome = nil
        }
    }

    func reindex() async {
        await run { () async throws(FindTheThingError) in
            let audit = try await operation.reindexShelf(as: Self.actor)
            auditLine = audit.sentence
        }
    }

    func resetFixtures() async {
        await run { () async throws(FindTheThingError) in
            let audit = try await operation.resetFixtures(as: Self.actor)
            auditLine = audit.sentence
            outcome = nil
            donationLine = nil
        }
    }

    /// Explicit. Opening the experiment does not donate, and this does not search other apps.
    func donate() async {
        await run { () async throws(FindTheThingError) in
            let report = try await operation.donate(as: Self.actor)
            donationLine = switch report.status {
            case .donated:
                "Donated \(report.indexed) opted-in records. Removed \(report.removed)."
            case .notDonated:
                "This device has no app-index donation. In-app search is unchanged."
            case .failed:
                "The app index could not be updated. In-app search is unchanged."
            }
        }
    }

    private func run(_ body: () async throws(FindTheThingError) -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await body()
            failure = nil
        } catch {
            failure = error.message
        }
        await refreshIDs()
    }

    private func refreshIDs() async {
        indexedIDs = Set(await operation.index.snapshot().map(\.id))
    }
}
