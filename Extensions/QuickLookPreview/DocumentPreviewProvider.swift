import DocumentsEverywhere
import Foundation
import QuickLook
import UniformTypeIdentifiers

#if canImport(QuickLookSupport)
import QuickLookSupport
#endif
#if canImport(QuickLookUI)
import QuickLookUI
#endif

/// Quick Look preview for Native Lab `.anlab` documents (LAB-009).
///
/// Uses `DocumentPreviewBuilder` from DocumentsEverywhere so Finder/Files and the in-app browser
/// show the same preview. It never talks to the File Provider and needs no provider activation.
final class DocumentPreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(
        for request: QLFilePreviewRequest,
        completionHandler handler: @escaping @Sendable (QLPreviewReply?, (any Error)?) -> Void
    ) {
        let url = request.fileURL
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let preview = try DocumentPreviewBuilder.preview(of: data)
            let reply = QLPreviewReply(
                dataOfContentType: .html,
                contentSize: CGSize(width: 600, height: 400)
            ) { reply -> Data in
                reply.title = preview.title
                reply.stringEncoding = .utf8
                return Data(preview.html.utf8)
            }
            handler(reply, nil)
        } catch let error as DocumentsEverywhereError {
            handler(nil, error)
        } catch {
            handler(nil, DocumentsEverywhereError.notALabObject)
        }
    }
}
