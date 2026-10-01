import CryptoKit
import FindTheThing
import Foundation
import LabDomain
import LabSupport
import Testing
@testable import NativeLab

/// Replays the host session on an isolated index. No system donation or personal store is used.
@MainActor
@Suite struct FindTheThingHostEvidenceTests {
    @Test func aCleanSessionSearchesDeletesReindexesAndResets() async throws {
        let started = Date()
        let index = AppSearchIndex()
        let operation = FindTheThingOperation(index: index)
        let session = FindTheThingSession(operation: operation)
        let actor = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
        #expect(await index.isEmpty)
        await session.prepare()
        #expect(session.indexedIDs.count == 5)
        #expect(!session.indexedIDs.contains(MessyCollection.packingSlip.id))
        session.query = "cedar"
        await session.search()
        guard case .answer(let answer) = session.outcome else {
            Issue.record("The cedar query did not produce an answer")
            return
        }
        #expect(answer.method == .lexical)
        #expect(answer.citations.map(\.recordID) == [MessyCollection.cedarOil.id, MessyCollection.cedarTray.id])
        #expect(answer.citations.map(\.recordID) == answer.hits.map(\.documentID))
        for citation in answer.citations {
            #expect(await index.contains(citation.recordID))
            #expect(answer.prose.contains(citation.recordID.description))
        }
        session.query = "???"
        await session.search()
        guard case .unsupported = session.outcome else {
            Issue.record("Unsupported query was answered")
            return
        }
        session.query = "birchbark"
        await session.search()
        #expect(session.selectedID == MessyCollection.lockerNote.id)
        await session.deletePrivateNote()
        #expect(session.outcome == nil)
        #expect(!session.indexedIDs.contains(MessyCollection.lockerNote.id))
        await session.search()
        guard case .answer(let deleted) = session.outcome else {
            Issue.record("Deleted-record query did not produce an empty answer")
            return
        }
        #expect(deleted.hits.isEmpty && deleted.citations.isEmpty)
        await session.deletePrivateNote()
        #expect(session.auditLine == "Removed 1 from the app index.")
        await session.reindex()
        #expect(!session.indexedIDs.contains(MessyCollection.lockerNote.id))

        let other = SearchDocument(
            id: SearchRecordID(rawValue: UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000006")!),
            title: "Imported practice label", body: "An original user-namespace stand-in.", optedIn: true
        )
        _ = try await operation.reindex(await index.snapshot() + [other], as: actor)
        await session.resetFixtures()
        #expect(session.indexedIDs.count == 6)
        #expect(await index.document(other.id) == other)
        #expect(session.indexedIDs.contains(MessyCollection.lockerNote.id))
        #expect(session.outcome == nil && session.donationLine == nil)
        await session.donate()
        #expect(session.donationLine == "This device has no app-index donation. In-app search is unchanged.")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let input = try encoder.encode(MessyCollection.corpus)
        let hash = SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
        let record = try EvidenceRecord(
            subject: "LAB-006",
            check: "Clean Mac host session: lexical citations, unsupported query, private deletion, duplicate delete, reindex, reset preservation, unavailable donor",
            date: started, provenance: .current, execution: .fixture,
            inputs: ["MessyCollection.corpus:sorted-key-json@sha256:\(hash)"],
            steps: [
                "Run FindTheThingHostEvidenceTests in LabMac-Core with an empty isolated AppSearchIndex and IdleAppIndexDonor",
                "Prepare; search cedar and compare prose, hits, citations, and indexed UUIDs; search ???",
                "Search birchbark; Delete Private Note; search again; delete again; Reindex",
                "Add an original non-shelf record; Reset Fixtures; compare that record unchanged; donate using the idle donor"
            ],
            outcome: .passed(observed: "Five opted-in records, cedar citations 1002 and 1001 under the fixture UUID prefix; unsupported query refused. Deletion cleared the answer and removed the private hit and citations; repeated delete did nothing; reindex kept it out. Reset restored it while retaining the exact non-shelf record (six indexed). Idle donor reported unavailable without changing in-app search. OS: \(ProcessInfo.processInfo.operatingSystemVersionString). Adapter: FindTheThingSession → FindTheThingOperation → AppSearchIndex, lexical / idle donor."),
            limitations: [
                "Fixture path in the sandboxed Mac host, driven in process; no pointer, keyboard, VoiceOver, Spotlight UI, or live IndexedEntityDonor took part.",
                "Reset preservation uses an original non-shelf index record, not a real imported document or persistent store. The index is in memory.",
                "No physical iPhone, iPad, semantic model, system search result, or external URL opening was tested. Supports implemented at most."
            ]
        )
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        Attachment.record(String(decoding: try encoder.encode(record), as: UTF8.self), named: "LAB-006-host-replay.json")
        #expect(record.provenance.xcodeBuild != "unknown")
    }
}
