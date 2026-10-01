import Foundation
import PortableObjects
import UniformTypeIdentifiers

/// A labeled preview of a custom document for Quick Look and the in-app browser.
///
/// Built from the same bytes the Quick Look extension receives, so Finder/Files and the document
/// browser agree without activating the File Provider.
public struct DocumentPreview: Hashable, Sendable {
    public let title: String
    public let subtitle: String
    public let plainText: String
    /// UTF-8 HTML suitable for `QLPreviewReply` with `UTType.html`.
    public let html: String
    public let documentID: UUID?
    public let revision: DocumentRevision?

    public init(
        title: String,
        subtitle: String,
        plainText: String,
        html: String,
        documentID: UUID? = nil,
        revision: DocumentRevision? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.plainText = plainText
        self.html = html
        self.documentID = documentID
        self.revision = revision
    }
}

/// Builds a preview from document bytes. Shared by the Quick Look extension and the host browser.
public enum DocumentPreviewBuilder {
    /// Previews a Native Lab `.anlab` object. Other formats are refused with a content-free error.
    public static func preview(of data: Data) throws(DocumentsEverywhereError) -> DocumentPreview {
        let document: LabDocument
        do throws(PortableObjectError) {
            document = try LabDocument(decoding: data)
        } catch {
            throw map(error)
        }

        let revision = document.revision.map(DocumentRevision.init(documentRevision:))
        let subtitle: String = {
            if let revision { return "Revision \(revision.content) · Native Lab object" }
            return "Native Lab object"
        }()
        let plain = document.plainText
        let html = htmlDocument(
            title: document.title,
            subtitle: subtitle,
            body: plain
        )
        return DocumentPreview(
            title: document.title,
            subtitle: subtitle,
            plainText: plain,
            html: html,
            documentID: document.documentID,
            revision: revision
        )
    }

    /// Previews a sample by loading its bundled resource bytes.
    public static func preview(sample id: ProviderItemID, from catalog: SampleCatalog = .bundled) throws(DocumentsEverywhereError) -> DocumentPreview {
        let data = try catalog.data(for: id)
        return try preview(of: data)
    }

    private static func htmlDocument(title: String, subtitle: String, body: String) -> String {
        let escapedTitle = escape(title)
        let escapedSubtitle = escape(subtitle)
        let escapedBody = escape(body).replacingOccurrences(of: "\n", with: "<br>\n")
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <title>\(escapedTitle)</title>
        <style>
        body { font: -apple-system-body; margin: 1.5rem; color: #1c1c1e; }
        h1 { font: -apple-system-headline; margin-bottom: 0.25rem; }
        .sub { color: #636366; margin-bottom: 1.25rem; }
        .body { white-space: pre-wrap; font: -apple-system-body; }
        </style>
        </head>
        <body>
        <h1>\(escapedTitle)</h1>
        <p class="sub">\(escapedSubtitle)</p>
        <div class="body">\(escapedBody)</div>
        </body>
        </html>
        """
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func map(_ error: PortableObjectError) -> DocumentsEverywhereError {
        switch error {
        case .notALabObject: .notALabObject
        case .newerSchema(let found, let supported): .newerSchema(found: found, supported: supported)
        case .unsupportedSchema: .unsupportedSchema
        case .missingField(let field): .missingField(field.rawValue)
        case .invalidDocumentID: .invalidDocumentID
        case .invalidRevision: .invalidRevision
        case .cancelled: .cancelled
        default: .notALabObject
        }
    }
}

extension UTType {
    /// Content type the Quick Look reply uses for the HTML preview.
    public static var documentsEverywherePreview: UTType { .html }
}
