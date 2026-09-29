import Foundation
import LabDomain

/// The portable form of one lab item that Export produces.
///
/// It is a small, versioned document about one item, not a copy of the store: it carries the
/// item's own fields and its collection's identity, and never receipts, request IDs, other items,
/// or metadata the store keeps but does not interpret.
///
/// ```json
/// {
///   "format": "native-lab-item",
///   "formatVersion": 1,
///   "id": "<UUID>",
///   "title": "…",
///   "note": "…",
///   "archived": false,
///   "revision": 1,
///   "demoSample": true,
///   "collection": { "id": "<UUID>", "title": "…" }
/// }
/// ```
public struct PortableLabItem: Codable, Hashable, Sendable {
    public static let format = "native-lab-item"
    public static let currentFormatVersion = 1

    public struct CollectionReference: Codable, Hashable, Sendable {
        public let id: UUID
        public let title: String
    }

    public let format: String
    public let formatVersion: Int
    public let id: UUID
    public let title: String
    public let note: String
    public let archived: Bool
    public let revision: Int
    public let demoSample: Bool
    public let collection: CollectionReference

    public init(item: LabItem, collection: LabCollection) {
        format = Self.format
        formatVersion = Self.currentFormatVersion
        id = item.id.rawValue
        title = item.title.value
        note = item.note.value
        archived = item.isArchived
        revision = item.revision.rawValue
        demoSample = item.namespace == .demo
        self.collection = CollectionReference(id: collection.id.rawValue, title: collection.title.value)
    }

    /// Stable JSON: sorted keys, pretty-printed, so two exports of the same state are identical.
    public func jsonData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // Every field is a plain value, so encoding cannot fail.
        return (try? encoder.encode(self)) ?? Data()
    }

    /// A plain-text rendering for people: title, note, then the facts.
    public var plainText: String {
        var lines = [title]
        if !note.isEmpty { lines += ["", note] }
        lines += [
            "",
            "Collection: \(collection.title)",
            "Status: \(archived ? "Archived" : "Active")",
            "Revision: \(revision)",
            "Identifier: \(id.uuidString)",
        ]
        return lines.joined(separator: "\n") + "\n"
    }
}

/// The representations Export offers.
public enum AtlasExportFormat: String, Hashable, Sendable, CaseIterable {
    case json
    case plainText = "plain-text"

    public var fileExtension: String {
        switch self {
        case .json: "json"
        case .plainText: "txt"
        }
    }

    public var title: String {
        switch self {
        case .json: "JSON"
        case .plainText: "Plain Text"
        }
    }
}

/// One export: the portable document and its bytes in the chosen representation.
public struct AtlasExport: Hashable, Sendable {
    public let document: PortableLabItem
    public let format: AtlasExportFormat
    public let data: Data
    public let filename: String

    init(document: PortableLabItem, format: AtlasExportFormat) {
        self.document = document
        self.format = format
        data = switch format {
        case .json: document.jsonData()
        case .plainText: Data(document.plainText.utf8)
        }
        filename = "\(Self.safeName(document.title)).\(format.fileExtension)"
    }

    /// The text of the export, for a preview before it is shared.
    public var text: String { String(decoding: data, as: UTF8.self) }

    /// A file name from a title: no path separators, no leading dot, at most 60 characters.
    static func safeName(_ title: String) -> String {
        let replaced = title.map { character -> Character in
            "/:\\".contains(character) ? "-" : character
        }
        var name = String(replaced).trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
        if name.count > 60 { name = String(name.prefix(60)).trimmingCharacters(in: .whitespaces) }
        return name.isEmpty ? "Lab item" : name
    }
}
