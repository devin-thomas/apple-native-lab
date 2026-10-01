import Foundation
import LabDomain
import Testing
import WalletMoment
@testable import NativeLab

/// The fixture flow through the sandboxed host and an isolated SQLite store.
@MainActor
@Suite struct WalletMomentHostTests {
    @Test func saveUpdateAndResetKeepReceiptsAndAvoidDuplicateCards() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "WalletMomentTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        let session = WalletMomentSession()
        await session.requestSignedPass()
        #expect(session.signingMessage == WalletMomentError.signingUnavailable.userMessage)
        let saved = try #require(await session.saveEventCard(in: library))
        #expect(saved.receipt.conflict == nil)
        let id = try #require(session.savedItemID)
        let count = library.receipts.count
        _ = await session.saveEventCard(in: library)
        #expect(library.receipts.count == count)
        #expect(session.savedItemID == id)
        let updated = try #require(await session.applySeatUpdate(in: library))
        #expect(updated.receipt.conflict == nil)
        #expect(session.savedDefinition?.seat == "GA-17")
        await session.resetEventCard(in: library)
        #expect(session.savedItemID == nil)
        #expect(session.lastReceipt?.receipt.conflict == nil)
        #expect(session.lastReceipt?.receipt.admitted.adapter == .appUI)
        _ = await session.saveEventCard(in: library)
        #expect(session.savedItemID != id)
        #expect(session.savedItemID != nil)
    }
}
