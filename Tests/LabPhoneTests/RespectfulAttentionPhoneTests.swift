import Foundation
import LabDomain
import RespectfulAttention
import Testing
@testable import NativeLab

/// CoreLocal fallback inside the iPhone simulator host. No live system alert adapter is used.
@MainActor
@Suite struct RespectfulAttentionPhoneTests {
    @Test func aFreshAgendaSchedulesAndCancelsWithoutSystemPermission() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "RespectfulAttentionPhoneTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let defaults = try #require(UserDefaults(suiteName: "RespectfulAttentionPhoneTests-\(UUID().uuidString)"))
        let model = AttentionModel(system: UnavailableAttentionSystem(), defaults: defaults)
        model.connect(library)
        await model.refresh()
        #expect(model.stored.isEmpty)
        #expect(model.gate.permission == .unavailable)
        #expect(!model.gate.mayPrompt)
        for offer in model.offers { await model.schedule(offer) }
        #expect(model.stored.count == 3)
        #expect(library.receipts.prefix(3).allSatisfy { $0.receipt.admitted.adapter == .appUI })
        #expect(model.alarmState(for: model.offers[2], systemScheduled: false) == .unavailable)
        await model.cancelAll()
        #expect(model.stored.isEmpty)
        #expect(library.receipts.first?.receipt.removed.count == 3)
    }
}
