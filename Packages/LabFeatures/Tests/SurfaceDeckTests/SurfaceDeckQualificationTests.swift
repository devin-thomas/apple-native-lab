import Foundation
import LabDomain
@testable import SurfaceDeck
import Synchronization
import SwiftUI
import Testing
#if canImport(Vision) && os(macOS)
import Vision
#endif

/// LAB-004-B: the qualification criteria and step 3 (denial, cancellation, stale and duplicate
/// state, and reset beside imported data), through the same `SessionActions`, intents, snapshot
/// file, presentation, and timeline the widget extension and the hosts use. Fixture path: an
/// in-memory store behind `OperationService` with `GrantAuthorizationPolicy`. The host's snapshot
/// publisher and WidgetKit are stood in for as the comments say; the Mac hosted tests run the host.
@Suite struct SurfaceDeckQualificationTests {
    static let start = Date(timeIntervalSince1970: 1_790_683_200)

    // MARK: Criterion 1: stale widget toggles reconcile to current state

    /// A widget that drew revision 1 is tapped after the deck paused the session. The service
    /// answers with a conflict receipt and changes nothing; the host rewrites the snapshot from the
    /// settled state, and the widget's next timeline shows, and offers, the current state.
    @Test func aStaleWidgetToggleConflictsAndTheNextTimelineShowsTheCurrentState() async throws {
        let backend = ServiceSessionBackend()
        let folder = try TemporaryFolder()
        let file = folder.snapshotFile
        let deck = SessionActions(backend: backend, entryPoint: .appUI)

        let started = try await deck.setRunning(true, seen: .neverStarted, surface: .app)
        try file.write(SessionSnapshot(state: started.state, writtenAt: Self.start, detail: nil))
        let drawn = SessionTimeline(reading: file.read(), now: Self.start)
        #expect(drawn.entries[0].presentation.isOn && drawn.entries[0].presentation.seen == .revision(.r(1)))

        // The deck pauses; the widget's reload has not arrived, so it still shows revision 1.
        _ = try await deck.setRunning(false, seen: .revision(.r(1)), surface: .app)
        let commitsBefore = backend.commits.count

        let tap = SetDemoSessionIntent(showing: drawn.entries[0].presentation.state, surface: .widget)
        #expect(tap.value == false && tap.seenRevision == 1)
        let outcome = try await tap.run(with: backend.link)
        guard case .conflict(let receipt, let current) = outcome else {
            Issue.record("Expected a conflict, got \(outcome)")
            return
        }
        #expect(receipt.admitted.adapter == .appIntent)
        #expect(receipt.conflict?.expected == .r(1) && receipt.conflict?.current == .r(2))
        #expect(receipt.changes.isEmpty && receipt.undo == nil)
        #expect(receipt.summary == "Not applied because the demo session changed: expected revision 1, found 2.")
        #expect(current == SessionState(isRunning: false, revision: 2))
        #expect(try await backend.stored() == LabSession(id: SurfaceDeck.sessionID, isRunning: false, revision: .r(2)))
        #expect(backend.commits.count == commitsBefore + 1, "the stale tap reached the service once")
        #expect(await backend.store.receipt(for: receipt.requestID) == receipt, "and its conflict receipt is recorded")
        #expect(backend.settled.last == outcome, "the host hears the conflict and can redraw the widget")

        // The host writes what settled; the widget's next timeline reads it.
        try file.write(SessionSnapshot(state: outcome.state, writtenAt: Self.start.addingTimeInterval(5), detail: nil))
        let redrawn = SessionTimeline(reading: file.read(), now: Self.start.addingTimeInterval(5))
        let shown = redrawn.entries[0].presentation
        #expect(shown.availability == .current && !shown.isOn && shown.stateTitle == "Paused")
        #expect(shown.seen == .revision(.r(2)))

        // A tap on the redrawn widget now changes the session.
        let next = try await SetDemoSessionIntent(showing: shown.state, surface: .widget).run(with: backend.link)
        #expect(next.didChange && next.state == SessionState(isRunning: true, revision: 3))
    }

    /// The widget's current entry and its hour-later stale entry offer the same toggle, so a tap on
    /// either reconciles the same way.
    @Test func bothEntriesOfAStaleTimelineReconcileTheSameWay() async throws {
        for index in [0, 1] {
            let backend = ServiceSessionBackend()
            let deck = SessionActions(backend: backend, entryPoint: .appUI)
            let started = try await deck.setRunning(true, seen: .neverStarted, surface: .app)
            let timeline = SessionTimeline(
                reading: .snapshot(SessionSnapshot(state: started.state, writtenAt: Self.start, detail: nil)), now: Self.start
            )
            _ = try await deck.setRunning(false, seen: .revision(.r(1)), surface: .app)

            let entry = timeline.entries[index].presentation
            let outcome = try await SetDemoSessionIntent(showing: entry.state, surface: .widget).run(with: backend.link)
            #expect(outcome.receipt?.conflict != nil, "entry \(index)")
            #expect(outcome.state == SessionState(isRunning: false, revision: 2), "entry \(index)")
        }
    }

    /// A widget tapped twice before it redraws: the first tap commits, the second finds the
    /// session moved and changes nothing.
    @Test func twoTapsFromOneEntryChangeTheSessionOnce() async throws {
        let backend = ServiceSessionBackend()
        _ = try await SessionActions(backend: backend, entryPoint: .appUI).setRunning(true, seen: .neverStarted, surface: .app)
        let shown = SurfacePresentation(
            reading: .snapshot(SessionSnapshot(state: SessionState(isRunning: true, revision: 1), writtenAt: Self.start, detail: nil)),
            confirmedAt: Self.start, now: Self.start
        )
        let first = try await SetDemoSessionIntent(showing: shown.state, surface: .widget).run(with: backend.link)
        let second = try await SetDemoSessionIntent(showing: shown.state, surface: .widget).run(with: backend.link)
        #expect(first.didChange && first.state == SessionState(isRunning: false, revision: 2))
        #expect(second.receipt?.conflict != nil && second.state == first.state)
        #expect(backend.commits.filter { $0.receipt.conflict == nil }.count == 2, "the deck's start and the first tap")
        #expect(try await backend.stored()?.revision == .r(2))
    }

    /// A widget or Control drawn before Reset Demo: the reset paused the session at its next
    /// revision, so the old toggle conflicts instead of applying.
    @Test func aToggleDrawnBeforeResetDemoConflictsAfterIt() async throws {
        let backend = ServiceSessionBackend()
        _ = try await backend.reset()
        _ = try await SessionActions(backend: backend, entryPoint: .appUI).setRunning(true, seen: .neverStarted, surface: .app)
        let drawn = SessionState(isRunning: true, revision: 1)
        _ = try await backend.reset()
        #expect(try await backend.stored() == LabSession(id: SurfaceDeck.sessionID, isRunning: false, revision: .r(2)))

        for surface in [SessionSurface.widget, .control] {
            let outcome = try await SetDemoSessionIntent(showing: drawn, surface: surface).run(with: backend.link)
            #expect(outcome.receipt?.conflict != nil, "\(surface)")
            #expect(outcome.state == SessionState(isRunning: false, revision: 2))
        }
    }

    /// A timeline read with no snapshot offers a toggle that only shows the current state, and the
    /// host is still told so it can write the first snapshot.
    @Test func aPlaceholderWidgetToggleOnlyReconciles() async throws {
        let backend = ServiceSessionBackend()
        _ = try await SessionActions(backend: backend, entryPoint: .appUI).setRunning(true, seen: .neverStarted, surface: .app)
        let folder = try TemporaryFolder()
        let timeline = SessionTimeline(reading: folder.snapshotFile.read(), now: Self.start)
        for entry in timeline.entries {
            let intent = SetDemoSessionIntent(showing: entry.presentation.state, surface: .widget)
            #expect(intent.seenRevision == -1)
            let outcome = try await intent.run(with: backend.link)
            #expect(outcome == .reconciled(SessionState(isRunning: true, revision: 1)))
        }
        #expect(backend.commits.count == 1)
        #expect(backend.settled.suffix(2).allSatisfy { $0.state == SessionState(isRunning: true, revision: 1) })
    }

    // MARK: Criterion 2: locked-device view redacts private labels

    /// Off by default, no surface has a private label to show: the snapshot holds the state only,
    /// and every layout reads "Details hidden" or nothing.
    @Test(arguments: SessionWidgetLayout.allCases)
    func withDetailsOffNoLayoutHasAPrivateLabel(_ layout: SessionWidgetLayout) throws {
        let snapshot = SessionSnapshot(state: SessionState(isRunning: true, revision: 3), writtenAt: Self.start, detail: nil)
        let text = String(decoding: try snapshot.encoded(), as: UTF8.self)
        #expect(!text.contains("changedFrom") && !text.contains("changedAt"))
        let shown = SurfacePresentation(reading: .snapshot(snapshot), confirmedAt: Self.start, now: Self.start)
        #expect(shown.detailText == nil && shown.statusText == "Details hidden")
        #expect(!shown.accessibilityLabel.contains("Changed"))
    }

    #if canImport(Vision) && os(macOS)
    /// With Show Details on, the medium and Lock Screen layouts draw "Changed from …" when
    /// unlocked. Drawn with the privacy redaction a locked device applies, that line is gone and
    /// the state is still readable. The words are read back from the rendered pixels by text
    /// recognition, not from the view's code.
    @MainActor
    @Test(arguments: [SessionWidgetLayout.medium, .accessory])
    func theLockedRenderingHidesTheDetailLineAndKeepsTheState(_ layout: SessionWidgetLayout) throws {
        let detail = SnapshotDetail(changedFrom: .control, changedAt: Self.start)
        let snapshot = SessionSnapshot(state: SessionState(isRunning: true, revision: 3), writtenAt: Self.start, detail: detail)
        let shown = SurfacePresentation(reading: .snapshot(snapshot), confirmedAt: Self.start, now: Self.start)

        let unlocked = try Rendered.text(of: layout, shown, locked: false)
        #expect(unlocked.contains("changed from control center"), "unlocked: \(unlocked)")
        #expect(unlocked.contains("running"))

        let locked = try Rendered.text(of: layout, shown, locked: true)
        #expect(!locked.contains("changed"), "locked: \(locked)")
        #expect(!locked.contains("control center"), "locked: \(locked)")
        #expect(locked.contains("running"), "the state stays readable: \(locked)")
    }

    /// The small widget never draws the detail line, locked or not.
    @MainActor
    @Test func theSmallWidgetNeverDrawsTheDetailLine() throws {
        let detail = SnapshotDetail(changedFrom: .control, changedAt: Self.start)
        let snapshot = SessionSnapshot(state: SessionState(isRunning: true, revision: 3), writtenAt: Self.start, detail: detail)
        let shown = SurfacePresentation(reading: .snapshot(snapshot), confirmedAt: Self.start, now: Self.start)
        let text = try Rendered.text(of: .small, shown, locked: false)
        #expect(text.contains("running") && !text.contains("control center"), "\(text)")
    }
    #endif

    // MARK: Criterion 3: a denied update budget leaves a correct stale indicator

    /// WidgetKit shows each timeline entry from its date until the next one's, and asks for a new
    /// timeline after `refreshAfter` only if its budget allows. This stand-in shows what a widget
    /// displays at `date` when that refresh never comes.
    static func displayed(_ timeline: SessionTimeline, at date: Date) -> SurfacePresentation? {
        timeline.entries.last { $0.date <= date }?.presentation
    }

    @Test func whenTheRefreshIsDeclinedTheWidgetSaysItMayBeOutOfDate() {
        let snapshot = SessionSnapshot(state: SessionState(isRunning: true, revision: 4), writtenAt: Self.start, detail: nil)
        let timeline = SessionTimeline(reading: .snapshot(snapshot), now: Self.start)
        #expect(timeline.entries.count == 2 && timeline.refreshAfter == Self.start.addingTimeInterval(3_600))

        for minutes in [0.0, 1, 30, 59.9] {
            let shown = Self.displayed(timeline, at: Self.start.addingTimeInterval(minutes * 60))
            #expect(shown?.availability == .current, "\(minutes) minutes")
            #expect(shown?.statusText == "Details hidden")
        }
        // The refresh WidgetKit was asked for at one hour never comes: the budget is spent.
        for hours: Double in [1, 2, 24, 168] {
            let shown = Self.displayed(timeline, at: Self.start.addingTimeInterval(hours * 3_600))
            #expect(shown?.availability == .stale, "\(hours) hours")
            #expect(shown?.statusText == "May be out of date")
            #expect(shown?.stateTitle == "Running", "it still says what it last knew")
            #expect(shown?.accessibilityLabel == "Demo session, Running, may be out of date.")
            #expect(shown?.seen == .revision(.r(4)), "and its toggle still carries what it showed")
        }
    }

    @Test func whenTheRefreshIsGrantedTheStaleEntryNeverShows() {
        let snapshot = SessionSnapshot(state: SessionState(isRunning: false, revision: 2), writtenAt: Self.start, detail: nil)
        let first = SessionTimeline(reading: .snapshot(snapshot), now: Self.start)
        // WidgetKit asks at `refreshAfter` and the extension reads the file again.
        let second = SessionTimeline(reading: .snapshot(snapshot), now: first.refreshAfter)
        #expect(Self.displayed(second, at: first.refreshAfter)?.availability == .current)
        #expect(Self.displayed(second, at: first.refreshAfter.addingTimeInterval(3_599))?.availability == .current)
    }

    /// The app's reload after a change is declined too: the old timeline keeps drawing the old
    /// state until its hour is up, then says it may be out of date. A tap on it reconciles.
    @Test func aDeclinedReloadAfterAChangeShowsStaleThenReconcilesOnTap() async throws {
        let backend = ServiceSessionBackend()
        let deck = SessionActions(backend: backend, entryPoint: .appUI)
        let started = try await deck.setRunning(true, seen: .neverStarted, surface: .app)
        let timeline = SessionTimeline(
            reading: .snapshot(SessionSnapshot(state: started.state, writtenAt: Self.start, detail: nil)), now: Self.start
        )
        _ = try await deck.setRunning(false, seen: .revision(.r(1)), surface: .app)

        let later = try #require(Self.displayed(timeline, at: Self.start.addingTimeInterval(90 * 60)))
        #expect(later.availability == .stale && later.stateTitle == "Running")
        let outcome = try await SetDemoSessionIntent(showing: later.state, surface: .widget).run(with: backend.link)
        #expect(outcome.receipt?.conflict != nil)
        #expect(outcome.message == "The demo session changed since this was shown. It is paused. Nothing was changed.")
    }

    /// A placeholder is never mistaken for a stale state: without a snapshot, both entries say the
    /// session is not available.
    @Test func aMissingSnapshotIsNeverShownAsStale() {
        let timeline = SessionTimeline(reading: .unreadable, now: Self.start)
        for hours in [0.0, 1, 24] {
            let shown = Self.displayed(timeline, at: Self.start.addingTimeInterval(hours * 3_600))
            #expect(shown?.availability == .unavailable && shown?.statusText == "Open Native Lab", "\(hours) hours")
        }
    }

    // MARK: Step 3: denial, cancellation, duplicates, and reset beside imported data

    /// An entry point that is not allowed to commit is refused with a readable reason, and nothing
    /// is recorded or settled.
    @Test func aRefusedEntryPointChangesNothingAndSaysWhy() async throws {
        let backend = RefusingSessionBackend()
        let link = SurfaceDeckLink(backend: backend, openDeck: {})
        let error = await #expect(throws: SurfaceDeckError.self) {
            try await SetDemoSessionIntent(value: true, seen: .neverStarted, surface: .control).run(with: link)
        }
        #expect(error?.message == "This entry point is not allowed to change the demo session. Nothing was changed.")
        #expect(backend.settledCount == 0)
        #expect(try await backend.service.findSession(SurfaceDeck.sessionID, as: ServiceSessionBackend.appUI) == nil)
    }

    /// The system retries an intent with the same request: it commits once and returns the first
    /// receipt. The same request ID for a different change is refused.
    @Test func aRetriedRequestCommitsOnceAndAReusedIDIsRefused() async throws {
        let backend = ServiceSessionBackend()
        let actions = SessionActions(backend: backend, entryPoint: .appIntent)
        let request = RequestID()
        let first = try await actions.setRunning(true, seen: .neverStarted, surface: .control, requestID: request)
        let retry = try await actions.setRunning(true, seen: .neverStarted, surface: .control, requestID: request)
        #expect(retry.receipt == first.receipt)
        #expect(await backend.store.receipt(for: request) == first.receipt)
        #expect(try await backend.stored()?.revision == .initial, "one change, not two")

        let error = await #expect(throws: SurfaceDeckError.self) {
            try await actions.setRunning(false, seen: .revision(.initial), surface: .control, requestID: request)
        }
        #expect(error == .refused(.requestIDReused(request)))
        #expect(error?.message == "The demo session could not be changed. Nothing was changed.")
        #expect(try await backend.stored() == LabSession(id: SurfaceDeck.sessionID, isRunning: true))
    }

    /// A request cancelled before its commit records nothing, and the same request later commits
    /// exactly once.
    @Test func aCancelledRequestCanBeRetriedUnderTheSameID() async throws {
        let backend = ServiceSessionBackend()
        let request = RequestID()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SessionActions(backend: backend, entryPoint: .appIntent)
                .setRunning(true, seen: .neverStarted, surface: .widget, requestID: request)
        }
        await #expect(throws: SurfaceDeckError.cancelled) { try await cancelled.value }
        #expect(backend.commits.isEmpty)
        #expect(await backend.store.receipt(for: request) == nil)

        let outcome = try await SessionActions(backend: backend, entryPoint: .appIntent)
            .setRunning(true, seen: .neverStarted, surface: .widget, requestID: request)
        #expect(outcome.didChange && outcome.receipt?.requestID == request)
        #expect(backend.commits.count == 1)
        #expect(try await backend.stored()?.revision == .initial)
    }

    /// Reset Demo pauses the session and leaves an item imported the way the share extension
    /// imports, and the person's collection, exactly as they were.
    @Test func resetDemoPausesTheSessionAndLeavesImportedDataUntouched() async throws {
        let backend = ServiceSessionBackend()
        _ = try await backend.reset()
        let actor = ServiceSessionBackend.appUI
        let notes = try await backend.service.perform(OperationRequest(
            id: RequestID(), operation: .createCollection(draft: CollectionDraft(title: try EntityTitle("Field notes"))), actor: actor
        ))
        guard case .collection(let notesID)? = notes.changes.first?.entity else {
            Issue.record("Expected a new collection")
            return
        }
        let inbox = InMemoryStagingInbox()
        let staged = await inbox.stage(try StagingRecord.text(utf8: Array("Harbor walk\nBring the blue notebook.".utf8)))
        try backend.ledger.issue(to: .shareExtension, for: [.createItem], on: ImportAdopter.grantTarget(into: notesID))
        let imported = try await ImportAdopter(service: backend.service, inbox: inbox, ledger: backend.ledger).adopt(staged.id, into: notesID)

        _ = try await SetDemoSessionIntent(value: true, seen: .neverStarted, surface: .control).run(with: backend.link)
        let userBefore = try await backend.userState()
        #expect(userBefore.collections.map(\.id) == [notesID] && userBefore.items.count == 1)

        let reset = try await backend.reset()
        #expect(reset.changes.map(\.entity) == [.session(SurfaceDeck.sessionID)])
        #expect(reset.removed.isEmpty)
        #expect(try await backend.stored() == LabSession(id: SurfaceDeck.sessionID, isRunning: false, revision: .r(2)))
        let userAfter = try await backend.userState()
        #expect(userAfter.collections == userBefore.collections && userAfter.items == userBefore.items)
        #expect(await backend.store.receipt(for: imported.receipt.requestID) == imported.receipt)
    }
}

// MARK: - Support

extension ServiceSessionBackend {
    /// Reset Demo with a one-collection seed, as a person confirms it in the app.
    @discardableResult
    func reset() async throws -> ActionReceipt {
        let operation = DomainOperation.resetDemo(seed: try QualificationSeed.seed())
        try ledger.issue(for: operation, to: .appUI)
        return try await service.perform(OperationRequest(id: RequestID(), operation: operation, actor: Self.appUI))
    }

    /// The person's own collections and items.
    func userState() async throws -> (collections: [LabCollection], items: [LabItem]) {
        let collections = try await store.collections().filter { $0.namespace == .user }
        let items = try await store.items(in: nil).filter { $0.namespace == .user }
        return (collections, items)
    }
}

/// The host's rules, but the request arrives through the share extension's adapter, which needs a
/// grant for every commit and has none: the path a peer or an extension would take.
final class RefusingSessionBackend: SessionBackend {
    static let actor = ActorScope(adapter: .shareExtension, grants: AdapterKind.shareExtension.ceiling)

    let service = OperationService(store: InMemoryOperationStore(), policy: GrantAuthorizationPolicy(ledger: GrantLedger()))
    private let settled = Mutex(0)

    func session(via entryPoint: SessionEntryPoint) async throws(SurfaceDeckError) -> LabSession? {
        do { return try await service.findSession(SurfaceDeck.sessionID, as: Self.actor) } catch { throw .refused(error) }
    }

    func commit(
        _ operation: DomainOperation, requestID: RequestID, via entryPoint: SessionEntryPoint, surface: SessionSurface
    ) async throws(SurfaceDeckError) -> ActionReceipt {
        do {
            return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: Self.actor))
        } catch {
            throw .refused(error)
        }
    }

    func didSettle(_ outcome: SessionOutcome, surface: SessionSurface) async {
        settled.withLock { $0 += 1 }
    }

    var settledCount: Int { settled.withLock { $0 } }
}

enum QualificationSeed {
    static func seed() throws -> DemoSeed {
        let shelf = CollectionID(rawValue: UUID(uuidString: "5A0C3C8E-7B0E-4E4B-9B63-2D6A6F0F1A01")!)
        return try DemoSeed(
            version: 1,
            collections: [CollectionDraft(id: shelf, title: try EntityTitle("Samples"))],
            items: [ItemDraft(id: ItemID(rawValue: UUID(uuidString: "5A0C3C8E-7B0E-4E4B-9B63-2D6A6F0F1A02")!), in: shelf, title: try EntityTitle("Sample"))]
        )
    }
}

#if canImport(Vision) && os(macOS)
/// Draws a widget layout the way `SurfacePreviewGallery` frames it, then reads its words back with
/// text recognition. `locked` applies the privacy redaction a locked device applies.
@MainActor
enum Rendered {
    static func text(of layout: SessionWidgetLayout, _ presentation: SurfacePresentation, locked: Bool) throws -> String {
        let size: CGSize = switch layout {
        case .small: CGSize(width: 158, height: 158)
        case .medium: CGSize(width: 338, height: 158)
        case .accessory: CGSize(width: 200, height: 84)
        }
        let view = SessionWidgetView(presentation: presentation, layout: layout) { SessionToggleLook(isOn: presentation.isOn) }
            .padding(layout == .accessory ? 10 : 14)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .redacted(reason: locked ? .privacy : [])
        let renderer = ImageRenderer(content: view)
        renderer.scale = 4
        let image = try #require(renderer.cgImage, "the view rendered")
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        // On the CPU: while other builds loaded the Mac, the Neural Engine once refused to load the
        // recognizer (`e5rtError` 13), which failed these tests for a reason outside the view.
        for (stage, devices) in try request.supportedComputeStageDevices {
            if let cpu = devices.first(where: { if case .cpu = $0 { true } else { false } }) {
                request.setComputeDevice(cpu, for: stage)
            }
        }
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " | ")
            .lowercased()
    }
}
#endif
