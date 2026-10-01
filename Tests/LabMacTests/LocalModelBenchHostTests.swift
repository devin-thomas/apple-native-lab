import Foundation
import LabDomain
import LocalModelBench
import Testing
@testable import NativeLab

/// LAB-015 in the sandboxed Mac host: the fixture executor through `LocalModelBenchSession` and
/// `LibraryBenchBackend`, on a fresh SQLite store, never the app's real one.
@MainActor
@Suite struct LocalModelBenchHostTests {
    @Test func coldAndWarmStaySeparateAndRecordingUsesTheAppUI() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "LocalModelBenchHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let library = LabLibrary(locateStore: { folder.appending(path: LabStoreLocation.fileName) })
        await library.start()
        try #require(library.phase == .ready)
        let demoCount = library.collections.flatMap(\.items).count

        let demoBefore = library.collections.flatMap(\.items).map { "\($0.id) \($0.isArchived) \($0.revision)" }
        #expect(demoBefore.count == demoCount && demoCount > 0)

        let session = LocalModelBenchSession()
        await session.run(.cold)
        await session.run(.warm)
        let cold = try #require(session.reports[.cold])
        let warm = try #require(session.reports[.warm])
        #expect(cold.inference == false && warm.inference == false)
        #expect(try cold.score().medianLatencyNanoseconds == 31_000_000)
        #expect(try warm.score().medianLatencyNanoseconds == 9_000_000)
        #expect(throws: BenchError.mixedThermal) { try BenchScore(reports: [cold, warm]) }

        session.selection = .cold
        await session.record(using: library)
        let recorded = try #require(library.receipts.first { $0.receipt.admitted.operation.kind == .createItem })
        #expect(recorded.receipt.admitted.adapter == .appUI)
        #expect(recorded.receipt.status == .committed)

        await session.reset(using: library)
        let archived = try #require(library.receipts.first { $0.receipt.admitted.operation.kind == .archiveItem })
        #expect(archived.receipt.admitted.adapter == .appUI)
        let service = try await library.openedService()
        let stored = try await service.items(
            ItemFilter(collectionID: LocalModelBench.resultsCollectionID, includeArchived: true, limit: 50),
            as: LabDataService.appUI
        )
        #expect(stored.count == 1 && stored[0].isArchived)
        let demoAfter = library.collections.flatMap(\.items).map { "\($0.id) \($0.isArchived) \($0.revision)" }
        #expect(demoAfter == demoBefore)
    }

    @Test func theSidebarDestinationRoundTrips() {
        #expect(SidebarDestination(storageKey: SidebarDestination.localModelBench.storageKey) == .localModelBench)
        #expect(SidebarDestination.localModelBench.title == "Local Model Bench")
    }
}
