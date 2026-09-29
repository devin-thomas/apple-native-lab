import Foundation
import LabDomain
import LabStore
import Observation

/// The host's local data: the demo collections, the namespace census, and this session's receipts.
///
/// One instance serves every window. It opens the store in the app's container, seeds the demo
/// namespace on first run with the same Reset Demo operation a person can run, and sends every
/// change through `LabDataService` under the app-UI actor. Views read its snapshots and call its
/// actions; none of them sees the store or the service.
@MainActor
@Observable
final class LabLibrary {
    enum Phase: Hashable {
        case notStarted
        case opening
        case ready
        /// The store or the seed could not be used. Nothing was changed.
        case unavailable(String)
    }

    /// How many receipts the session keeps for the inspector, newest first.
    static let receiptLimit = 50

    private(set) var phase: Phase = .notStarted
    /// The seed's collections as stored, in seed order, each with its items ordered by title.
    private(set) var collections: [DemoCollection] = []
    private(set) var census: NamespaceCensus?
    /// Receipts from this session, newest first. They are not kept across launches.
    private(set) var receipts: [ReceiptRecord] = []
    /// A receipt whose undo offer was used, mapped to the receipt of that undo.
    private(set) var undone: [OperationID: OperationID] = [:]
    /// True while a change is being committed. Actions are refused until it finishes.
    private(set) var isWorking = false
    /// Why the last action or read failed, until the next one succeeds.
    private(set) var failure: String?
    private(set) var seed: DemoFixture?

    @ObservationIgnored private var service: LabDataService?
    @ObservationIgnored private var opening: Task<Void, Never>?
    @ObservationIgnored private let locateStore: @Sendable () throws -> URL
    @ObservationIgnored private let seedBundle: Bundle

    init(
        locateStore: @escaping @Sendable () throws -> URL = LabStoreLocation.defaultURL,
        seedBundle: Bundle = .main
    ) {
        self.locateStore = locateStore
        self.seedBundle = seedBundle
    }

    // MARK: Lifecycle

    /// Opens the store and seeds the demo on first run. Safe to call from every window; the work
    /// happens once.
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
        let fixture: DemoFixture
        do {
            fixture = try DemoSeedResource.load(from: seedBundle)
        } catch {
            phase = .unavailable(LibraryMessages.describe(error))
            return
        }
        seed = fixture
        do {
            service = try await LabDataService.open(at: try locateStore())
        } catch let error as StoreError {
            phase = .unavailable(LibraryMessages.describe(error))
            return
        } catch {
            phase = .unavailable("The app's Application Support folder is unavailable. Nothing was changed.")
            return
        }
        await refresh()
        // First run: an empty demo namespace receives the seed through the same authorized
        // operation as Reset Demo. It removes nothing, because there is nothing to remove, and a
        // demo that already exists is never reset without the person asking.
        if census?.demo == NamespaceCount(collections: 0, items: 0, archived: 0) {
            _ = await commit(.resetDemo(seed: fixture.seed), authority: .firstRunSeed)
        }
        phase = .ready
    }

    /// Reads the demo contents and the census again.
    func refresh() async {
        guard let service, let seed else { return }
        do {
            collections = try await service.demoContents(of: seed.seed)
        } catch {
            failure = LibraryMessages.describe(error)
        }
        do {
            census = try await service.census()
        } catch {
            census = nil
            failure = LibraryMessages.describe(error)
        }
    }

    // MARK: Actions

    var canAct: Bool { phase == .ready && !isWorking }

    /// Restores every demo sample to the seed and removes other demo entities. User data is never
    /// changed. Destructive and without undo, so callers confirm first.
    @discardableResult
    func resetDemo() async -> ReceiptRecord? {
        guard let seed else { return nil }
        return await commit(.resetDemo(seed: seed.seed), authority: .userAction)
    }

    /// Archives or restores one demo sample at the revision the caller saw.
    @discardableResult
    func setArchived(_ item: LabItem, _ archived: Bool) async -> ReceiptRecord? {
        guard item.namespace == .demo, item.isArchived != archived else { return nil }
        let operation: DomainOperation = archived
            ? .archiveItem(id: item.id, expected: item.revision)
            : .restoreItem(id: item.id, expected: item.revision)
        return await commit(operation, authority: .userAction)
    }

    /// Submits a receipt's undo offer as a new request. The offer is pinned to the revision the
    /// receipt produced, so if the entity changed since, the result is a conflict and nothing moves.
    @discardableResult
    func undo(_ record: ReceiptRecord) async -> ReceiptRecord? {
        guard let operation = record.receipt.undo, undone[record.id] == nil else { return nil }
        let result = await commit(operation, authority: .userAction)
        if let result, result.receipt.conflict == nil {
            undone[record.id] = result.id
        }
        return result
    }

    // MARK: Lookups

    var latestReceipt: ReceiptRecord? { receipts.first }

    func receipt(id: OperationID) -> ReceiptRecord? {
        receipts.first { $0.id == id }
    }

    func item(id: ItemID) -> LabItem? {
        collections.lazy.flatMap(\.items).first { $0.id == id }
    }

    func collection(containing item: LabItem) -> LabCollection? {
        collections.first { $0.id == item.collectionID }?.collection
    }

    /// Titles for every demo entity currently shown, for receipts to name what they touched.
    private var names: [EntityReference: String] {
        var names: [EntityReference: String] = [:]
        for content in collections {
            names[content.collection.reference] = content.collection.title.value
            for item in content.items { names[item.reference] = item.title.value }
        }
        return names
    }

    // MARK: Commit

    private func commit(_ operation: DomainOperation, authority: CommitAuthority) async -> ReceiptRecord? {
        guard let service, !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        let before = names
        do {
            let receipt = try await service.perform(operation, requestID: RequestID(), authority: authority)
            failure = nil
            await refresh()
            let record = ReceiptRecord(
                receipt: receipt, recordedAt: .now, names: before.merging(names) { _, current in current }
            )
            receipts.insert(record, at: 0)
            if receipts.count > Self.receiptLimit { receipts.removeLast(receipts.count - Self.receiptLimit) }
            return record
        } catch {
            failure = LibraryMessages.describe(error)
            await refresh()
            return nil
        }
    }
}
