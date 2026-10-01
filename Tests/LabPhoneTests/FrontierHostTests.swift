import CommercialFrontier
import Foundation
import LabDomain
import Testing
@testable import NativeLab

/// Hosted fixture replay through the real library and operation service; no system surfaces.
@MainActor @Suite struct FrontierHostTests {
    @Test func lifecycleReceiptsAndEscapePersistWithoutTouchingImports() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "FrontierHostTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = LabLibrary(locateStore: { folder.appending(path: LabStoreLocation.fileName) })
        await library.start()
        try #require(library.phase == .ready)
        let backend = LibraryFrontierBackend(library: library)
        let other = CollectionID()
        _ = try await backend.perform(.createCollection(draft: CollectionDraft(id: other, title: EntityTitle("Original imported collection"))), requestID: RequestID())
        let session = FrontierSession()
        await session.perform(.join, capability: .pushToTalk, library: library)
        await session.perform(.connect, capability: .carPlay, library: library)
        await session.perform(.authorizeSelf, capability: .screenTime, library: library)
        await session.perform(.restrictSample, capability: .screenTime, library: library)
        #expect(session.snapshots[.screenTime]?.restricted == true)
        await session.perform(.revoke, capability: .screenTime, library: library)
        #expect(session.snapshots[.screenTime] == FrontierSnapshot())
        await session.perform(.reset, capability: .pushToTalk, library: library)
        #expect(session.snapshots[.pushToTalk] == FrontierSnapshot())
        #expect(session.snapshots[.carPlay]?.active == true)
        let reopened = FrontierSession()
        await reopened.refresh(library: library)
        #expect(reopened.snapshots == session.snapshots)
        #expect(try await backend.collection(other)?.title.value == "Original imported collection")
        let receipt = try #require(library.receipts.first)
        #expect(receipt.receipt.admitted.adapter == .appUI)
        #expect(receipt.receipt.status == .committed)
        #expect(session.message?.contains("Receipt:") == true)
    }
}
