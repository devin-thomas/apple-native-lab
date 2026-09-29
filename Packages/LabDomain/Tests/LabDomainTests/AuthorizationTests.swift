import Foundation
import LabDomain
import Testing

/// CORE-002 acceptance: no caller bypasses the authorization policy by selecting a different
/// adapter. ADR-007: a model tool may read or propose but never commit.
@Suite struct AuthorizationTests {
    @Test func thePolicyRunsForEveryRequestIncludingReadsProposalsAndReplays() async throws {
        let policy = RecordingPolicy()
        let lab = Harness(policy: policy)
        let requestID = RequestID()
        let create = DomainOperation.createCollection(draft: CollectionDraft(title: "Samples"))

        let receipt = try await lab.perform(create, as: .appUI, id: requestID)
        try await lab.perform(create, as: .appUI, id: requestID)
        let collectionID = CollectionID(rawValue: receipt.affectedEntities[0].rawID)
        _ = try await lab.service.findCollection(collectionID, as: .modelTool)
        _ = try await lab.service.findItems(ItemFilter(), as: .granted(.shareExtension))
        _ = try await lab.service.findReceipt(for: requestID, as: .granted(.authorizedPeer))
        let archive = DomainOperation.archiveCollection(id: collectionID, expected: .initial)
        _ = try await lab.service.propose(archive, as: .modelTool)
        _ = try? await lab.perform(archive, as: .modelTool)

        let attempts = policy.attempts
        #expect(attempts.map(\.adapter) == [
            .appUI, .appUI, .modelTool, .shareExtension, .authorizedPeer, .modelTool, .modelTool,
        ])
        #expect(attempts.map(\.access.requiredPermission) == [
            .commit, .commit, .read, .read, .read, .propose, .commitDestructive,
        ])
    }

    @Test(arguments: AdapterKind.allCases)
    func aDenyingPolicyExemptsNoAdapter(_ adapter: AdapterKind) async throws {
        let lab = Harness(policy: RecordingPolicy(decision: .deny))
        let actor = ActorScope.granted(adapter)
        let collectionID = CollectionID()

        let commit = await #expect(throws: OperationError.self) {
            try await lab.perform(.createCollection(draft: CollectionDraft(id: collectionID, title: "Samples")), as: actor)
        }
        let read = await #expect(throws: OperationError.self) {
            try await lab.service.findCollection(collectionID, as: actor)
        }
        let propose = await #expect(throws: OperationError.self) {
            try await lab.service.propose(.createCollection(draft: CollectionDraft(title: "Samples")), as: actor)
        }

        for error in [commit, read, propose] {
            #expect(error?.denial?.adapter == adapter)
        }
        #expect(read?.denial?.reason == .deniedByPolicy)
        #expect(propose?.denial?.reason == .deniedByPolicy)
        #expect(commit?.denial?.reason == (adapter == .modelTool ? .outsideAdapterCeiling : .deniedByPolicy))
        #expect(await lab.appliedCommits == 0)
    }

    @Test func everyAdapterMeetsTheSameConflictAndMissingEntityRules() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        try await lab.perform(.updateItem(id: item.id, expected: .initial, changes: ItemChanges(note: "Newer")))

        for adapter in AdapterKind.allCases where adapter != .modelTool {
            let stale = try await lab.perform(
                .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "Overwrite")), as: .granted(adapter)
            )
            #expect(stale.conflict?.current == .r(2), "\(adapter.rawValue) must not overwrite")
            await #expect(throws: OperationError.notFound(.item(ItemID(rawValue: uuid(404))))) {
                try await lab.perform(
                    .updateItem(id: ItemID(rawValue: uuid(404)), expected: .initial, changes: ItemChanges(note: "x")),
                    as: .granted(adapter)
                )
            }
        }
        #expect(try await lab.item(item.id).title == "Amber sample")
    }

    @Test func aModelToolCannotCommitEvenWhenGrantedEverything() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        let before = await lab.appliedCommits

        let archive = await #expect(throws: OperationError.self) {
            try await lab.perform(.archiveItem(id: item.id, expected: .initial), as: .modelTool)
        }
        #expect(archive?.denial?.required == .commitDestructive)
        #expect(archive?.denial?.reason == .outsideAdapterCeiling)

        let update = await #expect(throws: OperationError.self) {
            try await lab.perform(
                .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "Model edit")), as: .modelTool
            )
        }
        #expect(update?.denial?.required == .commit)
        #expect(ActorScope.modelTool.effectivePermissions == [.read, .propose])

        #expect(await lab.appliedCommits == before)
        let current = try await lab.item(item.id)
        #expect(!current.isArchived && current.title == "Amber sample")
    }

    @Test func aModelToolReadsAndProposesAndAPersonCommitsTheProposal() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        let before = await lab.appliedCommits

        #expect(try await lab.service.findItem(item.id, as: .modelTool) == item)
        let proposal = try await lab.service.propose(.archiveItem(id: item.id, expected: .initial), as: .modelTool)
        #expect(proposal.isReady)
        #expect(proposal.proposedBy == .modelTool)
        #expect(proposal.summary == "Archive item “Amber sample”.")
        #expect(await lab.appliedCommits == before)
        #expect(try await !lab.item(item.id).isArchived)

        let receipt = try await lab.perform(proposal.operation, as: .appUI)
        #expect(receipt.status == .committed)
        #expect(receipt.admitted.adapter == .appUI)
        #expect(try await lab.item(item.id).isArchived)
    }

    @Test func aProposalIsValidatedAgainstCurrentState() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        try await lab.perform(.updateItem(id: item.id, expected: .initial, changes: ItemChanges(note: "Newer")))

        let stale = try await lab.service.propose(.archiveItem(id: item.id, expected: .initial), as: .modelTool)
        #expect(!stale.isReady)
        #expect(stale.conflict?.current == .r(2))
        await #expect(throws: OperationError.notFound(.item(ItemID(rawValue: uuid(404))))) {
            try await lab.service.propose(.archiveItem(id: ItemID(rawValue: uuid(404)), expected: .initial), as: .modelTool)
        }
    }

    @Test func aPermissivePolicyCannotWidenAnAdapterCeiling() async throws {
        let lab = Harness(policy: RecordingPolicy(decision: .allow))
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)

        for adapter in [AdapterKind.modelTool, .shareExtension, .authorizedPeer] {
            let error = await #expect(throws: OperationError.self) {
                try await lab.perform(.archiveItem(id: item.id, expected: .initial), as: .granted(adapter))
            }
            #expect(error?.denial?.reason == .outsideAdapterCeiling, "\(adapter.rawValue) archived")
        }
        #expect(try await !lab.item(item.id).isArchived)
    }

    @Test func grantsNarrowWhatAnAdapterMayDo() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        let editor = ActorScope(adapter: .appUI, grants: [.read, .commit])

        try await lab.perform(.updateItem(id: item.id, expected: .initial, changes: ItemChanges(note: "Allowed")), as: editor)
        let archive = await #expect(throws: OperationError.self) {
            try await lab.perform(.archiveItem(id: item.id, expected: .r(2)), as: editor)
        }
        #expect(archive?.denial?.reason == .notGranted)
        let proposal = await #expect(throws: OperationError.self) {
            try await lab.service.propose(.archiveItem(id: item.id, expected: .r(2)), as: editor)
        }
        #expect(proposal?.denial?.required == .propose)
    }

    @Test func undoIsAuthorizedLikeAnyOtherRequest() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        let archived = try await lab.perform(.archiveItem(id: item.id, expected: .initial))
        let undo = try #require(archived.undo)

        let denied = await #expect(throws: OperationError.self) { try await lab.perform(undo, as: .modelTool) }
        #expect(denied?.denial?.reason == .outsideAdapterCeiling)
        #expect(try await lab.item(item.id).isArchived)
    }

    @Test func appUIAndAppIntentProduceEquivalentStateAndReceipts() async throws {
        // SPEC R-02: the same operations through two entry points, each against a fresh store.
        func run(as adapter: AdapterKind) async throws -> (LabItem, [ActionReceipt]) {
            let lab = Harness(operationIDs: SequentialOperationIDs())
            let actor = ActorScope.granted(adapter)
            let collectionID = CollectionID(rawValue: uuid(10))
            let itemID = ItemID(rawValue: uuid(11))
            var receipts: [ActionReceipt] = []
            receipts.append(try await lab.perform(
                .createCollection(draft: CollectionDraft(id: collectionID, title: "Samples")),
                as: actor, id: RequestID(rawValue: uuid(20))
            ))
            receipts.append(try await lab.perform(
                .createItem(draft: ItemDraft(id: itemID, in: collectionID, title: "Amber sample")),
                as: actor, id: RequestID(rawValue: uuid(21))
            ))
            receipts.append(try await lab.perform(
                .updateItem(id: itemID, expected: .initial, changes: ItemChanges(note: "Checked")),
                as: actor, id: RequestID(rawValue: uuid(22))
            ))
            receipts.append(try await lab.perform(
                .archiveItem(id: itemID, expected: .r(2)), as: actor, id: RequestID(rawValue: uuid(23))
            ))
            return (try await lab.item(itemID), receipts)
        }

        let (uiItem, uiReceipts) = try await run(as: .appUI)
        let (intentItem, intentReceipts) = try await run(as: .appIntent)

        #expect(uiItem == intentItem)
        #expect(uiReceipts.count == intentReceipts.count)
        for (ui, intent) in zip(uiReceipts, intentReceipts) {
            #expect(ui.operationID == intent.operationID)
            #expect(ui.status == intent.status)
            #expect(ui.changes == intent.changes)
            #expect(ui.summary == intent.summary)
            #expect(ui.undo == intent.undo)
            #expect(ui.admitted.operation == intent.admitted.operation)
            #expect(ui.admitted.adapter == .appUI && intent.admitted.adapter == .appIntent)
        }
    }
}
