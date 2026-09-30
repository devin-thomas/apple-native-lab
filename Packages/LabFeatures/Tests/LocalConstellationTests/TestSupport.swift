import Foundation
import LabDomain
@testable import LocalConstellation
import PeerSession
import Testing

/// A show over the loopback: the conductor's `ShowHost` on an in-memory operation service, and a
/// paired controller and display, all with manual clocks.
struct Stage {
    let backend = ServiceShowBackend.inMemory()
    let sheet = try! CueSheet.bundled()
    let hub = LoopbackHub(hostLabel: "conductor")
    let clock = ManualPeerClock(start: PeerInstant(nanoseconds: 1_000_000_000))
    let host: ShowHost
    let controller: Client<Constellation>
    let display: Client<Constellation>

    init() async {
        host = await ShowHost(
            configuration: .init(identity: LocalIdentity(name: "Studio Mac"), trust: InMemoryTrustStore(), clock: clock, epoch: SessionEpoch(rawValue: 19)),
            sheet: sheet, backend: backend
        )
        await host.conductor.listen(on: hub)
        controller = Client(configuration: .init(identity: LocalIdentity(name: "Pocket phone"), role: .controller, trust: InMemoryTrustStore(), clock: clock))
        display = Client(configuration: .init(identity: LocalIdentity(name: "Living room TV"), role: .display, trust: InMemoryTrustStore(), clock: clock))
    }

    @discardableResult
    func pair(_ client: Client<Constellation>) async throws -> (joiner: LoopbackConnection, host: LoopbackConnection) {
        await host.conductor.openPairing()
        let ends = hub.dialBothEnds(from: client.identity.name)
        async let joined: Void = client.pair(over: ends.joiner)
        let request = try await eventually { await host.conductor.state.pairingRequest }
        _ = try await eventually { await client.state.codePrompt }
        await client.submitCode(request.code.description)
        await host.conductor.answerPairing(allow: true)
        try await joined
        try await until { await client.state.phase == ClientPhase.live }
        return ends
    }

    func finished(_ id: MessageID, on client: Client<Constellation>) async throws -> CommandResult {
        try await eventually {
            if case .finished(let result) = await client.state.commands.first(where: { $0.id == id })?.stage { result } else { nil }
        }
    }
}

struct TimedOut: Error {}

func eventually<Value: Sendable>(_ timeout: Duration = .seconds(5), _ condition: @Sendable () async -> Value?) async throws -> Value {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if let value = await condition() { return value }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for a condition")
    throw TimedOut()
}

func until(_ timeout: Duration = .seconds(5), _ condition: @Sendable () async -> Bool) async throws {
    _ = try await eventually(timeout) { await condition() ? true : nil }
}

/// `Fixtures/LAB-019/` at the repository root, found from this source file.
enum HostileFixtures {
    static let folder: URL = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/LAB-019", directoryHint: .isDirectory)
}
