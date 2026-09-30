import Foundation
import LabDomain
import LabStaging
import Synchronization
import UniformTypeIdentifiers

/// One `NSItemProvider` from the share sheet or the pasteboard, as an `AttachmentSource`.
///
/// It accepts the four kinds the experiment names, in this order of preference: a movie or an
/// image (a file), a file reference (a file copied in the Finder or Files), a web link (`http`
/// or `https`), and plain text. Anything else is refused as an unsupported type. Loading copies
/// bounded data while the provider's access is valid:
///
/// - A file is loaded with `loadFileRepresentation`, whose URL is valid only inside its
///   completion handler, so the handler checks its size against the intake's budget and clones
///   it into the scratch folder before returning. Nothing is read into memory.
/// - A file reference is read like a chosen file (`ChosenFile`): coordinated, cloned within budget.
/// - Text is loaded as UTF-8 bytes, so ill-formed text is refused rather than repaired.
/// - A link is loaded as a URL; the extension item's title is kept only when it is one short line.
///
/// Cancelling the task cancels the provider's `Progress` and returns at once, even if the
/// provider (for example a cloud-backed photo still downloading) never calls back. A late
/// callback copies nothing.
public struct ItemProviderAttachment: AttachmentSource, @unchecked Sendable {
    public enum Kind: String, Hashable, Sendable {
        case movie, image, fileReference, link, text, unsupported
    }

    // NSItemProvider is not Sendable. This value only calls its thread-safe loading methods.
    private let provider: NSItemProvider
    private let pageTitle: String?
    private let position: Int
    private let acceptsFileReferences: Bool
    public let kind: Kind
    /// The registered type the attachment is loaded as.
    public let contentType: String?

    /// - Parameters:
    ///   - position: 1-based position in the intake, for messages.
    ///   - pageTitle: A title the share sheet gave with a link, if any.
    ///   - acceptsFileReferences: Whether a reference to a local file may be read. Only the
    ///     host's paste and drop pass `true`: there the person copied or dragged the file, and
    ///     the system grants access to exactly that file. The share extension refuses file
    ///     references, so another app cannot point it at files it can read.
    public init(provider: NSItemProvider, position: Int, pageTitle: String? = nil, acceptsFileReferences: Bool = false) {
        self.provider = provider
        self.position = position
        self.pageTitle = pageTitle
        self.acceptsFileReferences = acceptsFileReferences
        let registered = provider.registeredTypeIdentifiers
        func first(conformingTo types: [UTType]) -> String? {
            registered.first { identifier in
                guard let type = UTType(identifier) else { return false }
                return types.contains { type.conforms(to: $0) }
            }
        }
        if let movie = first(conformingTo: [.movie, .audiovisualContent]) {
            (kind, contentType) = (.movie, movie)
        } else if let image = first(conformingTo: [.image]) {
            (kind, contentType) = (.image, image)
        } else if let file = first(conformingTo: [.fileURL]) {
            (kind, contentType) = (.fileReference, file)
        } else if let url = first(conformingTo: [.url]) {
            (kind, contentType) = (.link, url)
        } else if let text = first(conformingTo: [.plainText]) {
            (kind, contentType) = (.text, text)
        } else {
            (kind, contentType) = (.unsupported, registered.first)
        }
    }

    /// Every attachment of the share sheet's extension items, in order. A link's title comes
    /// from its item when that item holds exactly one attachment.
    public static func attachments(from items: [NSExtensionItem]) -> [ItemProviderAttachment] {
        var attachments: [ItemProviderAttachment] = []
        for item in items {
            let providers = item.attachments ?? []
            let title = providers.count == 1 ? usableTitle(item.attributedTitle?.string ?? item.attributedContentText?.string) : nil
            for provider in providers {
                attachments.append(ItemProviderAttachment(provider: provider, position: attachments.count + 1, pageTitle: title))
            }
        }
        return attachments
    }

    /// Pasted or dropped providers, in order. The host passes `acceptsFileReferences: true`.
    public static func attachments(from providers: [NSItemProvider], acceptsFileReferences: Bool = false) -> [ItemProviderAttachment] {
        providers.enumerated().map {
            ItemProviderAttachment(provider: $1, position: $0 + 1, acceptsFileReferences: acceptsFileReferences)
        }
    }

    /// A title is kept only when it is one line of ordinary text within the title limit. Anything
    /// else (a page's body text, say) is context the link does not need.
    static func usableTitle(_ raw: String?) -> String? {
        guard let title = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              title.utf8.count <= ImportLimits.standard.maximumTitleBytes,
              !title.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { return nil }
        return title
    }

    public func load(budget: Int, scratch: URL) async throws(ImportRejection) -> LoadedAttachment {
        guard !Task.isCancelled else { throw .cancelled }
        switch kind {
        case .movie, .image:
            return try await loadFile(budget: budget, scratch: scratch)
        case .fileReference:
            guard acceptsFileReferences else { throw .unsupportedFileType(file: position) }
            let url = try await loadURL()
            guard url.isFileURL else { throw .unsupportedFileType(file: position) }
            return try await ChosenFile(url: url, position: position).load(budget: budget, scratch: scratch)
        case .link:
            return try await loadLink()
        case .text:
            return try await loadText()
        case .unsupported:
            throw .unsupportedFileType(file: position)
        }
    }

    // MARK: Loading

    private func loadFile(budget: Int, scratch: URL) async throws(ImportRejection) -> LoadedAttachment {
        guard let type = contentType else { throw .unsupportedFileType(file: position) }
        let position = position
        let limit = ImportLimits.standard.maximumTotalBytes
        let copied: (URL, Int, String) = try await Self.bridge { finish in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                // The URL is valid only until this handler returns.
                finish { () throws(ImportRejection) -> (URL, Int, String) in
                    guard let url else { throw Self.rejection(for: error, position: position) }
                    let (copy, size) = try ScratchCopy.copy(url, position: position, budget: budget, limit: limit, into: scratch)
                    return (copy, size, url.lastPathComponent)
                }
            }
        }
        let fallback = kind == .movie ? "Shared movie \(position)" : "Shared image \(position)"
        let name = ScratchCopy.name(
            suggested: provider.suggestedName, loaded: URL(filePath: copied.2), typeIdentifier: type, fallback: fallback
        )
        return .file(IncomingFile.contents(of: copied.0, name: name), byteCount: copied.1)
    }

    private func loadLink() async throws(ImportRejection) -> LoadedAttachment {
        let url = try await loadURL()
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw .unsupportedLinkScheme
        }
        return .link(url, title: pageTitle)
    }

    private func loadURL() async throws(ImportRejection) -> URL {
        let position = position
        return try await Self.bridge { finish in
            provider.loadObject(ofClass: URL.self) { url, error in
                finish { () throws(ImportRejection) -> URL in
                    guard let url else { throw Self.rejection(for: error, position: position) }
                    return url
                }
            }
        }
    }

    private func loadText() async throws(ImportRejection) -> LoadedAttachment {
        let position = position
        let limit = ImportLimits.standard.maximumTextBytes
        if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
            let data: Data = try await Self.bridge { finish in
                provider.loadDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier) { data, error in
                    finish { () throws(ImportRejection) -> Data in
                        guard let data else { throw Self.rejection(for: error, position: position) }
                        guard data.count <= limit else { throw .textTooLarge(limit: limit) }
                        return data
                    }
                }
            }
            return .text(data)
        }
        let text: String = try await Self.bridge { finish in
            provider.loadObject(ofClass: String.self) { text, error in
                finish { () throws(ImportRejection) -> String in
                    guard let text else { throw Self.rejection(for: error, position: position) }
                    return text
                }
            }
        }
        return .text(Data(text.utf8))
    }

    private static func rejection(for error: (any Error)?, position: Int) -> ImportRejection {
        if let error = error as? CocoaError, error.code == .userCancelled { return .cancelled }
        if let error = error as NSError?, error.domain == NSCocoaErrorDomain, error.code == NSUserCancelledError { return .cancelled }
        return .unreadableSource(file: position)
    }

    /// Runs a callback-based load as a cancellable async call.
    ///
    /// `start` begins the load, returns its `Progress`, and calls `finish` from the callback with
    /// the work to do while the callback's data is valid. The first of the callback or a
    /// cancellation resumes the caller; whichever comes second does nothing, so a callback that
    /// arrives after a cancellation copies nothing.
    static func bridge<Value: Sendable>(
        _ start: (_ finish: @escaping @Sendable (() throws(ImportRejection) -> Value) -> Void) -> Progress
    ) async throws(ImportRejection) -> Value {
        let gate = LoadGate<Value>()
        let result: Result<Value, ImportRejection> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.begin(continuation)
                let progress = start { work in gate.finish(work) }
                gate.attach(progress)
            }
        } onCancel: {
            gate.cancel()
        }
        return try result.get()
    }
}

/// Resumes a load's caller exactly once: with the callback's result, or with a cancellation.
final class LoadGate<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Result<Value, ImportRejection>, Never>?
        var progress: Progress?
        var isCancelled = false
        var isDone = false
    }

    private let state = Mutex(State())

    func begin(_ continuation: CheckedContinuation<Result<Value, ImportRejection>, Never>) {
        let cancelledEarly = state.withLock { state -> Bool in
            state.continuation = continuation
            if state.isCancelled, !state.isDone {
                state.isDone = true
                return true
            }
            return false
        }
        if cancelledEarly { continuation.resume(returning: .failure(.cancelled)) }
    }

    func attach(_ progress: Progress) {
        let cancel = state.withLock { state -> Bool in
            state.progress = progress
            return state.isCancelled
        }
        if cancel { progress.cancel() }
    }

    /// Runs `work` only if nobody resumed the caller yet, then resumes it with the result.
    func finish(_ work: () throws(ImportRejection) -> Value) {
        let continuation = state.withLock { state -> CheckedContinuation<Result<Value, ImportRejection>, Never>? in
            guard !state.isDone else { return nil }
            state.isDone = true
            return state.continuation
        }
        guard let continuation else { return }
        do {
            continuation.resume(returning: .success(try work()))
        } catch {
            continuation.resume(returning: .failure(error))
        }
    }

    func cancel() {
        let (continuation, progress) = state.withLock { state -> (CheckedContinuation<Result<Value, ImportRejection>, Never>?, Progress?) in
            state.isCancelled = true
            guard !state.isDone, let continuation = state.continuation else { return (nil, state.progress) }
            state.isDone = true
            return (continuation, state.progress)
        }
        progress?.cancel()
        continuation?.resume(returning: .failure(.cancelled))
    }
}
