import FindTheThing
import Foundation
import LabDomain
import Testing

#if os(iOS) || os(macOS)
import CoreSpotlight
#endif

/// The shelf index: only opted-in records are stored, delete and reindex report counts, and a
/// search that cannot be answered invents nothing.
@Suite struct IndexAndSearchTests {
    @Test func theShelfIndexesOnlyOptedInRecords() async throws {
        let operation = try await loadedOperation()
        #expect(await operation.index.contains(MessyCollection.packingSlip.id) == false)
        #expect(await operation.index.contains(MessyCollection.lockerNote.id))
        #expect(await operation.index.snapshot().count == 5)

        let again = try await operation.reindex(MessyCollection.corpus, as: Actors.app)
        #expect(again.unchanged == 5)
        #expect(again.indexed == 0)
        #expect(again.skippedNotOptedIn == 1)
    }

    @Test func aRepeatedIdentifierIsCountedAndNotStoredTwice() async throws {
        let operation = FindTheThingOperation()
        var copy = MessyCollection.cedarTray
        copy = SearchDocument(
            id: copy.id, title: "Other tray", body: copy.body, revision: 2, optedIn: true
        )
        let audit = try await operation.reindex([MessyCollection.cedarTray, copy], as: Actors.app)
        #expect(audit.indexed == 1)
        #expect(audit.skippedDuplicate == 1)
        #expect(await operation.index.document(copy.id)?.title == "Cedar tray label")
    }

    @Test func changingARecordCountsAsAnUpdate() async throws {
        let operation = try await loadedOperation()
        let edited = SearchDocument(
            id: MessyCollection.emptyBin.id,
            title: MessyCollection.emptyBin.title,
            body: "Bin 12 now holds twine.",
            revision: 2,
            optedIn: true
        )
        var corpus = MessyCollection.corpus.filter { $0.id != edited.id }
        corpus.append(edited)
        let audit = try await operation.reindex(corpus, as: Actors.app)
        #expect(audit.updated == 1)
        #expect(audit.removed == 0)
        #expect(await operation.index.document(edited.id)?.body == "Bin 12 now holds twine.")
    }

    @Test func deletingThePrivateNoteRemovesItFromTheIndex() async throws {
        let operation = try await loadedOperation()
        let result = try await operation.delete([MessyCollection.lockerNote.id], as: Actors.app)
        #expect(result.removed == 1)
        #expect(result.receipts.isEmpty)
        #expect(await operation.index.contains(MessyCollection.lockerNote.id) == false)

        let answer = try #require(try await searched(operation, "birchbark"))
        #expect(answer.hits.isEmpty)
        #expect(answer.citations.isEmpty)
        #expect(answer.prose == "No records match.")

        let second = try await operation.delete([MessyCollection.lockerNote.id], as: Actors.app)
        #expect(second.removed == 0)
    }

    @Test func reindexKeepsADeletedFixtureOutUntilReset() async throws {
        let operation = try await loadedOperation()
        _ = try await operation.delete([MessyCollection.lockerNote.id], as: Actors.app)
        let rebuilt = try await operation.reindexShelf(as: Actors.app)
        #expect(rebuilt.indexed == 0)
        #expect(await operation.index.contains(MessyCollection.lockerNote.id) == false)
        #expect(rebuilt.skippedNotOptedIn == 1)

        let reset = try await operation.resetFixtures(as: Actors.app)
        #expect(reset.indexed == 1)
        #expect(await operation.index.contains(MessyCollection.lockerNote.id))
        let kept = try await operation.reindex(MessyCollection.corpus, as: Actors.app)
        #expect(kept.unchanged == 5)
    }

    @Test func cedarSearchCitesTheTwoRecordsInAStableOrder() async throws {
        let operation = try await loadedOperation()
        let answer = try #require(try await searched(operation, "  Cedár "))
        #expect(answer.method == .lexical)
        #expect(answer.hits.map(\.documentID) == [MessyCollection.cedarOil.id, MessyCollection.cedarTray.id])
        #expect(answer.citations.map(\.recordID) == answer.hits.map(\.documentID))
        #expect(answer.citations.map(\.deepLink) == answer.hits.map(\.deepLink))
        #expect(answer.prose.contains(MessyCollection.cedarOil.id.rawValue.uuidString))
        #expect(answer.prose.contains(MessyCollection.cedarTray.id.rawValue.uuidString))
        #expect(!answer.prose.contains(MessyCollection.cobaltCard.id.rawValue.uuidString))
        #expect(answer.hits[0].deepLink.url.absoluteString == "nativelab://find/\(MessyCollection.cedarOil.id.rawValue.uuidString)")
    }

    @Test func anUnlistedRecordIsNotAHit() async throws {
        let operation = try await loadedOperation()
        let answer = try #require(try await searched(operation, "flaxshuttle"))
        #expect(answer.hits.isEmpty)
        #expect(answer.citations.isEmpty)
        #expect(answer.prose == "No records match.")
    }

    @Test func anUnsupportedQueryInventsNothing() async throws {
        let operation = try await loadedOperation()
        let refusals = [
            "",
            "   ",
            String(repeating: "a", count: 121),
            "cedar\u{0007}",
            "???",
        ]
        for raw in refusals {
            guard case .unsupported(let refusal) = try await operation.search(raw, as: Actors.app) else {
                Issue.record("\(raw) was answered")
                continue
            }
            #expect(!refusal.reason.isEmpty)
            #expect(refusal.reason.contains("Nothing was invented."))
        }
        #expect(await operation.index.snapshot().count == 5)
    }

    @Test func semanticRetrievalDropsIdentifiersTheIndexDoesNotHold() async throws {
        let fake = SearchRecordID(rawValue: UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!)
        let operation = try await loadedOperation(retriever: ScriptedRetriever(
            isAvailable: true,
            ids: [fake, MessyCollection.cobaltCard.id]
        ))
        let answer = try #require(try await searched(operation, "pigment"))
        #expect(answer.method == .semantic)
        #expect(answer.hits.map(\.documentID) == [MessyCollection.cobaltCard.id])
        #expect(answer.citations.map(\.recordID) == [MessyCollection.cobaltCard.id])
        #expect(!answer.prose.contains(fake.rawValue.uuidString))
        #expect(answer.prose.contains(MessyCollection.cobaltCard.id.rawValue.uuidString))
    }

    @Test func aSemanticRetrieverThatInventsEveryIdentifierReturnsNoRecords() async throws {
        let fake = SearchRecordID(rawValue: UUID())
        let operation = try await loadedOperation(retriever: ScriptedRetriever(isAvailable: true, ids: [fake]))
        let answer = try #require(try await searched(operation, "invented-title"))
        #expect(answer.method == .semantic)
        #expect(answer.hits.isEmpty)
        #expect(answer.citations.isEmpty)
        #expect(answer.prose == "No records match.")
        #expect(!answer.prose.contains(fake.rawValue.uuidString))
    }

    @Test func lexicalSearchRunsBeforeSemanticRetrieval() async throws {
        let index = AppSearchIndex()
        let operation = FindTheThingOperation(
            index: index,
            retriever: ScriptedRetriever(
                isAvailable: true,
                ids: [MessyCollection.cobaltCard.id],
                onRetrieve: {
                    #expect(await index.lexicalSearchCount >= 1)
                }
            )
        )
        _ = try await operation.reindex(MessyCollection.corpus, as: Actors.app)
        let answer = try #require(try await searched(operation, "blue"))
        #expect(answer.method == .semantic)
        #expect(answer.hits.map(\.documentID) == [MessyCollection.cobaltCard.id])
    }

    @Test func withoutARetrieverTheSameHitModelIsLexical() async throws {
        let operation = try await loadedOperation()
        let answer = try #require(try await searched(operation, "blue"))
        #expect(answer.method == .lexical)
        #expect(answer.hits.map(\.documentID) == [MessyCollection.cobaltCard.id])
        #expect(answer.hits[0].snippet.contains("blue pigment"))
    }

    @Test func aCancelledReindexLeavesTheIndexEmpty() async throws {
        let operation = FindTheThingOperation()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await operation.reindex(MessyCollection.corpus, as: Actors.app)
        }
        await #expect(throws: FindTheThingError.cancelled) { try await task.value }
        #expect(await operation.index.isEmpty)
    }

    @Test func donationSendsOptedInRecordsAndRemovedIdentifiers() async throws {
        let donor = RecordingDonor()
        let operation = try await loadedOperation(donor: donor)
        _ = try await operation.delete([MessyCollection.lockerNote.id], as: Actors.app)
        let report = try await operation.donate(as: Actors.app)
        #expect(report.status == .donated)
        #expect(report.removed == 1)
        let present = await donor.present
        let allOptedIn = present.allSatisfy { $0.optedIn }
        let includesPackingSlip = present.contains { $0.id == MessyCollection.packingSlip.id }
        let includesLocker = present.contains { $0.id == MessyCollection.lockerNote.id }
        #expect(allOptedIn)
        #expect(!includesPackingSlip)
        #expect(!includesLocker)
        #expect(await donor.removed == [MessyCollection.lockerNote.id])
    }

    @Test func theIdleDonorDoesNotClaimADonation() async throws {
        let operation = try await loadedOperation()
        let report = try await operation.donate(as: Actors.app)
        #expect(report.status == .notDonated)
        #expect(report.indexed == 0)
    }

    #if os(iOS) || os(macOS)
    @Test func anIndexedEntityIsOnlyBuiltForAnOptedInRecord() throws {
        #expect(FindRecordEntity(MessyCollection.packingSlip) == nil)
        let entity = try #require(FindRecordEntity(MessyCollection.lockerNote))
        #expect(entity.id == MessyCollection.lockerNote.id.rawValue)
        #expect(entity.attributeSet.title == MessyCollection.lockerNote.title)
        #expect(entity.attributeSet.contentDescription == MessyCollection.lockerNote.body)
    }
    #endif

    @Test func sourcesDoNotSearchTheSystemIndexOrOpenANetworkRoute() throws {
        let folder = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/FindTheThing", directoryHint: .isDirectory)
        let forbidden = ["CSSearchQuery", "deleteAllSearchableItems", "PrivateCloudCompute", "URLSession", "import Network"]
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 8)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for symbol in forbidden {
                #expect(!source.contains(symbol), "\(file.lastPathComponent) mentions \(symbol)")
            }
        }
    }
}

private func searched(_ operation: FindTheThingOperation, _ raw: String) async throws -> SearchAnswer? {
    guard case .answer(let answer) = try await operation.search(raw, as: Actors.app) else { return nil }
    return answer
}
