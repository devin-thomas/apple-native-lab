import Foundation
import LabDomain
import Testing
@testable import TrustDesk

struct ServiceBackend: TrustDeskBackend {
    let service: OperationService
    let actor = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    func item(_ id: ItemID) async throws(TrustDeskError) -> LabItem? {
        do { return try await service.findItem(id, as: actor) } catch {
            if case .notFound = error { return nil }
            throw .operation(error)
        }
    }

    func collection(_ id: CollectionID) async throws(TrustDeskError) -> LabCollection? {
        do { return try await service.findCollection(id, as: actor) } catch {
            if case .notFound = error { return nil }
            throw .operation(error)
        }
    }

    func perform(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(TrustDeskError) -> ActionReceipt {
        _ = names
        do {
            return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
        } catch {
            throw .operation(error)
        }
    }
}

/// A backend whose every commit is cancelled. Reads report an empty lab.
struct CancelledBackend: TrustDeskBackend {
    func item(_ id: ItemID) async throws(TrustDeskError) -> LabItem? { nil }
    func collection(_ id: CollectionID) async throws(TrustDeskError) -> LabCollection? { nil }
    func perform(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(TrustDeskError) -> ActionReceipt {
        throw .cancelled
    }
}

struct UnavailableBackend: TrustDeskBackend {
    func item(_ id: ItemID) async throws(TrustDeskError) -> LabItem? {
        throw .labUnavailable("The store did not open.")
    }
    func collection(_ id: CollectionID) async throws(TrustDeskError) -> LabCollection? {
        throw .labUnavailable("The store did not open.")
    }
    func perform(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(TrustDeskError) -> ActionReceipt {
        throw .labUnavailable("The store did not open.")
    }
}

private func lab() -> (TrustDesk, ServiceBackend, MemorySecretStore) {
    let secrets = MemorySecretStore()
    let desk = TrustDesk(secrets: secrets, authorizer: ScriptedLocalAuthorizer(results: [.biometricFailed]))
    let backend = ServiceBackend(service: OperationService(store: InMemoryOperationStore()))
    return (desk, backend, secrets)
}

@Suite struct TrustDeskOperationTests {
    @Test func aDisplayNameChangeDoesNotChangeIdentity() async throws {
        let (desk, backend, secrets) = lab()
        let before = desk.identity.id
        let receipt = try await desk.rename(to: "North fixture", through: backend, requestID: RequestID())
        #expect(desk.identity.id == before)
        #expect(desk.identity.id == TrustDeskFixture.identity)
        #expect(desk.identity.displayName == "North fixture")
        let item = try #require(await backend.item(TrustDeskFixture.item))
        #expect(item.id == TrustDeskFixture.item)
        #expect(item.title.value == "North fixture")
        #expect(receipt.status == .committed)
        guard case .granted(let grant) = desk.confirmLocally() else {
            Issue.record("Local confirmation did not grant")
            return
        }
        _ = grant
        _ = try await desk.openSealedRecord(through: backend, requestID: RequestID())
        let again = try await desk.rename(to: "South fixture", through: backend, requestID: RequestID())
        #expect(desk.identity.id == before)
        #expect(try await backend.item(TrustDeskFixture.item)?.id == TrustDeskFixture.item)
        let stored = try secrets.read(account: before.account)
        #expect(stored == TrustDeskFixture.secret)
        let encoded = try JSONEncoder().encode(again)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("trust-desk-fixture-secret"))
    }

    @Test func anEmptyOrOversizedNameIsRefused() async throws {
        let (desk, backend, _) = lab()
        let id = desk.identity.id
        await #expect(throws: TrustDeskError.invalidDisplayName(.emptyTitle)) {
            try await desk.rename(to: "   ", through: backend, requestID: RequestID())
        }
        let long = String(repeating: "n", count: EntityTitle.maximumLength + 1)
        await #expect(throws: TrustDeskError.invalidDisplayName(.titleTooLong(limit: EntityTitle.maximumLength))) {
            try await desk.rename(to: long, through: backend, requestID: RequestID())
        }
        await #expect(throws: TrustDeskError.invalidDisplayName(.controlCharacter(in: .title))) {
            try await desk.rename(to: "bad\u{0007}name", through: backend, requestID: RequestID())
        }
        #expect(desk.identity.id == id)
        #expect(desk.identity.displayName == TrustDeskFixture.defaultDisplayName)
        #expect(try await backend.item(TrustDeskFixture.item) == nil)
    }

    @Test func aBiometricFailureKeepsALocalConfirmationPath() async throws {
        let (desk, backend, secrets) = lab()
        let outcome = await desk.authorizeWithDevice()
        guard case .biometricFailed = outcome else {
            Issue.record("Expected a biometric failure")
            return
        }
        #expect(desk.liveGrant() == nil)
        #expect(try secrets.read(account: TrustDeskFixture.identity.account) == nil)
        #expect(try await backend.item(TrustDeskFixture.item) == nil)
        guard case .granted(let grant) = desk.confirmLocally() else {
            Issue.record("Local confirmation did not grant")
            return
        }
        #expect(grant.method == .localConfirmation)
        #expect(grant.identity == TrustDeskFixture.identity)
        let opened = try await desk.openSealedRecord(through: backend, requestID: RequestID())
        guard case .committed(let receipt) = opened else {
            Issue.record("The open did not commit")
            return
        }
        #expect(receipt.status == .committed)
        #expect(receipt.admitted.adapter == .appUI)
        if case .updateItem(let id, _, _) = receipt.admitted.operation {
            #expect(id == TrustDeskFixture.item)
        } else {
            Issue.record("The receipt was not an item update")
        }
        let item = try #require(await backend.item(TrustDeskFixture.item))
        #expect(item.note.value == TrustDeskFixture.releasedNote)
        #expect(!item.note.value.contains("trust-desk-fixture-secret"))
        #expect(try secrets.read(account: TrustDeskFixture.identity.account) == TrustDeskFixture.secret)
        let encoded = try JSONEncoder().encode(receipt)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("trust-desk-fixture-secret"))
    }

    @Test func aPasskeyAssertionDoesNotAuthorizeTheSealedRecord() async throws {
        let (desk, backend, secrets) = lab()
        let reference = desk.registerPasskey()
        #expect(reference.kind == .passkeySimulation)
        #expect(reference.isExportableAppSecret == false)
        #expect(reference.relyingParty == TrustDeskFixture.relyingPartyID)
        let assertion = try desk.authenticatePasskey()
        #expect(assertion.label == TrustDeskFixture.passkeySimulationLabel)
        #expect(assertion.userHandle == TrustDeskFixture.identity.userHandle)
        #expect(assertion.credentialID == Data(base64Encoded: reference.account))
        #expect(throws: TrustDeskError.passkeyIsNotAnAppSecret) {
            try desk.exportPasskeyMaterial(reference)
        }
        #expect(throws: TrustDeskError.passkeyIsNotAnAppSecret) {
            try desk.copyAppSecret(reference)
        }
        let encoded = try JSONEncoder().encode(reference)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains("passkeySimulation"))
        #expect(!text.contains("trust-desk-fixture-secret"))
        await #expect(throws: TrustDeskError.noLiveGrant) {
            try await desk.openSealedRecord(through: backend, requestID: RequestID())
        }
        #expect(try secrets.read(account: TrustDeskFixture.identity.account) == nil)
        let second = try desk.authenticatePasskey()
        #expect(second.challenge != assertion.challenge)
        #expect(second.credentialID == assertion.credentialID)
        #expect(second.userHandle == assertion.userHandle)
    }

    @Test func renamingDoesNotReplaceThePasskey() async throws {
        let (desk, backend, _) = lab()
        let reference = desk.registerPasskey()
        _ = try await desk.rename(to: "Renamed fixture", through: backend, requestID: RequestID())
        #expect(desk.identity.id == TrustDeskFixture.identity)
        let assertion = try desk.authenticatePasskey()
        #expect(assertion.displayName == "Renamed fixture")
        #expect(assertion.userHandle == TrustDeskFixture.identity.userHandle)
        #expect(assertion.credentialID == Data(base64Encoded: reference.account))
        #expect(desk.passkeyReference()?.account == reference.account)
    }

    @Test func anExpiredOrRevokedGrantDoesNotOpenTheRecord() async throws {
        let secrets = MemorySecretStore()
        let clock = ManualGrantClock()
        let desk = TrustDesk(secrets: secrets, authorizer: ScriptedLocalAuthorizer(results: []), clock: clock)
        let backend = ServiceBackend(service: OperationService(store: InMemoryOperationStore()))
        guard case .granted(let grant) = desk.confirmLocally() else {
            Issue.record("Local confirmation did not grant")
            return
        }
        clock.advance(by: .seconds(60))
        await #expect(throws: TrustDeskError.grantExpired) {
            try await desk.openSealedRecord(through: backend, requestID: RequestID())
        }
        #expect(try secrets.read(account: TrustDeskFixture.identity.account) == nil)

        let again = TrustDesk(secrets: secrets, authorizer: ScriptedLocalAuthorizer(results: []))
        guard case .granted(let live) = again.confirmLocally() else {
            Issue.record("Local confirmation did not grant")
            return
        }
        again.revoke(live.id)
        await #expect(throws: TrustDeskError.grantRevoked) {
            try await again.openSealedRecord(through: backend, requestID: RequestID())
        }
        _ = grant
        #expect(try await backend.item(TrustDeskFixture.item) == nil)
    }

    @Test func aGrantCannotOutliveTheMaximum() throws {
        let ledger = DeskGrantLedger(clock: ManualGrantClock())
        #expect(throws: TrustDeskError.lifetimeOutOfRange) {
            try ledger.issue(
                for: TrustDeskFixture.identity,
                purpose: .openSealedRecord,
                method: .localConfirmation,
                lifetime: .seconds(301)
            )
        }
    }

    @Test func aCancelledOpenCommitsNothing() async throws {
        let (desk, _, secrets) = lab()
        _ = desk.confirmLocally()
        await #expect(throws: TrustDeskError.cancelled) {
            try await desk.openSealedRecord(through: CancelledBackend(), requestID: RequestID())
        }
        #expect(try secrets.read(account: TrustDeskFixture.identity.account) == nil)
    }

    @Test func anUnavailableLabCommitsNothing() async throws {
        let (desk, _, secrets) = lab()
        _ = desk.confirmLocally()
        await #expect(throws: TrustDeskError.labUnavailable("The store did not open.")) {
            try await desk.openSealedRecord(through: UnavailableBackend(), requestID: RequestID())
        }
        #expect(try secrets.read(account: TrustDeskFixture.identity.account) == nil)
        let reference = desk.registerPasskey()
        #expect(reference.kind == .passkeySimulation)
    }

    @Test func aSecretWriteFailureRollsTheNoteBack() async throws {
        let desk = TrustDesk(secrets: UnavailableSecretStore(), authorizer: ScriptedLocalAuthorizer(results: []))
        let backend = ServiceBackend(service: OperationService(store: InMemoryOperationStore()))
        _ = desk.confirmLocally()
        await #expect(throws: TrustDeskError.self) {
            try await desk.openSealedRecord(through: backend, requestID: RequestID())
        }
        let item = try #require(await backend.item(TrustDeskFixture.item))
        #expect(item.note.value == TrustDeskFixture.sealedNote)
    }

    @Test func resetRemovesOnlyTheDeskFixture() async throws {
        let (desk, backend, secrets) = lab()
        _ = desk.confirmLocally()
        _ = try await desk.openSealedRecord(through: backend, requestID: RequestID())
        _ = desk.registerPasskey()
        let otherCollection = CollectionID()
        let otherItem = ItemID()
        _ = try await backend.perform(
            .createCollection(draft: CollectionDraft(id: otherCollection, title: try EntityTitle("Other records"))),
            requestID: RequestID(),
            names: [:]
        )
        _ = try await backend.perform(
            .createItem(draft: ItemDraft(id: otherItem, in: otherCollection, title: try EntityTitle("Kept"))),
            requestID: RequestID(),
            names: [:]
        )
        let demoID = CollectionID()
        let demo = try DemoSeed(
            version: 1,
            collections: [CollectionDraft(id: demoID, title: try EntityTitle("Demo"))],
            items: []
        )
        _ = try await backend.perform(.resetDemo(seed: demo), requestID: RequestID(), names: [:])
        _ = try await desk.resetDesk(through: backend, requestID: RequestID())
        let deskItem = try #require(await backend.item(TrustDeskFixture.item))
        #expect(deskItem.title.value == TrustDeskFixture.defaultDisplayName)
        #expect(deskItem.note.value == TrustDeskFixture.sealedNote)
        #expect(try secrets.read(account: TrustDeskFixture.identity.account) == nil)
        #expect(desk.passkeyReference() == nil)
        #expect(desk.liveGrant() == nil)
        #expect(try await backend.item(otherItem)?.title.value == "Kept")
        let demoCollection = try #require(await backend.collection(demoID))
        #expect(demoCollection.namespace == .demo)
        #expect(demoCollection.title.value == "Demo")
    }

    @Test func openingTwiceDoesNotStoreASecondSecret() async throws {
        let (desk, backend, secrets) = lab()
        _ = desk.confirmLocally()
        let first = try await desk.openSealedRecord(through: backend, requestID: RequestID())
        guard case .committed = first else {
            Issue.record("Expected a commit")
            return
        }
        let second = try await desk.openSealedRecord(through: backend, requestID: RequestID())
        guard case .alreadyOpen = second else {
            Issue.record("Expected the record to already be open")
            return
        }
        #expect(try secrets.read(account: TrustDeskFixture.identity.account) == TrustDeskFixture.secret)
    }

    @Test func authenticationBeforeRegistrationIsRefused() throws {
        let (desk, _, _) = lab()
        #expect(throws: TrustDeskError.passkeyNotRegistered) {
            try desk.authenticatePasskey()
        }
    }
}

@Suite struct KeychainSecretStoreTests {
    @Test func aScopedRecordDoesNotExposeAnotherService() throws {
        let account = "lab-041-a-\(UUID().uuidString)"
        let desk = KeychainSecretStore()
        let other = KeychainSecretStore(service: "lab.trust-desk.other")
        defer {
            try? desk.remove(account: account)
            try? other.remove(account: account)
        }
        do {
            try desk.write(TrustDeskFixture.secret, account: account)
            try other.write(Data("other-service".utf8), account: account)
            #expect(try desk.read(account: account) == TrustDeskFixture.secret)
            #expect(try other.read(account: account) == Data("other-service".utf8))
            try desk.remove(account: account)
            #expect(try desk.read(account: account) == nil)
            #expect(try other.read(account: account) == Data("other-service".utf8))
        } catch {
            // The unsandboxed test process has no keychain access group (-34018) and cannot
            // unlock the login keychain without UI (-25308). The sandboxed host test writes
            // the same store.
            guard case .secretStoreUnavailable(let reason) = error else {
                Issue.record("Unexpected keychain error: \(error)")
                return
            }
            #expect(reason == "OSStatus -34018" || reason == "OSStatus -25308")
        }
    }
}

@Suite struct InstalledAuthenticationProbeTests {
    @Test func aPromptlessLocalAuthenticationCheckDoesNotSucceed() async {
        let attempt = await DeviceOwnerAuthorizer().probeWithoutPrompt()
        #expect(attempt != .succeeded)
    }

    @Test func thePlatformPasskeyProviderIsTheInstalledSymbol() {
        #expect(PasskeyPlatformProbe.providerIsInThisSDK)
        #if !os(watchOS)
        #expect(PasskeyPlatformProbe.providerSymbol().contains("ASAuthorizationPlatformPublicKeyCredentialProvider"))
        #endif
    }
}
