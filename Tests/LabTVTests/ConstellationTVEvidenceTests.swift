import CryptoKit
import Foundation
import LabSupport
import LocalConstellation
import PeerSession
import Testing
@testable import NativeLabTV

/// LAB-019-B in the built Apple TV app, in the tvOS simulator: the declared fallback, the whole
/// simulation on this Apple TV with the show stored in memory, as `TVConstellationModel` runs it.
/// An unpaired device is refused, the display and the controller pair with the code, a stale
/// command is reconciled, the silent display goes stale on both sides and recovers, and a peer's
/// start commits through the operation service as the authorized peer. Nothing browses or
/// advertises.
///
/// It attaches an `EvidenceRecord` on the simulator path, with the toolchain read from this app
/// bundle. To keep it, run the test with a result bundle and export the attachment:
///
///     xcodebuild … -scheme LabTV -destination 'id=<tvOS simulator>' \
///       -only-testing:LabTVTests/ConstellationTVEvidenceTests -resultBundlePath <bundle> \
///       LAB_SOURCE_REVISION=<sha> test
///     xcrun xcresulttool export attachments --path <bundle> --output-path <folder>
@MainActor
@Suite(.serialized) struct ConstellationTVEvidenceTests {
    nonisolated static let check = "Local Constellation's fallback in the Apple TV app in the tvOS simulator: an unpaired device is refused, the display and the controller pair with the code, a stale command is reconciled, a silent display goes stale on both sides and recovers, and an allowed start commits as the authorized peer"

    @Test func theFallbackRunsTheInteractionOnAppleTV() async throws {
        let started = Date()
        var differences: [String] = []
        var comparisons = 0
        func compare(_ same: Bool, _ what: String) {
            comparisons += 1
            #expect(same, "\(what)")
            if !same { differences.append(what) }
        }

        let model = TVConstellationModel()
        await model.startSimulation()
        let simulation = try #require(model.simulation)

        await simulation.strangerTriesToJoin()
        compare(simulation.lastOutcome?.hasSuffix("It received no session data.") == true, "an unpaired device is refused before any session data")

        for role in [PeerRole.display, .controller] {
            let pairing = Task { await simulation.pair(role) }
            let request = try await wait { simulation.conductor?.pairingRequest }
            _ = try await wait { simulation.state(of: role)?.codePrompt }
            #expect(await simulation.submitCode(request.code.digits, on: role))
            await simulation.answerPairing(allow: true)
            await pairing.value
            _ = try await wait { simulation.state(of: role)?.phase == .live ? true : nil }
        }
        compare(simulation.conductor?.peers.count == 2, "the display and the controller pair with the code")

        await simulation.send(.next)
        _ = try await wait { simulation.display?.snapshot?.cueTitle == "Lanterns" ? true : nil }
        compare(simulation.display?.snapshot?.cue == 1, "the display follows the controller's Next")

        // A stale command: the controller is out of range while the conductor moves.
        simulation.setLinkDown(.controller, true)
        await simulation.conductorMove(.goTo(cue: 4))
        simulation.setLinkDown(.controller, false)
        let sentBefore = simulation.controller?.commands.count ?? 0
        await simulation.send(.next)
        let stale = try await wait { () -> CommandResult? in
            guard let commands = simulation.controller?.commands, commands.count > sentBefore,
                  case .finished(let result) = commands[commands.count - 1].stage else { return nil }
            return result
        }
        compare(stale.disposition == .stale, "a Next from an older revision is refused as stale")
        _ = try await wait { simulation.controller?.snapshot?.cueTitle == "Ember" ? true : nil }
        compare(simulation.conductor?.snapshot.cueTitle == "Ember", "nothing moved, and the controller is reconciled to Ember")

        // The display walks out of range; both sides show it stale, then it comes back.
        simulation.setLinkDown(.display, true)
        let displayStale = (try? await wait(.seconds(6)) { simulation.display?.phase == .stale ? true : nil }) != nil
        let rosterStale = (try? await wait(.seconds(3)) {
            if case .stale = simulation.conductor?.peers.first(where: { $0.role == .display })?.presence { true } else { nil }
        }) != nil
        compare(displayStale && rosterStale, "the silent display and the conductor's roster both read Stale")
        simulation.setLinkDown(.display, false)
        _ = try await wait(.seconds(3)) { simulation.display?.phase == .live ? true : nil }
        compare(simulation.conductor?.peers.first { $0.role == .display }?.presence == .live, "back in range, both read Live")

        // A peer's start, allowed at the conductor, commits through the in-memory operation service.
        await simulation.send(.start)
        let pending = try await wait { simulation.conductor?.pending.first }
        await simulation.allow(pending.commandID)
        _ = try await wait { simulation.display?.snapshot?.isRunning == true ? true : nil }
        compare(simulation.lastOutcome == "Started at Controller (simulated phone)'s request, allowed at the conductor.",
                "the allowed start commits and the display shows it running")
        compare(model.joiner == nil, "nothing was browsed")
        await simulation.stop()

        #expect(comparisons == 9, "every check above is counted")
        let record = try EvidenceRecord(
            subject: "LAB-019",
            check: Self.check,
            date: started,
            provenance: .current,
            execution: try Execution(observing: .current),
            inputs: [try Self.cueSheetInput(), "session:\(LocalConstellation.showSessionID)"],
            steps: [
                "xcodebuild -scheme LabTV -destination <tvOS simulator> -only-testing:LabTVTests/ConstellationTVEvidenceTests test",
                "TVConstellationModel starts the simulation with the show stored in memory, as the Apple TV app does",
                "An unpaired device tries to rejoin",
                "The display, then the controller, pair: the code read from the conductor's request and submitted through the model, then Allow",
                "The controller's Next; the controller out of range while the conductor goes to cue 5; its Next back in range",
                "The display's link down in both directions for over 2 s, then back",
                "The controller's start request, allowed at the conductor",
            ],
            outcome: differences.isEmpty
                ? .passed(observed: "All \(comparisons) checks held. The unpaired device received no session data; the display showed Lanterns, then Ember; a stale Next was answered \"\(stale.summary)\"; the silent display read Stale on both sides and Live again in range; the allowed start committed and the display showed the show running.")
                : .failed(observed: "\(differences.count) of \(comparisons) checks failed: " + differences.joined(separator: "; ") + "."),
            limitations: [
                "Simulator path: the Apple TV app's hosted tests in the tvOS simulator on the development Mac. It supports implemented at most.",
                "The simulation is the declared fallback: the conductor, the controller, and the display run in this one app, joined by the in-process loopback. No network, Bonjour, or local network permission took part.",
                "Driven through the simulation's model, not the remote; the screen is driven with the remote by ConstellationRemoteUITests.",
                "The show was stored in memory, as the Apple TV app stores it; the Apple TV has no lab store.",
                "No physical Apple TV ran.",
            ]
        )
        #expect(differences.isEmpty)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        Attachment.record(String(decoding: try encoder.encode(record), as: UTF8.self) + "\n", named: "LAB-019-local-constellation-tvos-simulator.json")
        #expect(record.path == .simulator)
        #expect(record.supportedState == .implemented)
    }

    /// The cue sheet as this app bundles it, by its SHA-256, from the LocalConstellation module's
    /// resource bundle.
    nonisolated static func cueSheetInput() throws -> String {
        let root = try #require(Bundle.main.resourceURL)
        let bundles = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasSuffix("LocalConstellation.bundle") }
        let bundle = try #require(bundles.first.flatMap(Bundle.init(url:)), "the LocalConstellation resource bundle")
        let data = try Data(contentsOf: try #require(bundle.url(forResource: "cue-sheet", withExtension: "json")))
        return "cue-sheet:app-bundle@sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func wait<Value>(_ timeout: Duration = .seconds(10), _ read: @MainActor () -> Value?) async throws -> Value {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let value = read() { return value }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out")
        throw CancellationError()
    }
}
