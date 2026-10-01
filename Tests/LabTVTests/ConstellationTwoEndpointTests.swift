import Foundation
import LabSupport
import LocalConstellation
import PeerSession
import PeerSessionNetwork
import Testing
@testable import NativeLabTV

/// LAB-019-B's optional two-endpoint demonstration, the Apple TV's side: the Apple TV app in a
/// tvOS simulator joins, as the display, a show that a test process on the same Mac conducts
/// (`ConstellationTwoEndpointConductor` in PeerSessionNetworkTests). They connect over TCP on the
/// loopback interface only, with nothing advertised or browsed, and every frame after the
/// handshake is sealed. The code the conductor shows reaches this side through a file, and this
/// side types it as its person would.
///
/// Runs only when the exchange folder is named. Start the Mac side first, then:
///
///     xcodebuild … -scheme LabTV -destination 'id=<tvOS simulator>' \
///       -only-testing:LabTVTests/ConstellationTwoEndpointTests \
///       TEST_RUNNER_LAB_019_DEMO_DIR=<folder> -resultBundlePath <bundle> test
///
/// It attaches an `EvidenceRecord` on the simulator path that includes the Mac side's report.
@MainActor
@Suite(.serialized) struct ConstellationTwoEndpointTests {
    nonisolated static let folder = ProcessInfo.processInfo.environment["LAB_019_DEMO_DIR"]
    nonisolated static let check = "Local Constellation between two processes on one Mac: the Apple TV app in the tvOS simulator joins, as the display, a show a macOS test process conducts, over TCP on the loopback interface, pairing with the code, following the show, rejoining without a code, and refusing an unpaired identity"

    @Test(.enabled(if: folder != nil), .timeLimit(.minutes(30)))
    func theAppleTVDisplayJoinsAMacConductorOverLoopbackTCP() async throws {
        let started = Date()
        let folder = URL(filePath: try #require(Self.folder), directoryHint: .isDirectory)
        var observations: [String] = []
        var differences: [String] = []
        func compare(_ same: Bool, _ what: String) {
            #expect(same, "\(what)")
            if same { observations.append(what) } else { differences.append(what) }
        }

        let portText = try await poll(.seconds(1_500)) { read(folder, "port") }
        let port = try #require(UInt16(portText))
        let trust = InMemoryTrustStore()
        let display = Client<Constellation>(configuration: .init(
            identity: LocalIdentity(name: "Apple TV simulator display"), role: .display, trust: trust
        ))
        await display.startTicking()

        // Pair: the conductor shows a code; this side types it, then says it matched.
        let connection = LANEndpoint.loopback(port: port).connect(scope: .loopbackOnly)
        let joining = Task { () async -> HandshakeFailure? in
            do { try await display.pair(over: connection); return nil } catch { return error as? HandshakeFailure }
        }
        _ = try await poll(.seconds(60)) { await display.state.codePrompt }
        let code = try await poll(.seconds(60)) { read(folder, "code") }
        compare(await display.submitCode(code), "the conductor's code is six digits and is typed here")
        try write(folder, "matched", "")
        compare(await joining.value == nil, "the pairing completes once the conductor's person allows it")
        _ = try await poll(.seconds(30)) { await display.state.phase == .live ? true : nil }
        let host = await display.state.host
        compare(host?.name == "Mac conductor (test process)", "the display pinned the Mac conductor's identity")

        // The conductor moves to cue 3 and starts the show.
        _ = try await poll(.seconds(60)) { read(folder, "moved") }
        let shown = try await poll(.seconds(30)) { () -> ShowSnapshot? in
            let snapshot = await display.state.snapshot
            return snapshot?.cueTitle == "Tide line" && snapshot?.isRunning == true ? snapshot : nil
        }
        compare(shown.cue == 2, "the display shows cue 3, Tide line, running")
        try write(folder, "saw", "")

        _ = try await poll(.seconds(60)) { read(folder, "measured") }
        let clock = try await poll(.seconds(30)) { await display.state.clock.flatMap { $0.sampleCount >= 6 ? $0 : nil } }
        observations.append("This side's estimate of the conductor's clock: offset \(clock.offset.millisecondsText), uncertainty \(clock.uncertainty.millisecondsText), best round trip \(clock.roundTrip.millisecondsText).")

        // Leave without a goodbye, as out of range; then resume without a code.
        await display.vanish()
        _ = try await poll(.seconds(60)) { read(folder, "saw-disconnect") }
        try await display.resume(over: LANEndpoint.loopback(port: port).connect(scope: .loopbackOnly))
        _ = try await poll(.seconds(30)) { await display.state.phase == .live ? true : nil }
        let resumed = await display.state
        compare(resumed.reconnections == 1 && resumed.codePrompt == nil, "the display resumes without a code")

        // An identity the conductor never paired, with the conductor pinned, asks to resume.
        let strangerTrust = InMemoryTrustStore()
        await strangerTrust.pin(PinnedPeer(identity: try #require(host), roles: [.conductor], pinnedAt: .now))
        let stranger = Client<Constellation>(configuration: .init(
            identity: LocalIdentity(name: "Unpaired device"), role: .display, trust: strangerTrust
        ))
        var refusal: HandshakeFailure?
        do {
            try await stranger.resume(over: LANEndpoint.loopback(port: port).connect(scope: .loopbackOnly), to: try #require(host).id)
        } catch {
            refusal = error as? HandshakeFailure
        }
        let strangerSaw = await stranger.state
        compare(refusal == .refused(.pairingRequired, theirOffer: Constellation.offer) && strangerSaw.snapshot == nil,
                "an unpaired identity is told to pair first and receives no session data")
        await stranger.shutdown()
        try write(folder, "stranger-done", "")

        // The conductor ends the session.
        let report = try await poll(.seconds(120)) { read(folder, "conductor-report") }
        _ = try await poll(.seconds(30)) { if case .disconnected = await display.state.phase { true } else { nil } }
        compare(await display.state.phase == .disconnected(reason: "The conductor ended the session."), "the display says the conductor ended the session")
        await display.shutdown()
        try write(folder, "done", "")

        let record = try EvidenceRecord(
            subject: "LAB-019",
            check: Self.check,
            date: started,
            provenance: .current,
            execution: try Execution(observing: .current),
            inputs: [try ConstellationTVEvidenceTests.cueSheetInput(), "transport:tcp-loopback"],
            steps: [
                "On one Mac: LAB_019_DEMO_DIR=<folder> swift test --package-path Packages/LabFeatures --filter ConstellationTwoEndpointConductor, the conductor, on a LANListener with LANScope.loopbackOnly and no Bonjour name",
                "xcodebuild -scheme LabTV -destination <tvOS simulator> -only-testing:LabTVTests/ConstellationTwoEndpointTests TEST_RUNNER_LAB_019_DEMO_DIR=<folder> test, the display, connecting to LANEndpoint.loopback(port:)",
                "The port and the code passed through files in the folder; the display's side typed the code and wrote \"matched\" before the conductor's side allowed it",
                "The conductor moved to cue 3 and started the show",
                "The display closed its link without a goodbye, then resumed",
                "A second identity in the Apple TV app asked to resume",
                "The conductor stopped",
            ],
            outcome: differences.isEmpty
                ? .passed(observed: observations.joined(separator: " ") + " The Mac side reported: " + report.replacingOccurrences(of: "\n", with: " "))
                : .failed(observed: "\(differences.count) checks failed: " + differences.joined(separator: "; ") + "."),
            limitations: [
                "Simulator path on the Apple TV side: the Apple TV app's hosted tests in the tvOS simulator. The conductor was a macOS test process on the same Mac, not the Mac app. It supports implemented at most.",
                "Loopback only: TCP on the Mac's loopback interface, with nothing advertised or browsed. No Bonjour, no Wi-Fi or Ethernet, no local network permission prompt, and no physical Apple TV, iPhone, or Mac took part. Round trips over loopback are not network measurements.",
                "The code reached the display through a file, standing in for a person who reads it from one screen and types it on another; the conductor's Allow was given by the test after the display said it matched.",
                "The display's views and the remote did not take part: the joiner ran in the app's test process.",
            ]
        )
        #expect(differences.isEmpty)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        Attachment.record(String(decoding: try encoder.encode(record), as: UTF8.self) + "\n", named: "LAB-019-local-constellation-two-endpoint-loopback.json")
        #expect(record.path == .simulator)
    }

    private func poll<Value: Sendable>(_ timeout: Duration, _ read: @MainActor () async -> Value?) async throws -> Value {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let value = await read() { return value }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Timed out")
        throw CancellationError()
    }

    private func read(_ folder: URL, _ name: String) -> String? {
        (try? Data(contentsOf: folder.appending(path: name))).map { String(decoding: $0, as: UTF8.self) }
    }

    private func write(_ folder: URL, _ name: String, _ text: String) throws {
        let temporary = folder.appending(path: ".\(name).partial")
        try Data(text.utf8).write(to: temporary)
        _ = try? FileManager.default.removeItem(at: folder.appending(path: name))
        try FileManager.default.moveItem(at: temporary, to: folder.appending(path: name))
    }
}
