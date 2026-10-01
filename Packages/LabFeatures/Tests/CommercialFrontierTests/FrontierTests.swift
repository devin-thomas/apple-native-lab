import Foundation
import LabDomain
import Testing
@testable import CommercialFrontier

struct ServiceBackend: FrontierBackend {
    let service: OperationService
    var actor = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
    func item(_ id: ItemID) async throws -> LabItem? {
        do { return try await service.findItem(id, as: actor) }
        catch OperationError.notFound { return nil }
    }
    func collection(_ id: CollectionID) async throws -> LabCollection? {
        do { return try await service.findCollection(id, as: actor) }
        catch OperationError.notFound { return nil }
    }
    func perform(_ operation: DomainOperation, requestID: RequestID) async throws -> ActionReceipt {
        try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
    }
}

struct UnavailableBackend: FrontierBackend {
    func item(_ id: ItemID) async throws -> LabItem? { throw FrontierError.unavailable }
    func collection(_ id: CollectionID) async throws -> LabCollection? { throw FrontierError.unavailable }
    func perform(_ operation: DomainOperation, requestID: RequestID) async throws -> ActionReceipt { throw FrontierError.unavailable }
}

@MainActor @Suite struct FrontierTests {
    private func backend() -> ServiceBackend {
        ServiceBackend(service: OperationService(store: InMemoryOperationStore(), policy: GrantAuthorizationPolicy(ledger: GrantLedger())))
    }

    @Test func threeIndependentLifecyclesAndReceipts() async throws {
        let desk = FrontierDesk(), backend = backend()
        for (capability, start, stop) in [(FrontierCapabilityCase.pushToTalk, FrontierAction.join, FrontierAction.leave),
                                        (.carPlay, .connect, .disconnect), (.screenTime, .authorizeSelf, .revoke)] {
            let receipt = try await desk.perform(start, for: capability, through: backend, requestID: RequestID())
            #expect(receipt.admitted.adapter == .appUI)
            #expect(try await desk.snapshot(capability, through: backend).active)
            _ = try await desk.perform(stop, for: capability, through: backend, requestID: RequestID())
            #expect(try await desk.snapshot(capability, through: backend) == FrontierSnapshot())
        }
        #expect(FrontierFixture.audioRows.count == 2)
    }

    @Test func screenTimeEscapeClearsRestrictionsAndAuthorization() async throws {
        let desk = FrontierDesk(), backend = backend()
        _ = try await desk.perform(.authorizeSelf, for: .screenTime, through: backend, requestID: RequestID())
        _ = try await desk.perform(.restrictSample, for: .screenTime, through: backend, requestID: RequestID())
        #expect(try await desk.snapshot(.screenTime, through: backend).restricted)
        _ = try await desk.perform(.revoke, for: .screenTime, through: backend, requestID: RequestID())
        #expect(try await desk.snapshot(.screenTime, through: backend) == FrontierSnapshot())
        #expect(FrontierFixture.escape.contains("Settings"))
        #expect(FrontierFixture.escape.contains("Never shield"))
    }

    @Test func invalidActionsAndUnapprovedRestrictionWriteNothing() async throws {
        let desk = FrontierDesk(), backend = backend()
        for (capability, action) in [(FrontierCapabilityCase.pushToTalk, FrontierAction.restrictSample),
                                    (.carPlay, .join), (.screenTime, .restrictSample), (.pushToTalk, .leave)] {
            await #expect(throws: FrontierError.invalidTransition) {
                try await desk.perform(action, for: capability, through: backend, requestID: RequestID())
            }
            #expect(try await backend.item(capability.itemID) == nil)
        }
        #expect(try await backend.collection(FrontierFixture.collection) == nil)
    }

    @Test func deniedRequestsAndDuplicateReauthorization() async throws {
        let desk = FrontierDesk(), backend = backend(), request = RequestID()
        let first = try await desk.perform(.join, for: .pushToTalk, through: backend, requestID: request)
        let duplicate = try await desk.perform(.join, for: .pushToTalk, through: backend, requestID: request)
        #expect(first.operationID == duplicate.operationID)
        var denied = backend
        denied.actor = ActorScope(adapter: .modelTool, grants: Set(Permission.allCases))
        await #expect(throws: (any Error).self) {
            try await desk.perform(.join, for: .pushToTalk, through: denied, requestID: request)
        }
        await #expect(throws: OperationError.requestIDReused(request)) {
            try await desk.perform(.leave, for: .pushToTalk, through: backend, requestID: request)
        }
        #expect(try await desk.snapshot(.pushToTalk, through: backend).active)
    }

    @Test func deniedFirstRequestCreatesNothing() async throws {
        let desk = FrontierDesk(), allowed = backend()
        var denied = allowed
        denied.actor = ActorScope(adapter: .appUI, grants: [.read])
        await #expect(throws: (any Error).self) {
            try await desk.perform(.authorizeSelf, for: .screenTime, through: denied, requestID: RequestID())
        }
        #expect(try await allowed.item(FrontierCapabilityCase.screenTime.itemID) == nil)
        #expect(try await allowed.collection(FrontierFixture.collection) == nil)
    }

    @Test func cancellationAndUnavailablePath() async throws {
        let desk = FrontierDesk(), backend = backend()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: FrontierError.cancelled) {
                try await desk.perform(.join, for: .pushToTalk, through: backend, requestID: RequestID())
            }
        }
        await task.value
        #expect(try await backend.item(FrontierCapabilityCase.pushToTalk.itemID) == nil)
        await #expect(throws: FrontierError.unavailable) {
            try await desk.perform(.connect, for: .carPlay, through: UnavailableBackend(), requestID: RequestID())
        }
        _ = try await desk.perform(.connect, for: .carPlay, through: backend, requestID: RequestID())
        #expect(try await desk.snapshot(.carPlay, through: backend).active)
    }

    @Test func staleUpdateRefusesAndKeepsLatestState() async throws {
        let desk = FrontierDesk(), backend = backend()
        _ = try await desk.perform(.join, for: .pushToTalk, through: backend, requestID: RequestID())
        await #expect(throws: FrontierError.conflict) {
            try await desk.perform(.leave, for: .pushToTalk, through: StaleBackend(base: backend), requestID: RequestID())
        }
        #expect(try await desk.snapshot(.pushToTalk, through: backend).active)
    }

    @Test func malformedOwnedRecordIsNotOverwritten() async throws {
        let desk = FrontierDesk(), backend = backend()
        _ = try await desk.perform(.join, for: .pushToTalk, through: backend, requestID: RequestID())
        let item = try #require(try await backend.item(FrontierCapabilityCase.pushToTalk.itemID))
        let changes = try ItemChanges(title: nil, note: ItemNote("Unrecognized state"))
        _ = try await backend.perform(.updateItem(id: item.id, expected: item.revision, changes: changes), requestID: RequestID())
        await #expect(throws: FrontierError.invalidRecord) {
            try await desk.perform(.reset, for: .pushToTalk, through: backend, requestID: RequestID())
        }
        #expect(try await backend.item(item.id)?.note.value == "Unrecognized state")
    }

    @Test func resetIsConfinedAndStateSurvivesAnotherDesk() async throws {
        let desk = FrontierDesk(), backend = backend()
        _ = try await desk.perform(.join, for: .pushToTalk, through: backend, requestID: RequestID())
        _ = try await desk.perform(.connect, for: .carPlay, through: backend, requestID: RequestID())
        let unrelated = CollectionID()
        _ = try await backend.perform(.createCollection(draft: CollectionDraft(id: unrelated, title: try EntityTitle("Unrelated user collection"))), requestID: RequestID())
        _ = try await desk.perform(.reset, for: .pushToTalk, through: backend, requestID: RequestID())
        #expect(try await FrontierDesk().snapshot(.pushToTalk, through: backend) == FrontierSnapshot())
        #expect(try await FrontierDesk().snapshot(.carPlay, through: backend).active)
        #expect(try await backend.collection(unrelated) != nil)
    }
}

/// Injects a competing revision after the desk has read its snapshot.
struct StaleBackend: FrontierBackend {
    let base: ServiceBackend
    func item(_ id: ItemID) async throws -> LabItem? { try await base.item(id) }
    func collection(_ id: CollectionID) async throws -> LabCollection? { try await base.collection(id) }
    func perform(_ operation: DomainOperation, requestID: RequestID) async throws -> ActionReceipt {
        if case .updateItem(let id, let expected, _) = operation {
            let changes = try ItemChanges(title: nil, note: ItemNote("Simulation: {\"active\":true,\"restricted\":false} "))
            _ = try await base.perform(.updateItem(id: id, expected: expected, changes: changes), requestID: RequestID())
        }
        return try await base.perform(operation, requestID: requestID)
    }
}
