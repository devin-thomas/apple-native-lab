import Foundation
import LabDomain
@testable import LabStore
import Testing

/// CORE-003 acceptance: an interrupted transaction leaves either the old state or the complete new
/// state. Every interruption is placed deterministically by a fault point inside the store's
/// transaction, never by timing.
@Suite struct InterruptedTransactionTests {
    /// A store holding demo samples (one of them retired from the current seed), edited samples,
    /// and user data, plus a Reset Demo request whose single commit creates nothing, rewrites
    /// several samples, removes one, and records a receipt.
    struct Scenario {
        let directory: TemporaryDirectory
        let faults: FaultPlan
        let store: SQLiteOperationStore
        let service: OperationService
        let reset: OperationRequest

        static func make() async throws -> Scenario {
            let directory = try TemporaryDirectory()
            let faults = FaultPlan()
            let store = try await SQLiteOperationStore.open(directory.storeURL, hook: faults.hook)
            let service = OperationService(store: store)
            let seed = try RepositoryFixtures.demoSeed()
            let retired = ItemDraft(id: ItemID(rawValue: uuid(88)), in: seed.collections[0].id, title: "Retired swatch")
            let older = try DemoSeed(version: 1, collections: seed.collections, items: seed.items + [retired])

            // Fixed request IDs, so every scenario's receipts table holds the same rows.
            var nextRequest = 200
            func perform(_ operation: DomainOperation, as actor: ActorScope = .appUI) async throws {
                nextRequest += 1
                _ = try await service.perform(OperationRequest(id: RequestID(rawValue: uuid(nextRequest)), operation: operation, actor: actor))
            }
            try await perform(.resetDemo(seed: older))
            try await perform(.updateCollection(id: seed.collections[1].id, expected: .initial, title: "Renamed shelf"))
            try await perform(.updateItem(id: seed.items[0].id, expected: .initial, changes: ItemChanges(title: "Edited")))
            try await perform(.archiveItem(id: seed.items[5].id, expected: .initial))
            let mine = CollectionID(rawValue: uuid(90))
            try await perform(.createCollection(draft: CollectionDraft(id: mine, title: "Mine")), as: .shareExtension)
            try await perform(
                .createItem(draft: ItemDraft(id: ItemID(rawValue: uuid(91)), in: mine, title: "Imported record")), as: .shareExtension
            )

            let reset = OperationRequest(id: RequestID(rawValue: uuid(99)), operation: .resetDemo(seed: seed), actor: .appUI)
            return Scenario(directory: directory, faults: faults, store: store, service: service, reset: reset)
        }
    }

    /// The fault points one uninterrupted reset passes, and the state it leaves.
    static func reference() async throws -> (points: [FaultPoint], after: DatabaseDump, receipt: ActionReceipt) {
        let scenario = try await Scenario.make()
        let start = scenario.faults.seen.count
        let receipt = try await scenario.service.perform(scenario.reset)
        return (Array(scenario.faults.seen[start...]), try DatabaseDump(scenario.directory.storeURL), receipt)
    }

    @Test func theResetUnderTestWritesSeveralRowsInOneCommit() async throws {
        let (points, _, receipt) = try await Self.reference()
        #expect(points.first == .began)
        #expect(points.suffix(2) == [.receiptRecorded, .committed])
        #expect(points.filter { if case .wrote = $0 { true } else { false } }.count == 3)
        #expect(points.contains(.removed(.item(ItemID(rawValue: uuid(88))))))
        #expect(receipt.changes.count == 3 && receipt.removed.count == 1)
    }

    /// Interrupts the same commit at every point before `COMMIT`, one fresh store per point.
    @Test func everyInterruptionBeforeCommitLeavesTheOldStateAndTheRetryCompletesIt() async throws {
        let reference = try await Self.reference()
        let interruptible = reference.points.count - 1 // every point except `.committed`
        #expect(interruptible == 8)

        for offset in 0..<interruptible {
            let scenario = try await Scenario.make()
            let before = try DatabaseDump(scenario.directory.storeURL)
            scenario.faults.interrupt(atOffset: offset)

            await #expect(throws: OperationError.storeFailure(.commitFailed), "interrupted at \(reference.points[offset])") {
                try await scenario.service.perform(scenario.reset)
            }
            #expect(try DatabaseDump(scenario.directory.storeURL) == before, "partial state after \(reference.points[offset])")
            #expect(try await scenario.store.receipt(for: scenario.reset.id) == nil)

            // A fresh connection, as after a relaunch, sees the same old state.
            let reopened = try await SQLiteOperationStore(url: scenario.directory.storeURL)
            #expect(try await reopened.receipt(for: scenario.reset.id) == nil)

            // The same store and request then complete the whole change.
            let receipt = try await scenario.service.perform(scenario.reset)
            #expect(receipt.changes == reference.receipt.changes)
            #expect(receipt.removed == reference.receipt.removed)
            #expect(try DatabaseDump(scenario.directory.storeURL) == reference.after)
        }
    }

    @Test func anInterruptionAfterCommitLeavesTheCompleteNewStateAndTheRetryReplays() async throws {
        let reference = try await Self.reference()
        let scenario = try await Scenario.make()
        scenario.faults.interrupt { $0 == .committed }

        // The process "dies" after COMMIT but before it can report the result.
        await #expect(throws: OperationError.storeFailure(.commitFailed)) { try await scenario.service.perform(scenario.reset) }
        #expect(try DatabaseDump(scenario.directory.storeURL) == reference.after)
        let recorded = try #require(try await scenario.store.receipt(for: scenario.reset.id))

        let start = scenario.faults.seen.count
        #expect(try await scenario.service.perform(scenario.reset) == recorded)
        #expect(!scenario.faults.seen[start...].contains(.committed), "the retry must not commit again")
        #expect(try DatabaseDump(scenario.directory.storeURL) == reference.after)
    }

    /// Copies the files as a process that stops mid-transaction would leave them, with the
    /// transaction's uncommitted pages already written to the log, and opens the copy.
    @Test func aCrashMidTransactionRecoversTheOldStateFromTheFilesOnDisk() async throws {
        let directory = try TemporaryDirectory()
        let faults = FaultPlan()
        let store = try await SQLiteOperationStore.open(directory.storeURL, hook: faults.hook)
        let service = OperationService(store: store)
        // A small page cache and spill threshold and a large commit make SQLite write uncommitted
        // pages to the log before COMMIT, so recovery has partial data on disk to ignore. (The
        // system library's default spill threshold is 20,000 pages.)
        try await store.execute("PRAGMA cache_size = 8; PRAGMA cache_spill = 8")
        let shelf = CollectionDraft(id: CollectionID(rawValue: uuid(1)), title: "Large shelf")
        let longNote = try ItemNote(String(repeating: "Original synthetic sample text. ", count: 60))
        let large = try DemoSeed(version: 1, collections: [shelf], items: (0..<150).map { index in
            try ItemDraft(id: ItemID(rawValue: uuid(1_000 + index)), in: shelf.id, title: EntityTitle("Sample \(index)"), note: longNote)
        })
        _ = try await service.perform(OperationRequest(
            id: RequestID(), operation: .createCollection(draft: CollectionDraft(title: "Mine")), actor: .appUI
        ))
        let before = try DatabaseDump(directory.storeURL)

        let wal = directory.file("store.sqlite-wal")
        let midTransaction = try TemporaryDirectory()
        let afterCommit = try TemporaryDirectory()
        let walAtBegin = Locked(0)
        let walBeforeCommit = Locked(0)
        faults.observe { point in
            switch point {
            case .began:
                walAtBegin.set(Self.size(of: wal))
            case .receiptRecorded:
                walBeforeCommit.set(Self.size(of: wal))
                Self.copyStoreFiles(from: directory, to: midTransaction)
            case .committed:
                Self.copyStoreFiles(from: directory, to: afterCommit)
            default:
                break
            }
        }
        let receipt = try await service.perform(OperationRequest(id: RequestID(), operation: .resetDemo(seed: large), actor: .appUI))
        faults.observe(nil)
        let after = try DatabaseDump(directory.storeURL)

        #expect(walBeforeCommit.value > walAtBegin.value, "no uncommitted pages reached the log, so the test proves less")
        let recoveredMid = try await SQLiteOperationStore(url: midTransaction.storeURL)
        #expect(try DatabaseDump(midTransaction.storeURL) == before)
        #expect(try await recoveredMid.receipt(for: receipt.requestID) == nil)
        #expect(try await recoveredMid.items(in: nil).isEmpty)

        let recoveredAfter = try await SQLiteOperationStore(url: afterCommit.storeURL)
        #expect(try DatabaseDump(afterCommit.storeURL) == after)
        #expect(try await recoveredAfter.receipt(for: receipt.requestID) == receipt)
        #expect(try await recoveredAfter.items(in: nil).count == 150)
    }

    static func size(of url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int) ?? 0
    }

    /// Copies the database and its write-ahead log, but not the shared-memory index, which a
    /// crashed process leaves stale and SQLite rebuilds on open.
    static func copyStoreFiles(from source: TemporaryDirectory, to destination: TemporaryDirectory) {
        for name in ["store.sqlite", "store.sqlite-wal"] {
            try? FileManager.default.copyItem(at: source.file(name), to: destination.file(name))
        }
    }
}
