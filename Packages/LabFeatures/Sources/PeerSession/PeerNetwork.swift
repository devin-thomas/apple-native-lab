import Foundation
import Synchronization

/// What a network adapter can tell a person about itself.
public enum NetworkStatus: Hashable, Sendable {
    case starting
    /// Advertising or browsing.
    case ready
    /// The system refused access: for the local network, the person declined the prompt, turned
    /// it off in Settings, or a policy blocks it. The single-device simulation is the route from
    /// here.
    case denied
    /// Waiting for a usable network, such as Wi-Fi being off.
    case waiting(String)
    case failed(String)
    case stopped

    public var title: String {
        switch self {
        case .starting: "Starting"
        case .ready: "Ready"
        case .denied: "Access denied"
        case .waiting: "Waiting for a network"
        case .failed: "Failed"
        case .stopped: "Stopped"
        }
    }
}

/// A peer found by browsing. Its only way to connect is the closure the adapter made, so an
/// endpoint cannot be built from a message or a string a peer sent.
public struct PeerEndpoint: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    private let open: @Sendable () -> any PeerConnection

    public init(id: String, name: String, open: @escaping @Sendable () -> any PeerConnection) {
        self.id = id
        self.name = name
        self.open = open
    }

    public func connect() -> any PeerConnection { open() }

    public static func == (lhs: PeerEndpoint, rhs: PeerEndpoint) -> Bool { lhs.id == rhs.id && lhs.name == rhs.name }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
    }
}

/// A host advertising itself: the connections it accepts and how the adapter is doing.
public struct PeerAdvertisement: Sendable {
    public let listener: any PeerListener
    public let statuses: AsyncStream<NetworkStatus>

    public init(listener: any PeerListener, statuses: AsyncStream<NetworkStatus>) {
        self.listener = listener
        self.statuses = statuses
    }
}

/// A joiner browsing for hosts.
public struct PeerBrowse: Sendable {
    public let results: AsyncStream<[PeerEndpoint]>
    public let statuses: AsyncStream<NetworkStatus>
    public let stop: @Sendable () -> Void

    public init(results: AsyncStream<[PeerEndpoint]>, statuses: AsyncStream<NetworkStatus>, stop: @escaping @Sendable () -> Void) {
        self.results = results
        self.statuses = statuses
        self.stop = stop
    }
}

/// A way to find and reach peers: the local network, a Watch relay, Wi-Fi Aware, or the
/// in-process loopback. Starting either side is the explicit action that may make the system ask
/// for permission, so a host calls these only from a person's action.
public protocol PeerNetwork: Sendable {
    func advertise(as name: String) throws(TransportError) -> PeerAdvertisement
    func browse() -> PeerBrowse
}

/// An in-process network: hosts advertise on it and joiners in the same process find them. For
/// tests and demonstrations of the live path without a network.
public final class LoopbackNetwork: PeerNetwork {
    private struct Host {
        let hub: LoopbackHub
        let name: String
    }

    private let hosts = Mutex<[String: Host]>([:])
    private let watchers = Mutex<[UUID: AsyncStream<[PeerEndpoint]>.Continuation]>([:])

    public init() {}

    public func advertise(as name: String) throws(TransportError) -> PeerAdvertisement {
        let id = UUID().uuidString
        let hub = LoopbackHub(hostLabel: name)
        hosts.withLock { $0[id] = Host(hub: hub, name: name) }
        let (statuses, continuation) = AsyncStream<NetworkStatus>.makeStream()
        continuation.yield(.ready)
        announce()
        return PeerAdvertisement(listener: Listener(hub: hub) { [weak self] in
            self?.hosts.withLock { $0[id] = nil }
            continuation.yield(.stopped)
            continuation.finish()
            self?.announce()
        }, statuses: statuses)
    }

    public func browse() -> PeerBrowse {
        let id = UUID()
        let (results, continuation) = AsyncStream<[PeerEndpoint]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let (statuses, statusContinuation) = AsyncStream<NetworkStatus>.makeStream()
        statusContinuation.yield(.ready)
        watchers.withLock { $0[id] = continuation }
        continuation.yield(endpoints)
        return PeerBrowse(results: results, statuses: statuses) { [weak self] in
            self?.watchers.withLock { $0[id] = nil }
            continuation.finish()
            statusContinuation.yield(.stopped)
            statusContinuation.finish()
        }
    }

    private var endpoints: [PeerEndpoint] {
        hosts.withLock { hosts in
            hosts.map { id, host in
                PeerEndpoint(id: id, name: host.name) { [hub = host.hub] in hub.dial(from: "loopback joiner") }
            }.sorted { $0.name < $1.name }
        }
    }

    private func announce() {
        let current = endpoints
        for continuation in watchers.withLock({ Array($0.values) }) { continuation.yield(current) }
    }

    private final class Listener: PeerListener {
        let hub: LoopbackHub
        let onStop: @Sendable () -> Void

        init(hub: LoopbackHub, onStop: @escaping @Sendable () -> Void) {
            self.hub = hub
            self.onStop = onStop
        }

        var connections: AsyncStream<any PeerConnection> { hub.connections }

        func stop() {
            hub.stop()
            onStop()
        }
    }
}
