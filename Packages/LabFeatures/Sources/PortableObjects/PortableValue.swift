import Foundation
import LabDomain

/// One JSON value, kept exactly: the lossless model behind a lab document.
///
/// Foundation's decoders lose what a portable document must keep. They round numbers through
/// `Double`, merge `null` into "absent", and drop fields a type does not name. This tree keeps
/// every member of every object, `null` apart from absent, a number as the literal it was written
/// as (so `0`, `0.0`, and `1e2` stay distinct), and every string as its exact Unicode scalars,
/// with no normalization.
///
/// It is built only from bytes that already passed `StrictJSON` (strict UTF-8, no duplicate keys,
/// no unpaired surrogates, bounded depth), so the parser here never meets those cases.
public indirect enum PortableValue: Sendable {
    case null
    case bool(Bool)
    /// A number as written. It always matches the JSON number grammar.
    case number(String)
    case string(String)
    case array([PortableValue])
    case object([String: PortableValue])

    /// A whole number, written without a fraction or exponent.
    public static func integer(_ value: Int) -> PortableValue { .number(String(value)) }

    public var objectValue: [String: PortableValue]? {
        if case .object(let members) = self { members } else { nil }
    }

    public var stringValue: String? {
        if case .string(let text) = self { text } else { nil }
    }

    public var arrayValue: [PortableValue]? {
        if case .array(let elements) = self { elements } else { nil }
    }

    /// The value as an `Int` when it is a whole number written without a fraction or exponent.
    public var integerValue: Int? {
        guard case .number(let literal) = self,
              literal.utf8.allSatisfy({ $0 == UInt8(ascii: "-") || (0x30...0x39).contains($0) })
        else { return nil }
        return Int(literal)
    }

    public var isNull: Bool {
        if case .null = self { true } else { false }
    }
}

// MARK: - Equality

/// Values are equal when they would be written identically: strings and keys compare by their
/// Unicode scalars, not by Swift's canonical equivalence, so "é" and "e\u{301}" differ, as they do
/// in the bytes of a document.
extension PortableValue: Hashable {
    public static func == (lhs: PortableValue, rhs: PortableValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case (.bool(let a), .bool(let b)): a == b
        case (.number(let a), .number(let b)): a.utf8.elementsEqual(b.utf8)
        case (.string(let a), .string(let b)): a.utf8.elementsEqual(b.utf8)
        case (.array(let a), .array(let b)): a == b
        case (.object(let a), .object(let b)):
            a.count == b.count && Self.sortedMembers(a).elementsEqual(Self.sortedMembers(b)) { left, right in
                left.key.utf8.elementsEqual(right.key.utf8) && left.value == right.value
            }
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .null: hasher.combine(0)
        case .bool(let value): hasher.combine(1); hasher.combine(value)
        case .number(let literal): hasher.combine(2); hasher.combine(Array(literal.utf8))
        case .string(let text): hasher.combine(3); hasher.combine(Array(text.utf8))
        case .array(let elements): hasher.combine(4); hasher.combine(elements)
        case .object(let members):
            hasher.combine(5)
            for (key, value) in Self.sortedMembers(members) {
                hasher.combine(Array(key.utf8))
                hasher.combine(value)
            }
        }
    }

    /// Members ordered by the UTF-8 bytes of their keys: the canonical order.
    static func sortedMembers(_ members: [String: PortableValue]) -> [(key: String, value: PortableValue)] {
        members.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
    }
}

// MARK: - Reading

extension PortableValue {
    /// Parses bytes that already passed `StrictJSON.validate`. Anything unexpected is `nil`.
    static func parse(validated bytes: [UInt8]) -> PortableValue? {
        var parser = Parser(bytes: bytes)
        guard let value = parser.value() else { return nil }
        parser.skipWhitespace()
        return parser.index == bytes.count ? value : nil
    }

    /// Parses strict JSON from untrusted bytes: `StrictJSON` first, then the tree.
    static func parse(untrusted bytes: [UInt8], maximumDepth: Int, maximumBytes: Int) throws(StrictJSONError) -> PortableValue {
        try StrictJSON.validate(bytes, maximumDepth: maximumDepth, maximumBytes: maximumBytes)
        guard let value = parse(validated: bytes) else { throw .invalidSyntax(offset: 0) }
        return value
    }

    /// A recursive reader. Depth is bounded by the validator that ran first (at most 16 levels in
    /// a lab document), so recursion cannot exhaust the stack.
    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func value() -> PortableValue? {
            skipWhitespace()
            guard index < bytes.count else { return nil }
            switch bytes[index] {
            case UInt8(ascii: "{"): return object()
            case UInt8(ascii: "["): return array()
            case UInt8(ascii: "\""): return string().map(PortableValue.string)
            case UInt8(ascii: "t"): return literal("true", .bool(true))
            case UInt8(ascii: "f"): return literal("false", .bool(false))
            case UInt8(ascii: "n"): return literal("null", .null)
            default: return number()
            }
        }

        mutating func object() -> PortableValue? {
            index += 1
            var members: [String: PortableValue] = [:]
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object(members)
            }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\""), let key = string() else { return nil }
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
                index += 1
                guard let member = value() else { return nil }
                members[key] = member
                skipWhitespace()
                guard index < bytes.count else { return nil }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
                return nil
            }
        }

        mutating func array() -> PortableValue? {
            index += 1
            var elements: [PortableValue] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array(elements)
            }
            while true {
                guard let element = value() else { return nil }
                elements.append(element)
                skipWhitespace()
                guard index < bytes.count else { return nil }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(elements) }
                return nil
            }
        }

        mutating func string() -> String? {
            index += 1
            var scalars = String.UnicodeScalarView()
            var run: [UInt8] = []
            func flush() {
                if !run.isEmpty {
                    scalars.append(contentsOf: String(decoding: run, as: UTF8.self).unicodeScalars)
                    run.removeAll(keepingCapacity: true)
                }
            }
            while index < bytes.count {
                let byte = bytes[index]
                switch byte {
                case UInt8(ascii: "\""):
                    index += 1
                    flush()
                    return String(scalars)
                case UInt8(ascii: "\\"):
                    flush()
                    index += 1
                    guard index < bytes.count else { return nil }
                    let escaped = bytes[index]
                    index += 1
                    switch escaped {
                    case UInt8(ascii: "\""): scalars.append("\"")
                    case UInt8(ascii: "\\"): scalars.append("\\")
                    case UInt8(ascii: "/"): scalars.append("/")
                    case UInt8(ascii: "b"): scalars.append("\u{08}")
                    case UInt8(ascii: "f"): scalars.append("\u{0C}")
                    case UInt8(ascii: "n"): scalars.append("\n")
                    case UInt8(ascii: "r"): scalars.append("\r")
                    case UInt8(ascii: "t"): scalars.append("\t")
                    case UInt8(ascii: "u"):
                        guard let unit = hexUnit() else { return nil }
                        var value = UInt32(unit)
                        if (0xD800...0xDBFF).contains(unit) {
                            guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") else {
                                return nil
                            }
                            index += 2
                            guard let low = hexUnit(), (0xDC00...0xDFFF).contains(low) else { return nil }
                            value = 0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(low) - 0xDC00)
                        }
                        guard let scalar = Unicode.Scalar(value) else { return nil }
                        scalars.append(scalar)
                    default:
                        return nil
                    }
                default:
                    run.append(byte)
                    index += 1
                }
            }
            return nil
        }

        mutating func hexUnit() -> UInt16? {
            guard index + 4 <= bytes.count else { return nil }
            var value: UInt16 = 0
            for _ in 0..<4 {
                let byte = bytes[index]
                let digit: UInt8
                switch byte {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
                case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
                case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = byte - UInt8(ascii: "A") + 10
                default: return nil
                }
                value = value << 4 | UInt16(digit)
                index += 1
            }
            return value
        }

        mutating func number() -> PortableValue? {
            let start = index
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: "-"), UInt8(ascii: "+"), UInt8(ascii: "."), UInt8(ascii: "e"), UInt8(ascii: "E"),
                     UInt8(ascii: "0")...UInt8(ascii: "9"):
                    index += 1
                default:
                    return index > start ? .number(String(decoding: bytes[start..<index], as: UTF8.self)) : nil
                }
            }
            return index > start ? .number(String(decoding: bytes[start..<index], as: UTF8.self)) : nil
        }

        mutating func literal(_ text: StaticString, _ value: PortableValue) -> PortableValue? {
            let expected = text.withUTF8Buffer { Array($0) }
            guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else { return nil }
            index += expected.count
            return value
        }

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }
    }
}

// MARK: - Writing

extension PortableValue {
    /// The canonical text: two-space indentation, members in `order` first and every other member
    /// by the UTF-8 bytes of its key, strings as raw UTF-8 with only `"`, `\`, and control
    /// characters escaped, numbers as their literal, and a final line break at the top level.
    ///
    /// The same value always produces the same bytes, so a document that is read and written again
    /// is byte-identical to its canonical form.
    func canonicalText(topLevelOrder order: [String] = []) -> String {
        var output = ""
        write(into: &output, indent: 0, order: order)
        output.append("\n")
        return output
    }

    /// Compact canonical text with no whitespace, for metadata kept inside the store.
    func compactText() -> String {
        var output = ""
        writeCompact(into: &output)
        return output
    }

    private func write(into output: inout String, indent: Int, order: [String]) {
        switch self {
        case .null: output.append("null")
        case .bool(let value): output.append(value ? "true" : "false")
        case .number(let literal): output.append(literal)
        case .string(let text): Self.writeString(text, into: &output)
        case .array(let elements):
            guard !elements.isEmpty else { output.append("[]"); return }
            output.append("[\n")
            for (position, element) in elements.enumerated() {
                output.append(String(repeating: "  ", count: indent + 1))
                element.write(into: &output, indent: indent + 1, order: [])
                output.append(position == elements.count - 1 ? "\n" : ",\n")
            }
            output.append(String(repeating: "  ", count: indent))
            output.append("]")
        case .object(let members):
            guard !members.isEmpty else { output.append("{}"); return }
            output.append("{\n")
            let ordered = Self.ordered(members, first: order)
            for (position, member) in ordered.enumerated() {
                output.append(String(repeating: "  ", count: indent + 1))
                Self.writeString(member.key, into: &output)
                output.append(": ")
                member.value.write(into: &output, indent: indent + 1, order: [])
                output.append(position == ordered.count - 1 ? "\n" : ",\n")
            }
            output.append(String(repeating: "  ", count: indent))
            output.append("}")
        }
    }

    private func writeCompact(into output: inout String) {
        switch self {
        case .null: output.append("null")
        case .bool(let value): output.append(value ? "true" : "false")
        case .number(let literal): output.append(literal)
        case .string(let text): Self.writeString(text, into: &output)
        case .array(let elements):
            output.append("[")
            for (position, element) in elements.enumerated() {
                if position > 0 { output.append(",") }
                element.writeCompact(into: &output)
            }
            output.append("]")
        case .object(let members):
            output.append("{")
            for (position, member) in Self.sortedMembers(members).enumerated() {
                if position > 0 { output.append(",") }
                Self.writeString(member.key, into: &output)
                output.append(":")
                member.value.writeCompact(into: &output)
            }
            output.append("}")
        }
    }

    private static func ordered(_ members: [String: PortableValue], first: [String]) -> [(key: String, value: PortableValue)] {
        let leading = first.compactMap { key in members[key].map { (key: key, value: $0) } }
        let named = Set(first)
        return leading + sortedMembers(members.filter { !named.contains($0.key) })
    }

    private static func writeString(_ text: String, into output: inout String) {
        output.append("\"")
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": output.append("\\\"")
            case "\\": output.append("\\\\")
            case "\n": output.append("\\n")
            case "\r": output.append("\\r")
            case "\t": output.append("\\t")
            case "\u{08}": output.append("\\b")
            case "\u{0C}": output.append("\\f")
            case "\u{00}"..."\u{1F}":
                let hex = String(scalar.value, radix: 16, uppercase: false)
                output.append("\\u" + String(repeating: "0", count: 4 - hex.count) + hex)
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        output.append("\"")
    }
}
