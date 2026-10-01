import Foundation
import LabDomain
import Testing
@testable import TrustDesk

/// Qualification uses fresh stores and scripted authorization, never a biometric prompt.
@Suite struct TrustDeskQualificationTests {
    @Test func cancellationAndUnavailabilityRetainAnExistingOpenRecord() async throws {
        let backend = ServiceBackend(service: OperationService(store: InMemoryOperationStore()))
        let secrets = MemorySecretStore()
        let desk = TrustDesk(secrets: secrets, authorizer: ScriptedLocalAuthorizer(results: [
            .cancelled, .unavailable("Fixture unavailable"), .biometricFailed
        ]))
        _ = desk.confirmLocally()
        _ = try await desk.openSealedRecord(through: backend, requestID: RequestID())
        let before = try await backend.item(TrustDeskFixture.item)
        for _ in 0..<3 {
            _ = await desk.authorizeWithDevice()
            #expect(desk.liveGrant() != nil)
            #expect(try await backend.item(TrustDeskFixture.item) == before)
            #expect(try secrets.read(account: desk.identity.id.account) == TrustDeskFixture.secret)
        }
        desk.revoke(desk.liveGrant()!.id)
        await #expect(throws: TrustDeskError.grantRevoked) {
            try await desk.openSealedRecord(through: backend, requestID: RequestID())
        }
        #expect(try await backend.item(TrustDeskFixture.item) == before)
    }

    @Test func deniedCommitWritesNeitherRecordNorSecret() async throws {
        let backend = ServiceBackend(service: OperationService(store: InMemoryOperationStore()))
        let secrets = MemorySecretStore()
        let desk = TrustDesk(secrets: secrets, authorizer: ScriptedLocalAuthorizer(results: []))
        _ = desk.confirmLocally()
        await #expect(throws: TrustDeskError.self) {
            try await desk.openSealedRecord(through: DeniedCommitBackend(base: backend), requestID: RequestID())
        }
        #expect(try await backend.item(TrustDeskFixture.item) == nil)
        #expect(try secrets.read(account: desk.identity.id.account) == nil)
    }

    @Test func aStaleOpenDoesNotWriteASecret() async throws {
        let backend = ServiceBackend(service: OperationService(store: InMemoryOperationStore()))
        let secrets = MemorySecretStore()
        let desk = TrustDesk(secrets: secrets, authorizer: ScriptedLocalAuthorizer(results: []))
        _ = try await desk.rename(to: "Fixture before conflict", through: backend, requestID: RequestID())
        _ = desk.confirmLocally()
        let racing = StaleOpenBackend(base: backend)
        let result = try await desk.openSealedRecord(through: racing, requestID: RequestID())
        guard case .committed(let receipt) = result, case .conflict = receipt.status else {
            Issue.record("Expected a conflict receipt")
            return
        }
        #expect(try secrets.read(account: desk.identity.id.account) == nil)
        #expect(try await backend.item(TrustDeskFixture.item)?.note.value == TrustDeskFixture.sealedNote)
        #expect(try await backend.item(TrustDeskFixture.item)?.title.value == "Concurrent fixture")
    }

    @Test func completeFixtureReplayFromCleanState() async throws {
        let backend = ServiceBackend(service: OperationService(store: InMemoryOperationStore()))
        let secrets = MemorySecretStore()
        let desk = TrustDesk(secrets: secrets, authorizer: ScriptedLocalAuthorizer(results: [.biometricFailed]))
        #expect(try await backend.item(TrustDeskFixture.item) == nil)
        _ = await desk.authorizeWithDevice()
        #expect(desk.liveGrant() == nil)
        _ = desk.confirmLocally()
        _ = try await desk.openSealedRecord(through: backend, requestID: RequestID())
        let reference = desk.registerPasskey()
        _ = try await desk.rename(to: "Renamed qualification fixture", through: backend, requestID: RequestID())
        let assertion = try desk.authenticatePasskey()
        #expect(assertion.userHandle == TrustDeskFixture.identity.userHandle)
        #expect(assertion.credentialID == Data(base64Encoded: reference.account))
        #expect(throws: TrustDeskError.passkeyIsNotAnAppSecret) { try desk.exportPasskeyMaterial(reference) }
        _ = try await desk.resetDesk(through: backend, requestID: RequestID())
        #expect(desk.liveGrant() == nil)
        #expect(desk.passkeyReference() == nil)
        #expect(try secrets.read(account: desk.identity.id.account) == nil)
        #expect(try await backend.item(TrustDeskFixture.item)?.note.value == TrustDeskFixture.sealedNote)
        _ = desk.confirmLocally()
        _ = try await desk.openSealedRecord(through: backend, requestID: RequestID())
        #expect(try await backend.item(TrustDeskFixture.item)?.note.value == TrustDeskFixture.releasedNote)
    }
}

/// Advances the stored revision after the desk reads it, before its update commits.
private struct StaleOpenBackend: TrustDeskBackend {
    let base: ServiceBackend
    func item(_ id: ItemID) async throws(TrustDeskError) -> LabItem? { try await base.item(id) }
    func collection(_ id: CollectionID) async throws(TrustDeskError) -> LabCollection? { try await base.collection(id) }
    func perform(_ operation: DomainOperation, requestID: RequestID, names: [EntityReference: String]) async throws(TrustDeskError) -> ActionReceipt {
        if case .updateItem(let id, let expected, _) = operation {
            do {
                let changes = try ItemChanges(title: EntityTitle("Concurrent fixture"), note: nil)
                _ = try await base.perform(.updateItem(id: id, expected: expected, changes: changes), requestID: RequestID(), names: [:])
            } catch let error as TrustDeskError { throw error }
            catch { throw .labUnavailable("Fixture setup failed") }
        }
        return try await base.perform(operation, requestID: requestID, names: names)
    }
}

private struct DeniedCommitBackend: TrustDeskBackend {
    let base: ServiceBackend
    func item(_ id: ItemID) async throws(TrustDeskError) -> LabItem? { try await base.item(id) }
    func collection(_ id: CollectionID) async throws(TrustDeskError) -> LabCollection? { try await base.collection(id) }
    func perform(_ operation: DomainOperation, requestID: RequestID, names: [EntityReference: String]) async throws(TrustDeskError) -> ActionReceipt {
        do {
            return try await base.service.perform(OperationRequest(id: requestID, operation: operation, actor: ActorScope(adapter: .appUI, grants: [.read])))
        } catch { throw .operation(error) }
    }
}
