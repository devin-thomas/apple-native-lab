import FindTheThing
import Foundation
import Testing

@Suite struct QualificationTests {
    @Test func resetPreservesEveryNonShelfRecordExactly() async throws {
        let operation = try await loadedOperation()
        let other = SearchDocument(
            id: SearchRecordID(rawValue: UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000006")!),
            title: "Imported practice label", body: "Original text with café and 空.", revision: 7,
            optedIn: true, isPrivate: true
        )
        _ = try await operation.reindex(MessyCollection.corpus + [other], as: Actors.app)
        _ = try await operation.delete([MessyCollection.lockerNote.id], as: Actors.app)
        _ = try await operation.reindexShelf(as: Actors.app)
        #expect(await operation.index.document(other.id) == other)
        _ = try await operation.resetFixtures(as: Actors.app)
        #expect(await operation.index.document(other.id) == other)
        #expect(await operation.index.snapshot().count == 6)
    }

    @Test func aFailedDonationRetainsRemovalIDsForRetry() async throws {
        let donor = RetryDonor()
        let operation = try await loadedOperation(donor: donor)
        _ = try await operation.delete([MessyCollection.lockerNote.id], as: Actors.app)
        let first = try await operation.donate(as: Actors.app)
        #expect(first.status == .failed)
        #expect(await operation.index.pendingRemovalIDs() == [MessyCollection.lockerNote.id])
        let second = try await operation.donate(as: Actors.app)
        #expect(second.status == .donated && second.removed == 1)
        #expect(await operation.index.pendingRemovalIDs().isEmpty)
        #expect(await donor.attempts == 2)
    }
}

private actor RetryDonor: AppIndexDonor {
    private(set) var attempts = 0
    func sync(present: [SearchDocument], removed: [SearchRecordID]) async -> DonationReport {
        attempts += 1
        return DonationReport(indexed: attempts == 1 ? 0 : present.count,
                              removed: attempts == 1 ? 0 : removed.count,
                              status: attempts == 1 ? .failed : .donated)
    }
}
