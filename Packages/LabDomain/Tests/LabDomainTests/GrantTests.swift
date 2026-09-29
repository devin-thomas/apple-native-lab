import Foundation
import LabDomain
import Testing

/// CORE-006: a sensitive commit needs a short-lived grant that names its adapter, operation,
/// and target, checked at commit. A grant only narrows (ADR-011).
@Suite struct GrantTests {
    private func archive(_ item: LabItem) -> DomainOperation { .archiveItem(id: item.id, expected: item.revision) }

    private func lab() async throws -> (GrantedLab, LabCollection, LabItem) {
        let lab = GrantedLab()
        let collection = try await lab.makeCollection()
        let itemID = ItemID()
        _ = try await lab.service.perform(OperationRequest(
            id: RequestID(), operation: .createItem(draft: ItemDraft(id: itemID, in: collection.id, title: "Sample")), actor: .appUI
        ))
        return (lab, collection, try await lab.service.findItem(itemID, as: .appUI))
    }

    @Test func aSensitiveCommitWithoutAGrantFailsClosed() async throws {
        let (lab, _, item) = try await lab()
        let before = await lab.appliedCommits
        let error = await #expect(throws: OperationError.self) {
            _ = try await lab.service.perform(OperationRequest(id: RequestID(), operation: archive(item), actor: .appUI))
        }
        #expect(error?.denial?.reason == .deniedByPolicy)
        #expect(lab.ledger.check(archive(item), from: .appUI) == .missing)
        #expect(await lab.appliedCommits == before)
        #expect(try await !lab.service.findItem(item.id, as: .appUI).isArchived)
    }

    @Test func aMatchingLiveGrantAllowsExactlyThatCommit() async throws {
        let (lab, _, item) = try await lab()
        let grant = try lab.ledger.issue(for: archive(item), to: .appUI)
        #expect(grant.adapter == .appUI && grant.operations == [.archiveItem] && grant.target == .entity(.item(item.id)))
        #expect(grant.expiresAt - grant.issuedAt == GrantLedger.defaultLifetime)
        #expect(lab.ledger.check(archive(item), from: .appUI) == .granted(grant.id))
        let receipt = try await lab.service.perform(OperationRequest(id: RequestID(), operation: archive(item), actor: .appUI))
        #expect(receipt.status == .committed)
    }

    @Test func anExpiredGrantFailsClosed() async throws {
        let (lab, _, item) = try await lab()
        try lab.ledger.issue(for: archive(item), to: .appUI, lifetime: .seconds(30))
        lab.clock.advance(by: .seconds(30))
        #expect(lab.ledger.check(archive(item), from: .appUI) == .expired)
        let error = await #expect(throws: OperationError.self) {
            _ = try await lab.service.perform(OperationRequest(id: RequestID(), operation: archive(item), actor: .appUI))
        }
        #expect(error?.denial?.reason == .deniedByPolicy)
        #expect(try await !lab.service.findItem(item.id, as: .appUI).isArchived)
    }

    @Test func aGrantIsCheckedAtCommitNotWhenTheRequestIsPrepared() async throws {
        let (lab, _, item) = try await lab()
        try lab.ledger.issue(for: archive(item), to: .appUI, lifetime: .seconds(10))
        let request = OperationRequest(id: RequestID(), operation: archive(item), actor: .appUI)
        #expect(lab.ledger.check(archive(item), from: .appUI).isGranted)
        lab.clock.advance(by: .seconds(11)) // The person hesitated; the approval lapsed.
        await #expect(throws: OperationError.self) { try await lab.service.perform(request) }
        #expect(try await !lab.service.findItem(item.id, as: .appUI).isArchived)
    }

    @Test func aGrantForAnotherTargetOperationOrAdapterIsOutOfScope() async throws {
        let (lab, collection, item) = try await lab()
        let otherItemID = ItemID()
        _ = try await lab.service.perform(OperationRequest(
            id: RequestID(), operation: .createItem(draft: ItemDraft(id: otherItemID, in: collection.id, title: "Other")), actor: .appUI
        ))
        let other = try await lab.service.findItem(otherItemID, as: .appUI)
        try lab.ledger.issue(for: archive(other), to: .appUI)
        try lab.ledger.issue(to: .appIntent, for: [.archiveItem], on: .entity(.item(item.id)))
        try lab.ledger.issue(to: .appUI, for: [.updateItem], on: .entity(.item(item.id)))

        #expect(lab.ledger.check(archive(item), from: .appUI) == .outOfScope)
        let error = await #expect(throws: OperationError.self) {
            _ = try await lab.service.perform(OperationRequest(id: RequestID(), operation: archive(item), actor: .appUI))
        }
        #expect(error?.denial?.reason == .deniedByPolicy)
        #expect(try await !lab.service.findItem(item.id, as: .appUI).isArchived)
    }

    @Test func aRevokedGrantNoLongerCounts() async throws {
        let (lab, _, item) = try await lab()
        let grant = try lab.ledger.issue(for: archive(item), to: .appUI)
        lab.ledger.revoke(grant.id)
        #expect(lab.ledger.check(archive(item), from: .appUI) == .missing)
        try lab.ledger.issue(for: archive(item), to: .appUI)
        lab.ledger.revokeAll()
        #expect(lab.ledger.liveGrants.isEmpty)
    }

    @Test func aClockReadingBeforeIssueFailsClosed() throws {
        let clock = ManualGrantClock()
        clock.advance(by: .seconds(100))
        let ledger = GrantLedger(clock: clock)
        let operation = DomainOperation.archiveItem(id: ItemID(), expected: .initial)
        try ledger.issue(for: operation, to: .appUI)
        clock.advance(by: .seconds(-50))
        #expect(!ledger.check(operation, from: .appUI).isGranted)
    }

    @Test func grantsNeverWidenAnAdapterCeiling() async throws {
        let (lab, collection, item) = try await lab()
        // The ledger refuses to issue what the ceiling forbids.
        #expect(throws: GrantError.exceedsAdapterCeiling(.archiveItem)) {
            try lab.ledger.issue(for: archive(item), to: .shareExtension)
        }
        #expect(throws: GrantError.exceedsAdapterCeiling(.createItem)) {
            try lab.ledger.issue(to: .modelTool, for: [.createItem], on: .newItem(in: collection.id))
        }
        #expect(throws: GrantError.exceedsAdapterCeiling(.resetDemo)) {
            try lab.ledger.issue(to: .authorizedPeer, for: [.resetDemo], on: .demo)
        }
        // And the service applies the ceiling before any policy: a permissive policy plus a
        // grant for the app UI still cannot let a share extension or model tool archive.
        try lab.ledger.issue(for: archive(item), to: .appUI)
        for adapter in [AdapterKind.shareExtension, .authorizedPeer, .modelTool] {
            let error = await #expect(throws: OperationError.self) {
                _ = try await lab.service.perform(OperationRequest(id: RequestID(), operation: archive(item), actor: .granted(adapter)))
            }
            #expect(error?.denial?.reason == .outsideAdapterCeiling, "\(adapter.rawValue)")
        }
        // A grant does not add a permission the actor lacks.
        let readOnly = ActorScope(adapter: .appUI, grants: [.read])
        let error = await #expect(throws: OperationError.self) {
            _ = try await lab.service.perform(OperationRequest(id: RequestID(), operation: archive(item), actor: readOnly))
        }
        #expect(error?.denial?.reason == .notGranted)
        #expect(try await !lab.service.findItem(item.id, as: .appUI).isArchived)
    }

    @Test func issuingValidatesScopeAndLifetime() {
        let ledger = GrantLedger(clock: ManualGrantClock())
        let item = EntityReference.item(ItemID())
        #expect(throws: GrantError.noOperations) { try ledger.issue(to: .appUI, for: [], on: .entity(item)) }
        #expect(throws: GrantError.lifetimeOutOfRange(maximum: GrantLedger.maximumLifetime)) {
            try ledger.issue(to: .appUI, for: [.archiveItem], on: .entity(item), lifetime: .seconds(301))
        }
        #expect(throws: GrantError.lifetimeOutOfRange(maximum: GrantLedger.maximumLifetime)) {
            try ledger.issue(to: .appUI, for: [.archiveItem], on: .entity(item), lifetime: .zero)
        }
        #expect(throws: GrantError.targetMismatch(.archiveCollection)) {
            try ledger.issue(to: .appUI, for: [.archiveCollection], on: .entity(item))
        }
        #expect(throws: GrantError.targetMismatch(.resetDemo)) { try ledger.issue(to: .appUI, for: [.resetDemo], on: .entity(item)) }
    }

    @Test func nonSensitiveCommitsReadsAndProposalsNeedNoGrant() async throws {
        let (lab, _, item) = try await lab()
        let update = DomainOperation.updateItem(id: item.id, expected: item.revision, changes: try ItemChanges(note: "Edited"))
        _ = try await lab.service.perform(OperationRequest(id: RequestID(), operation: update, actor: .appUI))
        _ = try await lab.service.findItem(item.id, as: .granted(.shareExtension))
        _ = try await lab.service.propose(.archiveItem(id: item.id, expected: .r(2)), as: .modelTool)
        // Every commit from outside the app is sensitive, even a creation.
        let error = await #expect(throws: OperationError.self) {
            _ = try await lab.service.perform(OperationRequest(id: RequestID(), operation: update.rebased(onto: .r(2)), actor: .granted(.shareExtension)))
        }
        #expect(error?.denial?.reason == .deniedByPolicy)
    }

    @Test func aReplayIsAuthorizedAgainAndNeedsALiveGrant() async throws {
        let (lab, _, item) = try await lab()
        try lab.ledger.issue(for: archive(item), to: .appUI, lifetime: .seconds(5))
        let request = OperationRequest(id: RequestID(), operation: archive(item), actor: .appUI)
        let first = try await lab.service.perform(request)
        lab.clock.advance(by: .seconds(6))
        await #expect(throws: OperationError.self) { try await lab.service.perform(request) }
        try lab.ledger.issue(for: archive(item), to: .appUI)
        #expect(try await lab.service.perform(request) == first)
    }

    @Test func aGrantCannotBeMadeFromData() {
        // No decoder, no public initializer, no parser: text that looks like a grant is text.
        func isDecodable<T>(_ type: T.Type) -> Bool { type is any Decodable.Type }
        #expect(!isDecodable(CommitGrant.self))
        #expect(!isDecodable(GrantID.self))
        #expect(!isDecodable(GrantTarget.self))
        #expect(!isDecodable(ActorScope.self))
        #expect(!isDecodable(OperationRequest.self))
        #expect(!isDecodable(DiagnosticEvent.self))
        #expect(!isDecodable(DiagnosticName.self))
        #expect(isDecodable(StagingID.self) == false && isDecodable(DomainOperation.self))
    }

    @Test func requirementPresets() {
        let sensitive = GrantRequirement.sensitiveCommits
        #expect(sensitive.requiresGrant(.archiveItem, from: .appUI))
        #expect(sensitive.requiresGrant(.resetDemo, from: .appIntent))
        #expect(sensitive.requiresGrant(.createItem, from: .shareExtension))
        #expect(sensitive.requiresGrant(.updateItem, from: .authorizedPeer))
        #expect(!sensitive.requiresGrant(.createItem, from: .appUI))
        #expect(!sensitive.requiresGrant(.updateItem, from: .appIntent))
        #expect(OperationKind.allCases.allSatisfy { GrantRequirement.everyCommit.requiresGrant($0, from: .appUI) })
    }
}
