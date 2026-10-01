import Foundation
import LabDomain
import RespectfulAttention
import Testing

@Suite struct RespectfulAttentionTests {
    @Test func aDeniedGateDoesNotPromptAgain() async {
        let client = PromptCounter(permission: .denied)
        let gate = PromptGate(permission: .denied)
        let again = await gate.resolving { await client.request() }
        #expect(again == gate)
        #expect(await client.calls == 0)

        let asked = PromptGate(permission: .notDetermined)
        let once = await asked.resolving { await client.answer(.denied) }
        #expect(once.permission == .denied)
        #expect(once.prompts == 1)
        _ = await once.resolving { await client.answer(.authorized) }
        #expect(await client.calls == 1)
    }

    @Test func aDismissedPromptIsNotRepeated() async {
        let client = PromptCounter(permission: .notDetermined)
        let gate = PromptGate(permission: .notDetermined)
        let once = await gate.resolving { await client.request() }
        #expect(once.mayPrompt == false)
        #expect(once.prompts == 1)
        _ = await once.resolving { await client.request() }
        #expect(await client.calls == 1)
    }

    @Test func cancelKeepsAlertsTheLabDoesNotOwn() {
        let lab = LabAlertIdentity.notificationID(RespectfulAttention.offers[0].id)
        let foreign = "com.example.other.meeting"
        let clock = "clock-alarm-7"
        let selection = CancelLabAlerts.selection(from: [lab, foreign, clock, lab])
        #expect(selection.remove == [lab, lab])
        #expect(selection.keep == [foreign, clock])
    }

    @Test func aFocusScopeShowsOnlyItsLabAlerts() throws {
        let scope = RespectfulAttention.sampleFocus
        let extraID = AttentionID(rawValue: UUID(uuidString: "04300000-0000-4000-8000-000000000099")!)
        let extra = LabAttention(
            id: extraID, channel: .reminder,
            reason: try AttentionReason("Outside the sample"),
            moment: try CivilMoment(year: 2026, month: 10, day: 1, hour: 11, minute: 0, timeZoneIdentifier: "America/Chicago")
        )
        let stored = try RespectfulAttention.offers.map { offer in
            let draft = try offer.draft(consent: .explicit)
            return LabAttention(id: draft.id, channel: draft.channel, reason: draft.reason, moment: draft.moment)
        } + [extra]
        let visible = scope.visible(stored).map(\.id)
        #expect(visible == RespectfulAttention.offers.map(\.id))
        #expect(!visible.contains(extraID))
        let foreign = "com.example.other.meeting"
        #expect(scope.allowsNotification(LabAlertIdentity.notificationID(RespectfulAttention.offers[0].id)))
        #expect(!scope.allowsNotification(foreign))
        let described = LabFocusFilterIntent.notificationPredicate(
            includedIdentifiers: [LabAlertIdentity.notificationID(RespectfulAttention.offers[2].id), foreign]
        ).predicateFormat
        #expect(described.contains(LabAlertIdentity.notificationID(RespectfulAttention.offers[2].id)))
        #expect(!described.contains(foreign))
    }

    @Test func theAgendaShowsTimersWithoutPermission() throws {
        let now = try CivilMoment(year: 2026, month: 10, day: 1, hour: 8, minute: 0, timeZoneIdentifier: "America/Chicago")
            .instant(deviceZone: .current)
        let rows = try RespectfulAttention.offers.map { offer in
            let draft = try offer.draft(consent: .explicit)
            return LabAttention(id: draft.id, channel: draft.channel, reason: draft.reason, moment: draft.moment)
        }
        let timers = LabAgenda.timers(rows, scope: nil, at: now, deviceZone: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(timers.count == 3)
        #expect(timers.allSatisfy { $0.when.contains("America/Chicago") })
        #expect(timers.allSatisfy { $0.why.isEmpty == false })
        #expect(timers.first { $0.channel == .alarm }?.remainingSeconds == 7 * 60 * 60 + 30 * 60)
        let filtered = LabAgenda.timers(rows, scope: FocusScope(name: "Lab Sample", included: [rows[2].id]), at: now, deviceZone: .current)
        #expect(filtered.map(\.channel) == [.alarm])
    }

    @Test func anUnavailableAlarmStaysInTheAgendaAndDoesNotLookScheduled() {
        #expect(AlarmRouting.state(channel: .alarm, routeAvailable: false, permission: .unavailable, systemScheduled: false) == .unavailable)
        #expect(AlarmRouting.state(channel: .alarm, routeAvailable: true, permission: .denied, systemScheduled: false) == .denied)
        #expect(AlarmRouting.state(channel: .reminder, routeAvailable: true, permission: .authorized, systemScheduled: true) == .notAnAlarm)
        #expect(AlarmRouting.state(channel: .alarm, routeAvailable: true, permission: .authorized, systemScheduled: true) == .scheduled)
    }

    @Test func previewsDoNotRequireAStoreAndWithheldConsentSchedulesNothing() async throws {
        let previews = RespectfulAttention.offers.map { $0.preview(deviceZone: TimeZone(identifier: "Europe/Paris")!) }
        #expect(previews.map(\.why) == ["Review the sample notebook", "Show only the lab agenda", "Stand and stretch"])
        let backend = MemoryBackend()
        let actions = AttentionActions(backend: backend, entryPoint: .appUI)
        await #expect(throws: AttentionError.invalid(.consentRequired)) {
            try await actions.schedule(RespectfulAttention.offers[0], consent: .withheld)
        }
        #expect(await backend.stored.isEmpty)
    }

    @Test func schedulingAndCancellingShareTheReceiptPath() async throws {
        let backend = MemoryBackend()
        let actions = AttentionActions(backend: backend, entryPoint: .appUI)
        let scheduled = try await actions.schedule(RespectfulAttention.offers[0], consent: .explicit)
        #expect(scheduled.receipt.status == .committed)
        let cancelled = try await actions.cancelAll()
        #expect(cancelled.receipt.removed.count == 1)
        #expect(try await actions.attentions().isEmpty)
    }

    @Test func theScheduleIntentNeedsExplicitConsentAndCancelNeedsConfirmation() async throws {
        let backend = MemoryBackend()
        let link = RespectfulAttentionLink(backend: backend)
        let scheduled = try await ScheduleLabAlertIntent(choice: .focusFilter).run(with: link) { _ in }
        #expect(scheduled.contains("Show only the lab agenda"))
        #expect(await backend.stored.map(\.channel) == [.focusFilter])

        await #expect(throws: CancellationError.self) {
            try await CancelLabAlertsIntent().run(with: link) { _, _ in
                throw CancellationError()
            }
        }
        #expect(await backend.stored.count == 1)

        let cancelled = try await CancelLabAlertsIntent().run(with: link) { operation, _ in
            AttentionConfirmation(confirmed: operation)
        }
        #expect(cancelled.contains("Cancelled"))
        #expect(await backend.stored.isEmpty)
    }

    @Test func aCancelledScheduleCommitsNothing() async {
        let backend = CancellingBackend()
        let actions = AttentionActions(backend: backend, entryPoint: .appUI)
        let task = Task {
            try await actions.schedule(RespectfulAttention.offers[2], consent: .explicit)
        }
        task.cancel()
        await #expect(throws: AttentionError.cancelled) { try await task.value }
        #expect(await backend.commits == 0)
    }

    @Test func theUnavailableBackendRefuses() async {
        let actions = RespectfulAttentionLink.unavailable.actions(.appIntent)
        await #expect(throws: AttentionError.self) {
            try await actions.schedule(RespectfulAttention.offers[0], consent: .explicit)
        }
    }

    @Test func aRecordingSystemDropsOnlyLabAlarms() async {
        let lab = RespectfulAttention.offers[2].id
        let other = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let system = RecordingAttentionSystem(
            notifications: [LabAlertIdentity.notificationID(lab), "com.example.other.meeting"],
            alarms: [lab.rawValue, other]
        )
        await system.cancel(labIDs: [lab])
        #expect(await system.notifications == ["com.example.other.meeting"])
        #expect(await system.alarms == [other])
        #expect(await system.permissionRequests == 0)
    }
}

private actor PromptCounter {
    private(set) var calls = 0
    private let permission: SystemPermission

    init(permission: SystemPermission) { self.permission = permission }

    func request() -> SystemPermission {
        calls += 1
        return permission
    }

    func answer(_ permission: SystemPermission) -> SystemPermission {
        calls += 1
        return permission
    }
}

private actor RecordingAttentionSystem {
    var notifications: [String]
    var alarms: Set<UUID>
    private(set) var permissionRequests = 0

    init(notifications: [String], alarms: Set<UUID>) {
        self.notifications = notifications
        self.alarms = alarms
    }

    func cancel(labIDs: [AttentionID]) {
        let notes = Set(labIDs.map(LabAlertIdentity.notificationID))
        let ids = Set(labIDs.map(\.rawValue))
        notifications.removeAll { notes.contains($0) }
        alarms.subtract(ids)
    }
}

/// Blocks in `attentions` until the task is cancelled, then refuses. A schedule cannot commit.
private actor CancellingBackend: AttentionBackend {
    private(set) var commits = 0

    func attentions(via entryPoint: AttentionEntryPoint) async throws(AttentionError) -> [LabAttention] {
        while !Task.isCancelled { await Task.yield() }
        throw .cancelled
    }

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        via entryPoint: AttentionEntryPoint,
        confirmation: AttentionConfirmation?
    ) async throws(AttentionError) -> ActionReceipt {
        commits += 1
        throw .cancelled
    }
}

/// An in-memory operation service behind the attention backend, so the feature tests take the
/// same receipt path as the app.
private actor MemoryBackend: AttentionBackend {
    let service: OperationService
    init() { service = OperationService(store: InMemoryOperationStore()) }

    var stored: [LabAttention] {
        get async {
            let reader = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
            return (try? await service.findAttentions(as: reader)) ?? []
        }
    }

    func attentions(via entryPoint: AttentionEntryPoint) async throws(AttentionError) -> [LabAttention] {
        do { return try await service.findAttentions(as: ActorScope(adapter: entryPoint.adapter, grants: Set(Permission.allCases))) }
        catch { throw .refused(error) }
    }

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        via entryPoint: AttentionEntryPoint,
        confirmation: AttentionConfirmation?
    ) async throws(AttentionError) -> ActionReceipt {
        _ = confirmation
        do {
            return try await service.perform(OperationRequest(
                id: requestID, operation: operation,
                actor: ActorScope(adapter: entryPoint.adapter, grants: Set(Permission.allCases))
            ))
        } catch {
            throw .refused(error)
        }
    }
}
