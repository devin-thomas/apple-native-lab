import Foundation
import LabDomain
import LabSupport
import Observation
import ShareIngress

/// Where the host keeps its own staging folder: beside the store, in the app's container. On the
/// Mac the App Sandbox resolves it inside the app's container, so no file entitlement is needed.
enum ShareInboxLocation {
    static let folderName = "Share Inbox"

    static func hostRoot() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return support.appending(path: LabStoreLocation.folderName, directoryHint: .isDirectory)
            .appending(path: folderName, directoryHint: .isDirectory)
    }
}

/// An import the person added this session, kept so its screen can show the result and receipt.
struct AddedImport: Hashable, Sendable {
    /// The import as it was reviewed, so its screen stays after it leaves the inbox.
    let entry: InboxEntry
    let collectionTitle: String
    let record: ReceiptRecord
    /// The same content was already in that collection; the original receipt came back.
    let isDuplicate: Bool
}

/// The host's share inbox (LAB-007): the import fallbacks that work in every build, and the
/// review list for everything staged, including what the share extension staged.
///
/// - Paste, the file picker, and drop stage into the host's own folder through `IngressStation`,
///   the same code the share extension runs, and are later adopted as the app UI.
/// - A SystemSurfaces build also reads the App Group folder the share extension writes; those
///   imports are adopted as the share extension.
/// - Adding goes through `LabLibrary.adoptImport`, `LabDataService`, `ImportAdopter`, and the one
///   `OperationService`, with a grant only the Add action issues, and leaves a receipt.
///
/// Nothing is added without the person choosing a collection and Add. Views read this model's
/// snapshots and call its actions.
@MainActor
@Observable
final class ShareInboxModel {
    enum Phase: Hashable {
        case notStarted
        case opening
        case ready
        /// The host's staging folder could not be opened. Nothing was changed.
        case unavailable(String)
    }

    /// Whether this build's share extension can reach the inbox.
    enum ShareSheetStatus: Hashable {
        /// A CoreLocal build: no share extension is built in; paste and the file picker import.
        case notInThisBuild
        /// A SystemSurfaces build whose App Group folder opened.
        case available
        /// A SystemSurfaces build without its App Group container, as under a free Personal Team.
        case unavailable
    }

    /// The intake running now.
    struct ActiveIntake: Hashable {
        let surface: IngressSurface
        let count: Int
    }

    /// The one inbox every window and tab shows.
    static let shared = ShareInboxModel()

    private(set) var phase: Phase = .notStarted
    private(set) var snapshot: InboxSnapshot = .empty
    private(set) var shareSheet: ShareSheetStatus
    private(set) var activeIntake: ActiveIntake?
    private(set) var lastReport: IntakeReport?
    /// Why the last add or removal failed, as a sentence, until the next one succeeds.
    private(set) var failure: String?
    private(set) var isAdding = false
    /// Imports added this session, by the entry they came from.
    private(set) var added: [InboxEntry.ID: AddedImport] = [:]
    /// The person's own collections that can take new items, by title.
    private(set) var collections: [LabCollection] = []
    /// The collection the person last chose, offered first next time.
    var destinationID: CollectionID?

    @ObservationIgnored private var inbox: ShareInbox?
    @ObservationIgnored private var hostStation: IngressStation?
    @ObservationIgnored private var intakeTask: Task<Void, Never>?
    @ObservationIgnored private var opening: Task<Void, Never>?
    @ObservationIgnored private let locateHost: @Sendable () throws -> URL
    @ObservationIgnored private let sharedRoot: URL?

    /// - Parameters:
    ///   - bundle: Its `LabAppGroupIdentifier` Info.plist key, present only in a SystemSurfaces
    ///     build, names the App Group folder the share extension writes.
    ///   - sharedRoot: A share-extension folder to read instead of the bundle's App Group, for tests.
    ///   - canChooseFiles: Whether this build can show the file picker; read from the running
    ///     build's entitlements unless a test states it.
    init(
        bundle: Bundle = .main,
        locateHost: @escaping @Sendable () throws -> URL = ShareInboxLocation.hostRoot,
        sharedRoot override: URL? = nil,
        canChooseFiles: Bool = ShareInboxModel.fileSelectionAllowed()
    ) {
        self.locateHost = locateHost
        self.canChooseFiles = canChooseFiles
        if let override {
            shareSheet = .available
            sharedRoot = override
        } else if IngressArea.declaredAppGroup(in: bundle) == nil {
            shareSheet = .notInThisBuild
            sharedRoot = nil
        } else if let root = IngressArea.shareExtensionRoot(for: bundle) {
            shareSheet = .available
            sharedRoot = root
        } else {
            shareSheet = .unavailable
            sharedRoot = nil
        }
    }

    /// Whether this build can show the file picker. A sandboxed Mac app may show an open panel
    /// only with a user-selected file entitlement, read-only or read-write; without one, AppKit
    /// refuses the panel, so Choose Files is disabled with its reason. The CoreLocal Mac host has
    /// carried `com.apple.security.files.user-selected.read-write` since LAB-008-A, so Choose Files
    /// is on there. iPhone and iPad need no entitlement.
    let canChooseFiles: Bool

    static func fileSelectionAllowed(_ source: some CapabilitySource = LiveCapabilitySource()) -> Bool {
        #if os(macOS)
        guard source.entitlement("com.apple.security.app-sandbox") == .present else { return true }
        return source.entitlement("com.apple.security.files.user-selected.read-only") == .present
            || source.entitlement("com.apple.security.files.user-selected.read-write") == .present
        #else
        return true
        #endif
    }

    /// The limits one import must stay within, shown before an import starts.
    var limits: ImportLimits { hostStation?.limits ?? .standard }

    // MARK: Lifecycle

    /// Opens the staging folders once and reads the inbox. Safe to call from every view.
    func start() async {
        if let opening {
            await opening.value
            return
        }
        let task = Task { await open() }
        opening = task
        await task.value
    }

    private func open() async {
        phase = .opening
        let host: IngressArea
        do {
            host = try IngressArea(source: .host, root: try locateHost())
        } catch {
            phase = .unavailable("The inbox folder in the app's container couldn't be opened. Nothing was imported.")
            return
        }
        var areas = [host]
        if let sharedRoot {
            if let shared = try? IngressArea(source: .shareExtension, root: sharedRoot) {
                areas.append(shared)
            } else {
                shareSheet = .unavailable
            }
        }
        hostStation = IngressStation(area: host)
        inbox = ShareInbox(areas: areas)
        phase = .ready
        await refresh()
    }

    /// Reads the inbox again, for example when the app returns after a share.
    func refresh() async {
        guard let inbox else { return }
        snapshot = await inbox.snapshot()
    }

    // MARK: Intake (the fallbacks)

    var canImport: Bool { phase == .ready && activeIntake == nil }

    /// Pasted items. A file copied in the Finder or Files is read like a chosen file: the system
    /// grants access to exactly that file.
    func paste(_ providers: [NSItemProvider]) {
        receive(ItemProviderAttachment.attachments(from: providers, acceptsFileReferences: true), via: .paste)
    }

    func importFiles(_ urls: [URL]) {
        receive(ChosenFile.attachments(from: urls), via: .filePicker)
    }

    func drop(_ urls: [URL]) {
        receive(ChosenFile.attachments(from: urls), via: .drop)
    }

    /// Stops the running intake. Whatever it had staged is removed again.
    func cancelIntake() {
        intakeTask?.cancel()
    }

    private func receive(_ sources: [any AttachmentSource], via surface: IngressSurface) {
        guard canImport, let station = hostStation else { return }
        activeIntake = ActiveIntake(surface: surface, count: sources.count)
        intakeTask = Task { [weak self] in
            let report = await station.receive(sources, via: surface)
            guard let self else { return }
            lastReport = report
            activeIntake = nil
            intakeTask = nil
            await refresh()
            LabAnnouncement(intake: report).post()
        }
    }

    /// Waits for the running intake, if any. For tests and scripted runs.
    func waitForIntake() async {
        await intakeTask?.value
    }

    // MARK: Review

    /// Loads the person's collections that can take a new item.
    func loadCollections(from library: LabLibrary) async {
        do {
            let service = try await library.openedService()
            collections = try await service.collections(as: LabDataService.appUI)
                .filter { $0.namespace == .user && !$0.isArchived }
                .sorted { $0.title.value.localizedStandardCompare($1.title.value) == .orderedAscending }
            if let destinationID, !collections.contains(where: { $0.id == destinationID }) { self.destinationID = nil }
            if destinationID == nil, collections.count == 1 { destinationID = collections[0].id }
        } catch {
            collections = []
            failure = LibraryMessages.describe(error)
        }
    }

    /// Creates a collection of the person's own, through the same operation service, and chooses it.
    @discardableResult
    func createCollection(titled title: String, in library: LabLibrary) async -> Bool {
        let draft: CollectionDraft
        do {
            draft = CollectionDraft(title: try EntityTitle(title))
        } catch {
            failure = "A collection needs a title of 1 to \(EntityTitle.maximumLength) characters."
            return false
        }
        do {
            _ = try await library.submit(
                .createCollection(draft: draft), requestID: RequestID(), authority: .userAction,
                names: [.collection(draft.id): draft.title.value]
            )
        } catch {
            switch error {
            case .unavailable(let reason): failure = reason
            case .refused(let refusal): failure = LibraryMessages.describe(refusal)
            }
            return false
        }
        await loadCollections(from: library)
        destinationID = draft.id
        failure = nil
        return true
    }

    /// Adds a reviewed import to the chosen collection. This is the only path that commits one.
    @discardableResult
    func add(_ entry: InboxEntry, to collectionID: CollectionID, in library: LabLibrary) async -> AddedImport? {
        guard !isAdding, let inbox, let staging = await inbox.stagingInbox(for: entry.source) else { return nil }
        isAdding = true
        defer { isAdding = false }
        let title = collections.first { $0.id == collectionID }?.title.value ?? "your collection"
        do {
            let (record, isDuplicate) = try await library.adoptImport(
                entry.id.staging, from: staging, as: entry.source.adapter, into: collectionID
            )
            await inbox.didAdopt(entry.id)
            let result = AddedImport(entry: entry, collectionTitle: title, record: record, isDuplicate: isDuplicate)
            added[entry.id] = result
            destinationID = collectionID
            failure = nil
            await refresh()
            LabAnnouncement(receipt: ReceiptPresentation(record)).post()
            return result
        } catch {
            failure = error.message
            await refresh()
            LabAnnouncement(failure: error.message).post()
            return nil
        }
    }

    /// Removes a waiting import the person chose not to add.
    func discard(_ entry: InboxEntry) async {
        do {
            try await inbox?.discard(entry.id)
            failure = nil
        } catch {
            failure = error.userMessage
        }
        await refresh()
    }

    /// Removes an import that was set aside.
    func remove(_ entry: QuarantineEntry) async {
        do {
            try await inbox?.removeQuarantined(entry)
            failure = nil
        } catch {
            failure = error.userMessage
        }
        await refresh()
    }
}
