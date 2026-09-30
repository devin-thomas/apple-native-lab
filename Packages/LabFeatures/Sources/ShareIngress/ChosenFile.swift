import Foundation
import LabDomain
import LabStaging
import UniformTypeIdentifiers

/// A file a person chose in the host's file picker or dropped on its inbox, as an
/// `AttachmentSource`.
///
/// Access to it lasts only while this loads: security-scoped access is started and stopped
/// here, and never stored as a bookmark. The file is read through a file coordinator, which
/// downloads a cloud-backed file first; cancelling the task cancels the coordinator, so a slow
/// download can be abandoned without leaving anything behind. The coordinated read clones the
/// file into the scratch folder, within the intake's budget, and staging reads that copy.
public struct ChosenFile: AttachmentSource {
    public let url: URL
    public let position: Int
    public let contentType: String?

    public init(url: URL, position: Int) {
        self.url = url
        self.position = position
        contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier
            ?? UTType(filenameExtension: url.pathExtension)?.identifier
    }

    /// Chosen or dropped URLs, in order.
    public static func attachments(from urls: [URL]) -> [ChosenFile] {
        urls.enumerated().map { ChosenFile(url: $1, position: $0 + 1) }
    }

    public func load(budget: Int, scratch: URL) async throws(ImportRejection) -> LoadedAttachment {
        guard !Task.isCancelled else { throw .cancelled }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let (url, position) = (url, position)
        let limit = ImportLimits.standard.maximumTotalBytes
        let coordinator = Coordinator()
        let copied: (URL, Int) = try await ItemProviderAttachment.bridge { finish in
            let progress = Progress(totalUnitCount: 1)
            progress.cancellationHandler = { coordinator.value.cancel() }
            DispatchQueue.global(qos: .userInitiated).async {
                var coordinationError: NSError?
                var ran = false
                coordinator.value.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readable in
                    ran = true
                    finish { () throws(ImportRejection) -> (URL, Int) in
                        try ScratchCopy.copy(readable, position: position, budget: budget, limit: limit, into: scratch)
                    }
                }
                if !ran {
                    finish { () throws(ImportRejection) -> (URL, Int) in
                        if let coordinationError, coordinationError.domain == NSCocoaErrorDomain,
                           coordinationError.code == NSUserCancelledError {
                            throw .cancelled
                        }
                        throw .unreadableSource(file: position)
                    }
                }
            }
            return progress
        }
        return .file(IncomingFile.contents(of: copied.0, name: url.lastPathComponent), byteCount: copied.1)
    }
}

/// `NSFileCoordinator` documents `cancel()` as callable from any thread; the coordinated read
/// itself runs on one background queue.
private final class Coordinator: @unchecked Sendable {
    let value = NSFileCoordinator()
}
