import Foundation
@testable import LabDomain
import LabStore
import Testing

// Only OperationService can build an `AuthorizedCommit`, and it never builds one that breaks a
// namespace rule. This file imports LabDomain @testable to hand each store such a commit directly
// and prove the store refuses it on its own, writing nothing.

/// Store contract rule 5: namespaces are fixed, and a store refuses to remove user data.
@Suite struct StoreInvariantTests {
    struct Fixture {
        let lab: ContractHarness
        let userCollection: LabCollection
        let userItem: LabItem
        let demoCollection: LabCollection
        let demoItem: LabItem
    }

    func fixture(_ kind: StoreKind) async throws -> Fixture {
        let lab = try await ContractHarness.make(kind)
        let userCollection = try await lab.makeCollection("Mine")
        let userItem = try await lab.makeItem("Imported record", in: userCollection)
        let seed = try RepositoryFixtures.demoSeed()
        try await lab.perform(.resetDemo(seed: seed))
        return Fixture(
            lab: lab,
            userCollection: userCollection,
            userItem: userItem,
            demoCollection: try await lab.collection(seed.collections[0].id),
            demoItem: try await lab.item(seed.items[0].id)
        )
    }

    func commit(
        collections: [LabCollection] = [],
        items: [LabItem] = [],
        removals: [EntityReference] = []
    ) -> AuthorizedCommit {
        let request = OperationRequest(
            id: RequestID(), operation: .createCollection(draft: CollectionDraft(title: "Unused")), actor: .granted(.appUI)
        )
        let receipt = ActionReceipt(
            operationID: OperationID(), requestID: request.id, admitted: AdmittedRequest(request), status: .committed,
            changes: [], removed: [], summary: "A commit the service would never plan.", undo: nil
        )
        return AuthorizedCommit(receipt: receipt, preconditions: [], collections: collections, items: items, removals: removals)
    }

    /// Applies a commit the store must refuse, and checks that nothing changed.
    func expectRefusal(_ commit: AuthorizedCommit, by fixture: Fixture, naming entity: EntityReference) async throws {
        let before = try await fixture.lab.state()
        let error = await #expect(throws: (any Error).self) { try await fixture.lab.store.inner.apply(commit) }
        switch error {
        case let violation as NamespaceViolation: #expect(violation.entity == entity)
        case let failure as StoreError: #expect(failure == .namespaceViolation(entity))
        default: Issue.record("Expected a namespace violation, got \(String(describing: error))")
        }
        let after = try await fixture.lab.state()
        #expect(after.0 == before.0)
        #expect(after.1 == before.1)
        #expect(try await fixture.lab.store.receipt(for: commit.requestID) == nil)
    }

    @Test(arguments: StoreKind.allCases)
    func anEntityNeverChangesNamespace(_ kind: StoreKind) async throws {
        let f = try await fixture(kind)
        let hijacked = LabCollection(
            id: f.userCollection.id, title: "Now a sample", revision: f.userCollection.revision.next(), namespace: .demo
        )
        try await expectRefusal(commit(collections: [hijacked]), by: f, naming: hijacked.reference)

        let adopted = LabItem(
            id: f.demoItem.id, collectionID: f.demoItem.collectionID, title: "Now mine",
            revision: f.demoItem.revision.next(), namespace: .user
        )
        try await expectRefusal(commit(items: [adopted]), by: f, naming: adopted.reference)
    }

    @Test(arguments: StoreKind.allCases)
    func anItemAlwaysHasItsCollectionsNamespace(_ kind: StoreKind) async throws {
        let f = try await fixture(kind)
        let intruder = LabItem(id: ItemID(), collectionID: f.demoCollection.id, title: "My note in the demo", namespace: .user)
        try await expectRefusal(commit(items: [intruder]), by: f, naming: intruder.reference)
    }

    @Test(arguments: StoreKind.allCases)
    func userDataIsNeverRemoved(_ kind: StoreKind) async throws {
        let f = try await fixture(kind)
        try await expectRefusal(commit(removals: [f.userItem.reference]), by: f, naming: f.userItem.reference)
        try await expectRefusal(commit(removals: [f.userCollection.reference]), by: f, naming: f.userCollection.reference)
        let missing = EntityReference.item(ItemID())
        try await expectRefusal(commit(removals: [missing]), by: f, naming: missing)
    }

    @Test(arguments: StoreKind.allCases)
    func aViolationLateInACommitUndoesItsEarlierWrites(_ kind: StoreKind) async throws {
        let f = try await fixture(kind)
        // A valid rename of a sample, then a removal of user data in the same commit.
        let renamed = LabCollection(
            id: f.demoCollection.id, title: "Renamed first", revision: f.demoCollection.revision.next(), namespace: .demo
        )
        try await expectRefusal(
            commit(collections: [renamed], removals: [f.userItem.reference]), by: f, naming: f.userItem.reference
        )
        #expect(try await f.lab.collection(f.demoCollection.id).title == f.demoCollection.title)
    }
}
