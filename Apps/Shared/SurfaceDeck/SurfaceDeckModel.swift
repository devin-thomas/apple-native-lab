import Foundation
import LabDomain
import Observation
import SurfaceDeck

/// The Surface Deck in this app (LAB-004): the demo session's state, its receipts, the snapshot
/// the widget and the Control read, and the person's choice to show details on them.
///
/// Every change goes through `SessionActions`, so the deck's button, the Control, the widget's
/// toggle, and Shortcuts all take one path: `LabLibrary.submit` into `LabDataService` and
/// `OperationService`, with a receipt. After each request the model writes a new snapshot, and a
/// stale surface is asked to redraw. It never polls: it reacts to receipts and requests.
@MainActor
@Observable
final class SurfaceDeckModel {
    enum Phase: Hashable {
        case notStarted
        case ready
        /// The store cannot be used. The reason is a sentence for a person.
        case unavailable(String)
    }

    /// The model the app and its intents share.
    static let shared = SurfaceDeckModel()

    static let detailsKey = "SurfaceDeck.showsDetailsOnSurfaces"
    static let lastChangeKey = "SurfaceDeck.lastChange"

    private(set) var phase: Phase = .notStarted
    private(set) var state: SessionState = .neverStarted
    /// Where and when the session last changed, as far as this app knows.
    private(set) var lastChange: SnapshotDetail?
    /// The result of the latest request from any entry point, as a sentence.
    private(set) var lastMessage: String?
    private(set) var publication: SnapshotPublication?
    /// The snapshot the surfaces read now, or would read in a build that has them.
    private(set) var snapshot: SessionSnapshot?
    private(set) var isWorking = false
    /// Incremented when the launch action asks a host to show the deck.
    private(set) var openRequests = 0
    /// True from a launch-action request until iPhone shows the deck. A cold launch may run the
    /// intent before any view exists, so the request waits here instead of in a view.
    var isDeckRequested = false

    /// Whether the widget shows where and when the session last changed. Off by default, so a
    /// snapshot is redacted unless the person turns this on.
    var showsDetailsOnSurfaces: Bool {
        didSet {
            defaults.set(showsDetailsOnSurfaces, forKey: Self.detailsKey)
            publish()
        }
    }

    @ObservationIgnored private var library: LabLibrary?
    @ObservationIgnored private let publisher: SnapshotPublisher
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date
    /// The surface of an intent between its commit and its settle, so a refresh that runs in
    /// between does not credit the change to the app.
    @ObservationIgnored private var pendingSurface: SessionSurface?

    init(
        publisher: SnapshotPublisher = .live(),
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.publisher = publisher
        self.defaults = defaults
        self.now = now
        showsDetailsOnSurfaces = defaults.bool(forKey: Self.detailsKey)
        lastChange = defaults.data(forKey: Self.lastChangeKey).flatMap { try? JSONDecoder().decode(SnapshotDetail.self, from: $0) }
    }

    // MARK: Connection

    /// The backend the deck and the App Intents commit through.
    var backend: LibrarySessionBackend? { library.map { LibrarySessionBackend(library: $0, model: self) } }

    func connect(_ library: LabLibrary) {
        self.library = library
    }

    var hasSurfaces: Bool { publisher.hasSurfaces }

    /// Session receipts from this app session, newest first: changes, conflicts, and Reset Demo.
    var receipts: [ReceiptRecord] {
        (library?.receipts ?? []).filter { record in
            record.receipt.admitted.operation.kind == .setSession
                || record.receipt.affectedEntities.contains(.session(SurfaceDeck.sessionID))
        }
    }

    // MARK: Reading

    /// Reads the session through the service and publishes the snapshot if it changed.
    func refresh() async {
        guard let library else { return }
        let service: LabDataService
        do {
            service = try await library.openedService()
        } catch {
            switch error {
            case .unavailable(let reason): phase = .unavailable(reason)
            case .refused: phase = .unavailable("The demo session could not be read.")
            }
            return
        }
        do {
            let current = SessionState(try await service.session(SurfaceDeck.sessionID, as: LabDataService.appUI))
            if phase == .ready, current != state {
                // A change this model did not settle: Reset Demo, or an undo from a receipt.
                note(SnapshotDetail(changedFrom: pendingSurface ?? .app, changedAt: now()))
                lastMessage = receipts.first?.receipt.summary
            }
            state = current
            phase = .ready
        } catch {
            phase = .unavailable(SurfaceDeckError.refused(error).message)
            return
        }
        publish()
    }

    // MARK: Actions

    var canAct: Bool { phase == .ready && !isWorking && library?.canAct == true }

    /// Starts or pauses the session from the deck, as the app UI, pinned to the state it shows.
    @discardableResult
    func setRunning(_ running: Bool) async -> SessionOutcome? {
        guard let backend, canAct else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            return try await SessionActions(backend: backend, entryPoint: .appUI)
                .setRunning(running, seen: state.seen, surface: .app)
        } catch {
            lastMessage = error.message
            return nil
        }
    }

    /// Called by the backend just before an intent's commit.
    func willCommit(from surface: SessionSurface) {
        pendingSurface = surface
    }

    /// Called after every request from any entry point, including one that changed nothing.
    func settle(_ outcome: SessionOutcome, surface: SessionSurface) {
        pendingSurface = nil
        if outcome.didChange { note(SnapshotDetail(changedFrom: surface, changedAt: now())) }
        state = outcome.state
        phase = .ready
        lastMessage = outcome.message
        // A surface that asked from a stale or missing state must redraw even if the file
        // already holds the current one.
        publish(force: !outcome.didChange)
    }

    /// Asks the host to show the deck (the launch action).
    func requestOpen() {
        openRequests += 1
        isDeckRequested = true
    }

    // MARK: Snapshot

    /// The snapshot for the current state, with details only when the person chose them.
    func makeSnapshot() -> SessionSnapshot {
        SessionSnapshot(state: state, writtenAt: now(), detail: showsDetailsOnSurfaces ? lastChange : nil)
    }

    private func publish(force: Bool = false) {
        guard phase == .ready else { return }
        let next = makeSnapshot()
        let result = publisher.publish(next, force: force)
        // "Unchanged" keeps the report of the last real write, which is what the surfaces hold.
        if result != .unchanged || publication == nil { publication = result }
        if snapshot?.differs(from: next) ?? true { snapshot = next }
    }

    private func note(_ detail: SnapshotDetail) {
        lastChange = detail
        defaults.set(try? JSONEncoder().encode(detail), forKey: Self.lastChangeKey)
    }

    /// The presentation the in-app previews draw: the same snapshot the surfaces read, or the
    /// placeholder before there is one.
    func previewPresentation(at date: Date) -> SurfacePresentation {
        guard let snapshot else { return .placeholder }
        return SurfacePresentation(reading: .snapshot(snapshot), confirmedAt: date, now: date)
    }
}
