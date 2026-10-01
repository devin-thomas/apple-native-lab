import Foundation
import LabDomain
import PointInspect
import Testing
@testable import NativeLab

/// LAB-012 in the sandboxed Mac host: a typed record through `LibraryPointInspectBackend` and
/// `LabLibrary`, on a fresh SQLite store per test, never the app's real store.
@MainActor
@Suite struct PointInspectHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "PointInspectHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func startedLibrary() async throws -> LabLibrary {
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        return library
    }

    @Test func theAppBundlesTheSwatchFixture() throws {
        let url = try #require(Bundle.main.url(forResource: "swatch-card", withExtension: "png"))
        let data = try Data(contentsOf: url)
        let image = try SelectedImage(data: data, origin: .fixtureReplay)
        #expect(image.evidence.media == .png)
        #expect(image.evidence.staysLocal)
    }

    @Test func applyingATypedRecordCommitsAsTheAppUI() async throws {
        let library = try await startedLibrary()
        let before = library.receipts.count
        let flow = PointInspectFlow(backend: LibraryPointInspectBackend(library: library))
        let url = try #require(Bundle.main.url(forResource: "swatch-card", withExtension: "png"))
        let image = try SelectedImage(data: Data(contentsOf: url), origin: .fixtureReplay)
        let observation = try await flow.inspect(
            image,
            route: .manual(title: "Swatch card", body: "green and blue"),
            inspector: UnavailableImageInspector(),
            consent: .fixtureReplay
        ).get()
        #expect(observation.suggestion.source == .manual)
        #expect(library.receipts.count == before)

        let receipt = try await flow.commit(observation).get()
        #expect(receipt.admitted.adapter == .appUI)
        #expect(library.receipts.count == before + 2)
        let service = try await library.openedService()
        let proposed = try await service.propose(try observation.operation(), as: PointInspect.proposer)
        #expect(proposed.proposedBy == .modelTool)
        #expect(library.receipts.count == before + 2)
        let filter = try ItemFilter(collectionID: PointInspect.collectionID, includeArchived: false, limit: 20)
        let items = try await service.items(filter, as: LabDataService.appUI)
        #expect(items.count == 1)
        #expect(items[0].namespace == .user)
        #expect(items[0].title.value == "Swatch card")
        #expect(items[0].note.value.contains("green and blue"))
    }
}
