import Foundation
import LabDomain
import LabStore
import LabSupport
import SurfaceDeck
import Testing
@testable import NativeLab

/// LAB-004-B criteria 1 to 3 with their evidence, in the sandboxed Mac app: the deck, the widget's
/// toggle and the Control as App Intents, the host's snapshot publisher, and Reset Demo beside an
/// import, on a fresh SQLite store that the host's first run seeds. The widget extension is stood
/// in for by reading the snapshot file into a `SessionTimeline`, as `SessionTimelineProvider` does;
/// WidgetKit's choice to decline a refresh is stood in for by keeping the older timeline.
///
/// The test attaches an `EvidenceRecord` of what it observed, with the toolchain read from this
/// app bundle. To keep it, run the test with a result bundle and export the attachment:
///
///     xcodebuild … -scheme LabMac-Core -only-testing:LabMacTests/SurfaceDeckHostEvidenceTests \
///       -resultBundlePath <bundle> LAB_SOURCE_REVISION=<sha> test
///     xcrun xcresulttool export attachments --path <bundle> --output-path <folder>
@MainActor
@Suite struct SurfaceDeckHostEvidenceTests {
    static let check = "Surface Deck in the Mac host: a stale widget toggle reconciles, the snapshot is redacted by default, a declined refresh shows the stale mark, and Reset Demo leaves imported data alone"

    @Test func theQualificationScenarioRunsInTheHost() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "SurfaceDeckHostEvidenceTests-\(UUID().uuidString)")
        let started = Date()
        var observations: [String] = []
        var differences: [String] = []
        var comparisons = 0
        func compare(_ same: Bool, _ what: String) {
            comparisons += 1
            #expect(same, "\(what)")
            if !same { differences.append(what) }
        }

        // First run: the host seeds the demo and writes a never-started, redacted snapshot.
        let deck = try await QualifiedDeck.start(in: folder)
        let first = try #require(deck.snapshot)
        compare(first.state == .neverStarted && first.isRedacted, "the first snapshot is never started and redacted")
        let fileText = try String(contentsOf: deck.file.url, encoding: .utf8)
        compare(!fileText.contains("changedFrom") && !fileText.contains("Swatch") && !fileText.contains("swatch"),
                "the snapshot file names no detail and no content")

        // Criterion 1: a stale widget toggle.
        _ = await deck.model.setRunning(true)
        compare(deck.snapshot?.state == SessionState(isRunning: true, revision: 1), "the deck's start reaches the snapshot")
        let t0 = Date(timeIntervalSince1970: 1_790_683_200)
        let widget = SessionTimeline(reading: deck.file.read(), now: t0)
        compare(widget.entries[0].presentation.stateTitle == "Running", "the widget draws Running at revision 1")
        let reloadsBeforePause = deck.reloads.count
        _ = await deck.model.setRunning(false)
        compare(deck.reloads.count == reloadsBeforePause + 1, "the pause asks WidgetKit for one reload")

        // Criterion 3: that reload is declined, so the widget keeps its timeline.
        let at30 = displayedEntry(widget, at: t0.addingTimeInterval(30 * 60))
        let at90 = try #require(displayedEntry(widget, at: t0.addingTimeInterval(90 * 60)))
        compare(at30?.availability == .current && at30?.stateTitle == "Running", "at 30 minutes the widget still looks current")
        compare(at90.availability == .stale && at90.statusText == "May be out of date" && at90.stateTitle == "Running",
                "at 90 minutes the widget says it may be out of date")
        compare(at90.accessibilityLabel == "Demo session, Running, may be out of date.", "VoiceOver hears the stale mark")
        observations.append("After a declined reload, the widget read Running, current, at 30 minutes and \"May be out of date\" at 90 minutes.")

        // The person taps the stale widget's toggle.
        let reloadsBeforeTap = deck.reloads.count
        let tap = SetDemoSessionIntent(showing: at90.state, surface: .widget)
        let outcome = try await tap.run(with: deck.link)
        let conflict = try #require(outcome.receipt)
        compare(conflict.conflict?.expected == Revision(rawValue: 1) && conflict.conflict?.current == Revision(rawValue: 2),
                "the tap is a conflict: expected revision 1, found 2")
        compare(conflict.admitted.adapter == .appIntent && conflict.changes.isEmpty && conflict.undo == nil,
                "the conflict is an App Intent receipt that changes nothing")
        compare(try await deck.storedSession() == LabSession(id: SurfaceDeck.sessionID, isRunning: false, revision: Revision(rawValue: 2)!),
                "the store stays paused at revision 2")
        compare(deck.model.receipts.first?.receipt == conflict, "the deck lists the conflict first")
        compare(deck.reloads.count == reloadsBeforeTap + 1, "the host asks the stale widget to redraw")
        let redrawn = SessionTimeline(reading: deck.file.read(), now: t0.addingTimeInterval(91 * 60)).entries[0].presentation
        compare(redrawn.availability == .current && redrawn.stateTitle == "Paused" && redrawn.seen == .revision(Revision(rawValue: 2)!),
                "the redrawn widget shows Paused at revision 2")
        observations.append("The tap was recorded as \"\(conflict.summary)\"; the store stayed paused at revision 2 and the redrawn widget showed Paused.")
        let restarted = try await SetDemoSessionIntent(showing: redrawn.state, surface: .widget).run(with: deck.link)
        compare(restarted.didChange && restarted.state == SessionState(isRunning: true, revision: 3), "a tap on the redrawn widget starts the session")

        // Criterion 2: the snapshot is redacted until the person shows details, and again after.
        compare(deck.snapshot?.isRedacted == true && !deck.model.showsDetailsOnSurfaces, "details are off by default")
        deck.model.showsDetailsOnSurfaces = true
        compare(deck.snapshot?.detail?.changedFrom == .widget, "with details on, the snapshot says the widget made the last change")
        let shown = SurfacePresentation(reading: deck.file.read(), confirmedAt: .now, now: .now)
        compare(shown.detailText == "Changed from the widget" && !shown.accessibilityLabel.contains("widget"),
                "the detail is its own line, never in the spoken summary")
        deck.model.showsDetailsOnSurfaces = false
        compare(deck.snapshot?.isRedacted == true, "turning details off redacts the snapshot again")

        // Reset Demo beside an import made through a second connection as the share extension.
        let notes = try await deck.library.submit(
            .createCollection(draft: CollectionDraft(title: try EntityTitle("Field notes"))),
            requestID: RequestID(), authority: .userAction, names: [:]
        )
        guard case .collection(let notesID)? = notes.receipt.changes.first?.entity else {
            Issue.record("Expected a new collection")
            return
        }
        let ledger = GrantLedger()
        let extensionService = OperationService(store: try await SQLiteOperationStore(url: deck.storeURL), policy: GrantAuthorizationPolicy(ledger: ledger))
        let inbox = InMemoryStagingInbox()
        let staged = await inbox.stage(try StagingRecord.text(utf8: Array("Harbor walk\nBring the blue notebook.".utf8)))
        try ledger.issue(to: .shareExtension, for: [.createItem], on: ImportAdopter.grantTarget(into: notesID))
        let imported = try await ImportAdopter(service: extensionService, inbox: inbox, ledger: ledger).adopt(staged.id, into: notesID)
        let reader = try await SQLiteOperationStore(url: deck.storeURL)
        let userBefore = (try await reader.collections().filter { $0.namespace == .user }, try await reader.items(in: nil).filter { $0.namespace == .user })

        let reset = try #require(await deck.library.resetDemo())
        await deck.model.refresh()
        compare(reset.receipt.changes.map(\.entity) == [.session(SurfaceDeck.sessionID)] && reset.receipt.removed.isEmpty,
                "Reset Demo changes only the session")
        compare(reset.receipt.summary == "Reset the demo to its original 3 collections and 12 items: paused 1 session.", "Reset Demo says it paused the session")
        let userAfter = (try await reader.collections().filter { $0.namespace == .user }, try await reader.items(in: nil).filter { $0.namespace == .user })
        compare(userAfter.0 == userBefore.0 && userAfter.1 == userBefore.1 && userAfter.1.count == 1, "the person's collection and imported item are unchanged")
        compare(try await reader.receipt(for: imported.receipt.requestID) == imported.receipt, "the import's receipt is still recorded")
        compare(deck.snapshot?.state == SessionState(isRunning: false, revision: 4), "the snapshot follows the reset")
        let beforeReset = try await SetDemoSessionIntent(showing: SessionState(isRunning: true, revision: 3), surface: .control).run(with: deck.link)
        compare(beforeReset.receipt?.conflict != nil && beforeReset.state == SessionState(isRunning: false, revision: 4),
                "a Control drawn before the reset conflicts after it")

        #expect(comparisons == 25, "every check above is counted")
        let record = try EvidenceRecord(
            subject: "LAB-004",
            check: Self.check,
            date: started,
            provenance: .current,
            execution: .fixture,
            inputs: [
                "seed:app-bundle@sha256:\(ContentDigest.sha256(try Data(contentsOf: try #require(Bundle.main.url(forResource: "seed", withExtension: "json")))).hex)",
                "session:\(SurfaceDeck.sessionID)",
            ],
            steps: [
                "xcodebuild -scheme LabMac-Core -only-testing:LabMacTests/SurfaceDeckHostEvidenceTests test",
                "A fresh SQLite store in the app container, seeded by the host's first run; the snapshot in a temporary App Group folder; a fresh defaults suite",
                "The deck starts the session, and the widget draws a timeline from the snapshot file",
                "The deck pauses the session; the reload it asks for is declined, so the widget keeps its timeline",
                "The widget's stale entry is read at 30 and 90 minutes, and its toggle runs as an App Intent",
                "The widget redraws from the file and its toggle starts the session",
                "Show Details on Widgets is turned on, then off",
                "A collection is created in the app and an item is adopted into it through a second connection as the share extension",
                "Reset Demo, then a Control toggle drawn before it",
            ],
            outcome: differences.isEmpty
                ? .passed(observed: "All \(comparisons) checks held. " + observations.joined(separator: " ") + " The snapshot held only the state, revision, and write time until details were turned on, and again after they were turned off. Reset Demo paused the session at revision 4, changed nothing else, left the person's collection and imported item as they were, and a Control drawn before it conflicted.")
                : .failed(observed: "\(differences.count) of \(comparisons) checks failed: " + differences.joined(separator: "; ") + "."),
            limitations: [
                "Fixture path: hosted tests in the sandboxed Mac app on the development Mac, on a fresh store seeded from the bundled demo seed. It supports implemented at most.",
                "The widget extension, WidgetKit, and Control Center did not run. The widget is stood in for by reading the snapshot file into SessionTimeline, as the extension's timeline provider does, and a declined refresh by keeping the older timeline. The Mac has no widget or Control.",
                "The intents ran through run(with:), the call their perform() makes. No system surface invoked them.",
                "The locked-device redaction is not observed here: the snapshot's contents and the spoken summary are. The SurfaceDeck package tests read the redacted rendering, and no locked device was used.",
                "No physical iPhone or iPad and no iOS simulator ran in this check.",
            ]
        )
        #expect(differences.isEmpty)
        Attachment.record(try Self.json(record), named: "LAB-004-surface-deck-host-qualification.json")
        #expect(record.result == .passed)
        #expect(record.provenance.xcodeBuild != "unknown" && record.provenance.sdkName.hasPrefix("macosx"))
        #expect(record.supportedState == .implemented)
    }

    private static func json(_ record: EvidenceRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return String(decoding: try encoder.encode(record), as: UTF8.self) + "\n"
    }
}
