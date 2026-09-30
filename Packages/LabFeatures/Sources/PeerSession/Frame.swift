import Foundation

/// The outer wire format every transport carries: a 4-byte big-endian length, then the frame.
///
/// A frame's first byte says what follows. A handshake frame is plaintext JSON that holds public
/// keys, nonces, names, roles, and versions, and never session data. A sealed frame is an
/// authenticated, encrypted `SessionEnvelope` (`SecureChannel`). The loopback transport and the
/// network transport carry exactly these bytes, which is what makes the single-device simulation's
/// wire messages identical to the live ones.
public enum FrameCodec {
    /// The largest frame either side accepts, prefix excluded.
    public static let maximumFrameBytes = 64 * 1024
    /// The largest handshake frame.
    public static let maximumHandshakeBytes = 4 * 1024

    public enum Kind: UInt8, Sendable {
        case handshake = 0x01
        case sealed = 0x02
    }

    /// The bytes to send for one frame, prefix included.
    public static func encode(_ frame: Data) throws(FrameError) -> Data {
        guard !frame.isEmpty else { throw .empty }
        guard frame.count <= maximumFrameBytes else { throw .tooLarge(frame.count) }
        var bytes = Data(capacity: frame.count + 4)
        let length = UInt32(frame.count).bigEndian
        withUnsafeBytes(of: length) { bytes.append(contentsOf: $0) }
        bytes.append(frame)
        return bytes
    }
}

public enum FrameError: Error, Hashable, Sendable {
    case empty
    /// A declared or actual frame length above `FrameCodec.maximumFrameBytes`.
    case tooLarge(Int)
    case unknownKind(UInt8)
}

/// Splits a byte stream into frames as bytes arrive, whatever the chunk boundaries.
///
/// It refuses a declared length above the limit before buffering it, so a peer cannot make the
/// receiver allocate a large buffer by claiming one. After a refusal the stream is unusable and
/// the transport closes the connection.
public struct FrameReader: Sendable {
    private var buffer = Data()
    private var failed = false

    public init() {}

    /// Adds received bytes and returns every frame they complete, in order.
    public mutating func append(_ bytes: Data) throws(FrameError) -> [Data] {
        guard !failed else { throw .empty }
        buffer.append(bytes)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let start = buffer.startIndex
            let length = buffer[start..<start + 4].reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0 else { failed = true; throw .empty }
            guard length <= FrameCodec.maximumFrameBytes else { failed = true; throw .tooLarge(length) }
            guard buffer.count >= 4 + length else { break }
            frames.append(Data(buffer[start + 4..<start + 4 + length]))
            buffer = Data(buffer[(start + 4 + length)...])
        }
        return frames
    }

    /// Bytes received that do not yet form a whole frame.
    public var pendingByteCount: Int { buffer.count }
}
