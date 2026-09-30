import Foundation
import LabDomain

/// A field of a lab document, named in errors. Only the schema's own fields are named, never a
/// field a document invents: its sender chose that name, and it must not reach a message or log.
public enum DocumentField: String, Hashable, Sendable, CaseIterable {
    case format
    case schemaVersion
    case documentID
    case kind
    case revision
    case title
    case fields
    case note = "fields.note"
    case provenance
    case attachments
    case extras
}

/// Why a portable object was refused, cancelled, or not imported.
///
/// Like `ImportRejection`, every case is content-free: it names a schema field, a position, or a
/// limit, never a value, a file name, or a field the document invented. `userMessage` is a
/// sentence a person can act on and always says that nothing was imported or changed, `code` is
/// stable, and `category` is what diagnostics record. A refused document changes nothing.
public enum PortableObjectError: Error, Hashable, Sendable {
    // MARK: The document
    /// Staging or its checks refused the bytes: too large, not strict JSON, and so on.
    case staging(ImportRejection)
    /// Valid JSON, but not an object with `"format": "native-lab-object"`.
    case notALabObject
    /// A `schemaVersion` above the one this build reads.
    case newerSchema(found: Int, supported: Int)
    case unsupportedSchema
    case unsupportedKind
    case missingField(DocumentField)
    case wrongType(DocumentField)
    case invalidDocumentID
    case invalidRevision
    case invalidTitle(ValidationError)
    case invalidNote(ValidationError)
    /// A top-level field that claims authority or file access, such as a grant, scope, operation,
    /// or bookmark. A document is data only.
    case authorityField
    case tooManyAttachments(limit: Int)
    /// Attachment `position` (1-based) has an unsafe path, such as one with `..` in it.
    case unsafeAttachmentPath(position: Int, PathRejection)
    case duplicateAttachmentPath(position: Int)
    case invalidAttachment(position: Int)
    case attachmentsTooLarge(limit: Int)

    // MARK: Importing
    /// The document lists attachments, and this build stores objects without them.
    case attachmentsNotSupported(count: Int)
    /// The fields the item keeps as extras are over `ItemExtras.maximumBytes`.
    case extrasTooLarge(limit: Int)
    case noDestination
    /// The chosen collection is missing, archived, or a demo collection.
    case destinationUnavailable
    /// The staged bytes are not the ones that were reviewed.
    case changedSinceReview
    /// The lab changed after the review, so the reviewed plan no longer applies.
    case stateChanged
    /// The lab already holds this object with the same content; there is nothing to import.
    case nothingToImport
    /// The lab's copy is archived, so the document's changes cannot be applied to it.
    case storedCopyArchived
    case cancelled
    case notAuthorized
    case identifierConflict
    case storeUnavailable
    /// The host has not opened its store.
    case unavailable
}

extension PortableObjectError: LocalizedError, CustomStringConvertible {
    public var userMessage: String {
        switch self {
        case .staging(let rejection): Self.stagingMessage(rejection)
        case .notALabObject:
            "This file is not a Native Lab object: it has no \"format\": \"native-lab-object\". Nothing was imported."
        case .newerSchema(let found, let supported):
            "This object was saved in schema version \(found) by a newer version of the lab; this version reads version \(supported). Nothing was imported."
        case .unsupportedSchema: "This object's schema version is not one this version reads. Nothing was imported."
        case .unsupportedKind: "This object is of a kind this version can't import; it imports collection items. Nothing was imported."
        case .missingField(let field): "This object has no “\(field.rawValue)”, which every lab object needs. Nothing was imported."
        case .wrongType(let field): "This object's “\(field.rawValue)” has the wrong kind of value. Nothing was imported."
        case .invalidDocumentID: "This object's “documentID” is not a valid identifier. Nothing was imported."
        case .invalidRevision: "This object's “revision” must be a whole number of 1 or more. Nothing was imported."
        case .invalidTitle(let reason): "This object's title \(Self.phrase(reason)). Nothing was imported."
        case .invalidNote(let reason): "This object's note \(Self.phrase(reason)). Nothing was imported."
        case .authorityField:
            "This object carries a field that claims permissions or file access. Objects are data only, so it was refused. Nothing was imported."
        case .tooManyAttachments(let limit): "This object lists more than \(limit) attachments. Nothing was imported."
        case .unsafeAttachmentPath(let position, let reason):
            "Attachment \(position) \(PortableObjectError.pathPhrase(reason)), so the object was refused. Nothing was imported."
        case .duplicateAttachmentPath(let position):
            "Attachment \(position) has the same path as an earlier attachment, so the object was refused. Nothing was imported."
        case .invalidAttachment(let position):
            "Attachment \(position) needs a path, a byte count, and a SHA-256, so the object was refused. Nothing was imported."
        case .attachmentsTooLarge(let limit):
            "This object's attachments add up to more than \(ImportRejection.formatted(limit)). Nothing was imported."
        case .attachmentsNotSupported(let count):
            "This object lists \(count == 1 ? "1 attachment" : "\(count) attachments"). This version stores objects without attachments, and importing it would leave them behind, so nothing was imported."
        case .extrasTooLarge(let limit):
            "This object's extra fields take more than \(ImportRejection.formatted(limit)), more than one lab item keeps. Nothing was imported."
        case .noDestination: "Choose one of your collections to import into. Nothing was imported."
        case .destinationUnavailable: "The chosen collection can't take new items. Choose another of your collections. Nothing was imported."
        case .changedSinceReview: "The file changed after you reviewed it, so it was not imported. Import it again."
        case .stateChanged: "The lab changed while you were reviewing this object. Review it again. Nothing was imported."
        case .nothingToImport: "This object is already in the lab with the same content. Nothing was imported."
        case .storedCopyArchived: "The lab's copy of this object is archived. Restore it before applying changes to it. Nothing was changed."
        case .cancelled: "The import was cancelled. Nothing was imported."
        case .notAuthorized: "This change isn't allowed from here. Nothing was imported."
        case .identifierConflict: "This import conflicts with an earlier request. Review the object again. Nothing was imported."
        case .storeUnavailable: "The lab store couldn't be used, so nothing was imported. Try again."
        case .unavailable: "The lab store isn't open yet. Try again in a moment. Nothing was imported."
        }
    }

    public var errorDescription: String? { userMessage }

    /// A stable, content-free code such as `unsafe-attachment-path/parent-reference`.
    public var code: String {
        switch self {
        case .staging(let rejection): "staging/\(rejection.code)"
        case .notALabObject: "not-a-lab-object"
        case .newerSchema: "newer-schema"
        case .unsupportedSchema: "unsupported-schema"
        case .unsupportedKind: "unsupported-kind"
        case .missingField(let field): "missing-field/\(field.rawValue)"
        case .wrongType(let field): "wrong-type/\(field.rawValue)"
        case .invalidDocumentID: "invalid-document-id"
        case .invalidRevision: "invalid-revision"
        case .invalidTitle: "invalid-title"
        case .invalidNote: "invalid-note"
        case .authorityField: "authority-field"
        case .tooManyAttachments: "too-many-attachments"
        case .unsafeAttachmentPath(_, let reason): "unsafe-attachment-path/\(reason.rawValue)"
        case .duplicateAttachmentPath: "duplicate-attachment-path"
        case .invalidAttachment: "invalid-attachment"
        case .attachmentsTooLarge: "attachments-too-large"
        case .attachmentsNotSupported: "attachments-not-supported"
        case .extrasTooLarge: "extras-too-large"
        case .noDestination: "no-destination"
        case .destinationUnavailable: "destination-unavailable"
        case .changedSinceReview: "changed-since-review"
        case .stateChanged: "state-changed"
        case .nothingToImport: "nothing-to-import"
        case .storedCopyArchived: "stored-copy-archived"
        case .cancelled: "cancelled"
        case .notAuthorized: "not-authorized"
        case .identifierConflict: "identifier-conflict"
        case .storeUnavailable: "store-unavailable"
        case .unavailable: "unavailable"
        }
    }

    public var description: String { code }

    public var category: DiagnosticCategory {
        switch self {
        case .staging(let rejection): rejection.category
        case .notALabObject, .missingField, .wrongType, .invalidDocumentID, .invalidRevision, .invalidTitle, .invalidNote,
             .invalidAttachment:
            .malformedData
        case .newerSchema, .unsupportedSchema, .unsupportedKind, .attachmentsNotSupported: .unsupported
        case .authorityField: .invalidInput
        case .tooManyAttachments, .attachmentsTooLarge, .extrasTooLarge: .tooLarge
        case .unsafeAttachmentPath, .duplicateAttachmentPath: .unsafePath
        case .noDestination, .destinationUnavailable: .notFound
        case .changedSinceReview: .tamperedStaging
        case .stateChanged, .storedCopyArchived: .conflict
        case .nothingToImport, .identifierConflict: .duplicate
        case .cancelled: .cancelled
        case .notAuthorized: .unauthorized
        case .storeUnavailable: .storeFailure
        case .unavailable: .unavailable
        }
    }

    /// Staging's own sentences name "file 1", which means the document here, so the common cases
    /// get a sentence about the document instead.
    private static func stagingMessage(_ rejection: ImportRejection) -> String {
        switch rejection {
        case .malformedJSON(_, .tooLarge(let limit)), .textTooLarge(let limit), .totalSizeTooLarge(let limit):
            "The document is larger than \(ImportRejection.formatted(limit)), the most a lab object can be. Nothing was imported."
        case .malformedJSON(_, let reason):
            "The document \(reason.documentPhrase), so it was refused. Nothing was imported."
        case .unreadableSource: "The file couldn't be read. Nothing was imported."
        case .unsupportedFileType: "That is not an ordinary file, so it can't be imported. Nothing was imported."
        case .cancelled: "The import was cancelled. Nothing was imported."
        default: rejection.userMessage
        }
    }

    private static func phrase(_ reason: ValidationError) -> String {
        switch reason {
        case .emptyTitle: "is empty"
        case .titleTooLong(let limit): "is longer than \(limit) characters"
        case .noteTooLong(let limit): "is longer than \(limit) characters"
        case .controlCharacter: "contains control characters that can't be stored"
        default: "is not valid"
        }
    }

    static func pathPhrase(_ reason: PathRejection) -> String {
        switch reason {
        case .parentReference: "has a path that points outside the object (it contains “..”)"
        case .absolute: "has a path that starts at the top of a disk"
        case .currentReference: "has a path with a “.” folder in it"
        case .emptyComponent: "has a path with an empty folder in it"
        case .backslash: "has a path with a backslash in it"
        case .lookalikeSeparator: "has a path with a character that works or looks like a folder separator"
        case .lookalikeDot: "has a path made of characters that stand for “.” or “..”"
        case .bidiControl: "has a path with a hidden text-direction character"
        case .invisibleCharacter: "has a path with an invisible character in it"
        default: "has an unsafe path"
        }
    }
}

extension StrictJSONError {
    /// The problem as the end of a sentence about a document.
    var documentPhrase: String {
        switch self {
        case .empty: "is empty"
        case .tooLarge: "is too large"
        case .invalidUTF8: "contains bytes that are not valid text"
        case .tooDeep(let limit): "is nested more than \(limit) levels deep"
        case .duplicateKey: "names the same field twice"
        case .unpairedSurrogate: "contains a broken character escape"
        case .invalidSyntax: "is not valid JSON"
        }
    }
}

extension ImportRejection {
    /// A byte count in the units people read, such as “2 MB”.
    static func formatted(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .binary)
    }
}
