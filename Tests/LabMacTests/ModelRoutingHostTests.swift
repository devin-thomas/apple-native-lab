import Foundation
import LabDomain
import ModelRouting
import Testing
@testable import NativeLab

/// The fixture workflow in the real Mac host, using a fresh SQLite store.
@MainActor
@Suite struct ModelRoutingHostTests {
    @Test func localFallbackNeedsReviewBeforeSavingAndResetKeepsTheStore() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "RoutingHost-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        let session = ModelRoutingSession()
        await session.start(with: library)
        #expect(session.policy == .localOnly)
        #expect(session.observation?.pcc.entitlement.state == .closed)
        #expect(session.prompt.contains("tracing vellum"))
        let initial = library.receipts.count
        await session.attemptCloud()
        #expect(session.usage.last?.outcome == .cloudRefused)
        await session.runLocal()
        #expect(session.localSummary != nil)
        #expect(library.receipts.count == initial)
        await session.prepareAnnotation()
        #expect(session.pendingAnnotation?.isReady == true)
        #expect(session.annotationTarget == "Tracing vellum")
        #expect(library.receipts.count == initial)
        await session.approveAnnotation()
        let saved = try #require(session.lastStoreReceipt)
        #expect(saved.receipt.conflict == nil)
        #expect(saved.receipt.admitted.adapter == .appUI)
        #expect(library.receipts.count == initial + 1)
        await session.approveAnnotation()
        #expect(library.receipts.count == initial + 1)
        session.manualAnswer = "An original manual answer."
        await session.runManual()
        #expect(session.usage.last?.outcome == .completedManual)
        await session.setPolicy(.cloudAllowed)
        await session.resetDemo()
        #expect(session.policy == .localOnly)
        #expect(session.usage.isEmpty)
        #expect(library.receipts.count == initial + 1)
    }
}
