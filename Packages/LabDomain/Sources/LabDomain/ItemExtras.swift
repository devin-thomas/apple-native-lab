/// Metadata an item carries that this build does not interpret: one JSON object, kept as text.
///
/// It is the entity's `extras` in docs/DATA_CONTRACTS.md. The domain never reads inside it and
/// never merges it. A creation sets it, every later revision of the item carries it unchanged,
/// and the store writes it once, when the item is created, and never rewrites it. An importer
/// (LAB-008 Portable Objects) keeps the fields of a document that the item has no place for here,
/// so exporting the item again returns them.
///
/// The text comes from outside the app, so it is validated: strict JSON (`StrictJSON`), an object
/// at the top, at most `maximumBytes` of UTF-8 and `maximumDepth` levels of nesting. The depth
/// leaves room for an importer to wrap a document nested to the import limit (16) in its own
/// entry. Its content is a person's data, so `description` and reflection print only its size.
public struct ItemExtras: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public static let maximumBytes = 64 * 1_024
    public static let maximumDepth = 32
    public static let empty = ItemExtras(unchecked: "{}")

    /// The JSON object, exactly as it was given.
    public let json: String

    public init(json: String) throws(ExtrasRejection) {
        let bytes = Array(json.utf8)
        guard bytes.count <= Self.maximumBytes else { throw .tooLarge(limit: Self.maximumBytes) }
        do {
            try StrictJSON.validate(bytes, maximumDepth: Self.maximumDepth, maximumBytes: Self.maximumBytes)
        } catch {
            throw .malformed
        }
        // StrictJSON allows only JSON whitespace before the first value.
        guard bytes.first(where: { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }) == UInt8(ascii: "{") else {
            throw .notAnObject
        }
        self.json = json
    }

    private init(unchecked json: String) { self.json = json }

    /// Whether there is nothing here: the empty object every item starts with.
    public var isEmpty: Bool { json == "{}" }

    public var description: String { "ItemExtras(<\(json.utf8.count) bytes>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [Mirror.Child](), displayStyle: .struct) }
}

/// Why metadata was refused as an item's extras.
public enum ExtrasRejection: Error, Hashable, Sendable {
    case tooLarge(limit: Int)
    /// Not strict JSON: ill-formed text, a duplicate key, nesting past the limit, and so on.
    case malformed
    /// Valid JSON, but not an object.
    case notAnObject
}

/// Encoded as a JSON string holding the object, so a receipt records the extras exactly as they
/// were given, and decoding validates them again.
extension ItemExtras: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        do {
            try self.init(json: text)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Item extras must be a strict JSON object.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(json)
    }
}
