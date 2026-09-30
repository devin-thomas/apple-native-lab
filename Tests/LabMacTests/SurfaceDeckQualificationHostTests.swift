import Foundation
import LabDomain
import LabStore
import SurfaceDeck
import Testing
@testable import NativeLab

/// A Surface Deck over a fresh SQLite store in the app's temporary folder, with the host's own
/// `SurfaceDeckModel` and `SnapshotPublisher` writing the snapshot to a temporary App Group folder
/// and counting the WidgetKit reloads it asks for. Never the app's own store, snapshot, or defaults.
@MainActor
struct QualifiedDeck {
    let library: LabLibrary
    let model: SurfaceDeckModel
    let file: SessionSnapshotFile
    let storeURL: URL
    let defaults: UserDefaults
    let reloads: ReloadCounter

    static func start(in folder: URL, withSurfaces: Bool = true) async throws -> QualifiedDeck {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let file = SessionSnapshotFile(url: SessionSnapshotFile.location(inGroupContainer: folder.appending(path: "group")))
        let reloads = ReloadCounter()
        let defaults = try #require(UserDefaults(suiteName: "SurfaceDeckQualification-\(UUID().uuidString)"))
        let model = SurfaceDeckModel(
            publisher: SnapshotPublisher(file: withSurfaces ? file : nil, reloadSurfaces: { reloads.increment() }),
            defaults: defaults
        )
        model.connect(library)
        await model.refresh()
        try #require(model.phase == .ready)
        return QualifiedDeck(library: library, model: model, file: file, storeURL: storeURL, defaults: defaults, reloads: reloads)
    }

    /// The link the widget's toggle, the Control, and Shortcuts reach the host through.
    var link: SurfaceDeckLink {
        get throws { SurfaceDeckLink(backend: try #require(model.backend), openDeck: { model.requestOpen() }) }
    }

    /// What the widget extension reads now.
    var snapshot: SessionSnapshot? {
        if case .snapshot(let stored) = file.read() { stored } else { nil }
    }

    /// The stored session, read through a second connection as a person's copy of the store would.
    func storedSession() async throws -> LabSession? {
        try await SQLiteOperationStore(url: storeURL).session(SurfaceDeck.sessionID)
    }
}

/// WidgetKit shows each timeline entry from its date until the next; this is what a widget holding
/// `timeline` displays at `date` if no newer timeline arrives.
func displayedEntry(_ timeline: SessionTimeline, at date: Date) -> SurfacePresentation? {
    timeline.entries.last { $0.date <= date }?.presentation
}

/// LAB-004-B in the sandboxed Mac host: the criteria and step 3 through `LabLibrary`,
/// `LabDataService`, the host's `SurfaceDeckModel` and `SnapshotPublisher`, and a fresh SQLite
/// store per test. The widget extension is stood in for by reading the snapshot file into a
/// `SessionTimeline`, as `SessionTimelineProvider` does. They add to `SurfaceDeckHostTests`
/// (LAB-004-A).
@MainActor
@Suite struct SurfaceDeckQualificationHostTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "SurfaceDeckQualificationHostTests-\(UUID().uuidString)")

    // MARK: Stale widget toggles

    /// A snapshot left from an earlier run is corrected at launch: the host rewrites it from the
    /// store and asks the surfaces to reload.
    @Test func aStaleSnapshotOnDiskIsCorrectedWhenTheAppStarts() async throws {
        let first = try await QualifiedDeck.start(in: folder)
        _ = await first.model.setRunning(true)
        _ = await first.model.setRunning(false)
        // An older snapshot, as a crash between commit and write would leave it.
        try first.file.write(SessionSnapshot(state: SessionState(isRunning: true, revision: 1), writtenAt: .now, detail: nil))

        let relaunched = try await QualifiedDeck.start(in: folder)
        #expect(relaunched.model.state == SessionState(isRunning: false, revision: 2))
        #expect(relaunched.snapshot?.state == relaunched.model.state)
        #expect(relaunched.reloads.count == 1)
    }

    /// The widget toggle and the Control toggle each reconcile from a stale state, and each
    /// conflict is listed with the deck's receipts as an App Intent.
    @Test(arguments: [SessionSurface.widget, .control])
    func aStaleSurfaceIsListedAsAConflictAndRedrawn(_ surface: SessionSurface) async throws {
        let deck = try await QualifiedDeck.start(in: folder)
        _ = await deck.model.setRunning(true)
        let drawn = try #require(deck.snapshot).state
        _ = await deck.model.setRunning(false)
        let reloadsBefore = deck.reloads.count

        let outcome = try await SetDemoSessionIntent(showing: drawn, surface: surface).run(with: deck.link)
        #expect(outcome.receipt?.conflict != nil)
        let listed = try #require(deck.model.receipts.first)
        #expect(listed.receipt == outcome.receipt)
        #expect(ReceiptPresentation(listed).adapter == "App Intent")
        #expect(deck.reloads.count == reloadsBefore + 1)
        #expect(deck.snapshot?.state == SessionState(isRunning: false, revision: 2))
        #expect(try await deck.storedSession()?.revision == Revision(rawValue: 2))
    }

    // MARK: Denial, cancellation, and duplicates

    /// With the store unavailable, every intent refuses with a reason and nothing is written.
    @Test func withTheStoreUnavailableTheIntentsRefuseAndTheSnapshotIsUntouched() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let blocker = folder.appending(path: "not-a-folder")
        try Data("x".utf8).write(to: blocker)
        let library = LabLibrary(locateStore: { blocker.appending(path: LabStoreLocation.fileName) })
        let file = SessionSnapshotFile(url: SessionSnapshotFile.location(inGroupContainer: folder.appending(path: "group")))
        let model = SurfaceDeckModel(
            publisher: SnapshotPublisher(file: file, reloadSurfaces: {}),
            defaults: try #require(UserDefaults(suiteName: "SurfaceDeckQualification-\(UUID().uuidString)"))
        )
        model.connect(library)
        await model.refresh()
        guard case .unavailable = model.phase else {
            Issue.record("Expected the deck to be unavailable, got \(model.phase)")
            return
        }
        let link = SurfaceDeckLink(backend: try #require(model.backend), openDeck: {})
        let error = await #expect(throws: SurfaceDeckError.self) {
            try await SetDemoSessionIntent(value: true, seen: .neverStarted, surface: .control).run(with: link)
        }
        guard case .unavailable(let reason)? = error else {
            Issue.record("Expected unavailable, got \(String(describing: error))")
            return
        }
        #expect(!reason.isEmpty)
        #expect(file.read() == .missing, "no snapshot is written for a state that could not be read")
        #expect(!model.canAct)
    }

    /// A request cancelled before its commit leaves no receipt in the list or the store, and the
    /// same request later commits once.
    @Test func aCancelledIntentLeavesNoReceiptAndCanBeRetried() async throws {
        let deck = try await QualifiedDeck.start(in: folder)
        let backend = try #require(deck.model.backend)
        let request = RequestID()
        let listed = deck.library.receipts.count
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SessionActions(backend: backend, entryPoint: .appIntent)
                .setRunning(true, seen: .neverStarted, surface: .widget, requestID: request)
        }
        await #expect(throws: SurfaceDeckError.cancelled) { try await task.value }
        #expect(deck.library.receipts.count == listed)
        #expect(try await SQLiteOperationStore(url: deck.storeURL).receipt(for: request) == nil)

        let retried = try await SessionActions(backend: backend, entryPoint: .appIntent)
            .setRunning(true, seen: .neverStarted, surface: .widget, requestID: request)
        #expect(retried.didChange)
        #expect(deck.library.receipts.count(where: { $0.receipt.requestID == request }) == 1)
    }

    /// The system retries a Control tap with the same request: one change, listed once.
    @Test func aRetriedIntentCommitsOnceAndIsListedOnce() async throws {
        let deck = try await QualifiedDeck.start(in: folder)
        let backend = try #require(deck.model.backend)
        let request = RequestID()
        let actions = SessionActions(backend: backend, entryPoint: .appIntent)
        let first = try await actions.setRunning(true, seen: .neverStarted, surface: .control, requestID: request)
        let again = try await actions.setRunning(true, seen: .neverStarted, surface: .control, requestID: request)
        #expect(again.receipt == first.receipt)
        #expect(deck.library.receipts.count(where: { $0.receipt.requestID == request }) == 1)
        #expect(try await deck.storedSession() == LabSession(id: SurfaceDeck.sessionID, isRunning: true))
    }

    /// The launch action asks the host to show the deck, and nothing changes in the store.
    @Test func theLaunchActionOnlyAsksTheHostToShowTheDeck() async throws {
        let deck = try await QualifiedDeck.start(in: folder)
        let listed = deck.library.receipts.count
        let before = deck.model.openRequests
        try deck.link.open()
        #expect(deck.model.openRequests == before + 1)
        #expect(deck.model.isDeckRequested)
        #expect(deck.library.receipts.count == listed)
        #expect(try await deck.storedSession() == nil)
    }
}
