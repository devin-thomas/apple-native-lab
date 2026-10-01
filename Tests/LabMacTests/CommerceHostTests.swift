import CommerceWithoutTricks
import Foundation
import LabDomain
import Testing
@testable import NativeLab

/// LAB-040 through the Mac host's library: verified purchases write app-UI receipts, unverified
/// transactions write nothing, and restore needs no Apple Account.
@MainActor
@Suite struct CommerceHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "CommerceHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func library() async throws -> LabLibrary {
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        return library
    }

    @Test func aVerifiedPurchaseWritesAnAppUIReceiptAndAnUnverifiedOneDoesNot() async throws {
        let library = try await library()
        let session = CommerceSession()
        #expect(CommerceWithoutTricks.createsRealCharge == false)
        session.purchaseScript = .verified
        session.selectedProductID = CommerceFixture.notebook.id
        let record = try #require(await session.purchase(in: library))
        #expect(record.receipt.admitted.adapter == .appUI)
        #expect(record.receipt.status == .committed)
        #expect(library.receipt(id: record.id) != nil)
        #expect(session.entitlement(for: CommerceFixture.notebook.id) != nil)

        session.purchaseScript = .unverified
        session.selectedProductID = CommerceFixture.compass.id
        let before = library.receipts.count
        #expect(await session.purchase(in: library) == nil)
        #expect(session.entitlement(for: CommerceFixture.compass.id) == nil)
        #expect(library.receipts.count == before)
        #expect(session.message?.contains("Unverified") == true)
    }

    @Test func restoreUsesLocalHistoryWithoutAnAccount() async throws {
        let library = try await library()
        let session = CommerceSession()
        session.purchaseScript = .verified
        _ = try #require(await session.purchase(in: library))
        let restored = try #require(await session.restore(in: library))
        #expect(restored.receipt.admitted.adapter == .appUI)
        #expect(session.message?.contains("No Apple Account") == true)
        #expect(session.entitlement(for: CommerceFixture.notebook.id)?.source == .restore)
    }
}
