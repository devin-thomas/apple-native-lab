import Foundation
import LabDomain
import LabStaging
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import ShareIngress

/// A temporary folder holding one host area and one share-extension area, as a SystemSurfaces
/// host sees them. Removed when the test ends.
final class Station: @unchecked Sendable {
    let folder: URL
    let host: IngressArea
    let shared: IngressArea
    let diagnostics = DiagnosticsLog(sinks: [])

    init(limits: ImportLimits = .standard) throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ShareIngressTests-\(UUID().uuidString)")
        host = try IngressArea(source: .host, root: folder.appending(path: "host"), limits: limits, diagnostics: diagnostics)
        shared = try IngressArea(source: .shareExtension, root: folder.appending(path: "group"), limits: limits, diagnostics: diagnostics)
    }

    deinit { try? FileManager.default.removeItem(at: folder) }

    var hostStation: IngressStation { IngressStation(area: host, diagnostics: diagnostics) }
    var shareStation: IngressStation { IngressStation(area: shared, diagnostics: diagnostics) }
    var inbox: ShareInbox { ShareInbox(areas: [host, shared]) }

    /// Everything under an area's staging folder that is not an empty directory, relative.
    func leftovers(in area: IngressArea, _ subfolder: String) -> [String] {
        let folder = area.staging.root.appending(path: subfolder)
        return (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
    }
}

/// Synthetic bytes standing in for an original image or movie. Nothing here is real media.
enum SyntheticMedia {
    static func bytes(_ count: Int, seed: UInt8 = 7) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
    }
}

/// Builds `NSItemProvider`s the way the share sheet and pasteboard hand them over.
enum Providers {
    static func text(_ text: String) -> NSItemProvider {
        NSItemProvider(object: text as NSString)
    }

    static func utf8Bytes(_ data: Data) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    static func link(_ address: String) -> NSItemProvider {
        NSItemProvider(object: URL(string: address)! as NSURL)
    }

    /// A file-backed attachment, as Photos or Files provide: the file exists only while the
    /// completion handler runs.
    static func file(_ data: Data, type: UTType, suggestedName: String?, folder: URL) throws -> NSItemProvider {
        let url = folder.appending(path: "source-\(UUID().uuidString)")
        try data.write(to: url)
        let provider = NSItemProvider()
        provider.suggestedName = suggestedName
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            completion(url, false, nil)
            return nil
        }
        return provider
    }

    /// A cloud-backed attachment that is still downloading: it calls back only when released,
    /// and reports when its progress is cancelled.
    static func slowFile(_ gate: ProviderGate, type: UTType = .jpeg) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = "Harbor"
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            let progress = Progress(totalUnitCount: 100)
            progress.cancellationHandler = { gate.markCancelled() }
            gate.hold { url in completion(url, false, url == nil ? CocoaError(.userCancelled) : nil) }
            return progress
        }
        return provider
    }
}

/// Holds a slow provider's callback until the test releases it.
final class ProviderGate: Sendable {
    private struct State {
        var callback: (@Sendable (URL?) -> Void)?
        var started = false
        var cancelled = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    func hold(_ callback: @escaping @Sendable (URL?) -> Void) {
        let waiters = state.withLock { state in
            state.callback = callback
            state.started = true
            defer { state.waiters = [] }
            return state.waiters
        }
        waiters.forEach { $0.resume() }
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            let started = state.withLock { state in
                if !state.started { state.waiters.append(continuation) }
                return state.started
            }
            if started { continuation.resume() }
        }
    }

    func markCancelled() { state.withLock { $0.cancelled = true } }
    var wasCancelled: Bool { state.withLock { $0.cancelled } }

    /// Calls the held callback, as a download that finished (or failed) late would.
    func release(with url: URL?) {
        let callback = state.withLock { state in
            defer { state.callback = nil }
            return state.callback
        }
        callback?(url)
    }
}

/// An attachment whose bytes arrive slowly, chunk by chunk, until cancelled.
struct TricklingFile: AttachmentSource {
    let chunks: Int
    let chunkSize: Int
    let started: ProviderGate
    var contentType: String? { UTType.movie.identifier }

    func load(budget: Int, scratch: URL) async throws(ImportRejection) -> LoadedAttachment {
        let (chunks, chunkSize, started) = (chunks, chunkSize, started)
        let file = IncomingFile(name: "Trickle.mov") {
            AsyncThrowingStream { continuation in
                let task = Task {
                    for index in 0..<chunks {
                        if index == 1 { started.hold { _ in } }
                        try? await Task.sleep(for: .milliseconds(20))
                        if Task.isCancelled { break }
                        continuation.yield(SyntheticMedia.bytes(chunkSize, seed: UInt8(index % 200)))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        return .file(file, byteCount: chunks * chunkSize)
    }
}

/// A source that records whether it was ever loaded.
final class CountingSource: AttachmentSource, @unchecked Sendable {
    private let loads = Mutex(0)
    var contentType: String? { UTType.plainText.identifier }
    var loadCount: Int { loads.withLock { $0 } }

    func load(budget: Int, scratch: URL) async throws(ImportRejection) -> LoadedAttachment {
        loads.withLock { $0 += 1 }
        return .text(Data("counted".utf8))
    }
}

/// The app-UI actor, as the host composes it.
extension ActorScope {
    static let testAppUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
}

/// `Fixtures/hostile/` at the repository root, found from this source file.
enum HostileFixtures {
    static let folder = URL(filePath: #filePath)
        .deletingLastPathComponent() // ShareIngressTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LabFeatures
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository root
        .appending(path: "Fixtures/hostile")

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: folder.appending(path: name))
    }
}

extension AttachmentResult {
    var stagingID: StagingID? {
        switch self {
        case .staged(let id), .duplicate(let id): id
        case .refused, .cancelled: nil
        }
    }

    var rejection: ImportRejection? {
        if case .refused(let rejection) = self { rejection } else { nil }
    }
}
