import Foundation
import LabDomain

/// One portable lab object: the native `.anlab` document, schema version 1.
///
/// The document is the parsed JSON object itself, kept whole, with typed, validated views of the
/// fields the schema defines. Nothing a document carries is dropped: fields this build does not
/// know, at the top level, inside `fields`, `provenance`, an attachment, or `extras`, stay in the
/// tree and are written back out, and so do `null`, `0`, and `""`, each distinct from absent.
///
/// ```json
/// {
///   "format": "native-lab-object",
///   "schemaVersion": 1,
///   "documentID": "UUID: the object's stable identity",
///   "kind": "collection-item",
///   "revision": 1,
///   "title": "…",
///   "fields": {"note": "…"},
///   "provenance": {"origin": "native-lab", "namespace": "user", "collectionID": "UUID", "collectionTitle": "…"},
///   "attachments": [],
///   "extras": {}
/// }
/// ```
///
/// `format`, `schemaVersion`, `documentID`, `kind`, and `title` are required. `revision` is the
/// exporting store's revision of the object. `fields.note` is text, `null`, or absent. Each
/// attachment is `{"path", "byteCount", "sha256", "mediaType"?}` with a safe relative path. A
/// top-level field that claims authority or file access (a grant, scope, operation, or bookmark)
/// is refused rather than kept. The canonical form is UTF-8, two-space indented, with the schema's
/// fields in the order above, then every other member sorted by the UTF-8 bytes of its key.
public struct LabDocument: Hashable, Sendable {
    public static let format = "native-lab-object"
    public static let schemaVersion = 1
    public static let collectionItemKind = "collection-item"
    public static let fileExtension = "anlab"

    /// The schema's top-level fields, in canonical order.
    static let schemaFields = [
        "format", "schemaVersion", "documentID", "kind", "revision", "title", "fields", "provenance", "attachments", "extras",
    ]

    /// Top-level names that claim authority or file access. A document is data only: it can never
    /// carry a grant, scope, adapter, operation, or permission, and it never carries a
    /// security-scoped bookmark or another way to reach a file outside itself. Compared without
    /// regard to case.
    static let authorityFields: Set<String> = [
        "actor", "adapter", "authorization", "bookmark", "bookmarkdata", "bookmarks", "grant", "grants", "operation",
        "operations", "permission", "permissions", "scope", "scopes", "securityscope",
    ]

    /// The whole document as read or built.
    public let root: [String: PortableValue]
    public let documentID: UUID
    public let kind: String
    /// The revision the exporting store had, when the document says.
    public let revision: Int?
    /// The title exactly as the document spells it.
    public let title: String
    public let note: NoteField
    public let attachments: [AttachmentDescriptor]

    /// `fields.note`: text, an explicit `null`, or absent. The three stay distinct.
    public enum NoteField: Hashable, Sendable {
        case text(String)
        case null
        case absent

        public var text: String? {
            if case .text(let value) = self { value } else { nil }
        }
    }

    /// One attachment the document lists. A bare `.anlab` carries no attachment bytes.
    public struct AttachmentDescriptor: Hashable, Sendable {
        public let path: StagedPath
        public let byteCount: Int
        public let sha256: ContentDigest
        public let mediaType: String?
    }

    public var itemID: ItemID { ItemID(rawValue: documentID) }

    // MARK: Reading

    /// Reads and validates a document from untrusted bytes: strict JSON within `limits` (size and
    /// nesting), then every schema rule.
    public init(decoding data: Data, limits: ImportLimits = .standard) throws(PortableObjectError) {
        let value: PortableValue
        do {
            value = try PortableValue.parse(
                untrusted: Array(data), maximumDepth: limits.maximumNestingDepth, maximumBytes: limits.maximumTextBytes
            )
        } catch {
            throw .staging(.malformedJSON(file: 1, error))
        }
        try self.init(validating: value, limits: limits)
    }

    /// Validates a parsed value as a document.
    public init(validating value: PortableValue, limits: ImportLimits = .standard) throws(PortableObjectError) {
        guard let root = value.objectValue, root["format"]?.stringValue == Self.format else { throw .notALabObject }

        guard let versionValue = root["schemaVersion"] else { throw .missingField(.schemaVersion) }
        guard let version = versionValue.integerValue else { throw .wrongType(.schemaVersion) }
        guard version <= Self.schemaVersion else { throw .newerSchema(found: version, supported: Self.schemaVersion) }
        guard version == Self.schemaVersion else { throw .unsupportedSchema }

        if root.keys.contains(where: { Self.authorityFields.contains($0.lowercased()) }) { throw .authorityField }

        guard let idValue = root["documentID"] else { throw .missingField(.documentID) }
        guard let idText = idValue.stringValue else { throw .wrongType(.documentID) }
        guard let documentID = UUID(uuidString: idText) else { throw .invalidDocumentID }

        guard let kindValue = root["kind"] else { throw .missingField(.kind) }
        guard let kind = kindValue.stringValue else { throw .wrongType(.kind) }
        guard kind == Self.collectionItemKind else { throw .unsupportedKind }

        var revision: Int?
        if let revisionValue = root["revision"] {
            guard let number = revisionValue.integerValue, number >= 1 else { throw .invalidRevision }
            revision = number
        }

        guard let titleValue = root["title"] else { throw .missingField(.title) }
        guard let title = titleValue.stringValue else { throw .wrongType(.title) }
        do { _ = try EntityTitle(title) } catch { throw .invalidTitle(error) }

        var note = NoteField.absent
        if let fields = root["fields"] {
            guard let members = fields.objectValue else { throw .wrongType(.fields) }
            switch members["note"] {
            case nil: note = .absent
            case .null?: note = .null
            case .string(let text)?:
                do { _ = try ItemNote(text) } catch { throw .invalidNote(error) }
                note = .text(text)
            default: throw .wrongType(.note)
            }
        }
        for field in [DocumentField.provenance, .extras] {
            if let member = root[field.rawValue], member.objectValue == nil { throw .wrongType(field) }
        }

        self.root = root
        self.documentID = documentID
        self.kind = kind
        self.revision = revision
        self.title = title
        self.note = note
        attachments = try Self.attachments(in: root["attachments"], limits: limits)
    }

    private static func attachments(in value: PortableValue?, limits: ImportLimits) throws(PortableObjectError) -> [AttachmentDescriptor] {
        guard let value else { return [] }
        guard let elements = value.arrayValue else { throw .wrongType(.attachments) }
        guard elements.count <= limits.maximumFiles else { throw .tooManyAttachments(limit: limits.maximumFiles) }
        var paths = StagedPathSet()
        var total = 0
        var descriptors: [AttachmentDescriptor] = []
        for (index, element) in elements.enumerated() {
            let position = index + 1
            guard let members = element.objectValue,
                  let rawPath = members["path"]?.stringValue,
                  let byteCount = members["byteCount"]?.integerValue, byteCount >= 0,
                  let digestText = members["sha256"]?.stringValue, let digest = ContentDigest(hex: digestText)
            else { throw .invalidAttachment(position: position) }
            let path: StagedPath
            do { path = try StagedPath(rawPath, limits: limits) } catch { throw .unsafeAttachmentPath(position: position, error) }
            guard paths.insert(path, isDirectory: false) else { throw .duplicateAttachmentPath(position: position) }
            guard byteCount <= limits.maximumTotalBytes - total else { throw .attachmentsTooLarge(limit: limits.maximumTotalBytes) }
            total += byteCount
            let mediaType: String?
            switch members["mediaType"] {
            case nil: mediaType = nil
            case .string(let text)?: mediaType = text
            default: throw .invalidAttachment(position: position)
            }
            descriptors.append(AttachmentDescriptor(path: path, byteCount: byteCount, sha256: digest, mediaType: mediaType))
        }
        return descriptors
    }

    // MARK: Writing

    /// The canonical `.anlab` bytes. JSON is the same bytes: the native document is JSON.
    public func encoded() -> Data {
        Data(canonicalText.utf8)
    }

    public var canonicalText: String {
        PortableValue.object(root).canonicalText(topLevelOrder: Self.schemaFields)
    }

    /// SHA-256 of the canonical bytes: the identity of this exact content.
    public var digest: ContentDigest { ContentDigest.sha256(encoded()) }

    /// A readable summary for people and text-only destinations. It is lossy by design: it keeps
    /// the title, note, identity, and revision, and says what it leaves out.
    public var plainText: String {
        var lines = [title]
        if let text = note.text, !text.isEmpty { lines += ["", text] }
        lines += ["", "Native Lab object (\(kind))", "Identifier: \(documentID.uuidString)"]
        if let revision { lines.append("Revision: \(revision)") }
        if let collection = provenanceCollectionTitle { lines.append("Collection: \(collection)") }
        lines += [
            "",
            "This text is a summary. The .anlab document keeps every field, including \(counted(keptFieldCount, "other field")).",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Inspection

    /// Members of `extras`.
    public var extrasCount: Int { root["extras"]?.objectValue?.count ?? 0 }

    /// Fields the schema does not define: at the top level and inside `fields`. They are kept.
    public var unknownFieldCount: Int {
        let topLevel = root.keys.filter { !Self.schemaFields.contains($0) }.count
        let inFields = root["fields"]?.objectValue?.keys.filter { $0 != "note" }.count ?? 0
        return topLevel + inFields
    }

    /// Everything the plain-text summary leaves out: unknown fields, extras, and provenance.
    var keptFieldCount: Int {
        unknownFieldCount + extrasCount + (root["provenance"]?.objectValue?.count ?? 0) + attachments.count
    }

    public var provenanceCollectionTitle: String? {
        root["provenance"]?.objectValue?["collectionTitle"]?.stringValue
    }

    public var provenanceOrigin: String? {
        root["provenance"]?.objectValue?["origin"]?.stringValue
    }

    private func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    // MARK: Equality

    /// Two documents are equal when their canonical bytes are.
    public static func == (lhs: LabDocument, rhs: LabDocument) -> Bool {
        PortableValue.object(lhs.root) == PortableValue.object(rhs.root)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(PortableValue.object(root))
    }
}
