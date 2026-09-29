/// A strict validator for untrusted JSON, run before any decoder sees the bytes.
///
/// Foundation's decoders accept a duplicate key by silently keeping one value, so a document can
/// show a reviewer one value and give the app another. They also recurse per nesting level. This
/// validator is iterative, so depth cannot exhaust the stack, and it refuses:
///
/// - input that is empty or larger than the limit;
/// - ill-formed UTF-8 (`StrictUTF8`), including overlong forms and encoded surrogates;
/// - nesting deeper than the limit;
/// - a key repeated in one object, compared after unescaping and under canonical Unicode
///   equivalence, which is how a Swift dictionary would merge them;
/// - an unpaired surrogate escape such as `"\ud800"`;
/// - anything else RFC 8259 does not allow, such as a byte-order mark, a trailing comma, raw
///   control characters in strings, comments, or trailing content.
public enum StrictJSON {
    public static func validate(
        _ input: some Collection<UInt8>,
        maximumDepth: Int,
        maximumBytes: Int
    ) throws(StrictJSONError) {
        guard !input.isEmpty else { throw .empty }
        guard input.count <= maximumBytes else { throw .tooLarge(limit: maximumBytes) }
        let bytes = Array(input)
        if let offset = StrictUTF8.firstInvalidOffset(in: bytes) { throw .invalidUTF8(offset: offset) }
        var parser = Parser(bytes: bytes, maximumDepth: maximumDepth)
        try parser.run()
    }

    private enum Container {
        case array
        case object(keys: Set<String>)
    }

    private struct Parser {
        let bytes: [UInt8]
        let maximumDepth: Int
        var index = 0
        var stack: [Container] = []

        init(bytes: [UInt8], maximumDepth: Int) {
            self.bytes = bytes
            self.maximumDepth = maximumDepth
        }

        mutating func run() throws(StrictJSONError) {
            // Each pass reads one value, then the separators and closing brackets that follow it.
            while true {
                try readValue()
                while true {
                    skipWhitespace()
                    guard let container = stack.last else {
                        guard index == bytes.count else { throw .invalidSyntax(offset: index) }
                        return
                    }
                    guard index < bytes.count else { throw .invalidSyntax(offset: index) }
                    let byte = bytes[index]
                    switch (byte, container) {
                    case (UInt8(ascii: ","), .array):
                        index += 1
                    case (UInt8(ascii: ","), .object):
                        index += 1
                        try readKey()
                    case (UInt8(ascii: "]"), .array), (UInt8(ascii: "}"), .object):
                        index += 1
                        stack.removeLast()
                        continue
                    default:
                        throw .invalidSyntax(offset: index)
                    }
                    break
                }
            }
        }

        /// Reads one value. An opened array or object is pushed, and its first key read, so the
        /// caller continues with the value that follows.
        mutating func readValue() throws(StrictJSONError) {
            while true {
                skipWhitespace()
                guard index < bytes.count else { throw .invalidSyntax(offset: index) }
                switch bytes[index] {
                case UInt8(ascii: "["):
                    try push(.array)
                    skipWhitespace()
                    if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
                        index += 1
                        stack.removeLast()
                        return
                    }
                    continue
                case UInt8(ascii: "{"):
                    try push(.object(keys: []))
                    skipWhitespace()
                    if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
                        index += 1
                        stack.removeLast()
                        return
                    }
                    try readKey()
                    continue
                case UInt8(ascii: "\""):
                    _ = try readString(keepingText: false)
                    return
                case UInt8(ascii: "t"):
                    try expect("true")
                    return
                case UInt8(ascii: "f"):
                    try expect("false")
                    return
                case UInt8(ascii: "n"):
                    try expect("null")
                    return
                case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
                    try readNumber()
                    return
                default:
                    throw .invalidSyntax(offset: index)
                }
            }
        }

        mutating func push(_ container: Container) throws(StrictJSONError) {
            guard stack.count < maximumDepth else { throw .tooDeep(limit: maximumDepth) }
            stack.append(container)
            index += 1
        }

        /// Reads `"key" :` inside the current object and records the key.
        mutating func readKey() throws(StrictJSONError) {
            skipWhitespace()
            let start = index
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw .invalidSyntax(offset: index) }
            let key = try readString(keepingText: true)
            guard case .object(var keys) = stack.removeLast() else { throw .invalidSyntax(offset: start) }
            guard keys.insert(key).inserted else { throw .duplicateKey(offset: start) }
            stack.append(.object(keys: keys))
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw .invalidSyntax(offset: index) }
            index += 1
        }

        mutating func readString(keepingText: Bool) throws(StrictJSONError) -> String {
            index += 1
            var text: [UInt8] = []
            while index < bytes.count {
                let byte = bytes[index]
                switch byte {
                case UInt8(ascii: "\""):
                    index += 1
                    return keepingText ? String(decoding: text, as: UTF8.self) : ""
                case UInt8(ascii: "\\"):
                    let escapeStart = index
                    index += 1
                    guard index < bytes.count else { throw .invalidSyntax(offset: index) }
                    let escaped = bytes[index]
                    index += 1
                    switch escaped {
                    case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): text.append(escaped)
                    case UInt8(ascii: "b"): text.append(0x08)
                    case UInt8(ascii: "f"): text.append(0x0C)
                    case UInt8(ascii: "n"): text.append(0x0A)
                    case UInt8(ascii: "r"): text.append(0x0D)
                    case UInt8(ascii: "t"): text.append(0x09)
                    case UInt8(ascii: "u"):
                        let unit = try readHexUnit()
                        let scalarValue: UInt32
                        switch unit {
                        case 0xD800...0xDBFF:
                            guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") else {
                                throw .unpairedSurrogate(offset: escapeStart)
                            }
                            index += 2
                            let low = try readHexUnit()
                            guard (0xDC00...0xDFFF).contains(low) else { throw .unpairedSurrogate(offset: escapeStart) }
                            scalarValue = 0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(low) - 0xDC00)
                        case 0xDC00...0xDFFF:
                            throw .unpairedSurrogate(offset: escapeStart)
                        default:
                            scalarValue = UInt32(unit)
                        }
                        if keepingText, let scalar = Unicode.Scalar(scalarValue) {
                            text.append(contentsOf: Array(String(Character(scalar)).utf8))
                        }
                    default:
                        throw .invalidSyntax(offset: escapeStart)
                    }
                case 0x00..<0x20:
                    throw .invalidSyntax(offset: index)
                default:
                    if keepingText { text.append(byte) }
                    index += 1
                }
            }
            throw .invalidSyntax(offset: index)
        }

        mutating func readHexUnit() throws(StrictJSONError) -> UInt16 {
            guard index + 4 <= bytes.count else { throw .invalidSyntax(offset: index) }
            var value: UInt16 = 0
            for _ in 0..<4 {
                let byte = bytes[index]
                let digit: UInt8
                switch byte {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
                case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
                case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = byte - UInt8(ascii: "A") + 10
                default: throw .invalidSyntax(offset: index)
                }
                value = value << 4 | UInt16(digit)
                index += 1
            }
            return value
        }

        mutating func readNumber() throws(StrictJSONError) {
            let start = index
            if bytes[index] == UInt8(ascii: "-") { index += 1 }
            guard index < bytes.count else { throw .invalidSyntax(offset: start) }
            if bytes[index] == UInt8(ascii: "0") {
                index += 1
            } else if isDigit(at: index) {
                while isDigit(at: index) { index += 1 }
            } else {
                throw .invalidSyntax(offset: index)
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                guard isDigit(at: index) else { throw .invalidSyntax(offset: index) }
                while isDigit(at: index) { index += 1 }
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
                guard isDigit(at: index) else { throw .invalidSyntax(offset: index) }
                while isDigit(at: index) { index += 1 }
            }
        }

        func isDigit(at position: Int) -> Bool {
            position < bytes.count && (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[position])
        }

        mutating func expect(_ literal: StaticString) throws(StrictJSONError) {
            let expected = literal.withUTF8Buffer { Array($0) }
            guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else {
                throw .invalidSyntax(offset: index)
            }
            index += expected.count
        }

        mutating func skipWhitespace() {
            while index < bytes.count {
                switch bytes[index] {
                case 0x20, 0x09, 0x0A, 0x0D: index += 1
                default: return
                }
            }
        }
    }
}
