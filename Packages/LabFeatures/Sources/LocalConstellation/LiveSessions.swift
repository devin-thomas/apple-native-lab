import Foundation
import LabDomain
import Observation
import PeerSession

/// The live conductor: this device hosts the show on a `PeerNetwork`, such as the local network.
///
/// Nothing is advertised until `start()`, which a host calls only from a person's action, after
/// staging the local network permission (CORE-004). A denial arrives as `networkStatus == .denied`,
/// and the simulation remains the route.
@MainActor
@Observable
public final class LiveConductor {
    public private(set) var state: ConductorState<Constellation>?
    public private(set) var networkStatus: NetworkStatus = .stopped
    public private(set) var lastOutcome: String?
    public private(set) var wire: [WireLine] = []
    public let deviceName: String

    private let network: any PeerNetwork
    private let backend: any ShowSessionBackend
    private let sheet: CueSheet
    private let identity: LocalIdentity
    private let trust: any PeerTrustStore
    private var host: ShowHost?
    private var listener: (any PeerListener)?
    private var tasks: [Task<Void, Never>] = []
    private let wireBuffer = WireBuffer()

    /// - Parameters:
    ///   - identity: This device's identity. Keep it for the life of the app, so pinned peers can
    ///     resume after the show restarts.
    ///   - trust: Where pins live. The lab keeps them in memory, so a relaunch means pairing again.
    public init(
        identity: LocalIdentity,
        trust: any PeerTrustStore,
        network: any PeerNetwork,
        backend: any ShowSessionBackend,
        sheet: CueSheet
    ) {
        self.identity = identity
        self.trust = trust
        self.network = network
        self.backend = backend
        self.sheet = sheet
        deviceName = identity.identity.name
    }

    public var isRunning: Bool { host != nil }

    /// Starts advertising and accepting peers, in a new epoch.
    public func start() async {
        guard host == nil else { return }
        let advertisement: PeerAdvertisement
        do {
            advertisement = try network.advertise(as: deviceName)
        } catch {
            networkStatus = .failed(String(describing: error))
            lastOutcome = "The show could not be advertised on this network."
            return
        }
        let buffer = wireBuffer
        let host = await ShowHost(
            configuration: .init(identity: identity, trust: trust, wireRecord: { buffer.append($0) }),
            sheet: sheet, backend: backend
        )
        self.host = host
        listener = advertisement.listener
        await host.conductor.listen(on: advertisement.listener)
        await host.conductor.startTicking()
        state = await host.conductor.state
        tasks.append(Task { @MainActor [weak self] in
            for await status in advertisement.statuses { self?.networkStatus = status }
        })
        tasks.append(Task { @MainActor [weak self] in
            for await state in host.conductor.states {
                guard let self else { return }
                self.state = state
                let names = Dictionary(state.peers.map { ($0.id, $0.identity.name) }, uniquingKeysWith: { first, _ in first })
                self.wire = buffer.recent.map { number, record in
                    WireLine(id: number, outgoing: record.direction == .sent, peerName: names[record.peer] ?? "a peer",
                             kind: record.kind, channel: record.channel, sequence: record.sequence, frameBytes: record.frameBytes)
                }
            }
        })
    }

    /// Ends the show: goodbye to every peer, and nothing advertised.
    public func stop() async {
        await host?.conductor.stop()
        listener?.stop()
        for task in tasks { task.cancel() }
        tasks.removeAll()
        host = nil
        listener = nil
        state = nil
        networkStatus = .stopped
    }

    public func openPairing() async { await host?.conductor.openPairing() }
    public func closePairing() async { await host?.conductor.closePairing() }
    public func answerPairing(allow: Bool) async { await host?.conductor.answerPairing(allow: allow) }

    public func allow(_ id: MessageID) async {
        guard let host else { return }
        lastOutcome = await host.allow(id).message
    }

    public func decline(_ id: MessageID) async {
        guard let host else { return }
        lastOutcome = await host.decline(id).message
    }

    public func setRunning(_ running: Bool) async {
        guard let host else { return }
        lastOutcome = await host.setRunning(running).message
    }

    public func move(_ command: ShowCommand) async {
        guard let host else { return }
        lastOutcome = await host.move(command).summary
    }

    public func forget(_ peer: PeerID) async {
        await host?.conductor.forget(peer)
    }

    public func syncFromStore() async {
        await host?.syncFromStore()
    }
}

/// The live controller or display: this device finds a conductor on a `PeerNetwork` and joins it.
@MainActor
@Observable
public final class LiveJoiner {
    public let role: PeerRole
    public private(set) var state: ClientState<Constellation>?
    public private(set) var conductors: [PeerEndpoint] = []
    public private(set) var networkStatus: NetworkStatus = .stopped
    public private(set) var lastOutcome: String?
    public private(set) var joinedEndpoint: PeerEndpoint?

    private let network: any PeerNetwork
    private let client: Client<Constellation>
    private var browse: PeerBrowse?
    private var tasks: [Task<Void, Never>] = []
    private var observing: Task<Void, Never>?

    public init(role: PeerRole, identity: LocalIdentity, trust: any PeerTrustStore, network: any PeerNetwork) {
        self.role = role
        self.network = network
        client = Client(configuration: .init(identity: identity, role: role, trust: trust))
    }

    /// Starts browsing for conductors, and the client's timer.
    public func startBrowsing() async {
        guard browse == nil else { return }
        if observing == nil {
            await client.startTicking()
            state = await client.state
            let client = client
            observing = Task { @MainActor [weak self] in
                for await state in client.states { self?.state = state }
            }
        }
        let browse = network.browse()
        self.browse = browse
        tasks.append(Task { @MainActor [weak self] in
            for await found in browse.results { self?.conductors = found }
        })
        tasks.append(Task { @MainActor [weak self] in
            for await status in browse.statuses { self?.networkStatus = status }
        })
    }

    public func stopBrowsing() {
        browse?.stop()
        browse = nil
        for task in tasks { task.cancel() }
        tasks.removeAll()
        networkStatus = .stopped
    }

    /// Joins a conductor: resumes without a code if this device pinned it, or pairs with the code
    /// the conductor shows.
    public func join(_ endpoint: PeerEndpoint) async {
        joinedEndpoint = endpoint
        do {
            if let host = await client.pairedHost {
                try await client.resume(over: endpoint.connect(), to: host.id)
                lastOutcome = "Rejoined \(host.name) without a code."
            } else {
                try await client.pair(over: endpoint.connect())
                lastOutcome = "Paired with \(endpoint.name)."
            }
        } catch .refused(.pairingRequired, _) {
            // The conductor no longer knows this device. Forget it too, so the next Join pairs.
            await client.forgetHost()
            lastOutcome = "\(endpoint.name) no longer knows this device. Choose Join again to pair with a code."
        } catch {
            lastOutcome = error.explanation
        }
    }

    /// Joins the same conductor again after the link dropped.
    public func rejoin() async {
        guard let joinedEndpoint else { return }
        await join(joinedEndpoint)
    }

    @discardableResult
    public func submitCode(_ typed: String) async -> Bool { await client.submitCode(typed) }
    public func cancelCode() async { await client.cancelCode() }
    public func send(_ command: ShowCommand) async { await client.send(command) }

    public func point(x: Double, y: Double) async {
        await client.publish(Pointer(x: min(max(x, 0), 1), y: min(max(y, 0), 1)))
    }

    public func leave() async {
        await client.disconnect()
    }

    public func shutdown() async {
        stopBrowsing()
        observing?.cancel()
        observing = nil
        await client.shutdown()
    }
}
