import Foundation
@testable import PeerSession
import Testing

/// A small vocabulary for the session layer's own tests: a counter a controller changes, a level
/// a controller samples, and a display that only watches.
enum Tally: SessionVocabulary {
    enum Command: WirePayload {
        case add(Int)
        case set(Int)
        /// Needs the person at the conductor: held until resolved.
        case ask(Int)

        static let wireKeys: Set<String> = ["add", "set", "ask"]

        var isValid: Bool {
            switch self {
            case .add(let amount): (-10...10).contains(amount)
            case .set(let value), .ask(let value): (0...1_000).contains(value)
            }
        }

        enum CodingKeys: String, CodingKey { case add, set, ask }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.allKeys.count == 1, let key = container.allKeys.first else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "One command"))
            }
            let value = try container.decode(Int.self, forKey: key)
            switch key {
            case .add: self = .add(value)
            case .set: self = .set(value)
            case .ask: self = .ask(value)
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .add(let value): try container.encode(value, forKey: .add)
            case .set(let value): try container.encode(value, forKey: .set)
            case .ask(let value): try container.encode(value, forKey: .ask)
            }
        }
    }

    struct Sample: WirePayload {
        let level: Double
        static let wireKeys: Set<String> = ["level"]
        var isValid: Bool { level.isFinite && (0...1).contains(level) }
    }

    struct Snapshot: WirePayload {
        let value: Int
        static let wireKeys: Set<String> = ["value"]
        var isValid: Bool { value >= 0 }
    }

    static let offer = ProtocolOffer(name: "native-lab.tally", versions: 1...1)
    static func rolesAllowed(toSend command: Command) -> Set<PeerRole> { [.controller, .conductor] }
    static let sampleSenders: Set<PeerRole> = [.controller]
    static let sampleReceivers: Set<PeerRole> = [.display]

    static func decide(_ command: Command, _ state: Snapshot, _ origin: CommandOrigin) -> CommandDecision<Snapshot> {
        switch command {
        case .add(let amount):
            let next = state.value + amount
            return next >= 0 ? .apply(Snapshot(value: next), summary: "Added \(amount).") : .refuse(summary: "The tally cannot go below zero.")
        case .set(let value):
            return .apply(Snapshot(value: value), summary: "Set to \(value).")
        case .ask(let value):
            return .hold(summary: "Set the tally to \(value)?")
        }
    }
}

/// A conductor, a controller, and a display on one loopback hub, each with its own manual clock.
struct Rig {
    let hub: LoopbackHub
    let conductorClock = ManualPeerClock(start: PeerInstant(nanoseconds: 5_000_000_000))
    let controllerClock = ManualPeerClock(start: PeerInstant(nanoseconds: 900_000_000_000))
    let displayClock = ManualPeerClock(start: PeerInstant(nanoseconds: 42_000_000))
    let conductorIdentity = LocalIdentity(name: "Studio Mac")
    let conductorTrust = InMemoryTrustStore()
    let conductor: Conductor<Tally>
    let controller: Client<Tally>
    let display: Client<Tally>
    let wire: WireLog
    let controllerWire = WireLog()
    let displayWire = WireLog()

    init(timing: SessionTiming = .standard, epoch: SessionEpoch = SessionEpoch(rawValue: 7)) {
        let wire = WireLog()
        self.wire = wire
        hub = LoopbackHub(hostLabel: "conductor", tap: { wire.appendBytes($0) })
        conductor = Conductor(
            configuration: .init(
                identity: conductorIdentity, trust: conductorTrust, clock: conductorClock, timing: timing,
                epoch: epoch, handshakeTimeout: .seconds(5), wireRecord: { wire.append($0) }
            ),
            initialState: Tally.Snapshot(value: 0),
            decide: Tally.decide
        )
        controller = Client(configuration: .init(
            identity: LocalIdentity(name: "Pocket phone"), role: .controller, trust: InMemoryTrustStore(),
            clock: controllerClock, timing: timing, handshakeTimeout: .seconds(5), wireRecord: { [controllerWire] in controllerWire.append($0) }
        ))
        display = Client(configuration: .init(
            identity: LocalIdentity(name: "Living room TV"), role: .display, trust: InMemoryTrustStore(),
            clock: displayClock, timing: timing, handshakeTimeout: .seconds(5), wireRecord: { [displayWire] in displayWire.append($0) }
        ))
        conductor.listenNow(on: hub)
    }

    /// Pairs a client: the conductor opens pairing, the client dials, the person types the code
    /// the conductor shows, and allows it there.
    @discardableResult
    func pair(_ client: Client<Tally>, label: String) async throws -> (joiner: LoopbackConnection, host: LoopbackConnection) {
        await conductor.openPairing()
        let ends = hub.dialBothEnds(from: label)
        let connection = ends.joiner
        async let joined: Void = client.pair(over: connection)
        let request = try await eventually { await conductor.state.pairingRequest }
        _ = try await eventually { await client.state.codePrompt }
        #expect(await client.submitCode(request.code.digits))
        await conductor.answerPairing(allow: true)
        try await joined
        _ = try await eventually { await client.state.phase == .live ? true : nil }
        return ends
    }

    /// Advances every clock together, as real time passes for all three devices.
    func advance(_ duration: Duration) {
        for clock in [conductorClock, controllerClock, displayClock] { clock.advance(by: duration) }
    }

    func tickAll() async {
        await conductor.tick()
        await controller.tick()
        await display.tick()
    }
}

extension Conductor {
    nonisolated func listenNow(on listener: any PeerListener) {
        Task { await self.listen(on: listener) }
    }
}

/// Every record and every raw byte sequence the rig's links produced.
final class WireLog: Sendable {
    private let records = Mutex<[WireRecord]>([])
    private let bytes = Mutex<[Data]>([])

    func append(_ record: WireRecord) { records.withLock { $0.append(record) } }
    func appendBytes(_ data: Data) { bytes.withLock { $0.append(data) } }
    var all: [WireRecord] { records.withLock { $0 } }
    var rawFrames: [Data] { bytes.withLock { $0 } }
}

import Synchronization

struct TimedOut: Error {}

/// Polls until `condition` returns a value, for up to `timeout` of real time.
func eventually<Value: Sendable>(
    _ timeout: Duration = .seconds(5),
    _ condition: @Sendable () async -> Value?
) async throws -> Value {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if let value = await condition() { return value }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for a condition")
    throw TimedOut()
}

/// Waits until `condition` holds.
func until(_ timeout: Duration = .seconds(5), _ condition: @Sendable () async -> Bool) async throws {
    _ = try await eventually(timeout) { await condition() ? true : nil }
}
