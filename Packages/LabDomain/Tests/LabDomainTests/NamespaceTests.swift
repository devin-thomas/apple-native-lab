import Foundation
import LabDomain
import Testing

/// A small seed with stable identifiers: two collections and three items.
enum Samples {
    static let shelf = CollectionID(rawValue: uuid(9001))
    static let drawer = CollectionID(rawValue: uuid(9002))
    static let amber = ItemID(rawValue: uuid(9101))
    static let cobalt = ItemID(rawValue: uuid(9102))
    static let ochre = ItemID(rawValue: uuid(9103))

    static func seed() throws -> DemoSeed {
        try DemoSeed(
            version: 1,
            collections: [CollectionDraft(id: shelf, title: "Sample shelf"), CollectionDraft(id: drawer, title: "Sample drawer")],
            items: [
                ItemDraft(id: amber, in: shelf, title: "Amber sample", note: "Warm"),
                ItemDraft(id: cobalt, in: shelf, title: "Cobalt sample", note: "Cool"),
                ItemDraft(id: ochre, in: drawer, title: "Ochre sample"),
            ]
        )
    }
}

/// A comparable view of an `EntityChange`, which only the service can create.
struct Change: Hashable {
    let entity: EntityReference
    let from: Revision?
    let to: Revision

    init(_ entity: EntityReference, from: Revision?, to: Revision) {
        self.entity = entity
        self.from = from
        self.to = to
    }
}

extension ActionReceipt {
    var revisionChanges: [Change] { changes.map { Change($0.entity, from: $0.previousRevision, to: $0.newRevision) } }
}

extension Harness {
    @discardableResult
    func resetDemo(_ seed: DemoSeed, as actor: ActorScope = .appUI, id: RequestID = RequestID()) async throws -> ActionReceipt {
        try await perform(.resetDemo(seed: seed), as: actor, id: id)
    }
}

/// CORE-003: user data and demo data are separate namespaces, and Reset Demo never touches user data.
@Suite struct NamespaceTests {
    @Test func everythingAPersonCreatesIsUserData() async throws {
        let lab = Harness()
        for adapter in [AdapterKind.appUI, .appIntent, .shareExtension, .authorizedPeer] {
            let collection = try await lab.makeCollection(EntityTitle("From \(adapter.rawValue)"))
            let item = try await lab.makeItem(in: collection)
            #expect(collection.namespace == .user)
            #expect(item.namespace == .user)
        }
    }

    @Test func resetDemoOnAnEmptyStoreAddsTheSeed() async throws {
        let lab = Harness()
        let receipt = try await lab.resetDemo(try Samples.seed())

        #expect(receipt.status == .committed)
        #expect(receipt.affectedEntities == [
            .collection(Samples.shelf), .collection(Samples.drawer),
            .item(Samples.amber), .item(Samples.cobalt), .item(Samples.ochre),
        ])
        #expect(receipt.changes.allSatisfy { $0.previousRevision == nil && $0.newRevision == .initial })
        #expect(receipt.removed.isEmpty)
        #expect(receipt.undo == nil)
        #expect(receipt.summary == "Reset the demo to its original 2 collections and 3 items: added 5.")

        let amber = try await lab.item(Samples.amber)
        #expect(amber.namespace == .demo && amber.title == "Amber sample" && amber.note == "Warm")
        #expect(try await lab.collection(Samples.drawer).namespace == .demo)
    }

    @Test func resetDemoRestoresEditedSamplesAtTheirNextRevision() async throws {
        let lab = Harness()
        try await lab.resetDemo(try Samples.seed())
        try await lab.perform(.updateItem(id: Samples.amber, expected: .initial, changes: ItemChanges(title: "Edited amber")))
        try await lab.perform(.archiveItem(id: Samples.cobalt, expected: .initial))
        try await lab.perform(.updateCollection(id: Samples.drawer, expected: .initial, title: "Renamed drawer"))

        let receipt = try await lab.resetDemo(try Samples.seed())

        #expect(receipt.revisionChanges == [
            Change(.collection(Samples.drawer), from: .r(2), to: .r(3)),
            Change(.item(Samples.amber), from: .r(2), to: .r(3)),
            Change(.item(Samples.cobalt), from: .r(2), to: .r(3)),
        ])
        #expect(receipt.summary == "Reset the demo to its original 2 collections and 3 items: restored 3.")
        #expect(try await lab.item(Samples.amber).title == "Amber sample")
        #expect(try await !lab.item(Samples.cobalt).isArchived)
        #expect(try await lab.collection(Samples.drawer).title == "Sample drawer")
        // Untouched samples keep their revision; restored ones never go back to revision 1.
        #expect(try await lab.item(Samples.ochre).revision == .initial)
        #expect(try await lab.item(Samples.amber).revision == .r(3))
    }

    @Test func aStaleOperationFromBeforeAResetIsAConflictNotAnOverwrite() async throws {
        let lab = Harness()
        try await lab.resetDemo(try Samples.seed())
        let rename = try await lab.perform(
            .updateItem(id: Samples.amber, expected: .initial, changes: ItemChanges(title: "Edited amber"))
        )
        try await lab.resetDemo(try Samples.seed())

        let lateUndo = try await lab.perform(try #require(rename.undo))
        #expect(lateUndo.conflict?.expected == .r(2))
        #expect(lateUndo.conflict?.current == .r(3))
    }

    @Test func resetDemoNeverTouchesUserData() async throws {
        let lab = Harness()
        try await lab.resetDemo(try Samples.seed())
        let importer = ActorScope.granted(.shareExtension)
        let imported = CollectionID()
        let record = ItemID()
        try await lab.perform(.createCollection(draft: CollectionDraft(id: imported, title: "Imported")), as: importer)
        try await lab.perform(
            .createItem(draft: ItemDraft(id: record, in: imported, title: "Imported record", note: "Keep me")), as: importer
        )
        try await lab.perform(.updateItem(id: record, expected: .initial, changes: ItemChanges(note: "Edited, keep me")))
        let userCollection = try await lab.collection(imported)
        let userItem = try await lab.item(record)

        let receipt = try await lab.resetDemo(try Samples.seed())

        #expect(try await lab.collection(imported) == userCollection)
        #expect(try await lab.item(record) == userItem)
        #expect(!receipt.affectedEntities.contains(.collection(imported)))
        #expect(!receipt.affectedEntities.contains(.item(record)))
    }

    @Test func nothingCanBeAddedToADemoCollection() async throws {
        let lab = Harness()
        try await lab.resetDemo(try Samples.seed())
        let before = await lab.appliedCommits

        for adapter in [AdapterKind.appUI, .appIntent, .shareExtension, .authorizedPeer] {
            await #expect(throws: OperationError.ruleViolation(.demoCollection(Samples.shelf))) {
                try await lab.perform(
                    .createItem(draft: ItemDraft(in: Samples.shelf, title: "My own note")), as: .granted(adapter)
                )
            }
        }
        #expect(await lab.appliedCommits == before)
        // Samples themselves can still be edited; Reset Demo puts them back.
        let edit = try await lab.perform(.updateItem(id: Samples.amber, expected: .initial, changes: ItemChanges(note: "Edited")))
        #expect(edit.status == .committed)
    }

    @Test func resetDemoNeedsTheDestructivePermission() async throws {
        let lab = Harness()
        let seed = try Samples.seed()

        for adapter in [AdapterKind.shareExtension, .authorizedPeer, .modelTool] {
            let refusal = await #expect(throws: OperationError.self) { try await lab.resetDemo(seed, as: .granted(adapter)) }
            #expect(refusal?.denial?.required == .commitDestructive)
            #expect(refusal?.denial?.reason == .outsideAdapterCeiling, "\(adapter.rawValue) reset the demo")
        }
        let editor = ActorScope(adapter: .appUI, grants: [.read, .commit])
        let notGranted = await #expect(throws: OperationError.self) { try await lab.resetDemo(seed, as: editor) }
        #expect(notGranted?.denial?.reason == .notGranted)
        #expect(await lab.appliedCommits == 0)

        let proposal = try await lab.service.propose(.resetDemo(seed: seed), as: .modelTool)
        #expect(proposal.summary == "Reset the demo to its original 2 collections and 3 items: add 5.")
        #expect(await lab.appliedCommits == 0)

        #expect(try await lab.resetDemo(seed, as: .appIntent).status == .committed)
    }

    @Test func thePolicyIsConsultedForAReset() async throws {
        let lab = Harness(policy: RecordingPolicy(decision: .deny))
        let refusal = await #expect(throws: OperationError.self) { try await lab.resetDemo(try Samples.seed()) }
        #expect(refusal?.denial?.reason == .deniedByPolicy)
    }

    @Test func aSeedThatNamesUserDataIsRefusedAndWritesNothing() async throws {
        let lab = Harness()
        let mine = try await lab.makeCollection("Mine", id: Samples.drawer)
        let before = await lab.appliedCommits

        await #expect(throws: OperationError.ruleViolation(.alreadyExists(.collection(Samples.drawer)))) {
            try await lab.resetDemo(try Samples.seed())
        }
        #expect(await lab.appliedCommits == before)
        #expect(try await lab.collection(Samples.drawer) == mine)
        await #expect(throws: OperationError.notFound(.collection(Samples.shelf))) { try await lab.collection(Samples.shelf) }

        let other = Harness()
        let userShelf = try await other.makeCollection("Mine")
        _ = try await other.makeItem("Mine too", in: userShelf, id: Samples.ochre)
        await #expect(throws: OperationError.ruleViolation(.alreadyExists(.item(Samples.ochre)))) {
            try await other.resetDemo(try Samples.seed())
        }
    }

    @Test func resetDemoRemovesSamplesANewerSeedNoLongerNames() async throws {
        let lab = Harness()
        try await lab.resetDemo(try Samples.seed())
        // Version 2 drops the drawer and the cobalt sample, and moves ochre onto the shelf.
        let newer = try DemoSeed(
            version: 2,
            collections: [CollectionDraft(id: Samples.shelf, title: "Sample shelf")],
            items: [
                ItemDraft(id: Samples.amber, in: Samples.shelf, title: "Amber sample", note: "Warm"),
                ItemDraft(id: Samples.ochre, in: Samples.shelf, title: "Ochre sample"),
            ]
        )

        let receipt = try await lab.resetDemo(newer)

        #expect(receipt.revisionChanges == [Change(.item(Samples.ochre), from: .initial, to: .r(2))])
        #expect(receipt.removed == [.item(Samples.cobalt), .collection(Samples.drawer)])
        #expect(receipt.summary == "Reset the demo to its original 1 collection and 2 items: restored 1, removed 2.")
        await #expect(throws: OperationError.notFound(.item(Samples.cobalt))) { try await lab.item(Samples.cobalt) }
        await #expect(throws: OperationError.notFound(.collection(Samples.drawer))) { try await lab.collection(Samples.drawer) }
        #expect(try await lab.item(Samples.ochre).collectionID == Samples.shelf)
    }

    @Test func aResetThatFindsTheDemoIntactChangesNothing() async throws {
        let lab = Harness()
        try await lab.resetDemo(try Samples.seed())
        let receipt = try await lab.resetDemo(try Samples.seed())
        #expect(receipt.status == .committed)
        #expect(receipt.affectedEntities.isEmpty)
        #expect(receipt.summary == "The demo already matched its original 2 collections and 3 items.")
        #expect(try await lab.item(Samples.amber).revision == .initial)
    }

    @Test func aResetReplaysLikeAnyOtherRequest() async throws {
        let lab = Harness()
        let requestID = RequestID()
        let seed = try Samples.seed()
        let original = try await lab.resetDemo(seed, id: requestID)
        try await lab.perform(.updateItem(id: Samples.amber, expected: .initial, changes: ItemChanges(note: "Edited after")))
        let commits = await lab.appliedCommits

        #expect(try await lab.resetDemo(seed, id: requestID) == original)
        #expect(await lab.appliedCommits == commits)
        #expect(try await lab.item(Samples.amber).note == "Edited after")

        let otherSeed = try DemoSeed(version: 2, collections: [CollectionDraft(id: Samples.shelf, title: "Sample shelf")], items: [])
        await #expect(throws: OperationError.requestIDReused(requestID)) { try await lab.resetDemo(otherSeed, id: requestID) }
    }

    @Test func aResetPlansAgainWhenASampleChangesBeforeItCommits() async throws {
        let shared = SpyStore()
        let app = Harness(store: shared)
        let otherProcess = OperationService(store: shared)
        try await app.resetDemo(try Samples.seed())
        try await app.perform(.archiveItem(id: Samples.cobalt, expected: .initial))

        await shared.runBeforeNextCommit {
            _ = try? await otherProcess.perform(OperationRequest(
                id: RequestID(),
                operation: .updateItem(id: Samples.amber, expected: .initial, changes: ItemChanges(title: "Concurrent edit")),
                actor: .granted(.shareExtension)
            ))
        }
        let receipt = try await app.resetDemo(try Samples.seed())

        #expect(receipt.status == .committed)
        #expect(receipt.changes.map(\.entity) == [.item(Samples.amber), .item(Samples.cobalt)])
        #expect(try await app.item(Samples.amber).title == "Amber sample")
        #expect(try await app.item(Samples.amber).revision == .r(3))
    }

    @Test func demoSeedsValidateThemselves() throws {
        let shelf = CollectionDraft(id: Samples.shelf, title: "Sample shelf")
        #expect(throws: DemoSeedError.unsupportedVersion(0)) { try DemoSeed(version: 0, collections: [shelf], items: []) }
        #expect(throws: DemoSeedError.noCollections) { try DemoSeed(version: 1, collections: [], items: []) }
        #expect(throws: DemoSeedError.duplicateID(uuid(9001))) {
            try DemoSeed(version: 1, collections: [shelf], items: [ItemDraft(id: ItemID(rawValue: uuid(9001)), in: Samples.shelf, title: "Twin")])
        }
        #expect(throws: DemoSeedError.unknownCollection(item: Samples.amber, collection: Samples.drawer)) {
            try DemoSeed(version: 1, collections: [shelf], items: [ItemDraft(id: Samples.amber, in: Samples.drawer, title: "Lost")])
        }
        let crowd = (0..<DemoSeed.maximumEntityCount).map { _ in ItemDraft(in: Samples.shelf, title: "Sample") }
        #expect(throws: DemoSeedError.tooManyEntities(limit: 200)) { try DemoSeed(version: 1, collections: [shelf], items: crowd) }

        let valid = try Samples.seed()
        let json = try JSONEncoder().encode(valid)
        #expect(try JSONDecoder().decode(DemoSeed.self, from: json) == valid)
        let orphaned = #"{"version":1,"collections":[{"id":"\#(uuid(9001))","title":"Shelf"}],"items":[{"id":"\#(uuid(9101))","collectionID":"\#(uuid(9002))","title":"Lost","note":""}]}"#
        #expect(throws: DemoSeedError.unknownCollection(item: Samples.amber, collection: Samples.drawer)) {
            try JSONDecoder().decode(DemoSeed.self, from: Data(orphaned.utf8))
        }
    }

    @Test func anEntityEncodedBeforeNamespacesDecodesAsUserData() throws {
        let legacyItem = #"{"id":"\#(uuid(1))","collectionID":"\#(uuid(2))","title":"Old","note":"","isArchived":false,"revision":4}"#
        let item = try JSONDecoder().decode(LabItem.self, from: Data(legacyItem.utf8))
        #expect(item.namespace == .user && item.revision == .r(4))
        let legacyCollection = #"{"id":"\#(uuid(2))","title":"Old","isArchived":true,"revision":1}"#
        #expect(try JSONDecoder().decode(LabCollection.self, from: Data(legacyCollection.utf8)).namespace == .user)

        let demo = LabItem(id: ItemID(rawValue: uuid(3)), collectionID: CollectionID(rawValue: uuid(2)), title: "Sample", namespace: .demo)
        #expect(try JSONDecoder().decode(LabItem.self, from: JSONEncoder().encode(demo)) == demo)
    }

    @Test func aReceiptOnlyRecordsRemovalsWhenThereAreSome() async throws {
        let lab = Harness()
        let plain = try await lab.perform(.createCollection(draft: CollectionDraft(title: "Samples")))
        let plainJSON = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!plainJSON.contains("removed"))

        try await lab.resetDemo(try Samples.seed())
        let smaller = try DemoSeed(version: 2, collections: [CollectionDraft(id: Samples.shelf, title: "Sample shelf")], items: [])
        let reset = try await lab.resetDemo(smaller)
        #expect(reset.removed.count == 4)
        #expect(try JSONDecoder().decode(ActionReceipt.self, from: JSONEncoder().encode(reset)) == reset)
    }
}
