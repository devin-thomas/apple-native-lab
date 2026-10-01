import Foundation
import LabDomain

/// Encodes and decodes the JSON inside frames.
///
/// Encoding is deterministic (sorted keys), so the same message is the same bytes on every
/// transport. Decoding treats every byte as untrusted: LabDomain's `StrictJSON` runs first
/// (duplicate keys, depth, size, strict UTF-8), and each object's keys must be ones the format
/// defines, so a smuggled field such as a grant, a scope, a path, or a command line is refused
/// rather than ignored.
enum WireJSON {
    static let maximumDepth = 8

    static func encode(_ value: some Encodable) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Every wire type encodes without failure: its fields are strings, integers, and
        // nested wire types, none of them non-finite floating point.
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }

    /// Validates, checks keys, and decodes.
    ///
    /// - Parameter allowedKeys: For each key path in the document (`""` is the top level, `"body"`
    ///   the object under `body`), the keys that object may have. An object at a path not listed
    ///   is not checked here; its own decoder must refuse unknown content.
    static func decode<Value: Decodable>(
        _ type: Value.Type,
        from bytes: Data,
        maximumBytes: Int,
        allowedKeys: [String: Set<String>]
    ) throws(WireDecodingError) -> Value {
        do {
            try StrictJSON.validate(bytes, maximumDepth: maximumDepth, maximumBytes: maximumBytes)
        } catch {
            throw .notStrictJSON
        }
        guard let object = try? JSONSerialization.jsonObject(with: bytes) else { throw .notStrictJSON }
        try checkKeys(object, path: "", allowed: allowedKeys)
        do {
            return try JSONDecoder().decode(Value.self, from: bytes)
        } catch {
            throw .invalidContent
        }
    }

    private static func checkKeys(_ object: Any, path: String, allowed: [String: Set<String>]) throws(WireDecodingError) {
        guard let dictionary = object as? [String: Any] else { return }
        if let keys = allowed[path] {
            for key in dictionary.keys where !keys.contains(key) {
                throw .unknownField
            }
        }
        for (key, value) in dictionary {
            try checkKeys(value, path: path.isEmpty ? key : "\(path).\(key)", allowed: allowed)
        }
    }
}

/// Why received bytes were refused. The cases never repeat the sender's text.
public enum WireDecodingError: Error, Hashable, Sendable {
    case notStrictJSON
    /// A field the format does not define.
    case unknownField
    /// Well-formed JSON whose content is not a valid message.
    case invalidContent
}

/// Text that came from, or goes to, another device.
public enum WireText {
    /// Keeps printable text only, collapses runs of white space, and truncates to `limit`
    /// characters, so text cannot carry control characters, bidirectional overrides, or line
    /// breaks into a view or a log.
    public static func clean(_ text: String, limit: Int) -> String {
        let allowed = text.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .surrogate, .privateUse, .unassigned, .lineSeparator, .paragraphSeparator:
                false
            default:
                true
            }
        }
        let words = String(String.UnicodeScalarView(allowed)).split(whereSeparator: \.isWhitespace)
        return String(words.joined(separator: " ").prefix(limit))
    }
}
