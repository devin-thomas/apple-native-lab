import Foundation
import LabDomain
import LabStore
import LabStaging
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

    @Test func aCleanReplayKeepsForeignSchedulesAndUserCollections() async throws {
        let (library, _) = try await started()
        let collection = CollectionID()
        _ = try await library.submit(
            .createCollection(draft: CollectionDraft(id: collection, title: EntityTitle("Imported sample notes"))),
            requestID: RequestID(), authority: .userAction, names: [:]
        )
        let ledger = GrantLedger()
        let service = OperationService(
            store: try await SQLiteOperationStore(url: folder.appending(path: LabStoreLocation.fileName)),
            policy: GrantAuthorizationPolicy(ledger: ledger)
        )
        let inbox = InMemoryStagingInbox()
        let staged = await inbox.stage(try StagingRecord.text(utf8: Array("Sample notebook\nOriginal qualification note.".utf8)))
        try ledger.issue(to: .shareExtension, for: [.createItem], on: ImportAdopter.grantTarget(into: collection))
        let imported = try await ImportAdopter(service: service, inbox: inbox, ledger: ledger).adopt(staged.id, into: collection)
        guard case .createItem(let draft) = imported.receipt.admitted.operation else {
            Issue.record("expected one imported sample item")
            return
        }
        let reader = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
        let beforeCollection = try await service.findCollection(collection, as: reader)
        let beforeImport = try await service.findItem(draft.id, as: reader)
        defaults.removeObject(forKey: "RespectfulAttention.promptGate")
        let system = QualificationAttentionSystem(permission: .authorized)
        let model = AttentionModel(system: system, defaults: defaults, deviceZone: { TimeZone(identifier: "Asia/Tokyo")! })
        model.connect(library)
        await model.refresh()
        #expect(model.stored.isEmpty)
        #expect(await system.requests == 0)
        let before = library.receipts.count
        for offer in model.offers {
            #expect(model.preview(offer).when.contains("America/Chicago"))
        }
        #expect(library.receipts.count == before)
        await model.allowSystemAlerts()
        for offer in model.offers { await model.schedule(offer) }
        #expect(model.stored.count == 3)
        #expect(await system.scheduled.count == 2)
        #expect(await system.requests == 1)
        let now = try CivilMoment(year: 2026, month: 10, day: 1, hour: 8, minute: 0, timeZoneIdentifier: "America/Chicago")
        let timers = LabAgenda.timers(model.stored, scope: nil, at: now.instant(deviceZone: .current), deviceZone: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(timers.first { $0.channel == .alarm }?.remainingSeconds == 27000)
        await model.cancelAll()
        #expect(model.stored.isEmpty)
        #expect(await system.scheduled.isEmpty)
        #expect(await system.cancelled == Set(model.offers.map(\.id)))
        #expect(system.foreignSchedules == ["other.reminder", "clock.alarm"])
        #expect(try await service.findCollection(collection, as: reader) == beforeCollection)
        await model.schedule(model.offers[0])
        _ = try #require(await library.resetDemo())
        await model.refresh()
        #expect(model.stored.isEmpty)
        #expect(try await service.findCollection(collection, as: reader) == beforeCollection)
        #expect(try await service.findItem(draft.id, as: reader) == beforeImport)
        // Reset clears domain rows; it does not call this injected system adapter.
        #expect(await system.scheduled.count == 1)
    }

    @Test func aDenialSurvivesModelRecreationAndNeverCallsTheSystemAgain() async throws {
        let (library, _) = try await started()
        defaults.removeObject(forKey: "RespectfulAttention.promptGate")
        let system = QualificationAttentionSystem(permission: .notDetermined)
        let model = AttentionModel(system: system, defaults: defaults)
        model.connect(library)
        await model.refresh()
        await model.allowSystemAlerts()
        await model.allowSystemAlerts()
        #expect(await system.requests == 1)
        #expect(model.gate.permission == .denied)
        let reopened = AttentionModel(system: system, defaults: defaults)
        reopened.connect(library)
        await reopened.refresh()
        await reopened.allowSystemAlerts()
        await reopened.schedule(reopened.offers[2])
        #expect(await system.requests == 1)
        #expect(await system.scheduled.isEmpty)
        #expect(reopened.stored.count == 1)
        #expect(reopened.permissionNote.contains("will not ask again"))
    }

    @Test func theAgendaIsASidebarDestinationWithOptionCommand6() {
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

/// Fixture adapter only: no AlarmKit, notification center, Clock, or system permission prompt.
private actor QualificationAttentionSystem: SystemAttentionClient {
    var state: SystemPermission
    private(set) var requests = 0
    private(set) var scheduled: Set<AttentionID> = []
    private(set) var cancelled: Set<AttentionID> = []
    let foreignSchedules = ["other.reminder", "clock.alarm"]

    init(permission: SystemPermission) { state = permission }
    func permission() -> SystemPermission { state }
    func requestPermission() -> SystemPermission {
        requests += 1
        if state == .notDetermined { state = .denied }
        return state
    }
    func schedule(_ offer: AttentionOffer) { scheduled.insert(offer.id) }
    func cancel(labIDs: [AttentionID]) {
        cancelled.formUnion(labIDs)
        scheduled.subtract(labIDs)
    }
}
