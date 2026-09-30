import Foundation
import LabDomain

/// What an item keeps of a document: its title and note, and every other field as extras.
public struct ItemContent: Hashable, Sendable {
    public let title: EntityTitle
    public let note: ItemNote
    /// The document without the fields the item holds itself, so exporting the item again gives
    /// the document back. See `DocumentMapping`.
    public let extras: ItemExtras
    /// Changes the item makes to what the document says, as sentences for the review.
    public let adjustments: [String]
}

/// How a lab document and a stored item correspond.
///
/// The item holds the document's identity (`documentID` is the item ID), its title, and its note.
/// Everything else the document carries, known or not (`kind`, the rest of `fields`,
/// `provenance`, `attachments`, `extras`, and any field this build does not know), goes into the
/// item's extras as one versioned entry:
///
/// ```json
/// {"portableObject": {"version": 1, "note": "text" | "null" | "absent", "document": {…}}}
/// ```
///
/// `document` is the document without `format`, `schemaVersion`, `documentID`, `revision`,
/// `title`, and `fields.note`; `note` records which form the note had, so an empty note exports
/// as `""`, `null`, or nothing, exactly as it arrived. `revision` is the store's own: an imported
/// object starts at revision 1 in its new store, and exports its current revision from then on.
public enum DocumentMapping {
    static let extrasKey = "portableObject"
    static let extrasVersion = 1
    /// The fields the item holds itself and every export writes from it.
    static let itemFields: Set<String> = ["format", "schemaVersion", "documentID", "revision", "title"]

    // MARK: Document to item

    /// What an item made from `document` holds.
    public static func itemContent(of document: LabDocument) throws(PortableObjectError) -> ItemContent {
        let title: EntityTitle
        do { title = try EntityTitle(document.title) } catch { throw .invalidTitle(error) }
        var adjustments: [String] = []
        if !title.value.unicodeScalars.elementsEqual(document.title.unicodeScalars) {
            adjustments.append("Spaces around the title are removed; a lab title can't begin or end with one.")
        }
        let note: ItemNote
        do { note = try ItemNote(document.note.text ?? "") } catch { throw .invalidNote(error) }

        var remainder = document.root.filter { !itemFields.contains($0.key) }
        if var fields = remainder["fields"]?.objectValue {
            fields["note"] = nil
            remainder["fields"] = .object(fields)
        }
        let form = switch document.note {
        case .text: "text"
        case .null: "null"
        case .absent: "absent"
        }
        let entry = PortableValue.object([
            extrasKey: .object([
                "version": .integer(extrasVersion),
                "note": .string(form),
                "document": .object(remainder),
            ]),
        ])
        let extras: ItemExtras
        do {
            extras = try ItemExtras(json: entry.compactText())
        } catch .tooLarge {
            throw .extrasTooLarge(limit: ItemExtras.maximumBytes)
        } catch {
            // The document passed strict JSON within the same depth, so its parts do too.
            throw .extrasTooLarge(limit: ItemExtras.maximumBytes)
        }
        return ItemContent(title: title, note: note, extras: extras, adjustments: adjustments)
    }

    // MARK: Item to document

    /// The document for a stored item. An item that came from a document gets that document back,
    /// with the item's current title, note, and revision. Any other item gets a new document
    /// whose provenance names this lab and the item's collection.
    public static func document(for item: LabItem, in collection: LabCollection?) throws(PortableObjectError) -> LabDocument {
        let stored = storedDocument(in: item.extras)
        var root = stored?.document ?? defaultRemainder(for: item, in: collection)
        root["format"] = .string(LabDocument.format)
        root["schemaVersion"] = .integer(LabDocument.schemaVersion)
        root["documentID"] = .string(item.id.rawValue.uuidString)
        root["revision"] = .integer(item.revision.rawValue)
        root["title"] = .string(item.title.value)

        var fields = root["fields"]?.objectValue
        if !item.note.value.isEmpty {
            fields = (fields ?? [:]).merging(["note": .string(item.note.value)]) { _, new in new }
        } else {
            switch stored?.noteForm ?? "text" {
            case "absent": break
            case "null": fields = (fields ?? [:]).merging(["note": .null]) { _, new in new }
            default: fields = (fields ?? [:]).merging(["note": .string("")]) { _, new in new }
            }
        }
        if let fields { root["fields"] = .object(fields) }
        return try LabDocument(validating: .object(root))
    }

    /// The document an item came from, when its extras hold one this build reads.
    static func storedDocument(in extras: ItemExtras) -> (document: [String: PortableValue], noteForm: String)? {
        guard !extras.isEmpty,
              let value = PortableValue.parse(validated: Array(extras.json.utf8)),
              let entry = value.objectValue?[extrasKey]?.objectValue,
              entry["version"]?.integerValue == extrasVersion,
              let document = entry["document"]?.objectValue,
              let form = entry["note"]?.stringValue
        else { return nil }
        return (document, form)
    }

    /// Whether the item's extras hold metadata other than a document this build reads, which an
    /// export does not include.
    public static func hasUnexportedExtras(_ item: LabItem) -> Bool {
        guard !item.extras.isEmpty else { return false }
        guard let members = PortableValue.parse(validated: Array(item.extras.json.utf8))?.objectValue else { return true }
        return members.count > 1 || storedDocument(in: item.extras) == nil
    }

    private static func defaultRemainder(for item: LabItem, in collection: LabCollection?) -> [String: PortableValue] {
        var provenance: [String: PortableValue] = [
            "origin": .string("native-lab"),
            "namespace": .string(item.namespace.rawValue),
        ]
        if let collection {
            provenance["collectionID"] = .string(collection.id.rawValue.uuidString)
            provenance["collectionTitle"] = .string(collection.title.value)
        }
        return [
            "kind": .string(LabDocument.collectionItemKind),
            "fields": .object([:]),
            "provenance": .object(provenance),
            "attachments": .array([]),
            "extras": .object([:]),
        ]
    }
}
