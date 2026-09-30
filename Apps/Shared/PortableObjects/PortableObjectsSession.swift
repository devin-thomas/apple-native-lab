import Foundation
import LabDomain
import Observation
import PortableObjects

/// LAB-008 Portable Objects in one window: the objects it can export, and the import under review.
///
/// Reads go through `LabDataService` as the app UI. The only commit is an import a person chose,
/// through `LabLibrary.submit`, so its receipt joins the session's receipts. Every import, from a
/// file, a drop, or the bundled sample, is staged and validated by `PortableObjectsImporter`
/// before anything is planned, and nothing here writes the store.
@MainActor
@Observable
final class PortableObjectsSession {
    /// One exportable object: an item with its collection.
    struct Entry: Identifiable, Hashable {
        let item: LabItem
        let collection: LabCollection?

        var id: ItemID { item.id }
        var collectionTitle: String { collection?.title.value ?? "Unknown collection" }
    }

    /// The objects of one collection.
    struct Group: Identifiable, Hashable {
        let collection: LabCollection
        let entries: [Entry]

        var id: CollectionID { collection.id }
    }

    /// What the last finished import did.
    struct Outcome: Hashable {
        let record: ReceiptRecord
        let sentence: String
        /// The object the import created or changed, which the list selects.
        let itemID: ItemID
    }

    private(set) var groups: [Group] = []
    /// Collections of your own that can take a new object: user data, not archived.
    private(set) var destinations: [LabCollection] = []
    var selectedItemID: ItemID?
    private(set) var review: ImportReview?
    var destinationID: CollectionID?
    /// Why the last step failed, as a sentence for the person, until the next one succeeds.
    private(set) var message: String?
    private(set) var outcome: Outcome?
    private(set) var isWorking = false

    @ObservationIgnored private var importer: PortableObjectsImporter?
    @ObservationIgnored private let locateStaging: @Sendable () throws -> URL

    /// Staged imports a previous launch left behind are removed once per launch, before any
    /// window could have one under review.
    private static var sweptThisLaunch = false

    init(locateStaging: @escaping @Sendable () throws -> URL = PortableObjectsSession.defaultStagingRoot) {
        self.locateStaging = locateStaging
    }

    /// `Application Support › Native Lab › Portable Objects Staging`, beside the store, in the
    /// app's own container.
    nonisolated static func defaultStagingRoot() throws -> URL {
        try LabStoreLocation.defaultURL().deletingLastPathComponent()
            .appending(path: "Portable Objects Staging", directoryHint: .isDirectory)
    }

    // MARK: Reading

    /// Reads every object and collection again through the service.
    func load(_ library: LabLibrary) async {
        let backend = LibraryPortableBackend(library: library)
        do {
            let items = try await backend.items()
            let collections = try await backend.collections()
            let byID = Dictionary(collections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let grouped = Dictionary(grouping: items) { $0.collectionID }
            groups = grouped.compactMap { id, members -> Group? in
                guard let collection = byID[id] else { return nil }
                let entries = members
                    .sorted { $0.title.value.localizedStandardCompare($1.title.value) == .orderedAscending }
                    .map { Entry(item: $0, collection: collection) }
                return Group(collection: collection, entries: entries)
            }
            .sorted(by: Self.groupOrder)
            destinations = collections.filter { $0.namespace == .user && !$0.isArchived }
                .sorted { $0.title.value.localizedStandardCompare($1.title.value) == .orderedAscending }
            if let chosen = destinationID, !destinations.contains(where: { $0.id == chosen }) { destinationID = nil }
            if destinationID == nil, destinations.count == 1 { destinationID = destinations[0].id }
        } catch {
            message = error.userMessage
        }
    }

    var entries: [Entry] { groups.flatMap(\.entries) }

    func entry(_ id: ItemID?) -> Entry? {
        id.flatMap { id in entries.first { $0.id == id } }
    }

    /// What exporting an object would produce. Computed from the object as read; nothing is written.
    func exportPreview(for id: ItemID?) -> ExportPreview? {
        guard let entry = entry(id) else { return nil }
        return try? ExportPreview(item: entry.item, collection: entry.collection)
    }

    /// The object as a drag or share carries it.
    func portableObject(for entry: Entry) -> PortableObject? {
        (try? ExportPreview(item: entry.item, collection: entry.collection))?.object
    }

    // MARK: Importing

    /// Stages and reviews objects dropped on this window. The first one is reviewed; a refused
    /// one says why.
    func receive(_ incoming: [IncomingObject], library: LabLibrary) async {
        guard let first = incoming.first else { return }
        switch first.content {
        case .bytes(let data):
            await open(library) { importer throws(PortableObjectError) in try await importer.review(data: data) }
        case .refused(let reason):
            fail(reason)
        }
    }

    /// Stages and reviews a file a person chose.
    func open(fileAt url: URL, library: LabLibrary) async {
        await open(library) { importer throws(PortableObjectError) in try await importer.review(fileAt: url) }
    }

    /// Stages and reviews the bundled sample object, through the same path as a file.
    func openSample(library: LabLibrary) async {
        guard let data = PortableSample.data else {
            message = "This build is missing its sample object. Nothing was imported."
            return
        }
        await open(library) { importer throws(PortableObjectError) in try await importer.review(data: data) }
    }

    private func open(
        _ library: LabLibrary,
        _ stage: (PortableObjectsImporter) async throws(PortableObjectError) -> ImportReview
    ) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        if let previous = review { await importer?.discard(previous.id) }
        review = nil
        outcome = nil
        do {
            let importer = try await openedImporter(library)
            let staged = try await stage(importer)
            await load(library)
            review = staged
            message = nil
        } catch {
            fail(error)
        }
    }

    /// Commits the reviewed import through the library and lists its receipt.
    @discardableResult
    func commit(library: LabLibrary) async -> ReceiptRecord? {
        guard let review, let importer, !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await importer.commit(review, into: destinationID)
            await load(library)
            self.review = nil
            message = nil
            let record = library.receipt(id: result.receipt.operationID)
                ?? ReceiptRecord(receipt: result.receipt, recordedAt: .now, names: [.item(review.document.itemID): review.document.title])
            outcome = Outcome(record: record, sentence: Self.sentence(for: result), itemID: review.document.itemID)
            selectedItemID = review.document.itemID
            return record
        } catch {
            await load(library)
            fail(error)
            return nil
        }
    }

    /// Closes the review and removes its staged bytes. Nothing was imported.
    func closeReview() async {
        guard let review else { return }
        self.review = nil
        await importer?.discard(review.id)
    }

    func dismissOutcome() {
        outcome = nil
    }

    private func openedImporter(_ library: LabLibrary) async throws(PortableObjectError) -> PortableObjectsImporter {
        if let importer { return importer }
        let root: URL
        do { root = try locateStaging() } catch { throw .staging(.stagingUnavailable) }
        let opened = try PortableObjectsImporter(backend: LibraryPortableBackend(library: library), stagingRoot: root)
        if !Self.sweptThisLaunch {
            Self.sweptThisLaunch = true
            for leftover in await opened.waitingImports() { await opened.discard(leftover) }
        }
        importer = opened
        return opened
    }

    private func fail(_ error: PortableObjectError) {
        message = error.userMessage
        LabAnnouncement(failure: error.userMessage).post()
    }

    private static func sentence(for result: ImportResult) -> String {
        let title = result.item?.title.value ?? "The object"
        switch (result.change, result.isReplay) {
        case (.created, false): return "Imported “\(title)” with its stable identifier."
        case (.updated, false): return "Applied the document's title and note to “\(title)”."
        case (_, true): return "This import had already been committed; its receipt is shown."
        }
    }

    /// Your own collections first, then the demo, each by title.
    private static func groupOrder(_ lhs: Group, _ rhs: Group) -> Bool {
        if lhs.collection.namespace != rhs.collection.namespace { return lhs.collection.namespace == .user }
        return lhs.collection.title.value.localizedStandardCompare(rhs.collection.title.value) == .orderedAscending
    }
}

/// Portable Objects' way into the host: reads as the app UI through `LabDataService`, and the
/// one commit, a person's import, through `LabLibrary.submit`. It never holds the store.
struct LibraryPortableBackend: PortableObjectsBackend {
    let library: LabLibrary

    func item(_ id: ItemID) async throws(PortableObjectError) -> LabItem? {
        let service = try await opened()
        do { return try await service.item(id, as: LabDataService.appUI) } catch .notFound { return nil } catch {
            throw PortableObjectError(error)
        }
    }

    func collection(_ id: CollectionID) async throws(PortableObjectError) -> LabCollection? {
        let service = try await opened()
        do { return try await service.collection(id, as: LabDataService.appUI) } catch .notFound { return nil } catch {
            throw PortableObjectError(error)
        }
    }

    func items() async throws(PortableObjectError) -> [LabItem] {
        let service = try await opened()
        let filter: ItemFilter
        do {
            filter = try ItemFilter(includeArchived: true, limit: ItemFilter.allowedLimits.upperBound)
        } catch {
            throw .storeUnavailable
        }
        do { return try await service.items(filter, as: LabDataService.appUI) } catch { throw PortableObjectError(error) }
    }

    func collections() async throws(PortableObjectError) -> [LabCollection] {
        let service = try await opened()
        do { return try await service.collections(as: LabDataService.appUI) } catch { throw PortableObjectError(error) }
    }

    func receipt(for requestID: RequestID) async throws(PortableObjectError) -> ActionReceipt? {
        let service = try await opened()
        do { return try await service.receipt(for: requestID, as: LabDataService.appUI) } catch { throw PortableObjectError(error) }
    }

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(PortableObjectError) -> ActionReceipt {
        do {
            return try await library.submit(operation, requestID: requestID, authority: .userAction, names: names).receipt
        } catch {
            switch error {
            case .unavailable: throw .unavailable
            case .refused(let refusal): throw PortableObjectError(refusal)
            }
        }
    }

    private func opened() async throws(PortableObjectError) -> LabDataService {
        do { return try await library.openedService() } catch { throw .unavailable }
    }
}
