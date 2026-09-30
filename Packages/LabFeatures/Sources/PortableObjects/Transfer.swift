import CoreTransferable
import Foundation
import LabDomain
import UniformTypeIdentifiers

/// The lab object's uniform type.
///
/// Its identifier follows the build's bundle prefix (`<prefix>.nativelab.object`), so a developer
/// with their own prefix exports their own type and no maintainer-owned identifier is assumed. The
/// host declares it in `UTExportedTypeDeclarations` (extension `anlab`, conforming to `public.json`)
/// and names it in the Info.plist key `LabObjectTypeIdentifier`, which this reads, so no source
/// hard-codes the prefix. A process without that key, such as a package test, uses the default
/// prefix's identifier.
public enum LabObjectType {
    public static let infoPlistKey = "LabObjectTypeIdentifier"
    public static let defaultIdentifier = "org.example.nativelab.object"

    public static let identifier: String = {
        guard let declared = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String,
              !declared.isEmpty, !declared.contains("$(")
        else { return defaultIdentifier }
        return declared
    }()
}

extension UTType {
    /// A Native Lab object: a `.anlab` JSON document.
    public static let labObject = UTType(exportedAs: LabObjectType.identifier, conformingTo: .json)
}

// MARK: - Export

/// One lab object on its way out: dragged to another window or app, shared, or saved to a file.
///
/// It offers, in order of fidelity:
///
/// 1. the native document (`UTType.labObject`, `.anlab`), complete;
/// 2. JSON (`public.json`, `.json`), the same bytes, for apps that read JSON but not lab objects;
/// 3. plain text (`public.utf8-plain-text`), a readable summary that is lossy by design.
///
/// A receiver takes the first it accepts. The native document is offered as a file too, because a
/// file manager (Finder, Files) accepts files, not data. No URL is offered: this build has no
/// destination a person approved that a link could open.
public struct PortableObject: Transferable, Hashable, Sendable {
    public let document: LabDocument
    /// The canonical bytes, computed once.
    public let data: Data

    public init(document: LabDocument) {
        self.document = document
        data = document.encoded()
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .labObject) { object in
            SentTransferredFile(try object.temporaryFile())
        }
        .suggestedFileName { $0.fileName(.nativeDocument) }
        DataRepresentation(exportedContentType: .labObject) { $0.data }
            .suggestedFileName { $0.fileName(.nativeDocument) }
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName { $0.fileName(.json) }
        DataRepresentation(exportedContentType: .utf8PlainText) { Data($0.document.plainText.utf8) }
            .suggestedFileName { $0.fileName(.plainText) }
    }

    /// Writes the document to a new file in the app's own temporary folder, named for the object,
    /// for a receiver that takes files. The receiver copies it; the system clears the folder.
    func temporaryFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Portable Objects/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fileName(.nativeDocument), directoryHint: .notDirectory)
        try data.write(to: url, options: [.withoutOverwriting])
        return url
    }

    /// A file name from the title: no path separators or leading dot, at most 60 characters,
    /// with the representation's extension.
    public func fileName(_ kind: RepresentationDescriptor.Kind) -> String {
        "\(Self.baseName(document.title)).\(kind.fileExtension ?? "txt")"
    }

    static func baseName(_ title: String) -> String {
        let replaced = title.unicodeScalars.map { scalar -> Character in
            "/:\\".unicodeScalars.contains(scalar) || scalar.properties.generalCategory == .control ? "-" : Character(scalar)
        }
        var name = String(replaced).trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespaces))
        if name.count > 60 { name = String(name.prefix(60)).trimmingCharacters(in: .whitespaces) }
        return name.isEmpty ? "Lab object" : name
    }
}

// MARK: - Import

/// One lab object arriving: dropped from another window or app. It only carries bytes; the
/// importer stages and validates them before anything else reads them.
///
/// A file is checked before it is read: it must be an ordinary file of at most `maximumBytes`,
/// or the object arrives refused with the reason, so the drop can say why. Bytes that arrive in
/// memory are checked the same way.
public struct IncomingObject: Transferable, Sendable {
    public enum Content: Sendable {
        case bytes(Data)
        case refused(PortableObjectError)
    }

    /// The largest document a drop accepts: the import limit for JSON text.
    public static let maximumBytes = ImportLimits.standard.maximumTextBytes

    public let content: Content

    public init(content: Content) {
        self.content = content
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .labObject) { received in IncomingObject(reading: received.file) }
        DataRepresentation(importedContentType: .labObject) { IncomingObject(data: $0) }
        FileRepresentation(importedContentType: .json) { received in IncomingObject(reading: received.file) }
        DataRepresentation(importedContentType: .json) { IncomingObject(data: $0) }
    }

    init(data: Data) {
        content = data.count <= Self.maximumBytes ? .bytes(data) : .refused(Self.tooLarge)
    }

    /// Reads a received file, which is only valid during the import, within the limit.
    init(reading url: URL) {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else {
            content = .refused(.staging(.unsupportedFileType(file: 1)))
            return
        }
        guard (values?.fileSize ?? 0) <= Self.maximumBytes else {
            content = .refused(Self.tooLarge)
            return
        }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
            content = data.count <= Self.maximumBytes ? .bytes(data) : .refused(Self.tooLarge)
        } catch {
            content = .refused(.staging(.unreadableSource(file: 1)))
        }
    }

    private static var tooLarge: PortableObjectError {
        .staging(.malformedJSON(file: 1, .tooLarge(limit: maximumBytes)))
    }
}

// MARK: - Representations

/// One way a lab object can leave the app, and what it keeps.
public struct RepresentationDescriptor: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case nativeDocument = "native-document"
        case json
        case plainText = "plain-text"
        case url

        public var fileExtension: String? {
            switch self {
            case .nativeDocument: LabDocument.fileExtension
            case .json: "json"
            case .plainText: "txt"
            case .url: nil
            }
        }
    }

    public enum Fidelity: Hashable, Sendable {
        /// Every field, byte for byte.
        case complete
        /// A readable summary that leaves fields out.
        case lossy
        /// Not offered, for the reason given.
        case notOffered(String)
    }

    public let kind: Kind
    public let title: String
    public let contentType: UTType?
    public let fidelity: Fidelity
    public let detail: String

    public var id: Kind { kind }

    /// Every representation, with what it keeps of `document`.
    public static func all(for document: LabDocument) -> [RepresentationDescriptor] {
        [
            RepresentationDescriptor(
                kind: .nativeDocument, title: "Lab object (.anlab)", contentType: .labObject, fidelity: .complete,
                detail: "The full native document. Import it on any device with Native Lab to get this object back, with its stable identity."
            ),
            RepresentationDescriptor(
                kind: .json, title: "JSON (.json)", contentType: .json, fidelity: .complete,
                detail: "The same bytes as the lab object, for apps that read JSON. Native Lab imports it too."
            ),
            RepresentationDescriptor(
                kind: .plainText, title: "Plain text (.txt)", contentType: .utf8PlainText, fidelity: .lossy,
                detail: "A readable summary: title, note, identifier, and revision. It leaves out \(document.keptFieldCount == 1 ? "1 other field" : "\(document.keptFieldCount) other fields") and can't be imported."
            ),
            RepresentationDescriptor(
                kind: .url, title: "Link", contentType: nil,
                fidelity: .notOffered("This build has no destination a link could open, so none is offered."),
                detail: "A link would need a place you approved to open it. None exists yet."
            ),
        ]
    }
}

// MARK: - Preview

/// One labeled field of a document, as a preview shows it.
public struct PreviewField: Hashable, Sendable, Identifiable {
    public let label: String
    public let value: String
    public var id: String { label }
}

extension LabDocument {
    /// Every field a person should see before exporting or importing this document.
    public var previewFields: [PreviewField] {
        let noteText = switch note {
        case .text(let text): text.isEmpty ? "Empty" : text
        case .null: "None (null)"
        case .absent: "None"
        }
        var rows = [
            PreviewField(label: "Title", value: title),
            PreviewField(label: "Note", value: noteText),
            PreviewField(label: "Stable identifier", value: documentID.uuidString),
            PreviewField(label: "Kind", value: kind),
        ]
        if let revision { rows.append(PreviewField(label: "Revision", value: "\(revision)")) }
        if let collection = provenanceCollectionTitle { rows.append(PreviewField(label: "Collection", value: collection)) }
        if let origin = provenanceOrigin { rows.append(PreviewField(label: "Origin", value: origin)) }
        rows.append(PreviewField(
            label: "Attachments",
            value: attachments.isEmpty ? "None" : (attachments.count == 1 ? "1 listed" : "\(attachments.count) listed")
        ))
        rows.append(PreviewField(label: "Extra fields", value: extrasCount == 0 ? "None" : "\(extrasCount), kept"))
        rows.append(PreviewField(
            label: "Other fields", value: unknownFieldCount == 0 ? "None" : "\(unknownFieldCount), kept as they are"
        ))
        return rows
    }
}

/// What an export will produce, before anything is written: the fields, the representations,
/// the file name, and the bytes.
public struct ExportPreview: Hashable, Sendable {
    public let object: PortableObject
    public let representations: [RepresentationDescriptor]
    /// Whether the item holds stored metadata the document does not include.
    public let omitsStoredMetadata: Bool

    public init(item: LabItem, collection: LabCollection?) throws(PortableObjectError) {
        let document = try DocumentMapping.document(for: item, in: collection)
        object = PortableObject(document: document)
        representations = RepresentationDescriptor.all(for: document)
        omitsStoredMetadata = DocumentMapping.hasUnexportedExtras(item)
    }

    public var document: LabDocument { object.document }
    public var fields: [PreviewField] { document.previewFields }
    public var text: String { document.canonicalText }
    public var byteCount: Int { object.data.count }
}

// MARK: - Bundled sample

/// The bundled sample object: an original fixture with a Unicode title, an empty note, extra
/// fields, and a field this build does not know, for trying an import on a new lab. It is imported
/// through the same staging and review as any file.
public enum PortableSample {
    public static let resourceName = "sample-object"

    public static var data: Data? {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: LabDocument.fileExtension) else { return nil }
        return try? Data(contentsOf: url)
    }
}
