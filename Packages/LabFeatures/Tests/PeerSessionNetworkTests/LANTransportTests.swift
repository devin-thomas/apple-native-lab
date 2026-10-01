#if !os(watchOS)
import CryptoKit
import Foundation
import PeerSession
@testable import PeerSessionNetwork
import Synchronization
import Testing

/// LAB-019: the Network framework adapter carries the session over TCP on this Mac's loopback
/// interface, and the frames it carries are the same envelopes the in-process loopback carries.
/// Nothing here leaves the loopback interface: `LANScope.loopbackOnly` requires it.
@Suite(.serialized) struct LANTransportTests {
    @Test func aConductorAndAControllerPairAndCommandOverTCP() async throws {
        let outcome = try await Script.run(over: .network)
        #expect(outcome.finalValue == 12)
        #expect(outcome.controller.contains { $0.kind == "snapshot" })
    }

    @Test func theNetworkCarriesTheSameEnvelopesAsTheLoopback() async throws {
        let loopback = try await Script.run(over: .loopback)
        let network = try await Script.run(over: .network)
        #expect(loopback.controller.count == network.controller.count)
        #expect(loopback.controller == network.controller, "identical wire messages")
        #expect(loopback.display == network.display)
        #expect(loopback.finalValue == network.finalValue)
    }

    @Test func aListenerOnlyAcceptsLoopbackWhenScopedSoAndStops() async throws {
        let listener = try LANListener(scope: .loopbackOnly, serviceType: "_nativelab-lc._tcp", name: nil)
        let port = try await eventually { listener.port.flatMap { $0 == 0 ? nil : $0 } }
        #expect(port > 0)
        listener.stop()
        var statuses: [NetworkStatus] = []
        for await status in listener.statuses {
            statuses.append(status)
            if status == .stopped { break }
        }
        #expect(statuses.contains(.stopped))
    }

    @Test func aPolicyDeniedBonjourErrorIsReportedAsDenied() {
        #expect(NetworkStatus.from(.dns(-65570)) == .denied)
        #expect(NetworkStatus.from(.posix(.ECONNREFUSED)) != .denied)
    }
}

/// One fixed interaction, run over either transport with fixed keys, clocks, and message IDs.
enum Script {
    enum Transport { case loopback, network }

    /// What one side saw: each envelope's direction, kind, channel, sequence, sealed size, and
    /// plaintext.
    struct Seen: Hashable {
        let direction: String
        let kind: String
        let channel: Channel
        let sequence: UInt64
        let frameBytes: Int
        let plaintext: Data
    }

    struct Outcome {
        let controller: [Seen]
        let display: [Seen]
        let finalValue: Int
    }

    static func key(_ byte: UInt8) -> Curve25519.Signing.PrivateKey {
        try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: byte, count: 32))
    }

    static func counter(_ prefix: UInt8) -> @Sendable () -> MessageID {
        let next = Mutex<UInt64>(0)
        return {
            let value = next.withLock { $0 += 1; return $0 }
            var bytes = [UInt8](repeating: prefix, count: 8)
            withUnsafeBytes(of: value.bigEndian) { bytes.append(contentsOf: $0) }
            return MessageID(rawValue: UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                                                   bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])))
        }
    }

    static func run(over transport: Transport) async throws -> Outcome {
        let controllerLog = SeenLog()
        let displayLog = SeenLog()
        func recorder(_ log: SeenLog) -> @Sendable (WireRecord) -> Void {
            { record in
                log.append(Seen(
                    direction: record.direction.rawValue, kind: record.kind, channel: record.channel,
                    sequence: record.sequence, frameBytes: record.frameBytes, plaintext: record.plaintext
                ))
            }
        }
        let conductorIdentity = LocalIdentity(privateKey: key(1), name: "Studio Mac")
        let conductorTrust = InMemoryTrustStore()
        let controllerTrust = InMemoryTrustStore(), displayTrust = InMemoryTrustStore()
        let controllerIdentity = LocalIdentity(privateKey: key(2), name: "Pocket phone")
        let displayIdentity = LocalIdentity(privateKey: key(3), name: "Living room TV")
        // Pairing happened earlier; this script resumes, so no code is typed.
        await conductorTrust.pin(PinnedPeer(identity: controllerIdentity.identity, roles: [.controller], pinnedAt: .distantPast))
        await conductorTrust.pin(PinnedPeer(identity: displayIdentity.identity, roles: [.display], pinnedAt: .distantPast))
        await controllerTrust.pin(PinnedPeer(identity: conductorIdentity.identity, roles: [.conductor], pinnedAt: .distantPast))
        await displayTrust.pin(PinnedPeer(identity: conductorIdentity.identity, roles: [.conductor], pinnedAt: .distantPast))

        let conductor = Conductor<Tally>(
            configuration: .init(
                identity: conductorIdentity, trust: conductorTrust, clock: ManualPeerClock(),
                sessionID: LiveSessionID(rawValue: UUID(uuidString: "0C0C0C0C-0000-4000-8000-000000000019")!),
                epoch: SessionEpoch(rawValue: 19), makeMessageID: counter(0xC0)
            ),
            initialState: Tally.Snapshot(value: 0), decide: Tally.decide
        )
        let controller = Client<Tally>(configuration: .init(
            identity: controllerIdentity, role: .controller, trust: controllerTrust, clock: ManualPeerClock(),
            makeMessageID: counter(0xA0), wireRecord: recorder(controllerLog)
        ))
        let display = Client<Tally>(configuration: .init(
            identity: displayIdentity, role: .display, trust: displayTrust, clock: ManualPeerClock(),
            makeMessageID: counter(0xD0), wireRecord: recorder(displayLog)
        ))

        let dial: @Sendable (String) async throws -> any PeerConnection
        var listener: LANListener?
        switch transport {
        case .loopback:
            let hub = LoopbackHub(hostLabel: "Studio Mac")
            await conductor.listen(on: hub)
            dial = { label in hub.dial(from: label) }
        case .network:
            let lan = try LANListener(scope: .loopbackOnly, serviceType: "_nativelab-lc._tcp", name: nil)
            listener = lan
            await conductor.listen(on: lan)
            let port = try await eventually { lan.port.flatMap { $0 == 0 ? nil : $0 } }
            dial = { _ in LANEndpoint.loopback(port: port).connect(scope: .loopbackOnly) }
        }

        try await controller.resume(over: dial("phone"), to: conductorIdentity.id)
        try await until { await controller.state.phase == ClientPhase.live }
        try await display.resume(over: dial("tv"), to: conductorIdentity.id)
        try await until { await display.state.phase == ClientPhase.live }

        for amount in [1, 2] {
            let id = await controller.send(.add(amount))
            try await until { if case .finished = await controller.state.commands.first(where: { $0.id == id })?.stage { true } else { false } }
        }
        try await until { await display.state.revision == 2 }
        await conductor.perform(.set(12))
        try await until { await display.state.snapshot?.value == 12 }
        try await until { await controller.state.snapshot?.value == 12 }
        await controller.publish(Tally.Sample(level: 0.5))
        try await until { await display.state.samples.isEmpty == false }

        let value = await conductor.state.snapshot.value
        await controller.shutdown()
        await display.shutdown()
        await conductor.stop()
        listener?.stop()
        return Outcome(controller: controllerLog.all, display: displayLog.all, finalValue: value)
    }
}

final class SeenLog: Sendable {
    private let entries = Mutex<[Script.Seen]>([])
    func append(_ seen: Script.Seen) { entries.withLock { $0.append(seen) } }
    var all: [Script.Seen] { entries.withLock { $0 } }
}

enum Tally: SessionVocabulary {
    enum Command: WirePayload {
        case add(Int)
        case set(Int)
        static let wireKeys: Set<String> = ["add", "set"]
        var isValid: Bool { true }
    }

    struct Sample: WirePayload {
        let level: Double
        static let wireKeys: Set<String> = ["level"]
        var isValid: Bool { level.isFinite }
    }

    struct Snapshot: WirePayload {
        let value: Int
        static let wireKeys: Set<String> = ["value"]
        var isValid: Bool { true }
    }

    static let offer = ProtocolOffer(name: "native-lab.tally", versions: 1...1)
    static func rolesAllowed(toSend command: Command) -> Set<PeerRole> { [.controller, .conductor] }
    static let sampleSenders: Set<PeerRole> = [.controller]
    static let sampleReceivers: Set<PeerRole> = [.display]

    static func decide(_ command: Command, _ state: Snapshot, _ origin: CommandOrigin) -> CommandDecision<Snapshot> {
        switch command {
        case .add(let amount): .apply(Snapshot(value: state.value + amount), summary: "Added \(amount).")
        case .set(let value): .apply(Snapshot(value: value), summary: "Set to \(value).")
        }
    }
}

struct TimedOut: Error {}

func eventually<Value: Sendable>(_ timeout: Duration = .seconds(10), _ condition: @Sendable () async -> Value?) async throws -> Value {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if let value = await condition() { return value }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for a condition")
    throw TimedOut()
}

func until(_ timeout: Duration = .seconds(10), _ condition: @Sendable () async -> Bool) async throws {
    _ = try await eventually(timeout) { await condition() ? true : nil }
}
#endif
