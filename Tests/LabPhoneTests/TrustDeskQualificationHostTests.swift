import Foundation
import LabDomain
import Testing
import TrustDesk
@testable import NativeLab

/// Clean hosted replay: real library and scoped Keychain, scripted authorization and passkeys.
@MainActor
@Suite struct TrustDeskQualificationHostTests {
    @Test func theFixtureReplayKeepsOtherUserData() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TrustDeskQualification-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = LabLibrary(locateStore: { folder.appending(path: LabStoreLocation.fileName) })
        await library.start()
        try #require(library.phase == .ready)
        let secrets = KeychainSecretStore(service: "lab.trust-desk.qualification.\(UUID())")
        defer { try? secrets.remove(account: TrustDeskFixture.identity.account) }
        let session = TrustDeskSession(secrets: secrets, authorizer: ScriptedLocalAuthorizer(results: [.biometricFailed, .cancelled]))
        let backend = LibraryTrustDeskBackend(library: library)
        let collection = CollectionID()
        let item = ItemID()
        _ = try await backend.perform(.createCollection(draft: CollectionDraft(id: collection, title: EntityTitle("Qualification imports"))), requestID: RequestID(), names: [:])
        _ = try await backend.perform(.createItem(draft: ItemDraft(id: item, in: collection, title: EntityTitle("Original imported fixture"))), requestID: RequestID(), names: [:])
        await session.authorizeWithDevice()
        #expect(session.liveGrant == nil)
        session.confirmLocally()
        let opened = try #require(await session.openSealedRecord(in: library))
        #expect(opened.receipt.admitted.adapter == .appUI)
        session.registerPasskey()
        let reference = try #require(session.passkeyReference)
        _ = try #require(await session.rename(to: "Qualification renamed", in: library))
        session.authenticatePasskey()
        #expect(session.passkeyReference?.account == reference.account)
        #expect(session.identity.id == TrustDeskFixture.identity)
        #expect(session.assertionSummary?.contains("Passkey protocol simulation") == true)
        await session.authorizeWithDevice()
        #expect(try secrets.read(account: session.identity.id.account) == TrustDeskFixture.secret)
        _ = await session.reset(in: library)
        #expect(session.liveGrant == nil)
        #expect(session.passkeyReference == nil)
        #expect(try secrets.read(account: session.identity.id.account) == nil)
        #expect(try await backend.item(item)?.title.value == "Original imported fixture")
        #expect(try await backend.item(TrustDeskFixture.item)?.note.value == TrustDeskFixture.sealedNote)
    }
}
