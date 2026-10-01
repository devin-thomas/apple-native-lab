#if os(macOS)
import Foundation
import LocalConstellation
import PeerSession
import PeerSessionNetwork
import Testing

/// LAB-019-B's optional two-endpoint demonstration, the Mac's side: this test process conducts a
/// show on a TCP listener bound to the loopback interface, with nothing advertised, and the Apple
/// TV app in a tvOS simulator on the same Mac joins it as the display
/// (`ConstellationTwoEndpointTests` in LabTVTests). Two processes, two monotonic clocks, the
/// Network framework, and the sealed session; no Bonjour and no network beyond loopback.
///
/// The two sides meet through files in one folder: the listener's port, then the code the
/// conductor shows, which the display's side types as its person would, then "matched", after
/// which this side allows the device, as the person at the conductor would. Runs only when the
/// folder is named, alongside the Apple TV side:
///
///     LAB_019_DEMO_DIR=<folder> swift test --package-path Packages/LabFeatures \
///       --filter ConstellationTwoEndpointConductor
@Suite struct ConstellationTwoEndpointConductor {
    static let folder = ProcessInfo.processInfo.environment["LAB_019_DEMO_DIR"]

    @Test(.enabled(if: folder != nil), .timeLimit(.minutes(30)))
    func theMacConductsADisplayInAnotherProcessOverLoopbackTCP() async throws {
        let exchange = DemoExchange(folder: URL(filePath: try #require(Self.folder), directoryHint: .isDirectory))
        var report: [String] = []
        let listener = try LANListener(scope: .loopbackOnly, serviceType: LocalConstellation.serviceType, name: nil)
        let port = try await eventually { listener.port.flatMap { $0 == 0 ? nil : $0 } }
        let host = await ShowHost(
            configuration: .init(identity: LocalIdentity(name: "Mac conductor (test process)"), trust: InMemoryTrustStore()),
            sheet: try CueSheet.bundled(), backend: ServiceShowBackend.inMemory()
        )
        await host.conductor.listen(on: listener)
        await host.conductor.startTicking()
        await host.conductor.openPairing(for: .seconds(1_500), attempts: 3)
        try exchange.write("port", "\(port)")

        // Pairing: show the code, and allow only after the display's side says it matched.
        let request = try await eventually(.seconds(1_500)) { await host.conductor.state.pairingRequest }
        try exchange.write("code", request.code.digits)
        _ = try await eventually(.seconds(120)) { exchange.read("matched") }
        await host.conductor.answerPairing(allow: true)
        let paired = try await eventually(.seconds(30)) {
            await host.conductor.state.peers.first { $0.role == .display && $0.isSynchronized }
        }
        report.append("Paired \(paired.identity.name) as the display: its side typed the code this side showed, and this side allowed it after the display said it matched.")

        // The conductor's person moves to cue 3 and starts the show.
        _ = await host.move(.goTo(cue: 2))
        let started = await host.setRunning(true)
        try exchange.write("moved", "Tide line, running")
        _ = try await eventually(.seconds(60)) { exchange.read("saw") }
        report.append("Moved to cue 3 and started the show: \(started.receipt?.admitted.adapter.rawValue ?? "no receipt").")

        // Clock estimates between the two processes' monotonic clocks.
        let measured = try await eventually(.seconds(30)) {
            await host.conductor.state.peers.first { $0.role == .display }?.clock.flatMap { $0.sampleCount >= 6 ? $0 : nil }
        }
        report.append("The conductor's estimate of the display's clock: offset \(measured.offset.millisecondsText), uncertainty \(measured.uncertainty.millisecondsText), best round trip \(measured.roundTrip.millisecondsText), from \(measured.sampleCount) round trips.")
        try exchange.write("measured", "")

        // The display drops its link without a goodbye, then resumes without a code.
        _ = try await eventually(.seconds(60)) {
            if case .disconnected = await host.conductor.state.peers.first(where: { $0.role == .display })?.presence { true } else { nil }
        }
        report.append("The display's link closed without a goodbye; the roster showed it Disconnected.")
        try exchange.write("saw-disconnect", "")
        let back = try await eventually(.seconds(60)) {
            await host.conductor.state.peers.first { $0.role == .display && $0.reconnections == 1 && $0.presence == .live }
        }
        report.append("It resumed without a code: \(back.reconnections) reconnection, Live.")

        // An identity this conductor never paired asks to resume from the display's process.
        _ = try await eventually(.seconds(60)) { exchange.read("stranger-done") }
        let events = await host.conductor.state.events.map(\.text)
        report.append(events.contains { $0.contains("unpaired device tried to rejoin") }
            ? "An unpaired identity was told to pair first, before any session data."
            : "No unpaired attempt was seen.")
        report.append("Admitted \(back.admittedCommands), refused \(back.refusedCommands); reliable gaps \(back.counters.reliableGaps), samples lost \(back.counters.replaceableMissing), refused frames \(back.counters.refusedFrames).")

        // The conductor ends the session; the display says so.
        await host.conductor.stop()
        listener.stop()
        try exchange.write("conductor-report", report.joined(separator: "\n"))
        _ = try await eventually(.seconds(60)) { exchange.read("done") }
    }
}

/// Files in one folder that the two processes write and read. Each file is written whole, then
/// renamed into place, so a reader never sees half of one.
struct DemoExchange: Sendable {
    let folder: URL

    func write(_ name: String, _ text: String) throws {
        let temporary = folder.appending(path: ".\(name).partial")
        try Data(text.utf8).write(to: temporary)
        _ = try? FileManager.default.removeItem(at: folder.appending(path: name))
        try FileManager.default.moveItem(at: temporary, to: folder.appending(path: name))
    }

    func read(_ name: String) -> String? {
        (try? Data(contentsOf: folder.appending(path: name))).map { String(decoding: $0, as: UTF8.self) }
    }
}
#endif
