import Foundation
import LabDomain
import Testing
import TrustDesk
@testable import NativeLab

/// LAB-041 through the Mac host's library: the sealed-record open is an app-UI receipt, a
/// biometric failure leaves the store empty of the desk item, and a passkey assertion does not
/// grant the open.
@MainActor
@Suite struct TrustDeskHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "TrustDeskHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func library() async throws -> LabLibrary {
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        return library
    }

    @Test func aFailedBiometricThenLocalConfirmationOpensThroughTheAppUI() async throws {
        let library = try await library()
        let secrets = MemorySecretStore()
        let session = TrustDeskSession(
            secrets: secrets,
            authorizer: ScriptedLocalAuthorizer(results: [.biometricFailed])
        )
        let before = session.identity.id
        await session.authorizeWithDevice()
        #expect(session.liveGrant == nil)
        #expect(session.message?.contains("Nothing was changed") == true)
        session.confirmLocally()
        let record = try #require(await session.openSealedRecord(in: library))
        #expect(record.receipt.admitted.adapter == .appUI)
        #expect(record.receipt.status == .committed)
        #expect(library.receipt(id: record.id) != nil)
        let renamed = try #require(await session.rename(to: "North fixture", in: library))
        #expect(session.identity.id == before)
        #expect(renamed.receipt.status == .committed)
        #expect(try secrets.read(account: before.account) == TrustDeskFixture.secret)
        session.registerPasskey()
        session.authenticatePasskey()
        #expect(session.assertionSummary?.contains("Passkey protocol simulation") == true)
        let withoutGrant = TrustDeskSession(secrets: MemorySecretStore(), authorizer: ScriptedLocalAuthorizer(results: []))
        withoutGrant.registerPasskey()
        withoutGrant.authenticatePasskey()
        #expect(await withoutGrant.openSealedRecord(in: library) == nil)
        #expect(withoutGrant.message?.contains("local authorization") == true)
    }

    @Test func aSandboxedKeychainRecordStaysInItsService() async throws {
        let account = "lab-041-a-\(UUID().uuidString)"
        let desk = KeychainSecretStore()
        let other = KeychainSecretStore(service: "lab.trust-desk.other")
        defer {
            try? desk.remove(account: account)
            try? other.remove(account: account)
        }
        try desk.write(TrustDeskFixture.secret, account: account)
        try other.write(Data("other-service".utf8), account: account)
        #expect(try desk.read(account: account) == TrustDeskFixture.secret)
        #expect(try other.read(account: account) == Data("other-service".utf8))
        try desk.remove(account: account)
        #expect(try desk.read(account: account) == nil)
        #expect(try other.read(account: account) == Data("other-service".utf8))
    }
}
