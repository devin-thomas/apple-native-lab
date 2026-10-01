import Foundation
import LabDomain

/// Why a Documents Everywhere action was refused, cancelled, or unavailable.
///
/// Every case is content-free: it names a field, a limit, or a state, never a file name or a
/// value from the document. `userMessage` is a sentence a person can act on; `code` is stable.
public enum DocumentsEverywhereError: Error, Hashable, Sendable {
    /// The bytes are not a Native Lab object the preview can read.
    case notALabObject
    case newerSchema(found: Int, supported: Int)
    case unsupportedSchema
    case missingField(String)
    case invalidDocumentID
    case invalidRevision
    /// The sample catalog does not name this identifier.
    case unknownSample
    /// The file or mirror entry is gone.
    case notFound
    /// An external edit arrived with a different base revision than the one this lab holds.
    case revisionConflict(expected: DocumentRevision, found: DocumentRevision)
    /// The provider is not active in this build (disabled until qualified).
    case providerDisabled
    /// The provider was connected, then disconnected; the authoritative source is untouched.
    case providerDisconnected
    case cancelled
    case notAuthorized
    case storeUnavailable
    case unavailable
    /// A path that would leave the experiment's fixture area.
    case unsafePath
    case invalidInput(String)
}

extension DocumentsEverywhereError: LocalizedError, CustomStringConvertible {
    public var userMessage: String {
        switch self {
        case .notALabObject:
            "This file is not a Native Lab object, so it has no Documents Everywhere preview."
        case .newerSchema(let found, let supported):
            "This object was saved in schema version \(found); this version reads version \(supported)."
        case .unsupportedSchema:
            "This object's schema version is not one this version reads."
        case .missingField(let field):
            "This object has no “\(field)”, which every lab object needs for a preview."
        case .invalidDocumentID:
            "This object's “documentID” is not a valid identifier."
        case .invalidRevision:
            "This object's “revision” must be a whole number of 1 or more."
        case .unknownSample:
            "That sample is not in this experiment's catalog."
        case .notFound:
            "That document is not available here."
        case .revisionConflict:
            "This document changed elsewhere since it was last opened here. Review both revisions before applying anything."
        case .providerDisabled:
            "The sample File Provider stays disabled in this build until it is qualified. Use the document browser instead."
        case .providerDisconnected:
            "The sample provider is disconnected. The lab's own copies of the documents are unchanged."
        case .cancelled:
            "The action was cancelled. Nothing was changed."
        case .notAuthorized:
            "This change isn't allowed from here. Nothing was changed."
        case .storeUnavailable:
            "The lab store couldn't be used. Try again."
        case .unavailable:
            "Documents Everywhere isn't ready yet. Try again in a moment."
        case .unsafePath:
            "That path points outside the experiment's sample area, so it was refused."
        case .invalidInput(let reason):
            "\(reason) Nothing was changed."
        }
    }

    public var errorDescription: String? { userMessage }

    public var code: String {
        switch self {
        case .notALabObject: "not-a-lab-object"
        case .newerSchema: "newer-schema"
        case .unsupportedSchema: "unsupported-schema"
        case .missingField(let field): "missing-field/\(field)"
        case .invalidDocumentID: "invalid-document-id"
        case .invalidRevision: "invalid-revision"
        case .unknownSample: "unknown-sample"
        case .notFound: "not-found"
        case .revisionConflict: "revision-conflict"
        case .providerDisabled: "provider-disabled"
        case .providerDisconnected: "provider-disconnected"
        case .cancelled: "cancelled"
        case .notAuthorized: "not-authorized"
        case .storeUnavailable: "store-unavailable"
        case .unavailable: "unavailable"
        case .unsafePath: "unsafe-path"
        case .invalidInput: "invalid-input"
        }
    }

    public var description: String { code }

    public var category: DiagnosticCategory {
        switch self {
        case .notALabObject, .missingField, .invalidDocumentID, .invalidRevision, .invalidInput:
            .malformedData
        case .newerSchema, .unsupportedSchema: .unsupported
        case .unknownSample, .notFound: .notFound
        case .revisionConflict: .conflict
        case .providerDisabled, .providerDisconnected, .unavailable: .unavailable
        case .cancelled: .cancelled
        case .notAuthorized: .unauthorized
        case .storeUnavailable: .storeFailure
        case .unsafePath: .unsafePath
        }
    }
}
