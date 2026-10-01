import Foundation
import Synchronization

/// One connection to one peer, carrying whole frames in order.
///
/// A transport moves `FrameCodec` bytes and nothing else: it neither reads nor changes a frame.
/// The session layer above it is the same for every transport, which is what lets later
/// experiments add a Watch relay, Wi-Fi Aware, or Bluetooth under the same messages.
public protocol PeerConnection: Sendable {
    /// Frames as they arrive, without their length prefix. Finishes when the connection closes;
    /// throws when it fails.
    var incoming: AsyncThrowingStream<Data, any Error> { get }
    /// Sends one frame. Throws `TransportError.closed` after `close()` or a failure.
    func send(_ frame: Data) async throws(TransportError)
    /// Closes both directions. The other side's `incoming` finishes.
    func close()
    /// Where the connection goes, for people and logs: never a key or an authority.
    var remoteLabel: String { get }
}

/// Incoming connections a host accepts.
public protocol PeerListener: Sendable {
    var connections: AsyncStream<any PeerConnection> { get }
    func stop()
}

public enum TransportError: Error, Hashable, Sendable {
    case closed
    case frame(FrameError)
    /// The system refused local network access (the person declined, or a policy blocks it).
    case localNetworkDenied
    case failed(String)
}

// MARK: - Loopback

/// Faults a loopback connection applies to frames sent through it, for the simulation and tests.
public struct LoopbackFaults: Sendable, Hashable {
    /// Frames to discard before delivering again. A discarded frame's counter is skipped, so the
    /// receiver sees a sequence gap exactly as it would from a lossy radio.
    public var dropNext: Int = 0
    /// While `true`, every frame is discarded, as if the peers were out of range.
    public var partitioned = false

    public init(dropNext: Int = 0, partitioned: Bool = false) {
        self.dropNext = dropNext
        self.partitioned = partitioned
    }
}

/// An in-process connection. It encodes each frame with `FrameCodec` and splits the bytes again
/// with a `FrameReader` on the other side, so the bytes it carries are exactly what a network
/// transport would carry.
public final class LoopbackConnection: PeerConnection {
    private struct State {
        var reader = FrameReader()
        var closed = false
        var faults = LoopbackFaults()
        var sentFrames = 0
        var droppedFrames = 0
        var sentBytes = 0
    }

    public let incoming: AsyncThrowingStream<Data, any Error>
    public let remoteLabel: String
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    private let state = Mutex(State())
    private let peerBox = Mutex<LoopbackConnection?>(nil)
    private let tap: (@Sendable (Data) -> Void)?

    init(remoteLabel: String, tap: (@Sendable (Data) -> Void)?) {
        self.remoteLabel = remoteLabel
        self.tap = tap
        (incoming, continuation) = AsyncThrowingStream<Data, any Error>.makeStream(bufferingPolicy: .unbounded)
    }

    /// Two connected ends. `tap`, when given, sees every byte sequence either end puts on the wire.
    public static func pair(
        _ firstLabel: String,
        _ secondLabel: String,
        tap: (@Sendable (Data) -> Void)? = nil
    ) -> (LoopbackConnection, LoopbackConnection) {
        // Each end is labeled with the peer it reaches.
        let first = LoopbackConnection(remoteLabel: secondLabel, tap: tap)
        let second = LoopbackConnection(remoteLabel: firstLabel, tap: tap)
        first.peerBox.withLock { $0 = second }
        second.peerBox.withLock { $0 = first }
        return (first, second)
    }

    public func send(_ frame: Data) async throws(TransportError) {
        let bytes: Data
        do { bytes = try FrameCodec.encode(frame) } catch { throw .frame(error) }
        let deliver: Bool = try state.withLock { (state) throws(TransportError) -> Bool in
            guard !state.closed else { throw .closed }
            state.sentFrames += 1
            state.sentBytes += bytes.count
            if state.faults.partitioned { state.droppedFrames += 1; return false }
            if state.faults.dropNext > 0 { state.faults.dropNext -= 1; state.droppedFrames += 1; return false }
            return true
        }
        tap?(bytes)
        guard deliver, let peer = peerBox.withLock({ $0 }) else { return }
        peer.receive(bytes)
    }

    private func receive(_ bytes: Data) {
        let result: Result<[Data], FrameError>? = state.withLock { state in
            guard !state.closed else { return nil }
            return Result { () throws(FrameError) -> [Data] in try state.reader.append(bytes) }
        }
        switch result {
        case .success(let frames): for frame in frames { continuation.yield(frame) }
        case .failure(let error): continuation.finish(throwing: TransportError.frame(error))
        case nil: break
        }
    }

    public func close() {
        let wasOpen = state.withLock { state in
            defer { state.closed = true }
            return !state.closed
        }
        guard wasOpen else { return }
        continuation.finish()
        let peer = peerBox.withLock { box in
            defer { box = nil }
            return box
        }
        peer?.close()
    }

    /// Changes the faults applied to frames this end sends.
    public func setFaults(_ faults: LoopbackFaults) {
        state.withLock { $0.faults = faults }
    }

    public var faults: LoopbackFaults { state.withLock { $0.faults } }

    /// Frames this end sent, and how many of them the faults discarded.
    public var counts: (sent: Int, dropped: Int, bytes: Int) {
        state.withLock { ($0.sentFrames, $0.droppedFrames, $0.sentBytes) }
    }
}

/// A loopback "network" a host listens on and joiners dial, all in one process.
public final class LoopbackHub: PeerListener {
    public let connections: AsyncStream<any PeerConnection>
    private let continuation: AsyncStream<any PeerConnection>.Continuation
    private let hostLabel: String
    private let tap: (@Sendable (Data) -> Void)?

    public init(hostLabel: String, tap: (@Sendable (Data) -> Void)? = nil) {
        self.hostLabel = hostLabel
        self.tap = tap
        (connections, continuation) = AsyncStream<any PeerConnection>.makeStream()
    }

    /// Connects a new joiner. The host's end arrives on `connections`; the joiner gets the other.
    public func dial(from label: String) -> LoopbackConnection {
        dialBothEnds(from: label).joiner
    }

    /// Connects a new joiner and returns both ends, so a simulation can apply faults to frames in
    /// either direction.
    public func dialBothEnds(from label: String) -> (joiner: LoopbackConnection, host: LoopbackConnection) {
        let (joinerEnd, hostEnd) = LoopbackConnection.pair(label, hostLabel, tap: tap)
        continuation.yield(hostEnd)
        return (joinerEnd, hostEnd)
    }

    public func stop() {
        continuation.finish()
    }
}
