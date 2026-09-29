import CryptoKit
import Foundation

/// A SHA-256 digest, written as 64 lowercase hexadecimal characters.
public struct ContentDigest: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let hex: String

    /// `nil` unless `hex` is exactly 64 lowercase hexadecimal characters.
    public init?(hex: String) {
        guard hex.utf8.count == 64, hex.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }) else {
            return nil
        }
        self.hex = hex
    }

    init(_ digest: SHA256.Digest) {
        hex = digest.map { byte in
            let digits = Array("0123456789abcdef".utf8)
            return String(decoding: [digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]], as: UTF8.self)
        }.joined()
    }

    public static func sha256(_ data: some DataProtocol) -> ContentDigest {
        ContentDigest(SHA256.hash(data: data))
    }

    /// The digest's 32 bytes.
    public var bytes: [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(32)
        var iterator = hex.utf8.makeIterator()
        while let high = iterator.next(), let low = iterator.next() {
            result.append(Self.nibble(high) << 4 | Self.nibble(low))
        }
        return result
    }

    private static func nibble(_ character: UInt8) -> UInt8 {
        character <= 0x39 ? character - 0x30 : character - 0x61 + 10
    }

    public var description: String { hex }

    public static func < (lhs: ContentDigest, rhs: ContentDigest) -> Bool { lhs.hex < rhs.hex }

    /// A version-8 UUID derived from this digest and a purpose label, so one piece of content
    /// always names the same staging record, request, or entity.
    func derivedUUID(_ label: String, _ extra: [UInt8] = []) -> UUID {
        var hasher = SHA256()
        hasher.update(data: Array("native-lab/\(label)/".utf8))
        hasher.update(data: bytes)
        hasher.update(data: extra)
        var raw = Array(hasher.finalize().prefix(16))
        raw[6] = (raw[6] & 0x0F) | 0x80
        raw[8] = (raw[8] & 0x3F) | 0x80
        return UUID(uuid: (
            raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
            raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]
        ))
    }
}

/// Computes a SHA-256 digest incrementally, for content streamed to disk.
public struct ContentHasher {
    private var hasher = SHA256()

    public init() {}

    public mutating func update(_ data: some DataProtocol) {
        hasher.update(data: data)
    }

    public func finalize() -> ContentDigest {
        ContentDigest(hasher.finalize())
    }
}
