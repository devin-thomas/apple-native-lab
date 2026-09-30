import Foundation
import LabDomain
@testable import SurfaceDeck
import Testing

/// LAB-004: a change from any surface lands through the operation service with a receipt, can be
/// reversed, and a stale surface reconciles to the current state instead of overwriting it.
@Suite struct SessionActionTests {
    @Test func theDeckAndTheControlChangeTheSameStateThroughTheServiceWithReceipts() async throws {
        let backend = ServiceSessionBackend()
        let deck = SessionActions(backend: backend, entryPoint: .appUI)
        let started = try await deck.setRunning(true, seen: .neverStarted, surface: .app)
        #expect(started.didChange)
        #expect(started.state == SessionState(isRunning: true, revision: 1))
        let appReceipt = try #require(started.receipt)
        #expect(appReceipt.admitted.adapter == .appUI)
        #expect(appReceipt.summary == "Started the demo session.")

        // The Control saw revision 1 (running) and asks to pause, as an App Intent.
        let intent = SetDemoSessionIntent(value: false, seen: .revision(.initial), surface: .control)
        let outcome = try await intent.run(with: backend.link)
        #expect(outcome.didChange)
        #expect(outcome.state == SessionState(isRunning: false, revision: 2))
        let intentReceipt = try #require(outcome.receipt)
        #expect(intentReceipt.admitted.adapter == .appIntent)
        #expect(outcome.message == "Paused the demo session. Its receipt in Native Lab offers an undo.")

        // Both receipts are the store's: the same service recorded them with their changes.
        for receipt in [appReceipt, intentReceipt] {
            #expect(try await backend.service.findReceipt(for: receipt.requestID, as: ServiceSessionBackend.appUI) == receipt)
        }
        #expect(try await backend.stored() == LabSession(id: SurfaceDeck.sessionID, isRunning: false, revision: .r(2)))
        #expect(backend.commits.map(\.surface) == [.app, .control])
        #expect(backend.settled.count == 2)
        #expect(backend.ledger.liveGrants.isEmpty, "no grant is issued or needed for a session change")
    }

    @Test func everyChangeIsReversedByItsReceiptsUndo() async throws {
        let backend = ServiceSessionBackend()
        let widget = SessionActions(backend: backend, entryPoint: .appIntent)
        let started = try await widget.setRunning(true, seen: .neverStarted, surface: .widget)
        let undo = try #require(started.receipt?.undo)
        let undone = try await backend.commit(undo, requestID: RequestID(), via: .appUI, surface: .app)
        #expect(undone.status == .committed)
        #expect(undone.summary == "Paused the demo session.")
        #expect(try await backend.stored()?.isRunning == false)
        #expect(undone.undo == .setSession(id: SurfaceDeck.sessionID, expected: .r(2), running: true))
    }

    @Test func aStaleControlGetsAConflictReceiptAndReconcilesToTheCurrentState() async throws {
        let backend = ServiceSessionBackend()
        let deck = SessionActions(backend: backend, entryPoint: .appUI)
        _ = try await deck.setRunning(true, seen: .neverStarted, surface: .app)
        _ = try await deck.setRunning(false, seen: .revision(.initial), surface: .app)

        // The Control still shows revision 1, running, and asks to pause.
        let intent = SetDemoSessionIntent(value: false, seen: .revision(.initial), surface: .control)
        let outcome = try await intent.run(with: backend.link)
        guard case .conflict(let receipt, let state) = outcome else {
            Issue.record("Expected a conflict, got \(outcome)")
            return
        }
        #expect(receipt.conflict?.current == .r(2))
        #expect(receipt.changes.isEmpty && receipt.undo == nil)
        #expect(state == SessionState(isRunning: false, revision: 2))
        #expect(outcome.message == "The demo session changed since this was shown. It is paused. Nothing was changed.")
        #expect(try await backend.stored()?.revision == .r(2))
        // The host hears about the conflict too, so it can rewrite the snapshot and reload.
        #expect(backend.settled.last == outcome)
    }

    @Test func aSurfaceThatSawNoSessionWhileOneExistsIsStaleAndChangesNothing() async throws {
        let backend = ServiceSessionBackend()
        _ = try await SessionActions(backend: backend, entryPoint: .appUI).setRunning(true, seen: .neverStarted, surface: .app)
        let intent = SetDemoSessionIntent(value: true, seen: .neverStarted, surface: .widget)
        let outcome = try await intent.run(with: backend.link)
        #expect(outcome == .stale(SessionState(isRunning: true, revision: 1)))
        #expect(backend.commits.count == 1)
    }

    @Test func aSurfaceWithoutASnapshotOnlyShowsTheCurrentState() async throws {
        let backend = ServiceSessionBackend()
        let intent = SetDemoSessionIntent(value: true, seen: .unknown, surface: .control)
        let outcome = try await intent.run(with: backend.link)
        #expect(outcome == .reconciled(.neverStarted))
        #expect(outcome.message == "The demo session is paused.")
        #expect(backend.commits.isEmpty)
        #expect(try await backend.stored() == nil)
        #expect(backend.settled == [outcome], "the host still rewrites the snapshot so the Control can show it")
    }

    @Test func shortcutsSetAValueAgainstWhateverIsCurrent() async throws {
        let backend = ServiceSessionBackend()
        let intent = SetDemoSessionIntent()
        intent.value = false
        #expect(try await intent.run(with: backend.link) == .unchanged(.neverStarted))
        intent.value = true
        let started = try await intent.run(with: backend.link)
        #expect(started.didChange)
        #expect(backend.commits.map(\.surface) == [.shortcuts])
        #expect(try await intent.run(with: backend.link) == .unchanged(SessionState(isRunning: true, revision: 1)))
        #expect(backend.commits.count == 1)
    }

    @Test func invalidSeenRevisionsNeverChangeTheSession() async throws {
        #expect(SeenRevision(parameter: nil) == .unspecified)
        #expect(SeenRevision(parameter: -1) == .unknown)
        #expect(SeenRevision(parameter: Int.min) == .unknown)
        #expect(SeenRevision(parameter: 0) == .neverStarted)
        #expect(SeenRevision(parameter: 7) == .revision(.r(7)))
        for seen in [SeenRevision.unspecified, .unknown, .neverStarted, .revision(.r(3))] {
            #expect(SeenRevision(parameter: seen.parameter) == seen)
        }

        let backend = ServiceSessionBackend()
        let intent = SetDemoSessionIntent()
        intent.seenRevision = -42
        intent.value = true
        #expect(try await intent.run(with: backend.link) == .reconciled(.neverStarted))
        // A revision that was never stored names a missing session: stale, nothing changed.
        intent.seenRevision = 9
        #expect(try await intent.run(with: backend.link) == .stale(.neverStarted))
        #expect(backend.commits.isEmpty)
    }

    @Test func aCancelledRequestCommitsNothing() async throws {
        let backend = ServiceSessionBackend()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SessionActions(backend: backend, entryPoint: .appIntent)
                .setRunning(true, seen: .neverStarted, surface: .control)
        }
        await #expect(throws: SurfaceDeckError.cancelled) { try await task.value }
        #expect(backend.commits.isEmpty)
        #expect(try await backend.stored() == nil)
    }

    @Test func withoutAHostEveryIntentRefusesWithAReadableReason() async throws {
        let intent = SetDemoSessionIntent(value: true, seen: .neverStarted, surface: .control)
        let error = await #expect(throws: SurfaceDeckError.self) { try await intent.run(with: .unavailable) }
        #expect(error?.message == "Native Lab has not opened its store yet. Open Native Lab and try again.")
        #expect(error?.localizedStringResource != nil)
    }

    @Test func getDemoSessionReadsWithoutChangingAnything() async throws {
        let backend = ServiceSessionBackend()
        #expect(try await GetDemoSessionIntent().run(with: backend.link) == .neverStarted)
        #expect(GetDemoSessionIntent.dialog(for: .neverStarted) == "The demo session has never been started.")
        _ = try await SessionActions(backend: backend, entryPoint: .appUI).setRunning(true, seen: .neverStarted, surface: .app)
        let state = try await GetDemoSessionIntent().run(with: backend.link)
        #expect(state == SessionState(isRunning: true, revision: 1))
        #expect(GetDemoSessionIntent.dialog(for: state) == "The demo session is running.")
        #expect(backend.commits.count == 1)
    }

    @Test func theIntentsAreTheDocumentedToggleAndLaunchAction() {
        #expect(SetDemoSessionIntent.authenticationPolicy == .requiresAuthentication)
        #expect(OpenSurfaceDeckIntent.supportedModes == .foreground(.immediate))
        #expect(OpenSurfaceDeckIntent().target == .deck)
        #expect(SetDemoSessionIntent.supportedModes == .background)
        // A surface offers the opposite of what it shows, from the revision it shows.
        let offered = SetDemoSessionIntent(showing: SessionState(isRunning: true, revision: 4), surface: .widget)
        #expect(offered.value == false && offered.seenRevision == 4 && offered.surface == .widget)
        let fresh = SetDemoSessionIntent(showing: .neverStarted, surface: .control)
        #expect(fresh.value == true && fresh.seenRevision == 0)
        // Without a snapshot the surface saw nothing, so the intent only reconciles.
        let placeholder = SetDemoSessionIntent(showing: nil, surface: .control)
        #expect(placeholder.seenRevision == -1)
    }
}
