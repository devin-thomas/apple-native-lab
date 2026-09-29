import Foundation
import Testing
@testable import NativeLab

/// CORE-005: the host's own data path, run inside the built, sandboxed Mac app. Each test uses a
/// fresh store file in the app container's temporary folder, never the app's real store.
@MainActor
@Suite struct LabLibraryHostTests {
    let folder: URL
    let storeURL: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "LabLibraryHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appending(path: LabStoreLocation.fileName)
    }

    private func library() -> LabLibrary {
        let url = storeURL
        return LabLibrary(locateStore: { url })
    }

    @Test func theBundledSeedIsTwelveOriginalSamples() throws {
        let fixture = try DemoSeedResource.load()
        #expect(fixture.seed.collections.count == 3)
        #expect(fixture.seed.items.count == 12)
        #expect(fixture.provenance.contains("Original synthetic sample data"))
    }

    @Test func firstRunOpensTheStoreAndSeedsTheDemoThroughResetDemo() async throws {
        let library = library()
        await library.start()
        #expect(library.phase == .ready)
        #expect(FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false)))
        #expect(library.collections.map(\.collection.title.value) == ["Pigment swatches", "Mineral specimens", "Paper stock"])
        #expect(library.collections.flatMap(\.items).count == 12)
        #expect(library.census == NamespaceCensus(
            demo: NamespaceCount(collections: 3, items: 12, archived: 0),
            user: NamespaceCount(collections: 0, items: 0, archived: 0)
        ))

        // The seeding left an ordinary receipt: one Reset Demo from the app UI, 15 entities created.
        let seeding = try #require(library.latestReceipt)
        let presentation = ReceiptPresentation(seeding)
        #expect(library.receipts.count == 1)
        #expect(presentation.operation == "Reset Demo")
        #expect(presentation.adapter == "App UI")
        #expect(presentation.isCommitted)
        #expect(presentation.changes.count == 15)
        #expect(presentation.changes.allSatisfy { $0.revision == "Created at revision 1" && $0.name != nil })
        #expect(presentation.summary == "Reset the demo to its original 3 collections and 12 items: added 15.")
        #expect(presentation.undo == nil)
        #expect(presentation.noUndoReason?.hasPrefix("Reset Demo has no undo") == true)
    }

    @Test func aLaterLaunchNeverResetsAnExistingDemo() async throws {
        let first = library()
        await first.start()
        let amber = try #require(first.collections.first?.items.first)
        try #require(await first.setArchived(amber, true) != nil)

        let relaunched = library()
        await relaunched.start()
        #expect(relaunched.phase == .ready)
        #expect(relaunched.receipts.isEmpty, "no automatic Reset Demo on a demo that already exists")
        #expect(relaunched.item(id: amber.id)?.isArchived == true)
        #expect(relaunched.census?.demo.archived == 1)
    }

    @Test func archiveOffersAnUndoThatRunsAsItsOwnRequest() async throws {
        let library = library()
        await library.start()
        let amber = try #require(library.collections.first?.items.first)

        let archive = try #require(await library.setArchived(amber, true))
        let archived = ReceiptPresentation(archive)
        #expect(archived.operation == "Archive Item")
        #expect(archived.changes.map(\.revision) == ["Revision 1 → 2"])
        #expect(archived.undo?.title == "Restore Item “\(amber.title.value)”")
        #expect(archived.undo?.expectedRevision == "Expects revision 2")
        #expect(library.item(id: amber.id)?.isArchived == true)

        let undo = try #require(await library.undo(archive))
        #expect(undo.receipt.requestID != archive.receipt.requestID)
        #expect(ReceiptPresentation(undo).operation == "Restore Item")
        #expect(library.undone[archive.id] == undo.id)
        #expect(library.item(id: amber.id)?.isArchived == false)
        #expect(library.item(id: amber.id)?.revision.rawValue == 3)
        #expect(await library.undo(archive) == nil, "an undo offer is used once")
    }

    @Test func resetDemoRestoresAnEditedSampleAtItsNextRevision() async throws {
        let library = library()
        await library.start()
        let cobalt = try #require(library.collections.first?.items.dropFirst().first)
        let archive = try #require(await library.setArchived(cobalt, true))

        let reset = try #require(await library.resetDemo())
        let presentation = ReceiptPresentation(reset)
        #expect(presentation.summary == "Reset the demo to its original 3 collections and 12 items: restored 1.")
        #expect(presentation.changes.map(\.name) == [cobalt.title.value])
        #expect(presentation.changes.map(\.revision) == ["Revision 2 → 3"])
        #expect(library.item(id: cobalt.id)?.isArchived == false)

        // The archive's undo was pinned to revision 2, so it is now refused and nothing moves.
        let stale = try #require(await library.undo(archive))
        let conflict = ReceiptPresentation(stale)
        #expect(!conflict.isCommitted)
        #expect(conflict.status == "Not applied: expected revision 2, found 3")
        #expect(conflict.changes.isEmpty)
        #expect(conflict.noUndoReason == "Nothing changed, so there is nothing to undo.")
        #expect(library.item(id: cobalt.id)?.revision.rawValue == 3)
        #expect(library.undone[archive.id] == nil)
    }

    @Test func aFileThatIsNotALabStoreIsLeftUnchanged() async throws {
        let garbage = Data("not a database, just some bytes".utf8)
        try garbage.write(to: storeURL)
        let library = library()
        await library.start()
        guard case .unavailable(let reason) = library.phase else {
            Issue.record("expected the store to be refused, got \(library.phase)")
            return
        }
        #expect(reason.contains("left unchanged"))
        #expect(try Data(contentsOf: storeURL) == garbage)
        #expect(library.receipts.isEmpty)
        #expect(await library.resetDemo() == nil)
    }

    @Test func aBuildWithoutItsSeedSaysSoAndWritesNothing() async throws {
        let url = storeURL
        // The test bundle has no seed.json, standing in for a damaged build.
        let library = LabLibrary(locateStore: { url }, seedBundle: Bundle(for: SeedlessBundleMarker.self))
        await library.start()
        #expect(library.phase == .unavailable("This build is missing its demo seed, so the demo cannot be created."))
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func demoSearchUsesTheDomainMatchingRules() async throws {
        let library = library()
        await library.start()
        let matches = DemoSearch.filter(library.collections, text: "  SWATCH ")
        #expect(matches.map(\.collection.title.value) == ["Pigment swatches"])
        #expect(matches.first?.items.count == 4)
        #expect(DemoSearch.filter(library.collections, text: "cafe\u{0301}").isEmpty)
        #expect(DemoSearch.filter(library.collections, text: "").flatMap(\.items).count == 12)
        #expect(DemoSearch.filter(library.collections, text: "bad\u{0007}").isEmpty, "invalid text matches nothing")
    }

    @Test func sidebarStorageKeysRoundTrip() {
        let destinations: [SidebarDestination] = [
            .collection, .catalog(.all), .catalog(.milestone(.m3)), .catalog(.category("Mac")),
            .catalog(.state(.deviceVerified)),
        ]
        for destination in destinations {
            #expect(SidebarDestination(storageKey: destination.storageKey) == destination)
        }
        #expect(SidebarDestination(storageKey: "state:unknown") == nil)
        #expect(SidebarDestination(storageKey: "") == nil)
    }
}

private final class SeedlessBundleMarker {}
