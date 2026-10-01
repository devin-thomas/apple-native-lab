import Foundation
import LabDomain
import Testing
@testable import CommerceWithoutTricks

@MainActor
@Suite struct CommerceLifecycleTests {
    @Test func cancellationAfterAReadStopsBeforeAWrite() async throws {
        let desk = CommerceDesk()
        let task = Task { @MainActor in
            do {
                _ = try await desk.purchase(CommerceFixture.notebook.id, script: .verified,
                                            through: CancellingReadBackend(), requestID: RequestID())
                Issue.record("Cancellation must refuse the commit")
            } catch { #expect((error as? CommerceError) == .cancelled) }
        }
        await task.value
        #expect(desk.entitlement(for: CommerceFixture.notebook.id) == nil)
        #expect(desk.state(for: CommerceFixture.notebook.id) == .available)
    }

    @Test func anAwaitingCommitRefusesAnotherDeskMutation() async throws {
        let (desk, backend) = commerceLab()
        let reentrant = ReentrantBackend(desk: desk, backend: backend)
        _ = try await desk.purchase(CommerceFixture.notebook.id, script: .verified,
                                    through: reentrant, requestID: RequestID())
        #expect(reentrant.refusedConcurrentAction)
        #expect(desk.entitlement(for: CommerceFixture.notebook.id) != nil)
        #expect(desk.entitlement(for: CommerceFixture.compass.id) == nil)
    }

    @Test func resetLeavesAnUnrelatedImportedRecordUnchanged() async throws {
        let (desk, backend) = commerceLab()
        let collection = CollectionID()
        let item = ItemID()
        _ = try await backend.perform(.createCollection(draft: CollectionDraft(id: collection, title: EntityTitle("Imported records"))), requestID: RequestID(), names: [:])
        _ = try await backend.perform(.createItem(draft: ItemDraft(id: item, in: collection, title: EntityTitle("Original import"), note: ItemNote("Keep this note"))), requestID: RequestID(), names: [:])
        let before = try await backend.item(item)
        _ = try await desk.purchase(CommerceFixture.notebook.id, script: .verified, through: backend, requestID: RequestID())
        _ = try await desk.reset(through: backend, requestID: RequestID())
        #expect(try await backend.item(item) == before)
    }
}

struct CancellingReadBackend: CommerceBackend {
    func item(_ id: ItemID) async throws(CommerceError) -> LabItem? { nil }
    func collection(_ id: CollectionID) async throws(CommerceError) -> LabCollection? {
        withUnsafeCurrentTask { $0?.cancel() }
        return nil
    }
    func perform(_ operation: DomainOperation, requestID: RequestID,
                 names: [EntityReference: String]) async throws(CommerceError) -> ActionReceipt {
        Issue.record("A cancelled task must not call the write backend")
        throw .cancelled
    }
}

@MainActor
final class ReentrantBackend: CommerceBackend {
    let desk: CommerceDesk
    let backend: ServiceBackend
    var refusedConcurrentAction = false
    init(desk: CommerceDesk, backend: ServiceBackend) { self.desk = desk; self.backend = backend }
    func item(_ id: ItemID) async throws(CommerceError) -> LabItem? { try await backend.item(id) }
    func collection(_ id: CollectionID) async throws(CommerceError) -> LabCollection? {
        do {
            _ = try await desk.purchase(CommerceFixture.compass.id, script: .verified,
                                        through: backend, requestID: RequestID())
        } catch { refusedConcurrentAction = error == .operationInProgress }
        return try await backend.collection(id)
    }
    func perform(_ operation: DomainOperation, requestID: RequestID,
                 names: [EntityReference: String]) async throws(CommerceError) -> ActionReceipt {
        try await backend.perform(operation, requestID: requestID, names: names)
    }
}

