import Foundation
import LabDomain
import LabSupport
import LocalModelBench
import Testing
@testable import NativeLab

/// The complete fixture interaction on a fresh hosted SQLite store. No model runs.
@MainActor
@Suite struct LocalModelBenchEvidenceTests {
    @Test func fourPhasesRecordRetryAndResetWithEvidence() async throws {
        let started = Date()
        let folder = FileManager.default.temporaryDirectory.appending(path: "LocalModelBenchEvidence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let library = LabLibrary(locateStore: { folder.appending(path: LabStoreLocation.fileName) })
        await library.start()
        try #require(library.phase == .ready)
        let session = LocalModelBenchSession()
        let baseline = library.collections.flatMap(\.items)
        #expect(session.reports.isEmpty && session.selection == nil)
        let importedID = ItemID()
        let collection = CollectionID()
        _ = try await library.submit(
            .createCollection(draft: CollectionDraft(id: collection, title: EntityTitle("Qualification imports"))),
            requestID: RequestID(), authority: .userAction, names: [:]
        )
        _ = try await library.submit(
            .createItem(draft: ItemDraft(id: importedID, in: collection,
                                        title: EntityTitle("Original sample"), note: ItemNote("Retain this imported sample."))),
            requestID: RequestID(), authority: .userAction, names: [:]
        )
        let service = try await library.openedService()
        let before = try await service.items(ItemFilter(collectionID: collection, includeArchived: true, limit: 50), as: LabDataService.appUI)
        for slot in BenchSlot.allCases {
            await session.run(slot)
            let report = try #require(session.reports[slot])
            #expect(report.phase == slot.phase && report.thermal == slot.thermal)
            #expect(!report.inference && report.allocatedBytes == 0)
            #expect(report.measurements.count == 4 && report.measurements.allSatisfy { $0.correct })
            #expect(report.executor == "fixture" && report.timebase == "fixture-script")
            #expect(report.thermalSensor == "not-observed")
        }
        let cold = try #require(session.reports[.cold])
        let warm = try #require(session.reports[.warm])
        #expect(try cold.score().medianLatencyNanoseconds == 31_000_000)
        #expect(try warm.score().medianLatencyNanoseconds == 9_000_000)
        #expect(throws: BenchError.mixedThermal) { try BenchScore(reports: [cold, warm]) }
        for slot in [BenchSlot.download, .warmup] {
            let report = try #require(session.reports[slot])
            #expect(throws: BenchError.notMeasured) { try report.score() }
        }
        session.selection = .cold
        await session.record(using: library)
        let first = try #require(library.receipts.first { $0.receipt.admitted.operation.kind == .createItem
            && $0.receipt.affectedEntities.contains(where: { if case .item(let id) = $0 { return id != importedID }; return false }) })
        let count = library.receipts.count
        await session.record(using: library)
        #expect(library.receipts.count == count)
        #expect(first.receipt.admitted.adapter == .appUI && first.receipt.status == .committed)
        await session.reset(using: library)
        let stored = try await service.items(ItemFilter(collectionID: LocalModelBench.resultsCollectionID, includeArchived: true, limit: 50), as: LabDataService.appUI)
        #expect(stored.count == 1 && stored[0].isArchived)
        let after = try await service.items(ItemFilter(collectionID: collection, includeArchived: true, limit: 50), as: LabDataService.appUI)
        #expect(after == before)
        #expect(library.collections.flatMap(\.items).filter { $0.namespace == .demo } == baseline)
        let resetCount = library.receipts.count
        await session.reset(using: library)
        #expect(library.receipts.count == resetCount)
        #expect(session.reports.count == 4)

        let record = try EvidenceRecord(
            subject: "LAB-015", check: "Four fixture phases, separate scores, hosted record retry and reset preserve imported data",
            date: started, provenance: .current, execution: .fixture,
            inputs: ["lab-015-fixture-v1@sha256:\(EvaluationCorpus.digest().hex)",
                     "cold-report@sha256:\(ContentDigest.sha256(try cold.canonical()).hex)"],
            steps: ["LocalModelBenchEvidenceTests on a clean SQLite store in the sandboxed Mac host",
                    "Create an original user sample; run Download, Warm-up, Measured cold, Measured warm through LocalModelBenchSession",
                    "Score each phase; reject combined cold/warm; record cold twice through LibraryBenchBackend; reset twice; compare retained data"],
            outcome: .passed(observed: "Four reports each passed four original cases. Cold median 31000000 ns and warm median 9000000 ns are fixture scripts. Mixed thermal throws; download and warm-up have no score. Recording twice returned one item with app-UI authority and no new retry receipt. Reset archived one report, preserved the imported sample and demo items, and added no receipt on repetition. In-memory reports remain available after reset."),
            limitations: ["Fixture executor, not inference. No model, download, hardware latency, memory-pressure or thermal measurement.",
                          "Hosted model/session calls only; no window, pointer, keyboard or assistive technology was driven.",
                          "Mac hosted test only; no physical mobile device or experiment screen in a simulator. All four hosts are checked separately by script/test.sh.",
                          "Memory admission uses a caller-declared budget; the session supplies physicalMemory, not free-memory telemetry."]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        Attachment.record(String(decoding: try encoder.encode(record), as: UTF8.self), named: "LAB-015-host-fixture.json")
        #expect(record.provenance.xcodeBuild != "unknown")
    }
}
