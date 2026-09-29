import CryptoKit
import Foundation
import LabDomain

/// The one JSON encoding the package writes: sorted keys, no escaped slashes, ISO 8601 dates.
///
/// Every value this package encodes is a fixed name, a validated ID, an enum, a number, or text
/// that was validated when it entered the domain, so the same value always produces the same
/// bytes. Fingerprints and exported files depend on that.
enum Canonical {
    static func encoder(pretty: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted] : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Compact canonical bytes, for hashing.
    static func data(_ value: some Encodable) throws -> Data {
        try encoder(pretty: false).encode(value)
    }

    /// Readable canonical text with a final newline, for files a person reviews.
    static func text(_ value: some Encodable) throws -> String {
        String(decoding: try encoder(pretty: true).encode(value), as: UTF8.self) + "\n"
    }

    static func digest(_ value: some Encodable) throws -> ContentDigest {
        ContentDigest.sha256(try data(value))
    }

    /// A version-8 UUID derived from a label, a digest, and a counter. The same inputs always give
    /// the same UUID, which is what makes a replay's receipt IDs repeat.
    static func derivedUUID(_ label: String, _ digest: ContentDigest, _ counter: Int) -> UUID {
        var hasher = SHA256()
        hasher.update(data: Data("native-lab/\(label)/".utf8))
        hasher.update(data: Data(digest.bytes))
        withUnsafeBytes(of: UInt64(counter).bigEndian) { hasher.update(bufferPointer: $0) }
        var raw = Array(hasher.finalize().prefix(16))
        raw[6] = (raw[6] & 0x0F) | 0x80
        raw[8] = (raw[8] & 0x3F) | 0x80
        return UUID(uuid: (
            raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
            raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]
        ))
    }
}

extension Duration {
    /// Whole nanoseconds, rounded toward zero.
    var nanoseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
    }
}

extension String {
    /// Empty or whitespace only.
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
