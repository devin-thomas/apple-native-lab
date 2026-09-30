#if !os(watchOS)
import Foundation
import Network
import PeerSession
import Synchronization

/// What the local-network adapter can tell a person about itself.
public enum LANStatus: Hashable, Sendable {
    case starting
    /// Advertising or browsing on the local network.
    case ready
    /// The system refused local network access: the person declined the prompt, or turned it off
    /// in Settings, or a policy blocks it. The single-device simulation is the route from here.
    case denied
    /// Waiting for a usable network, such as Wi-Fi being off.
    case waiting(String)
    case failed(String)
    case stopped

    public var title: String {
        switch self {
        case .starting: "Starting"
        case .ready: "Ready"
        case .denied: "Local network access denied"
        case .waiting: "Waiting for a local network"
        case .failed: "Failed"
        case .stopped: "Stopped"
        }
    }

    /// Maps a Network framework error. `kDNSServiceErr_PolicyDenied` (-65570) is how Bonjour
    /// reports that local network access is denied.
    static func from(_ error: NWError) -> LANStatus {
        if case .dns(let code) = error, code == -65570 { return .denied }
        return .failed(String(describing: error))
    }
}

/// Where the adapter may send traffic. Every choice is local-only; none reaches the internet.
public enum LANScope: Hashable, Sendable {
    /// The local network: Wi-Fi or Ethernet, advertised and found through Bonjour in `local.`.
    /// Cellular and peer-to-peer Wi-Fi are excluded.
    case localNetwork
    /// This device's loopback interface only, for tests and the loopback demonstration.
    case loopbackOnly

    func parameters(listening: Bool) -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        switch self {
        case .localNetwork:
            parameters.prohibitedInterfaceTypes = [.cellular]
            if listening { parameters.acceptLocalOnly = true }
        case .loopbackOnly:
            parameters.requiredInterfaceType = .loopback
        }
        return parameters
    }
}

/// One TCP connection carrying `FrameCodec` bytes.
///
/// It moves bytes and nothing else: the same frames the loopback carries, sealed by the session
/// layer. It never interprets a frame and never opens a connection on a peer's say-so.
public final class LANConnection: PeerConnection {
    public let incoming: AsyncThrowingStream<Data, any Error>
    public let remoteLabel: String
    private let connection: NWConnection
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    private let reader = Mutex(FrameReader())
    private let statusBox = Mutex<LANStatus>(.starting)
    private let queue = DispatchQueue(label: "native-lab.lan-connection")

    init(_ connection: NWConnection, label: String) {
        self.connection = connection
        remoteLabel = label
        (incoming, continuation) = AsyncThrowingStream<Data, any Error>.makeStream(bufferingPolicy: .unbounded)
        connection.stateUpdateHandler = { [weak self] state in self?.stateChanged(state) }
        connection.start(queue: queue)
        receiveNext()
    }

    public var status: LANStatus { statusBox.withLock { $0 } }

    private func stateChanged(_ state: NWConnection.State) {
        switch state {
        case .ready:
            statusBox.withLock { $0 = .ready }
        case .waiting(let error):
            let denied = connection.currentPath?.unsatisfiedReason == .localNetworkDenied
            statusBox.withLock { $0 = denied ? .denied : .waiting(String(describing: error)) }
            if denied {
                continuation.finish(throwing: TransportError.localNetworkDenied)
                connection.cancel()
            }
        case .failed(let error):
            statusBox.withLock { $0 = LANStatus.from(error) }
            continuation.finish(throwing: TransportError.failed(String(describing: error)))
        case .cancelled:
            statusBox.withLock { $0 = .stopped }
            continuation.finish()
        default:
            break
        }
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: FrameCodec.maximumFrameBytes + 4) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let result: Result<[Data], FrameError> = self.reader.withLock { reader in
                    Result { () throws(FrameError) -> [Data] in try reader.append(data) }
                }
                switch result {
                case .success(let frames):
                    for frame in frames { self.continuation.yield(frame) }
                case .failure(let failure):
                    self.continuation.finish(throwing: TransportError.frame(failure))
                    self.connection.cancel()
                    return
                }
            }
            if isComplete || error != nil {
                self.continuation.finish()
                self.connection.cancel()
                return
            }
            self.receiveNext()
        }
    }

    public func send(_ frame: Data) async throws(TransportError) {
        let bytes: Data
        do { bytes = try FrameCodec.encode(frame) } catch { throw .frame(error) }
        let failure: String? = await withCheckedContinuation { continuation in
            connection.send(content: bytes, completion: .contentProcessed { error in
                continuation.resume(returning: error.map { String(describing: $0) })
            })
        }
        if let failure { throw .failed(failure) }
    }

    public func close() {
        connection.cancel()
    }
}

/// Accepts connections on the local network and advertises them through Bonjour.
public final class LANListener: PeerListener {
    public let connections: AsyncStream<any PeerConnection>
    /// Status changes, newest first to matter.
    public let statuses: AsyncStream<LANStatus>
    private let listener: NWListener
    private let continuation: AsyncStream<any PeerConnection>.Continuation
    private let statusContinuation: AsyncStream<LANStatus>.Continuation
    private let queue = DispatchQueue(label: "native-lab.lan-listener")

    /// - Parameters:
    ///   - serviceType: The Bonjour type, such as `_nativelab-lc._tcp`. It must be listed in the
    ///     host's `NSBonjourServices`, or the system refuses to advertise it.
    ///   - name: The advertised name people see when browsing. `nil` advertises nothing, for
    ///     loopback tests that connect by port.
    public init(scope: LANScope, serviceType: String, name: String?) throws(TransportError) {
        do {
            listener = try NWListener(using: scope.parameters(listening: true))
        } catch {
            throw .failed(String(describing: error))
        }
        if let name {
            listener.service = NWListener.Service(name: WireText.clean(name, limit: 63), type: serviceType, domain: "local.")
        }
        (connections, continuation) = AsyncStream<any PeerConnection>.makeStream()
        (statuses, statusContinuation) = AsyncStream<LANStatus>.makeStream(bufferingPolicy: .bufferingNewest(4))
        listener.newConnectionLimit = 8
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: statusContinuation.yield(.ready)
            case .waiting(let error): statusContinuation.yield(LANStatus.from(error) == .denied ? .denied : .waiting(String(describing: error)))
            case .failed(let error):
                statusContinuation.yield(LANStatus.from(error))
                continuation.finish()
            case .cancelled:
                statusContinuation.yield(.stopped)
                continuation.finish()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            continuation.yield(LANConnection(connection, label: Self.label(for: connection.endpoint)))
        }
        statusContinuation.yield(.starting)
        listener.start(queue: queue)
    }

    /// The port the listener got, once it is ready.
    public var port: UInt16? { listener.port?.rawValue }

    public func stop() {
        listener.cancel()
    }

    static func label(for endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .service(let name, _, _, _): WireText.clean(name, limit: 63)
        case .hostPort(let host, _): WireText.clean(String(describing: host), limit: 63)
        default: "A local device"
        }
    }
}

/// A conductor found on the local network. It can only come from a `LANBrowser` result, or be the
/// loopback address in tests, so a peer's message can never make this device connect elsewhere.
public struct LANEndpoint: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    let endpoint: NWEndpoint

    /// A port on this device's loopback interface.
    public static func loopback(port: UInt16) -> LANEndpoint {
        LANEndpoint(
            id: "loopback:\(port)", name: "This device, port \(port)",
            endpoint: .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any)
        )
    }

    /// Opens a connection to this endpoint.
    public func connect(scope: LANScope) -> LANConnection {
        LANConnection(NWConnection(to: endpoint, using: scope.parameters(listening: false)), label: name)
    }
}

/// Finds conductors advertising on the local network.
public final class LANBrowser: Sendable {
    public let results: AsyncStream<[LANEndpoint]>
    public let statuses: AsyncStream<LANStatus>
    private let browser: NWBrowser
    private let queue = DispatchQueue(label: "native-lab.lan-browser")

    public init(serviceType: String) {
        let parameters = LANScope.localNetwork.parameters(listening: false)
        browser = NWBrowser(for: .bonjour(type: serviceType, domain: "local."), using: parameters)
        let (results, resultContinuation) = AsyncStream<[LANEndpoint]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let (statuses, statusContinuation) = AsyncStream<LANStatus>.makeStream(bufferingPolicy: .bufferingNewest(4))
        self.results = results
        self.statuses = statuses
        browser.browseResultsChangedHandler = { found, _ in
            let endpoints = found.compactMap { result -> LANEndpoint? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                let clean = WireText.clean(name, limit: 63)
                return LANEndpoint(id: "\(result.endpoint)", name: clean.isEmpty ? "Unnamed conductor" : clean, endpoint: result.endpoint)
            }
            resultContinuation.yield(endpoints.sorted { $0.name < $1.name })
        }
        browser.stateUpdateHandler = { state in
            switch state {
            case .ready: statusContinuation.yield(.ready)
            case .waiting(let error): statusContinuation.yield(LANStatus.from(error) == .denied ? .denied : .waiting(String(describing: error)))
            case .failed(let error):
                statusContinuation.yield(LANStatus.from(error))
                resultContinuation.finish()
            case .cancelled:
                statusContinuation.yield(.stopped)
                resultContinuation.finish()
            default: break
            }
        }
        statusContinuation.yield(.starting)
        browser.start(queue: queue)
    }

    public func stop() {
        browser.cancel()
    }
}
#endif
