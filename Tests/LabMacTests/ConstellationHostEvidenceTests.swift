import AppKit
import Foundation
import LabDomain
import LabStore
import LabSupport
import LocalConstellation
import PeerSession
import SwiftUI
import Testing
@testable import NativeLab

/// LAB-019-B criteria 1 to 3 with their evidence, in the sandboxed Mac app: the declared fallback,
/// the single-device simulation, over the host's own `LabLibrary` on a fresh SQLite store that the
/// host's first run seeds. The simulation's real views are operated through the accessibility
/// press action, as VoiceOver or Voice Control would; the pairing code is typed through the model,
/// because the hosted harness cannot type into a text field. The simulation runs on real time.
///
/// The test attaches an `EvidenceRecord` of what it observed, with the toolchain read from this
/// app bundle, and PNG renderings of the views at three moments. To keep them, run the test with
/// a result bundle and export the attachments:
///
///     xcodebuild … -scheme LabMac-Core -only-testing:LabMacTests/ConstellationHostEvidenceTests \
///       -resultBundlePath <bundle> LAB_SOURCE_REVISION=<sha> test
///     xcrun xcresulttool export attachments --path <bundle> --output-path <folder>
@MainActor
@Suite(.serialized) struct ConstellationHostEvidenceTests {
    static let check = "Local Constellation's fallback in the Mac host: the single-device simulation pairs with the code, refuses an unpaired device before any session data, reconciles a stale command, shows a silent link as stale then disconnected on both sides, commits an allowed start as the authorized peer, and Reset Demo pauses the show and leaves the person's data alone"

    @Test func theQualificationScenarioRunsInTheHost() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ConstellationHostEvidenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let started = Date()
        var observations: [String] = []
        var differences: [String] = []
        var comparisons = 0
        func compare(_ same: Bool, _ what: String) {
            comparisons += 1
            #expect(same, "\(what)")
            if !same { differences.append(what) }
        }

        // First run: the host seeds the demo. The show has never been started.
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let simulation = ConstellationSimulation(
            backend: LibraryShowBackend(library: library), storeDescription: "a test store", sheet: try CueSheet.bundled()
        )
        await simulation.start()
        defer { Task { await simulation.stop() } }
        let views = AccessHostedView(VStack(alignment: .leading, spacing: 24) {
            SimulatedDeviceSection(model: simulation, role: .controller)
            SimulatedDeviceSection(model: simulation, role: .display)
            SimulatedConductorSection(model: simulation)
        }.environment(library))
        defer { views.close() }
        compare(simulation.conductor?.snapshot.cue == 0 && simulation.conductor?.snapshot.isRunning == false,
                "the show opens at the first cue, paused")

        // Criterion 2: an unpaired device asks to rejoin and is refused before any session data.
        #expect(try await views.press("Unpaired Device Tries to Join"))
        _ = try await waitFor { simulation.lastOutcome?.contains("no session data") == true ? true : nil }
        compare(simulation.lastOutcome == "The unpaired device was refused: This device is not paired with the conductor. Pair it with a code first. It received no session data.",
                "the unpaired device is refused and receives no session data")
        compare(simulation.conductor?.peers.isEmpty == true, "the roster lists nobody")

        // Pairing: each device's Ask to Join, the code typed there, Allow at the conductor.
        for role in [PeerRole.controller, .display] {
            #expect(try await views.press("Ask to Join"))
            let request = try await waitFor { simulation.conductor?.pairingRequest }
            let shown = try await views.elements(until: { $0.contains { $0.role == "AXButton" && $0.label == "Allow" } })
            compare(shown.contains { $0.spoken.contains("Code \(request.code.digits.map(String.init).joined(separator: " "))") },
                    "the conductor shows the \(role.title.lowercased())'s code, read digit by digit")
            _ = try await waitFor { simulation.state(of: role)?.codePrompt }
            #expect(await simulation.submitCode(request.code.description, on: role))
            #expect(try await views.press("Allow"))
            _ = try await waitFor { simulation.state(of: role)?.phase == .live ? true : nil }
        }
        compare(simulation.conductor?.peers.map(\.role) == [.controller, .display], "both devices are in the roster")
        observations.append("Both simulated devices paired with the six-digit code; an unpaired device was refused with no session data.")

        // The controller moves the show; the display follows.
        #expect(try await views.press("Next"))
        _ = try await waitFor { simulation.display?.snapshot?.cueTitle == "Lanterns" ? true : nil }
        let boards = try await views.elements(until: { $0.filter { $0.spoken.hasPrefix("Cue 2 of 6, Lanterns.") }.count >= 2 })
        compare(boards.filter { $0.spoken.hasPrefix("Cue 2 of 6, Lanterns.") }.count >= 2, "the controller's and the display's boards read cue 2")

        // A peer's start waits for the person at the conductor and commits as the authorized peer.
        let receiptsBefore = library.receipts.count
        #expect(try await views.press("Ask to Start"))
        let pending = try await waitFor { simulation.conductor?.pending.first }
        compare(pending.command == .start && library.receipts.count == receiptsBefore, "the start waits, and nothing is committed")
        #expect(try await views.press("Allow"))
        _ = try await waitFor { simulation.display?.snapshot?.isRunning == true ? true : nil }
        let allowed = try #require(library.receipts.first)
        compare(allowed.receipt.admitted.adapter == .authorizedPeer
                && allowed.receipt.admitted.operation == .setSession(id: LocalConstellation.showSessionID, expected: nil, running: true),
                "Allow commits setSession as the authorized peer")
        compare(ReceiptPresentation(allowed).adapter == "Authorized peer", "the receipt names the authorized peer")
        observations.append("The controller's Ask to Start waited for Allow, then committed through LabDataService as the authorized peer: \"\(allowed.receipt.summary)\"")
        let runningPicture = try render(simulation)

        // Criterion 1: a stale command. The controller walks out of range while the conductor
        // moves; back in range, its Next is based on the revision it last saw.
        #expect(try await views.press("Walk Out of Range"))
        #expect(try await views.press("Next Cue"))
        _ = try await waitFor { simulation.conductor?.snapshot.cue == 2 ? true : nil }
        #expect(try await views.press("Bring Back in Range"))
        let seen = simulation.controller?.revision
        let sentBefore = simulation.controller?.commands.count ?? 0
        #expect(try await views.press("Next"))
        let stale = try await waitFor { () -> CommandResult? in
            guard let commands = simulation.controller?.commands, commands.count > sentBefore,
                  case .finished(let result) = commands[commands.count - 1].stage else { return nil }
            return result
        }
        compare(stale.disposition == .stale, "the controller's Next from revision \(seen ?? -1) is refused as stale")
        _ = try await waitFor { simulation.controller?.snapshot?.cue == 2 ? true : nil }
        compare(simulation.conductor?.snapshot.cue == 2 && simulation.controller?.snapshot?.cueTitle == "Tide line",
                "nothing moved, and the controller is reconciled to cue 3, Tide line")
        observations.append("A Next based on an older revision was answered \"\(stale.summary)\", and the controller then showed cue 3, Tide line.")

        // Criterion 3: the display walks out of range. Nothing is closed; both sides notice.
        simulation.setLinkDown(.display, true)
        try await Task.sleep(for: .seconds(1.5))
        let quiet = try await views.elements(until: { elements in
            elements.contains { $0.spoken.contains("Nothing heard from the conductor") }
                && elements.contains { $0.spoken.contains("Display (simulated TV)") && $0.spoken.contains("Stale") }
        })
        compare(quiet.contains { $0.spoken.contains("Nothing heard from the conductor") }, "the display's board says nothing was heard")
        compare(quiet.contains { $0.spoken.contains("Display (simulated TV)") && $0.spoken.contains("Stale") }, "the conductor's roster reads Stale")
        let stalePicture = try render(simulation)
        _ = try await waitFor(.seconds(12)) {
            if case .disconnected = simulation.display?.phase { true } else { nil }
        }
        _ = try await waitFor(.seconds(4)) {
            if case .disconnected = simulation.conductor?.peers.first(where: { $0.role == .display })?.presence { true } else { nil }
        }
        compare(simulation.conductor?.peers.count == 2, "the roster keeps the disconnected display")
        compare(simulation.controller?.phase == .live, "the controller stayed live")
        observations.append("With the display's link silently down, its board said \"Nothing heard from the conductor\" and the roster read Stale; after 8 s both sides showed Disconnected.")

        // Back in range, the display rejoins with the pinned identities, without a code.
        simulation.setLinkDown(.display, false)
        #expect(try await views.press("Reconnect"))
        _ = try await waitFor { simulation.display?.phase == .live ? true : nil }
        compare(simulation.display?.reconnections == 1 && simulation.display?.codePrompt == nil, "the display rejoins without a code")
        compare(simulation.display?.snapshot?.cueTitle == "Tide line" && simulation.display?.snapshot?.isRunning == true,
                "the rejoined display shows the current cue, running")

        // Reset Demo, beside a collection and an item of the person's own.
        let notes = try await library.submit(
            .createCollection(draft: CollectionDraft(title: try EntityTitle("Field notes"))),
            requestID: RequestID(), authority: .userAction, names: [:]
        )
        guard case .collection(let notesID)? = notes.receipt.changes.first?.entity else {
            Issue.record("Expected a new collection")
            return
        }
        _ = try await library.submit(
            .createItem(draft: ItemDraft(in: notesID, title: try EntityTitle("Graphite stick"))),
            requestID: RequestID(), authority: .userAction, names: [:]
        )
        let reader = try await SQLiteOperationStore(url: storeURL)
        let userBefore = (try await reader.collections().filter { $0.namespace == .user }, try await reader.items(in: nil).filter { $0.namespace == .user })
        let reset = try #require(await library.resetDemo())
        await simulation.syncFromStore()
        _ = try await waitFor { simulation.display?.snapshot?.isRunning == false ? true : nil }
        compare(reset.receipt.changes.map(\.entity) == [.session(LocalConstellation.showSessionID)] && reset.receipt.removed.isEmpty,
                "Reset Demo changes only the show's session")
        compare(reset.receipt.summary.hasSuffix("paused 1 session."), "Reset Demo says it paused the session")
        let userAfter = (try await reader.collections().filter { $0.namespace == .user }, try await reader.items(in: nil).filter { $0.namespace == .user })
        compare(userAfter.0 == userBefore.0 && userAfter.1 == userBefore.1 && userAfter.1.count == 1, "the person's collection and item are unchanged")
        let resetPicture = try render(simulation)

        // The conductor restarts in a new epoch; the controller rejoins without a code.
        let firstEpoch = simulation.conductor?.epoch
        #expect(try await views.press("Restart the Conductor"))
        _ = try await waitFor { simulation.conductor?.epoch != firstEpoch ? true : nil }
        _ = try await waitFor { if case .disconnected = simulation.controller?.phase { true } else { nil } }
        #expect(try await views.press("Reconnect"))
        _ = try await waitFor { simulation.controller?.phase == .live ? true : nil }
        compare(simulation.controller?.epoch == simulation.conductor?.epoch && simulation.controller?.snapshot?.isRunning == false,
                "after the restart the controller rejoins in the new epoch and sees the show paused")

        #expect(comparisons == 22, "every check above is counted")
        let seed = try #require(Bundle.main.url(forResource: "seed", withExtension: "json"))
        let record = try EvidenceRecord(
            subject: "LAB-019",
            check: Self.check,
            date: started,
            provenance: .current,
            execution: .fixture,
            inputs: [
                "cue-sheet:app-bundle@sha256:\(ContentDigest.sha256(try Self.cueSheetData()).hex)",
                "seed:app-bundle@sha256:\(ContentDigest.sha256(try Data(contentsOf: seed)).hex)",
                "session:\(LocalConstellation.showSessionID)",
            ],
            steps: [
                "xcodebuild -scheme LabMac-Core -only-testing:LabMacTests/ConstellationHostEvidenceTests test",
                "A fresh SQLite store in the app container, seeded by the host's first run; ConstellationSimulation over the host's LabLibrary",
                "The simulation's controller, display, and conductor views hosted in the app and pressed through the accessibility press action",
                "Unpaired Device Tries to Join",
                "Ask to Join on the controller, then the display: the code read from the conductor, typed through the model, Allow pressed",
                "The controller's Next, then Ask to Start, and Allow at the conductor",
                "Walk Out of Range on the controller, the conductor's Next Cue, Bring Back in Range, the controller's Next",
                "The display's link taken down in both directions for 8 s and more, then brought back, and Reconnect",
                "A collection and an item created as the person's own, then Reset Demo",
                "Restart the Conductor, then the controller's Reconnect",
            ],
            outcome: differences.isEmpty
                ? .passed(observed: "All \(comparisons) checks held. " + observations.joined(separator: " ") + " The display rejoined without a code. Reset Demo paused the show and changed nothing else; the person's collection and item were unchanged. After a restart the controller rejoined in the new epoch.")
                : .failed(observed: "\(differences.count) of \(comparisons) checks failed: " + differences.joined(separator: "; ") + "."),
            limitations: [
                "Fixture path: hosted tests in the sandboxed Mac app on the development Mac, on a fresh store seeded from the bundled demo seed. It supports implemented at most.",
                "The simulation is the declared fallback: the conductor, the controller, and the display run in this one process, joined by the in-process loopback, which carries the sealed frames a network would. No network, Bonjour browse, or local network permission took part.",
                "The views were pressed through the accessibility press action; no pointer, keyboard, or VoiceOver was used. The pairing code was typed through the model.",
                "The CoreLocal Mac build ran; the Companions build and its live controls did not.",
                "No physical iPhone, iPad, or Apple TV, and no simulator, ran in this check.",
            ]
        )
        #expect(differences.isEmpty)
        Attachment.record(try Self.json(record), named: "LAB-019-local-constellation-host-qualification.json")
        Attachment.record(runningPicture, named: "lab-019-mac-host-running.png")
        Attachment.record(stalePicture, named: "lab-019-mac-host-display-stale.png")
        Attachment.record(resetPicture, named: "lab-019-mac-host-after-reset.png")
        #expect(record.result == .passed)
        #expect(record.provenance.xcodeBuild != "unknown" && record.provenance.sdkName.hasPrefix("macosx"))
        #expect(record.supportedState == .implemented)
    }

    // MARK: Support

    private func waitFor<Value>(_ timeout: Duration = .seconds(5), _ read: @MainActor () -> Value?) async throws -> Value {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let value = read() { return value }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out")
        throw CancellationError()
    }

    /// The display and the conductor as the Mac app draws them, offscreen, as PNG bytes.
    private func render(_ simulation: ConstellationSimulation) throws -> Data {
        let view = HStack(alignment: .top, spacing: 24) {
            SimulatedDeviceSection(model: simulation, role: .display).frame(width: 420)
            ConductorPanel(state: simulation.conductor, actions: simulation.conductorActions, trueOffsets: simulation.trueOffsets)
                .frame(width: 520)
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderFrontRegardless()
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        host.display()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    /// The cue sheet as the app bundles it, in the LocalConstellation module's resource bundle.
    private static func cueSheetData() throws -> Data {
        let bundles = [Bundle.main.resourceURL].compactMap { $0 }.flatMap { root in
            (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        }.filter { $0.lastPathComponent.hasSuffix("LocalConstellation.bundle") }
        let bundle = try #require(bundles.first.flatMap(Bundle.init(url:)), "the LocalConstellation resource bundle")
        return try Data(contentsOf: try #require(bundle.url(forResource: "cue-sheet", withExtension: "json")))
    }

    private static func json(_ record: EvidenceRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return String(decoding: try encoder.encode(record), as: UTF8.self) + "\n"
    }
}
