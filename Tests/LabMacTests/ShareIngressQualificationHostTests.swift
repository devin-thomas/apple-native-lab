import Foundation
import LabDomain
import LabSupport
import ShareIngress
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import NativeLab

/// LAB-007-B in the sandboxed Mac host: Choose Files on this build and the disabled path without
/// the entitlement, cancelling an import from the inbox, hostile content, a stale review, and
/// Reset Demo beside imports. Each test uses a fresh store and fresh folders in the app
/// container's temporary folder, never the app's real store or inbox.
@MainActor
@Suite struct ShareIngressQualificationHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ShareIngressQualificationHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func started(canChooseFiles: Bool? = nil) async throws -> (LabLibrary, ShareInboxModel) {
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let hostRoot = folder.appending(path: "Share Inbox")
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let inbox = if let canChooseFiles {
            ShareInboxModel(locateHost: { hostRoot }, canChooseFiles: canChooseFiles)
        } else {
            ShareInboxModel(locateHost: { hostRoot })
        }
        await inbox.start()
        try #require(inbox.phase == .ready)
        return (library, inbox)
    }

    // MARK: Choose Files on the Mac

    /// This build is sandboxed and carries the user-selected read-write entitlement (added with
    /// LAB-008-A), so the inbox offers Choose Files. The entitlement is read from the running app's
    /// own signature.
    @Test func chooseFilesIsOnInThisMacBuild() async throws {
        let live = LiveCapabilitySource()
        #expect(live.entitlement("com.apple.security.app-sandbox") == .present)
        #expect(live.entitlement("com.apple.security.files.user-selected.read-write") == .present)
        #expect(ShareInboxModel.fileSelectionAllowed())
        let (_, inbox) = try await started()
        #expect(inbox.canChooseFiles)
    }

    /// Any sandboxed build without a user-selected file entitlement keeps Choose Files disabled
    /// with its reason, because AppKit would refuse the open panel.
    @Test func withoutTheEntitlementChooseFilesStaysDisabled() {
        #expect(!ShareInboxModel.fileSelectionAllowed(Entitlements(["com.apple.security.app-sandbox"])))
        #expect(ShareInboxModel.fileSelectionAllowed(Entitlements(["com.apple.security.app-sandbox", "com.apple.security.files.user-selected.read-only"])))
        #expect(ShareInboxModel.fileSelectionAllowed(Entitlements(["com.apple.security.app-sandbox", "com.apple.security.files.user-selected.read-write"])))
        #expect(ShareInboxModel.fileSelectionAllowed(Entitlements([])), "an unsandboxed build can always show the panel")
    }

    /// The file picker's path in the host: what the open panel returns is staged in order, marked
    /// File picker, and waits, since files cannot be added in this build.
    @Test func chosenFilesArriveInOrderAndWait() async throws {
        let (_, inbox) = try await started()
        let files = try ["harbor-sketch.png", "tide-clip.mov", "gull-count.txt"].map { name in
            let copy = folder.appending(path: name)
            try ShareIngressFixtures.intake(name).write(to: copy)
            return copy
        }
        inbox.importFiles(files)
        await inbox.waitForIntake()
        #expect(inbox.lastReport?.summary == "3 items are waiting for review.")
        let entries = inbox.snapshot.entries
        #expect(entries.map(\.headline) == ["harbor-sketch.png", "tide-clip.mov", "gull-count.txt"])
        #expect(entries.compactMap(\.origin?.surface) == [.filePicker, .filePicker, .filePicker])
        #expect(entries.compactMap(\.origin?.position) == [1, 2, 3])
        #expect(entries.compactMap(\.origin?.contentType) == [UTType.png.identifier, UTType.quickTimeMovie.identifier, UTType.plainText.identifier])
        #expect(entries.allSatisfy { $0.adoptability == .unavailable(.attachmentsNotAdoptable) })
        #expect(entries.map(\.symbolName) == ["photo", "film", "doc"])
        for entry in entries { await inbox.discard(entry) }
        #expect(inbox.snapshot.entries.isEmpty)
    }

    // MARK: Cancellation

    /// A paste whose file is still downloading is cancelled from the inbox's Cancel button: the
    /// inbox keeps nothing, says so, and the next paste works.
    @Test(.timeLimit(.minutes(1)))
    func cancellingAPasteWhileAFileDownloadsKeepsNothing() async throws {
        let (_, inbox) = try await started()
        let download = HeldDownload()
        inbox.paste([NSItemProvider(object: "Caption for the photo" as NSString), download.provider])
        #expect(inbox.activeIntake == ShareInboxModel.ActiveIntake(surface: .paste, count: 2))
        #expect(!inbox.canImport, "one import at a time")
        await download.waitUntilStarted()

        inbox.cancelIntake()
        await inbox.waitForIntake()
        #expect(inbox.lastReport?.wasCancelled == true)
        #expect(inbox.lastReport?.summary == "The import was cancelled. Nothing from it was kept.")
        #expect(inbox.snapshot.entries.isEmpty)
        #expect(inbox.activeIntake == nil && inbox.canImport)
        for _ in 0..<100 where !download.wasCancelled { try await Task.sleep(for: .milliseconds(10)) }
        #expect(download.wasCancelled, "the provider's progress was cancelled")

        inbox.paste([NSItemProvider(object: "After the cancel" as NSString)])
        await inbox.waitForIntake()
        #expect(inbox.snapshot.entries.map(\.headline) == ["After the cancel"])
    }

    // MARK: Malformed and hostile content

    /// A paste that mixes hostile content with good content refuses each bad item by position,
    /// never by content, and the good items are added normally afterwards.
    @Test func hostileContentPastedIntoTheHostNeverBlocksTheNextAdd() async throws {
        let (library, inbox) = try await started()
        let malformed = try ShareIngressFixtures.hostile("malformed-utf8.txt")
        let injection = String(decoding: try ShareIngressFixtures.hostile("prompt-injection.txt"), as: UTF8.self)
        let badBytes = NSItemProvider()
        badBytes.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            completion(malformed, nil)
            return nil
        }
        inbox.paste([
            badBytes,
            NSItemProvider(object: URL(string: "ftp://example.org/tides.txt")! as NSURL),
            NSItemProvider(object: URL(string: "https://user:secret@example.org/")! as NSURL),
            NSItemProvider(object: injection as NSString),
            NSItemProvider(object: "Harbor walk" as NSString),
        ])
        await inbox.waitForIntake()
        let report = try #require(inbox.lastReport)
        #expect(report.summary == "2 items are waiting for review, 3 were refused.")
        #expect(report.outcomes.filter(\.isRefused).map(\.position) == [1, 2, 3])
        let messages = report.outcomes.map(\.message).joined(separator: " ")
        #expect(!messages.contains("secret") && !messages.contains("ftp"))

        #expect(await inbox.createCollection(titled: "Field notes", in: library))
        let destination = try #require(inbox.destinationID)
        let receiptsBefore = library.receipts.count
        for entry in inbox.snapshot.entries {
            #expect(await inbox.add(entry, to: destination, in: library) != nil)
        }
        #expect(library.receipts.count == receiptsBefore + 2)
        #expect(library.census?.user == NamespaceCount(collections: 1, items: 2, archived: 0))
        #expect(library.census?.demo == NamespaceCount(collections: 3, items: 12, archived: 0), "the instructions did nothing")
        #expect(inbox.snapshot.entries.isEmpty)
    }

    // MARK: Stale state

    /// Another window removed the import after this one listed it. The Add says it is no longer
    /// waiting and commits nothing.
    @Test func anImportRemovedInAnotherWindowFailsItsAddAndCommitsNothing() async throws {
        let (library, inbox) = try await started()
        inbox.paste([NSItemProvider(object: "Removed elsewhere" as NSString)])
        await inbox.waitForIntake()
        let entry = try #require(inbox.snapshot.entries.first)
        #expect(await inbox.createCollection(titled: "Field notes", in: library))
        let destination = try #require(inbox.destinationID)

        let hostRoot = folder.appending(path: "Share Inbox")
        let otherWindow = ShareInboxModel(locateHost: { hostRoot })
        await otherWindow.start()
        let theirs = try #require(otherWindow.snapshot.entries.first)
        await otherWindow.discard(theirs)

        let receiptsBefore = library.receipts.count
        #expect(await inbox.add(entry, to: destination, in: library) == nil)
        #expect(inbox.failure == ImportRejection.notFound.userMessage)
        #expect(library.receipts.count == receiptsBefore)
        #expect(library.census?.user.items == 0)
        #expect(inbox.snapshot.entries.isEmpty, "the list was read again")
    }

    // MARK: Reset Demo beside imports

    /// Reset Demo restores an archived sample and leaves an added import and a waiting import
    /// exactly as they were.
    @Test func resetDemoLeavesAddedAndWaitingImportsAlone() async throws {
        let (library, inbox) = try await started()
        inbox.paste([NSItemProvider(object: "Harbor walk\nBring the blue notebook." as NSString)])
        await inbox.waitForIntake()
        #expect(await inbox.createCollection(titled: "Field notes", in: library))
        let destination = try #require(inbox.destinationID)
        let first = try #require(inbox.snapshot.entries.first)
        let added = try #require(await inbox.add(first, to: destination, in: library))
        inbox.paste([NSItemProvider(object: "Still waiting" as NSString)])
        await inbox.waitForIntake()
        let waiting = inbox.snapshot.entries

        let sample = try #require(library.collections.first?.items.first)
        #expect(await library.setArchived(sample, true) != nil)
        let reset = try #require(await library.resetDemo())
        #expect(reset.receipt.changes.map(\.entity) == [.item(sample.id)])
        #expect(reset.receipt.removed.isEmpty)
        #expect(library.census?.user == NamespaceCount(collections: 1, items: 1, archived: 0))
        #expect(library.census?.demo == NamespaceCount(collections: 3, items: 12, archived: 0))
        #expect(added.record.receipt.admitted.operation.kind == .createItem)
        await inbox.refresh()
        #expect(inbox.snapshot.entries == waiting)
    }
}

// MARK: - Support

/// A sandboxed or unsandboxed build with exactly these entitlements.
struct Entitlements: CapabilitySource {
    let present: Set<String>

    init(_ present: Set<String>) { self.present = present }

    var isSimulator: Bool { false }
    func permissionStatus(_ permission: PermissionKind) -> PermissionStatus { .notReadable }
    func hasCaptureDevice(_ kind: CaptureDeviceKind) -> Bool? { nil }
    func speechTranscription() async -> SpeechTranscriptionReading {
        SpeechTranscriptionReading(transcriberAvailable: nil, localeIdentifier: "en_US", asset: .unknown)
    }
    func languageModel() -> LanguageModelReading {
        LanguageModelReading(availability: .notCompiled, supportsCurrentLocale: nil, localeIdentifier: "en_US")
    }
    func worldTracking() -> WorldTrackingReading? { nil }
    func ultraWideband() -> UltraWidebandReading? { nil }
    func entitlement(_ key: String) -> EntitlementReading { present.contains(key) ? .present : .absent }
    func declaresPurposeString(_ key: String) -> Bool { false }
}

/// A file-backed item still downloading: it never calls back, and reports when its progress is
/// cancelled, as a cloud-backed photo does.
final class HeldDownload: @unchecked Sendable {
    private struct State {
        var started = false
        var cancelled = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())
    let provider: NSItemProvider

    init() {
        provider = NSItemProvider()
        provider.suggestedName = "Harbor"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { [self] _ in
            let progress = Progress(totalUnitCount: 100)
            progress.cancellationHandler = { [self] in state.withLock { $0.cancelled = true } }
            let waiters = state.withLock { state in
                state.started = true
                defer { state.waiters = [] }
                return state.waiters
            }
            waiters.forEach { $0.resume() }
            return progress
        }
    }

    var wasCancelled: Bool { state.withLock { $0.cancelled } }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            let started = state.withLock { state in
                if !state.started { state.waiters.append(continuation) }
                return state.started
            }
            if started { continuation.resume() }
        }
    }
}

/// The repository's fixtures, found from this source file.
enum ShareIngressFixtures {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent() // LabMacTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
    static let showcase = root.appending(path: "Fixtures/showcase/share-ingress", directoryHint: .isDirectory)

    static func intake(_ name: String) throws -> Data {
        try Data(contentsOf: showcase.appending(path: "intake/\(name)"))
    }

    static func hostile(_ name: String) throws -> Data {
        try Data(contentsOf: root.appending(path: "Fixtures/hostile/\(name)"))
    }
}
