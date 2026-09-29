import Foundation
import LabDomain
import LabStore
import Testing

/// The `OperationStore` contract, run against the in-memory reference and the SQLite store.
/// These port the store-facing CORE-002 tests: duplicate requests, revision preconditions, and a
/// failed commit.
@Suite struct StoreContractTests {
    // MARK: Duplicate requests

    @Test(arguments: StoreKind.allCases)
    func theSameRequestTwiceMutatesOnceAndReturnsTheOriginalReceipt(_ kind: StoreKind) async throws {
        let lab = try await ContractHarness.make(kind)
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        let before = await lab.appliedCommits
        let request = try OperationRequest(
            id: RequestID(),
            operation: .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "Amber study")),
            actor: .appUI
        )

        let first = try await lab.service.perform(request)
        let second = try await lab.service.perform(request)

        #expect(second == first)
        #expect(await lab.appliedCommits == before + 1)
        #expect(try await lab.item(item.id).revision == .r(2))
    }

    @Test(arguments: StoreKind.allCases)
    func aReplayAfterLaterChangesReturnsTheOriginalReceiptWithoutTouchingState(_ kind: StoreKind) async throws {
        let lab = try await ContractHarness.make(kind)
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        let requestID = RequestID()
        let rename = DomainOperation.updateItem(id: item.id, expected: .initial, changes: try ItemChanges(title: "Amber study"))

        let original = try await lab.perform(rename, id: requestID)
        try await lab.perform(.updateItem(id: item.id, expected: .r(2), changes: ItemChanges(note: "Later edit")))
        let replayed = try await lab.perform(rename, id: requestID)

        #expect(replayed == original)
        let current = try await lab.item(item.id)
        #expect(current.revision == .r(3))
        #expect(current.note == "Later edit")
    }

    @Test(arguments: StoreKind.allCases)
    func concurrentDuplicatesMutateOnce(_ kind: StoreKind) async throws {
        let lab = try await ContractHarness.make(kind)
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        let before = await lab.appliedCommits
        let requests = try [
            OperationRequest(
                id: RequestID(),
                operation: .createItem(draft: ItemDraft(in: samples.id, title: "Tapped twice")),
                actor: .granted(.appIntent)
            ),
            OperationRequest(
                id: RequestID(),
                operation: .updateItem(id: item.id, expected: .initial, changes: ItemChanges(note: "Tapped twice")),
                actor: .granted(.appIntent)
            ),
        ]

        let receipts = try await withThrowingTaskGroup(of: ActionReceipt.self) { group in
            for request in requests {
                for _ in 0..<24 {
                    group.addTask { try await lab.service.perform(request) }
                }
            }
            return try await group.reduce(into: [ActionReceipt]()) { $0.append($1) }
        }

        #expect(receipts.count == 48)
        #expect(Set(receipts).count == 2)
        #expect(receipts.allSatisfy { $0.status == .committed })
        #expect(await lab.appliedCommits == before + 2)
        #expect(try await lab.store.items(in: samples.id).count == 2)
        #expect(try await lab.item(item.id).revision == .r(2))
    }

    @Test(arguments: StoreKind.allCases)
    func concurrentDuplicatesFromSeveralProcessesMutateOnce(_ kind: StoreKind) async throws {
        let lab = try await ContractHarness.make(kind)
        let samples = try await lab.makeCollection()
        let services = [lab.service, try await lab.otherProcess(), try await lab.otherProcess()]
        let request = OperationRequest(
            id: RequestID(),
            operation: .createItem(draft: ItemDraft(in: samples.id, title: "Shared from three places")),
            actor: .granted(.shareExtension)
        )

        let receipts = try await withThrowingTaskGroup(of: ActionReceipt.self) { group in
            for service in services {
                for _ in 0..<8 {
                    group.addTask { try await service.perform(request) }
                }
            }
            return try await group.reduce(into: [ActionReceipt]()) { $0.append($1) }
        }

        #expect(Set(receipts).count == 1)
        #expect(try await lab.store.items(in: samples.id).count == 1)
    }

    @Test(arguments: StoreKind.allCases)
    func aReusedRequestIDWithADifferentPayloadIsRefused(_ kind: StoreKind) async throws {
        let lab = try await ContractHarness.make(kind)
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        let requestID = RequestID()
        let original = try await lab.perform(
            .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "Amber study")), id: requestID
        )
        let before = await lab.appliedCommits

        await #expect(throws: OperationError.requestIDReused(requestID)) {
            try await lab.perform(.archiveItem(id: item.id, expected: .r(2)), id: requestID)
        }
        await #expect(throws: OperationError.requestIDReused(requestID)) {
            try await lab.perform(
                .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "Amber study")),
                as: .granted(.appIntent), id: requestID
            )
        }

        #expect(await lab.appliedCommits == before)
        #expect(try await lab.service.findReceipt(for: requestID, as: .appUI) == original)
    }

    // MARK: Revision preconditions

    @Test(arguments: StoreKind.allCases)
    func aStaleRevisionIsARecordedConflictThatOverwritesNothing(_ kind: StoreKind) async throws {
        let lab = try await ContractHarness.make(kind)
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        try await lab.perform(.updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "Amber study")))
        let before = await lab.appliedCommits

        let requestID = RequestID()
        let stale = DomainOperation.updateItem(id: item.id, expected: .initial, changes: try ItemChanges(title: "Stale title"))
        let receipt = try await lab.perform(stale, id: requestID)

        #expect(receipt.conflict?.expected == .initial)
        #expect(receipt.conflict?.current == .r(2))
        #expect(receipt.changes.isEmpty)
        #expect(try await lab.item(item.id).title == "Amber study")
        #expect(await lab.appliedCommits == before + 1)
        #expect(try await lab.perform(stale, id: requestID) == receipt)
        #expect(await lab.appliedCommits == before + 1)
    }

    @Test(arguments: StoreKind.allCases)
    func aWriterInAnotherProcessBetweenReadAndCommitCausesAConflict(_ kind: StoreKind) async throws {
        let app = try await ContractHarness.make(kind)
        let otherProcess = try await app.otherProcess()
        let samples = try await app.makeCollection()
        let item = try await app.makeItem(in: samples)

        await app.store.runBeforeNextCommit {
            _ = try? await otherProcess.perform(OperationRequest(
                id: RequestID(),
                operation: .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "From the extension")),
                actor: .granted(.shareExtension)
            ))
        }
        let receipt = try await app.perform(.updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "From the app")))

        #expect(receipt.conflict?.current == .r(2))
        #expect(try await app.item(item.id).title == "From the extension")
    }

    @Test(arguments: StoreKind.allCases)
    func aCreationPinsItsCollectionAgainstAConcurrentArchive(_ kind: StoreKind) async throws {
        let app = try await ContractHarness.make(kind)
        let otherProcess = try await app.otherProcess()
        let samples = try await app.makeCollection()

        await app.store.runBeforeNextCommit {
            _ = try? await otherProcess.perform(OperationRequest(
                id: RequestID(), operation: .archiveCollection(id: samples.id, expected: .initial), actor: .appUI
            ))
        }
        await #expect(throws: OperationError.ruleViolation(.collectionArchived(samples.id))) {
            try await app.perform(.createItem(draft: ItemDraft(in: samples.id, title: "Late arrival")))
        }
        #expect(try await app.store.items(in: samples.id).isEmpty)
    }

    @Test(arguments: StoreKind.allCases)
    func concurrentWritersFromTheSameBaseProduceOneCommitAndConflicts(_ kind: StoreKind) async throws {
        let lab = try await ContractHarness.make(kind)
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        let services = [lab.service, try await lab.otherProcess(), try await lab.otherProcess()]

        let receipts = try await withThrowingTaskGroup(of: ActionReceipt.self) { group in
            for writer in 0..<12 {
                let service = services[writer % services.count]
                group.addTask {
                    try await service.perform(OperationRequest(
                        id: RequestID(),
                        operation: .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: EntityTitle("Writer \(writer)"))),
                        actor: .appUI
                    ))
                }
            }
            return try await group.reduce(into: [ActionReceipt]()) { $0.append($1) }
        }

        #expect(receipts.filter { $0.status == .committed }.count == 1)
        #expect(receipts.filter { $0.conflict?.current == .r(2) }.count == 11)
        #expect(try await lab.item(item.id).revision == .r(2))
    }

    // MARK: Failed commit

    @Test(arguments: StoreKind.allCases)
    func aFailedCommitRecordsNothingAndTheSameRequestCanBeRetried(_ kind: StoreKind) async throws {
        let lab = try await ContractHarness.make(kind)
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        let before = await lab.appliedCommits
        let request = try OperationRequest(
            id: RequestID(),
            operation: .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "Amber study", note: "Edited")),
            actor: .appUI
        )
        await lab.failNextCommit()

        await #expect(throws: OperationError.storeFailure(.commitFailed)) { try await lab.service.perform(request) }
        #expect(try await lab.service.findReceipt(for: request.id, as: .appUI) == nil)
        #expect(try await lab.item(item.id) == item)
        #expect(await lab.appliedCommits == before)

        let receipt = try await lab.service.perform(request)
        #expect(receipt.status == .committed)
        #expect(try await lab.service.perform(request) == receipt)
        #expect(try await lab.item(item.id).revision == .r(2))
        #expect(await lab.appliedCommits == before + 1)
    }

    // MARK: Reads and namespaces

    @Test(arguments: StoreKind.allCases)
    func readsIncludeArchivedEntities(_ kind: StoreKind) async throws {
        let lab = try await ContractHarness.make(kind)
        let shelf = try await lab.makeCollection("Shelf")
        let drawer = try await lab.makeCollection("Drawer")
        let kept = try await lab.makeItem("Kept", in: shelf)
        let archived = try await lab.makeItem("Archived", in: shelf)
        let elsewhere = try await lab.makeItem("Elsewhere", in: drawer)
        try await lab.perform(.archiveItem(id: archived.id, expected: .initial))
        try await lab.perform(.archiveCollection(id: drawer.id, expected: .initial))

        #expect(Set(try await lab.store.collections().map(\.id)) == [shelf.id, drawer.id])
        #expect(Set(try await lab.store.items(in: shelf.id).map(\.id)) == [kept.id, archived.id])
        #expect(Set(try await lab.store.items(in: nil).map(\.id)) == [kept.id, archived.id, elsewhere.id])
        #expect(try await lab.store.item(archived.id)?.isArchived == true)
        #expect(try await lab.store.collection(drawer.id)?.isArchived == true)
        #expect(try await lab.store.item(ItemID()) == nil)
    }

    @Test(arguments: StoreKind.allCases)
    func resetDemoRestoresSamplesRemovesLeftoversAndKeepsUserData(_ kind: StoreKind) async throws {
        let lab = try await ContractHarness.make(kind)
        let seed = try RepositoryFixtures.demoSeed()
        let pigments = try #require(seed.collections.first)
        let amber = try #require(seed.items.first)
        let extra = ItemDraft(id: ItemID(rawValue: uuid(77)), in: pigments.id, title: "Retired swatch")
        let older = try DemoSeed(version: 1, collections: seed.collections, items: seed.items + [extra])
        try await lab.perform(.resetDemo(seed: older))
        let mine = try await lab.makeCollection("Mine")
        let record = try await lab.makeItem("Imported record", in: mine)
        try await lab.perform(.updateItem(id: amber.id, expected: .initial, changes: ItemChanges(title: "Edited amber")))

        let receipt = try await lab.perform(.resetDemo(seed: seed))

        #expect(receipt.removed == [.item(extra.id)])
        #expect(receipt.affectedEntities.contains(.item(amber.id)))
        #expect(try await lab.store.item(extra.id) == nil)
        #expect(try await lab.item(amber.id).title == amber.title)
        #expect(try await lab.collection(mine.id) == mine)
        #expect(try await lab.item(record.id) == record)
        #expect(try await lab.store.items(in: nil).filter { $0.namespace == .demo }.count == seed.items.count)
    }

    /// The same script with the same identifiers yields identical receipts and state in both stores.
    @Test func bothStoresProduceIdenticalReceiptsAndState() async throws {
        func run(_ kind: StoreKind) async throws -> ([ActionReceipt], [LabCollection], [LabItem]) {
            let lab = try await ContractHarness.make(kind, operationIDs: SequentialOperationIDs())
            let seed = try RepositoryFixtures.demoSeed()
            let amber = try #require(seed.items.first).id
            let cobalt = seed.items[1].id
            let mine = CollectionID(rawValue: uuid(500))
            let record = ItemID(rawValue: uuid(501))
            let smaller = try DemoSeed(version: 2, collections: [seed.collections[0]], items: Array(seed.items.prefix(4)))
            let script: [DomainOperation] = try [
                .resetDemo(seed: seed),
                .createCollection(draft: CollectionDraft(id: mine, title: "Mine")),
                .createItem(draft: ItemDraft(id: record, in: mine, title: "Imported record", note: "Keep")),
                .updateItem(id: amber, expected: .initial, changes: ItemChanges(title: "Edited amber")),
                .archiveItem(id: cobalt, expected: .initial),
                .updateItem(id: amber, expected: .initial, changes: ItemChanges(note: "Stale")),
                .resetDemo(seed: seed),
                .resetDemo(seed: smaller),
                .updateItem(id: record, expected: .initial, changes: ItemChanges(note: "Still mine")),
            ]
            var receipts: [ActionReceipt] = []
            for (index, operation) in script.enumerated() {
                receipts.append(try await lab.perform(operation, id: RequestID(rawValue: uuid(600 + index))))
            }
            let (collections, items) = try await lab.state()
            return (receipts, collections, items)
        }

        let reference = try await run(.inMemory)
        let persistent = try await run(.sqlite)
        #expect(persistent.0 == reference.0)
        #expect(persistent.1 == reference.1)
        #expect(persistent.2 == reference.2)
        #expect(reference.0[5].conflict != nil)
        #expect(reference.0[7].removed.count == 10)
    }
}
