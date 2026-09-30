import Foundation
import LabDomain
import SurfaceDeck
import Synchronization
import Testing
@testable import NativeLab

/// LAB-004 in the sandboxed Mac host: the deck's button, the App Intent the Control and widget run,
/// and a receipt's undo all change the demo session through `LabLibrary`, `LabDataService`, and the
/// one `OperationService`, with receipts in the same list. The snapshot for surfaces is written
/// only when it changes, redacted by default. Each test uses a fresh store, snapshot folder, and
/// defaults suite, never the app's own.
@MainActor
@Suite struct SurfaceDeckHostTests {
    let folder: URL
    let defaults: UserDefaults
    let reloads = ReloadCounter()

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "SurfaceDeckHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defaults = try #require(UserDefaults(suiteName: "SurfaceDeckHostTests-\(UUID().uuidString)"))
    }

    private var snapshotFile: SessionSnapshotFile {
        SessionSnapshotFile(url: SessionSnapshotFile.location(inGroupContainer: folder.appending(path: "group")))
    }

    /// A library over a fresh store, and a deck that writes to a temporary snapshot file and counts
    /// the reloads it would ask WidgetKit for.
    private func started(withSurfaces: Bool = true) async throws -> (LabLibrary, SurfaceDeckModel) {
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let counter = reloads
        let publisher = SnapshotPublisher(file: withSurfaces ? snapshotFile : nil, reloadSurfaces: { counter.increment() })
        let model = SurfaceDeckModel(publisher: publisher, defaults: defaults)
        model.connect(library)
        await model.refresh()
        try #require(model.phase == .ready)
        return (library, model)
    }

    private var reloadCount: Int { reloads.count }

    private func storedSnapshot() -> SessionSnapshot? {
        if case .snapshot(let snapshot) = snapshotFile.read() { snapshot } else { nil }
    }

    // MARK: One state, every entry point, one path

    @Test func theDeckAndTheIntentChangeOneStateWithReceiptsInOneList() async throws {
        let (library, model) = try await started()
        #expect(model.state == .neverStarted)

        let started = try #require(await model.setRunning(true))
        #expect(started.didChange)
        #expect(started.receipt?.admitted.adapter == .appUI)
        #expect(model.state == SessionState(isRunning: true, revision: 1))

        // The Control's intent, seeing revision 1, pauses through the same library as an App Intent.
        let intent = SetDemoSessionIntent(value: false, seen: model.state.seen, surface: .control)
        let link = SurfaceDeckLink(backend: try #require(model.backend), openDeck: {})
        let paused = try await intent.run(with: link)
        #expect(paused.didChange)
        #expect(paused.receipt?.admitted.adapter == .appIntent)
        #expect(model.state == SessionState(isRunning: false, revision: 2))
        #expect(model.lastChange?.changedFrom == .control)

        // Both receipts are in the library's one list, newest first, and the deck lists them.
        let listed = library.receipts.prefix(2).map(\.receipt)
        #expect(listed == [try #require(paused.receipt), try #require(started.receipt)])
        #expect(model.receipts.map(\.id) == library.receipts.prefix(2).map(\.id))
        #expect(ReceiptPresentation(try #require(model.receipts.first)).operation == "Pause Session")
        #expect(ReceiptPresentation(try #require(model.receipts.first)).adapter == "App Intent")

        // The stored state is the same whichever entry point reads it.
        let service = try await library.openedService()
        #expect(try await service.session(SurfaceDeck.sessionID, as: LabDataService.appIntent)
            == service.session(SurfaceDeck.sessionID, as: LabDataService.appUI))
    }

    @Test func aReceiptsUndoReversesTheChangeAndTheSnapshotFollows() async throws {
        let (library, model) = try await started()
        _ = await model.setRunning(true)
        let record = try #require(model.receipts.first)
        #expect(ReceiptPresentation(record).undo?.title == "Pause Session “Demo session”")

        let undone = try #require(await library.undo(record))
        #expect(undone.receipt.status == .committed)
        await model.refresh()
        #expect(model.state == SessionState(isRunning: false, revision: 2))
        #expect(storedSnapshot()?.state == model.state)
    }

    @Test func aStaleControlChangesNothingAndItsSurfaceIsAskedToRedraw() async throws {
        let (_, model) = try await started()
        _ = await model.setRunning(true)
        _ = await model.setRunning(false)
        let reloadsBefore = reloadCount

        let stale = SetDemoSessionIntent(value: false, seen: .revision(Revision(rawValue: 1)!), surface: .control)
        let outcome = try await stale.run(with: SurfaceDeckLink(backend: try #require(model.backend), openDeck: {}))
        #expect(outcome.receipt?.conflict != nil)
        #expect(model.state == SessionState(isRunning: false, revision: 2))
        #expect(storedSnapshot()?.state == model.state)
        #expect(reloadCount == reloadsBefore + 1, "the file already held the current state, and the surface still redraws")
        #expect(model.lastMessage == "The demo session changed since this was shown. It is paused. Nothing was changed.")
    }

    // MARK: Snapshot

    @Test func theSnapshotIsRedactedByDefaultAndRewrittenOnlyOnChange() async throws {
        let (_, model) = try await started()
        #expect(!model.showsDetailsOnSurfaces)
        let first = try #require(storedSnapshot())
        #expect(first.isRedacted && first.state == .neverStarted)
        let afterFirst = reloadCount
        #expect(afterFirst == 1)

        // Reading again changes nothing, so nothing is written or reloaded.
        await model.refresh()
        #expect(reloadCount == afterFirst)
        #expect(storedSnapshot() == first)

        _ = await model.setRunning(true)
        #expect(storedSnapshot()?.state == SessionState(isRunning: true, revision: 1))
        #expect(storedSnapshot()?.isRedacted == true)
        #expect(reloadCount == afterFirst + 1)

        // Showing details is the person's choice, and it is a change surfaces must show.
        model.showsDetailsOnSurfaces = true
        #expect(storedSnapshot()?.detail?.changedFrom == .app)
        #expect(reloadCount == afterFirst + 2)
        #expect(defaults.bool(forKey: SurfaceDeckModel.detailsKey))
        model.showsDetailsOnSurfaces = false
        #expect(storedSnapshot()?.isRedacted == true)
    }

    @Test func resetDemoPausesTheSessionAndTheSnapshotFollows() async throws {
        let (library, model) = try await started()
        _ = await model.setRunning(true)
        let reset = try #require(await library.resetDemo())
        #expect(reset.receipt.summary == "Reset the demo to its original 3 collections and 12 items: paused 1 session.")
        await model.refresh()
        #expect(model.state == SessionState(isRunning: false, revision: 2))
        #expect(storedSnapshot()?.state == model.state)
        #expect(model.receipts.first?.id == reset.id, "the deck lists the reset that paused it")
        #expect(model.lastMessage == reset.receipt.summary, "the deck's line follows a change made elsewhere")
    }

    // MARK: CoreLocal

    @Test func theCoreLocalMacHasNoSurfacesAndTheDeckStillWorks() async throws {
        #expect(SnapshotPublisher.live().file == nil, "the CoreLocal Mac declares no App Group")
        let (_, model) = try await started(withSurfaces: false)
        #expect(!model.hasSurfaces)
        #expect(model.publication == .noSurfaces)
        _ = await model.setRunning(true)
        #expect(model.state.isRunning)
        // The previews draw the same snapshot a widget would read.
        let preview = model.previewPresentation(at: .now)
        #expect(preview.availability == .current && preview.isOn && preview.isRedacted)
        #expect(reloadCount == 0)
    }

    @Test func theDeckIsASidebarDestinationWithCommand7() {
        #expect(SidebarDestination(storageKey: SidebarDestination.surfaceDeck.storageKey) == .surfaceDeck)
        #expect(SidebarDestination.surfaceDeck.title == "Surface Deck")
    }
}

/// Counts the WidgetKit reloads a deck asks for.
final class ReloadCounter: Sendable {
    private let value = Mutex(0)

    func increment() { value.withLock { $0 += 1 } }

    var count: Int { value.withLock { $0 } }
}
