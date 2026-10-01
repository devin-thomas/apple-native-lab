import Foundation
import LabDomain
import Testing
@testable import CommerceWithoutTricks

@MainActor
@Suite struct CommerceFailureTests {
    @Test func refusedApprovalRefundRevocationAndResetKeepTheLastEntitlement() async throws {
        let (desk, backend) = commerceLab()
        let id = CommerceFixture.notebook.id
        _ = try await desk.purchase(id, script: .pendingApproval, through: backend, requestID: RequestID())
        await #expect(throws: CommerceError.cancelled) {
            try await desk.approvePending(id, through: CancelledBackend(), requestID: RequestID())
        }
        #expect(desk.state(for: id) == .pendingApproval)
        #expect(desk.entitlement(for: id) == nil)
        _ = try await desk.approvePending(id, through: backend, requestID: RequestID())
        let before = desk.entitlement(for: id)
        await #expect(throws: CommerceError.labUnavailable("The store did not open.")) {
            try await desk.refund(id, through: UnavailableBackend(), requestID: RequestID())
        }
        await #expect(throws: CommerceError.labUnavailable("The store did not open.")) {
            try await desk.revoke(id, through: UnavailableBackend(), requestID: RequestID())
        }
        await #expect(throws: CommerceError.labUnavailable("The store did not open.")) {
            try await desk.reset(through: UnavailableBackend(), requestID: RequestID())
        }
        #expect(desk.entitlement(for: id) == before)
        #expect(desk.state(for: id) == .purchased)
    }

    @Test func duplicateRequestsReplayAndRemainAuthorizationChecked() async throws {
        let (desk, backend) = commerceLab()
        let request = RequestID()
        let id = CommerceFixture.notebook.id
        let first = try await desk.purchase(id, script: .verified, through: backend, requestID: request)
        let before = try await backend.item(CommerceFixture.notebook.itemID)
        let retry = try await desk.purchase(id, script: .verified, through: backend, requestID: request)
        guard case .committed(let original) = first, case .committed(let replay) = retry else {
            Issue.record("A duplicate must return its original receipt")
            return
        }
        #expect(original == replay)
        #expect(try await backend.item(CommerceFixture.notebook.itemID) == before)
        await #expect(throws: CommerceError.operation(.requestIDReused(request))) {
            try await desk.purchase(id, script: .unverified, through: backend, requestID: request)
        }
        var denied = backend
        denied.actor = ActorScope(adapter: .appUI, grants: [.read])
        await #expect(throws: CommerceError.self) {
            try await desk.purchase(id, script: .verified, through: denied, requestID: request)
        }
        let fresh = CommerceDesk()
        await #expect(throws: CommerceError.self) {
            try await fresh.purchase(id, script: .verified, through: denied, requestID: RequestID())
        }
        #expect(fresh.entitlement(for: id) == nil)
        #expect(try await backend.item(CommerceFixture.notebook.itemID) == before)
    }

    @Test func laterFailuresCannotRestoreARefundedTransaction() async throws {
        let (desk, backend) = commerceLab()
        let id = CommerceFixture.notebook.id
        _ = try await desk.purchase(id, script: .verified, through: backend, requestID: RequestID())
        _ = try await desk.refund(id, through: backend, requestID: RequestID())
        for script in [SimulatedPurchaseScript.unverified, .cancelled, .failed, .pendingApproval] {
            _ = try await desk.purchase(id, script: script, through: backend, requestID: RequestID())
            #expect(try await desk.restore(through: backend, requestID: RequestID()).isEmpty)
            #expect(desk.entitlement(for: id) == nil)
        }
    }

    @Test func pendingAndUnverifiedAttemptsKeepAnEarlierVerifiedGrant() async throws {
        let (desk, backend) = commerceLab()
        let id = CommerceFixture.notebook.id
        _ = try await desk.purchase(id, script: .verified, through: backend, requestID: RequestID())
        let entitlement = desk.entitlement(for: id)
        for script in [SimulatedPurchaseScript.unverified, .pendingApproval, .cancelled, .failed] {
            _ = try await desk.purchase(id, script: script, through: backend, requestID: RequestID())
            #expect(desk.entitlement(for: id) == entitlement)
        }
        desk.setOffline(true)
        await #expect(throws: CommerceError.offlineUnavailable) {
            try await desk.restore(through: backend, requestID: RequestID())
        }
        #expect(desk.entitlement(for: id) == entitlement)
    }

    @Test func staleReceiptDoesNotGrantOrClearEntitlements() async throws {
        let (desk, backend) = commerceLab()
        let id = CommerceFixture.notebook.id
        _ = try await desk.purchase(id, script: .verified, through: backend, requestID: RequestID())
        let before = desk.entitlement(for: id)
        await #expect(throws: CommerceError.stateChanged) {
            try await desk.refund(id, through: RacingBackend(backend: backend), requestID: RequestID())
        }
        #expect(desk.entitlement(for: id) == before)
        #expect(desk.state(for: id) == .purchased)
    }
}

/// An intervening writer makes the desk's expected revision stale before its update commits.
struct RacingBackend: CommerceBackend {
    let backend: ServiceBackend
    func item(_ id: ItemID) async throws(CommerceError) -> LabItem? { try await backend.item(id) }
    func collection(_ id: CollectionID) async throws(CommerceError) -> LabCollection? { try await backend.collection(id) }
    func perform(_ operation: DomainOperation, requestID: RequestID,
                 names: [EntityReference: String]) async throws(CommerceError) -> ActionReceipt {
        if case .updateItem(let id, let expected, _) = operation {
            do {
                let changes = try ItemChanges(title: EntityTitle("Edited fixture"), note: nil)
                _ = try await backend.perform(.updateItem(id: id, expected: expected, changes: changes),
                                              requestID: RequestID(), names: [:])
            } catch let error as CommerceError { throw error }
            catch { throw .labUnavailable("Invalid test fixture") }
        }
        return try await backend.perform(operation, requestID: requestID, names: names)
    }
}

