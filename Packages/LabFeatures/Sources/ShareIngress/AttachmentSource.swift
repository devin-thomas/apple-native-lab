import Foundation
import LabDomain
import LabStaging
import UniformTypeIdentifiers

/// One shared, pasted, or chosen attachment, before anything is read.
///
/// The share extension wraps each `NSItemProvider` (`ItemProviderAttachment`), and the host's
/// file picker and drop wrap each chosen URL (`ChosenFile`). Tests supply their own. Loading
/// copies bounded data while access to it is valid, and must stop promptly when its task is
/// cancelled.
public protocol AttachmentSource: Sendable {
    /// The type identifier the source declared, such as `public.jpeg`. Provenance only.
    var contentType: String? { get }

    /// Loads the attachment.
    ///
    /// - Parameters:
    ///   - budget: File bytes this intake may still take. A file larger than this is refused
    ///     before it is copied.
    ///   - scratch: A folder the station owns for temporary copies. It is removed when the
    ///     intake ends, however it ends.
    func load(budget: Int, scratch: URL) async throws(ImportRejection) -> LoadedAttachment
}

/// An attachment's content, ready to stage.
public enum LoadedAttachment: Sendable {
    /// Text as UTF-8 bytes. Ill-formed UTF-8 is refused when staged, never repaired.
    case text(Data)
    /// A web page's address and, when the source gave a usable one, its title.
    case link(URL, title: String?)
    /// A file, with its size known before staging so the intake's total can be enforced.
    case file(IncomingFile, byteCount: Int)
}

extension ImportRejection {
    /// Each attachment is staged as its own import, so a rejection that names a file names file
    /// 1. This names its position in the intake instead, so the message matches the list.
    func repositioned(_ position: Int) -> ImportRejection {
        switch self {
        case .unreadableSource: .unreadableSource(file: position)
        case .unsupportedFileType: .unsupportedFileType(file: position)
        case .unsafePath(_, let reason): .unsafePath(file: position, reason)
        case .duplicatePath: .duplicatePath(file: position)
        case .malformedJSON(_, let reason): .malformedJSON(file: position, reason)
        case .missingStagedFile: .missingStagedFile(file: position)
        case .stagedFileChanged: .stagedFileChanged(file: position)
        default: self
        }
    }
}

/// Copies a file into the scratch folder, refusing anything but an ordinary file within budget.
/// The copy is a clone where the file system supports it. The copy is named by position, never by
/// the shared name, which is only ever used as a label.
enum ScratchCopy {
    static func copy(_ url: URL, position: Int, budget: Int, limit: Int, into scratch: URL) throws(ImportRejection) -> (URL, Int) {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        } catch {
            throw .unreadableSource(file: position)
        }
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw .unsupportedFileType(file: position) }
        let size = values.fileSize ?? 0
        guard size <= budget else { throw .totalSizeTooLarge(limit: limit) }
        let destination = scratch.appending(path: "\(position)-\(UUID().uuidString)", directoryHint: .notDirectory)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            throw .unreadableSource(file: position)
        }
        return (destination, size)
    }

    /// A name for a shared file: the source's suggested name, given the type's extension when it
    /// has none, or else `fallback`. The result is still validated as a `StagedPath` when staged,
    /// and a hostile name is refused there.
    static func name(suggested: String?, loaded: URL?, typeIdentifier: String?, fallback: String) -> String {
        let ext = typeIdentifier.flatMap(preferredExtension)
        if let suggested, !suggested.isEmpty {
            if (suggested as NSString).pathExtension.isEmpty, let ext { return "\(suggested).\(ext)" }
            return suggested
        }
        if let loaded, !loaded.lastPathComponent.isEmpty { return loaded.lastPathComponent }
        return ext.map { "\(fallback).\($0)" } ?? fallback
    }

    static func preferredExtension(_ identifier: String) -> String? {
        UTType(identifier)?.preferredFilenameExtension
    }
}
