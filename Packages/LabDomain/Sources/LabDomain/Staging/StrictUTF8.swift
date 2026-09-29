/// Strict UTF-8 validation for untrusted bytes.
///
/// Rejects everything the Unicode standard calls ill-formed: overlong encodings (such as `C0 AF`,
/// an overlong `/`), encoded surrogates (`ED A0 80`), values above U+10FFFF, stray continuation
/// bytes, and truncated sequences.
public enum StrictUTF8 {
    /// The byte offset of the first ill-formed sequence, or `nil` when every byte is valid.
    public static func firstInvalidOffset(in bytes: some Collection<UInt8>) -> Int? {
        var iterator = bytes.makeIterator()
        var offset = 0
        while let lead = iterator.next() {
            let start = offset
            offset += 1
            let count: Int
            var lower: UInt8 = 0x80
            var upper: UInt8 = 0xBF
            switch lead {
            case 0x00...0x7F: continue
            case 0xC2...0xDF: count = 1
            case 0xE0: count = 2; lower = 0xA0
            case 0xE1...0xEC, 0xEE...0xEF: count = 2
            case 0xED: count = 2; upper = 0x9F
            case 0xF0: count = 3; lower = 0x90
            case 0xF1...0xF3: count = 3
            case 0xF4: count = 3; upper = 0x8F
            default: return start
            }
            for index in 0..<count {
                guard let byte = iterator.next() else { return start }
                let low = index == 0 ? lower : 0x80
                let high = index == 0 ? upper : 0xBF
                guard byte >= low, byte <= high else { return start }
                offset += 1
            }
        }
        return nil
    }

    /// The text, or the offset of the first ill-formed sequence.
    public static func decode(_ bytes: some Collection<UInt8>) -> Result<String, InvalidOffset> {
        if let offset = firstInvalidOffset(in: bytes) { return .failure(InvalidOffset(offset: offset)) }
        return .success(String(decoding: bytes, as: UTF8.self))
    }

    public struct InvalidOffset: Error, Hashable, Sendable {
        public let offset: Int
    }
}
