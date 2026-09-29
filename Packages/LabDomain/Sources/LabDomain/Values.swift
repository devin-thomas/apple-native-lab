import Foundation

/// Why a payload value was rejected.
///
/// Payload values validate themselves when they are created or decoded, so an operation that
/// holds them is valid by construction and an adapter learns about bad input before it submits.
public enum ValidationError: Error, Hashable, Sendable {
    case emptyTitle
    case titleTooLong(limit: Int)
    case noteTooLong(limit: Int)
    case searchTextTooLong(limit: Int)
    case controlCharacter(in: Field)
    /// An update names no field to change.
    case emptyChanges
    case resultLimitOutOfRange(allowed: ClosedRange<Int>)
    case unsupportedSchemaVersion(Int)

    public enum Field: String, Hashable, Sendable, Codable {
        case title
        case note
        case searchText
    }
}

/// A validated single-line title for a collection or item.
///
/// A title is what people read. It is never identity, and two entities may share one. Leading and
/// trailing whitespace is removed; control characters, including line breaks, are rejected.
public struct EntityTitle: Hashable, Sendable, Codable, CustomStringConvertible {
    public static let maximumLength = 120

    public let value: String

    public init(_ raw: String) throws(ValidationError) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyTitle }
        guard trimmed.count <= Self.maximumLength else { throw .titleTooLong(limit: Self.maximumLength) }
        guard !trimmed.containsControlCharacter() else { throw .controlCharacter(in: .title) }
        value = trimmed
    }

    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public var description: String { value }
}

/// A validated free-text note on an item. It may be empty and may contain line breaks and tabs,
/// but no other control characters.
public struct ItemNote: Hashable, Sendable, Codable, CustomStringConvertible {
    public static let maximumLength = 2_000
    public static let empty = ItemNote(unchecked: "")

    public let value: String

    public init(_ raw: String) throws(ValidationError) {
        guard raw.count <= Self.maximumLength else { throw .noteTooLong(limit: Self.maximumLength) }
        guard !raw.containsControlCharacter(except: ["\n", "\r", "\t"]) else { throw .controlCharacter(in: .note) }
        value = raw
    }

    private init(unchecked value: String) { self.value = value }

    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public var description: String { value }
}

extension String {
    func containsControlCharacter(except allowed: Set<Unicode.Scalar> = []) -> Bool {
        unicodeScalars.contains { $0.properties.generalCategory == .control && !allowed.contains($0) }
    }
}
