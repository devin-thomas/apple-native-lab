import Foundation
import LabDomain
import RespectfulAttention
import Testing
@testable import NativeLab

/// LAB-043 in the sandboxed Mac host: scheduling and cancelling go through `LabLibrary` and leave
/// receipts in the same list the page and the intents share. CoreLocal never prompts and never
/// writes system alerts; the agenda is the fallback.
@MainActor
@Suite struct RespectfulAttentionHostTests {
    let folder: URL
    let defaults: UserDefaults

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "RespectfulAttentionHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defaults = try #require(UserDefaults(suiteName: "RespectfulAttentionHostTests-\(UUID().uuidString)"))
    }

    private func started() async throws -> (LabLibrary, AttentionModel) {
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let model = AttentionModel(system: UnavailableAttentionSystem(), defaults: defaults)
        model.connect(library)
        await model.refresh()
        try #require(model.phase == .ready)
        return (library, model)
    }

    @Test func thePageAndTheIntentScheduleOneAlertWithReceiptsInOneList() async throws {
        let (library, model) = try await started()
        #expect(model.gate.permission == .unavailable || model.gate.permission == .notDetermined)
        #expect(model.stored.isEmpty)

        await model.schedule(RespectfulAttention.offers[0])
        #expect(model.stored.map(\.id) == [RespectfulAttention.offers[0].id])
        #expect(model.lastMessage?.contains("Review the sample notebook") == true)

        let link = RespectfulAttentionLink(backend: LibraryAttentionBackend(library: library))
        let intent = ScheduleLabAlertIntent(choice: .alarm)
        let message = try await intent.run(with: link) { _ in }
        #expect(message.contains("Stand and stretch"))
        await model.refresh()
        #expect(Set(model.stored.map(\.channel)) == [.reminder, .alarm])

        let listed = library.receipts.prefix(2).map(\.receipt.admitted.adapter)
        #expect(listed == [.appIntent, .appUI])
    }

    @Test func cancelRemovesOnlyLabAlertsAndADeniedGateDoesNotPrompt() async throws {
        let (library, model) = try await started()
        await model.schedule(RespectfulAttention.offers[0])
        await model.schedule(RespectfulAttention.offers[2])
        #expect(model.stored.count == 2)

        // A sticky denial never prompts again.
        let data = try JSONEncoder().encode(PromptGate(permission: .denied, prompts: 1))
        defaults.set(data, forKey: "RespectfulAttention.promptGate")
        let again = AttentionModel(system: PromptingSystem(), defaults: defaults)
        #expect(again.gate.mayPrompt == false)
        await again.allowSystemAlerts()
        #expect(again.gate.permission == .denied)
        #expect(again.gate.prompts == 1)

        let cancel = CancelLabAlertsIntent()
        let message = try await cancel.run(with: RespectfulAttentionLink(backend: LibraryAttentionBackend(library: library))) { operation, _ in
            AttentionConfirmation(confirmed: operation)
        }
        #expect(message.contains("Cancelled"))
        await model.refresh()
        #expect(model.stored.isEmpty)
    }

    @Test func theAgendaIsASidebarDestinationWithCommand9() {
        #expect(SidebarDestination(storageKey: SidebarDestination.respectfulAttention.storageKey) == .respectfulAttention)
        #expect(SidebarDestination.respectfulAttention.title == "Respectful Attention")
    }
}

/// Counts permission requests. CoreLocal's live system never reaches this; the host test uses it
/// only to prove a denied gate does not call it.
private struct PromptingSystem: SystemAttentionClient {
    func permission() async -> SystemPermission { .denied }
    func requestPermission() async -> SystemPermission { .authorized }
    func schedule(_ offer: AttentionOffer) async {}
    func cancel(labIDs: [AttentionID]) async {}
}
