import Foundation
import LabDomain
import Observation
import PeerSession
import Synchronization

/// One frame in the simulation's wire log, as the conductor sent or received it.
public struct WireLine: Hashable, Sendable, Identifiable {
    public let id: UInt64
    public let outgoing: Bool
    public let peerName: String
    public let kind: String
    public let channel: Channel
    public let sequence: UInt64
    public let frameBytes: Int

    public var text: String {
        let arrow = outgoing ? "to" : "from"
        return "\(kind) \(arrow) \(peerName), \(channel.rawValue) #\(sequence), \(frameBytes) bytes sealed"
    }
}

/// The declared fallback: a conductor, a controller, and a display on this one device, joined by
/// the in-process loopback, which carries the same sealed frames a network would.
///
/// Everything a live session does happens here too: explicit pairing with a typed code, pinned
/// identities, role and version negotiation, reliable commands and replaceable pointer samples,
/// clock estimates against simulated device clocks, sequence gaps, staleness, reconnection, and a
/// peer's start or pause request that the person at the conductor allows before it commits
/// through the operation service. What it cannot show is a real network: its round trips are
/// microseconds, and nothing leaves the process.
@MainActor
@Observable
public final class ConstellationSimulation {
    /// Where the show's stored session lives in this simulation, for the page to say.
    public let storeDescription: String
    public private(set) var conductor: ConductorState<Constellation>?
    public private(set) var controller: ClientState<Constellation>?
    public private(set) var display: ClientState<Constellation>?
    public private(set) var wire: [WireLine] = []
    public private(set) var lastOutcome: String?
    public private(set) var isRunning = false
    /// Links the person took down, by role.
    public private(set) var linksDown: Set<PeerRole> = []
    /// Each simulated device's true clock offset from the conductor. Only a simulation knows this;
    /// the estimates in the roster have to find it.
    public let trueOffsets: [PeerRole: Duration] = [.controller: .milliseconds(1_850), .display: .milliseconds(-640)]

    private let backend: any ShowSessionBackend
    private let sheet: CueSheet
    private let baseClock = SystemPeerClock()
    private let conductorIdentity = LocalIdentity(name: "Conductor (this device)")
    private let conductorTrust = InMemoryTrustStore()
    private var host: ShowHost?
    private var hub: LoopbackHub?
    private var clients: [PeerRole: Client<Constellation>] = [:]
    private var connections: [PeerRole: (joiner: LoopbackConnection, host: LoopbackConnection)] = [:]
    private var tasks: [Task<Void, Never>] = []
    private let wireBuffer = WireBuffer()

    public init(backend: any ShowSessionBackend, storeDescription: String, sheet: CueSheet) {
        self.backend = backend
        self.storeDescription = storeDescription
        self.sheet = sheet
    }

    // MARK: Lifecycle

    /// Starts the conductor and creates the two simulated devices, unpaired.
    public func start() async {
        guard !isRunning else { return }
        isRunning = true
        await startConductor(epoch: .random())
        for role in [PeerRole.controller, .display] {
            let clock = OffsetPeerClock(base: baseClock, offset: trueOffsets[role] ?? .zero)
            let name = role == .controller ? "Controller (simulated phone)" : "Display (simulated TV)"
            let client = Client<Constellation>(configuration: .init(
                identity: LocalIdentity(name: name), role: role, trust: InMemoryTrustStore(), clock: clock
            ))
            clients[role] = client
            await client.startTicking()
            observe(client.states) { [weak self] state in
                if role == .controller { self?.controller = state } else { self?.display = state }
            }
            if role == .controller { controller = await client.state } else { display = await client.state }
        }
    }

    /// Ends every link and forgets every pairing. The show's stored session is left as it is.
    public func stop() async {
        for task in tasks { task.cancel() }
        tasks.removeAll()
        for client in clients.values { await client.shutdown() }
        await host?.conductor.stop()
        hub?.stop()
        clients.removeAll()
        connections.removeAll()
        host = nil
        hub = nil
        conductor = nil
        controller = nil
        display = nil
        wire.removeAll()
        linksDown.removeAll()
        isRunning = false
    }

    /// Starts over: new identities on the simulated devices, nothing paired.
    public func reset() async {
        await stop()
        lastOutcome = "The simulation started over. Nothing is paired."
        await start()
    }

    private func startConductor(epoch: SessionEpoch) async {
        let buffer = wireBuffer
        let hub = LoopbackHub(hostLabel: conductorIdentity.identity.name)
        self.hub = hub
        let host = await ShowHost(
            configuration: .init(
                identity: conductorIdentity, trust: conductorTrust, clock: baseClock, epoch: epoch,
                wireRecord: { buffer.append($0) }
            ),
            sheet: sheet, backend: backend
        )
        self.host = host
        await host.conductor.listen(on: hub)
        await host.conductor.startTicking()
        conductor = await host.conductor.state
        observe(host.conductor.states) { [weak self] state in
            guard let self else { return }
            self.conductor = state
            self.refreshWire(names: state.peers)
        }
    }

    private func observe<Value: Sendable>(_ stream: AsyncStream<Value>, _ apply: @escaping @MainActor (Value) -> Void) {
        tasks.append(Task { @MainActor in
            for await value in stream { apply(value) }
        })
    }

    private func refreshWire(names peers: [PeerStatus]) {
        let names = Dictionary(peers.map { ($0.id, $0.identity.name) }, uniquingKeysWith: { first, _ in first })
        wire = wireBuffer.recent.map { number, record in
            WireLine(
                id: number, outgoing: record.direction == .sent, peerName: names[record.peer] ?? "a peer",
                kind: record.kind, channel: record.channel, sequence: record.sequence, frameBytes: record.frameBytes
            )
        }
    }

    // MARK: Pairing

    /// Opens pairing at the conductor and has the device ask to join. The conductor shows a code;
    /// type it on the device, then allow it at the conductor.
    public func pair(_ role: PeerRole) async {
        guard let host, let hub, let client = clients[role] else { return }
        await host.conductor.openPairing(for: .seconds(120), attempts: 3)
        let ends = hub.dialBothEnds(from: client.identity.name)
        connections[role] = ends
        linksDown.remove(role)
        do {
            try await client.pair(over: ends.joiner)
            lastOutcome = "\(role.title) paired. Both devices pinned each other's identity."
        } catch {
            lastOutcome = error.explanation
        }
    }

    /// The code typed on a simulated device. `false` if it is not six digits.
    @discardableResult
    public func submitCode(_ typed: String, on role: PeerRole) async -> Bool {
        guard let client = clients[role] else { return false }
        return await client.submitCode(typed)
    }

    public func cancelCode(on role: PeerRole) async {
        await clients[role]?.cancelCode()
    }

    /// The person at the conductor answers the pairing request.
    public func answerPairing(allow: Bool) async {
        await host?.conductor.answerPairing(allow: allow)
    }

    /// A device the conductor never paired tries to rejoin with a made-up pin. It is refused, and
    /// the wire log shows it received no session data.
    public func strangerTriesToJoin() async {
        guard let hub else { return }
        let trust = InMemoryTrustStore()
        await trust.pin(PinnedPeer(identity: conductorIdentity.identity, roles: [.conductor], pinnedAt: .now))
        let stranger = Client<Constellation>(configuration: .init(
            identity: LocalIdentity(name: "Unpaired device"), role: .display, trust: trust, clock: baseClock
        ))
        do {
            try await stranger.resume(over: hub.dial(from: "Unpaired device"), to: conductorIdentity.id)
            lastOutcome = "Unexpected: the unpaired device joined."
        } catch {
            let seen = await stranger.state
            lastOutcome = seen.snapshot == nil
                ? "The unpaired device was refused: \(error.explanation) It received no session data."
                : "Unexpected: the unpaired device received session data."
        }
        await stranger.shutdown()
    }

    // MARK: The controller

    public func send(_ command: ShowCommand, from role: PeerRole = .controller) async {
        await clients[role]?.send(command)
    }

    public func point(x: Double, y: Double) async {
        let pointer = Pointer(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
        await clients[.controller]?.publish(pointer)
    }

    // MARK: The conductor

    public func allow(_ id: MessageID) async {
        guard let host else { return }
        lastOutcome = await host.allow(id).message
    }

    public func decline(_ id: MessageID) async {
        guard let host else { return }
        lastOutcome = await host.decline(id).message
    }

    public func conductorSetRunning(_ running: Bool) async {
        guard let host else { return }
        lastOutcome = await host.setRunning(running).message
    }

    public func conductorMove(_ command: ShowCommand) async {
        guard let host else { return }
        lastOutcome = await host.move(command).summary
    }

    /// Brings the show in line with the store after Reset Demo or an undo elsewhere.
    public func syncFromStore() async {
        await host?.syncFromStore()
    }

    /// The conductor quits and relaunches with the same identity and pins, in a new epoch. The
    /// devices lose their links; Reconnect resumes without a code.
    public func restartConductor() async {
        guard let old = host else { return }
        await old.conductor.stop()
        hub?.stop()
        for role in clients.keys { connections[role] = nil }
        await startConductor(epoch: .random())
        lastOutcome = "The conductor restarted in a new epoch. Reconnect the devices; commands from before are refused."
    }

    // MARK: Faults

    /// Takes a device's link down in both directions, as if it walked out of range, or brings it
    /// back. Nothing is closed: each side notices only by silence.
    public func setLinkDown(_ role: PeerRole, _ down: Bool) {
        guard let ends = connections[role] else { return }
        let faults = LoopbackFaults(partitioned: down)
        ends.joiner.setFaults(faults)
        ends.host.setFaults(faults)
        if down { linksDown.insert(role) } else { linksDown.remove(role) }
    }

    /// Loses the next frame the device sends, as a lossy radio would.
    public func dropNextFrame(from role: PeerRole) {
        guard let ends = connections[role] else { return }
        var faults = ends.joiner.faults
        faults.dropNext += 1
        ends.joiner.setFaults(faults)
        lastOutcome = "The next frame from the \(role.title.lowercased()) will be lost."
    }

    /// Closes a device's link without a goodbye.
    public func disconnect(_ role: PeerRole) async {
        await clients[role]?.vanish()
        connections[role] = nil
        linksDown.remove(role)
    }

    /// Rejoins with the pinned identity, without a code.
    public func reconnect(_ role: PeerRole) async {
        guard let hub, let client = clients[role] else { return }
        let ends = hub.dialBothEnds(from: client.identity.name)
        connections[role] = ends
        linksDown.remove(role)
        do {
            try await client.resume(over: ends.joiner)
            lastOutcome = "\(role.title) reconnected without a code, using the pinned identities."
        } catch {
            lastOutcome = error.explanation
        }
    }
}

/// The conductor's recent wire records, filled from its links' tasks, each numbered in arrival
/// order (a record's own ID counts within one link only).
final class WireBuffer: Sendable {
    private let records = Mutex<(next: UInt64, entries: [(UInt64, WireRecord)])>((0, []))

    func append(_ record: WireRecord) {
        records.withLock { state in
            state.next += 1
            state.entries.append((state.next, record))
            if state.entries.count > 40 { state.entries.removeFirst(state.entries.count - 40) }
        }
    }

    /// Newest first.
    var recent: [(UInt64, WireRecord)] { records.withLock { $0.entries.reversed() } }
}
