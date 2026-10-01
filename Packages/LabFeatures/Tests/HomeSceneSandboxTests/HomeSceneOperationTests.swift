import Foundation
import LabDomain
import Testing
@testable import HomeSceneSandbox

struct ServiceBackend: HomeSceneBackend {
    let service: OperationService
    var actor = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    func item(_ id: ItemID) async throws(HomeSceneError) -> LabItem? {
        do { return try await service.findItem(id, as: actor) } catch {
            if case .notFound = error { return nil }
            throw .operation(error)
        }
    }

    func collection(_ id: CollectionID) async throws(HomeSceneError) -> LabCollection? {
        do { return try await service.findCollection(id, as: actor) } catch {
            if case .notFound = error { return nil }
            throw .operation(error)
        }
    }

    func perform(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(HomeSceneError) -> ActionReceipt {
        _ = names
        do {
            return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
        } catch {
            throw .operation(error)
        }
    }
}

struct CancelledBackend: HomeSceneBackend {
    func item(_ id: ItemID) async throws(HomeSceneError) -> LabItem? { nil }
    func collection(_ id: CollectionID) async throws(HomeSceneError) -> LabCollection? { nil }
    func perform(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(HomeSceneError) -> ActionReceipt {
        throw .cancelled
    }
}

private func lab(hallwayReachable: Bool = false) -> (HomeSceneSandbox, ServiceBackend, FictionalHomeSource) {
    let source = FictionalHomeSource(hallwayReachable: hallwayReachable)
    let sandbox = HomeSceneSandbox(source: source)
    let backend = ServiceBackend(service: OperationService(store: InMemoryOperationStore()))
    return (sandbox, backend, source)
}

@Suite struct HomeSceneOperationTests {
    @Test func fictionalHomeExcludesLocksDoorsAlarmsAndHeatingByDefault() async throws {
        let (sandbox, _, _) = lab()
        let home = try await sandbox.refreshHome()
        #expect(home.isSimulated)
        #expect(home.name == FictionalHome.homeName)
        #expect(home.lights.count == 2)
        #expect(home.excludedByDefault.map(\.kind) == [.lock, .door, .alarm, .heating])
        #expect(home.excludedByDefault.filter { !$0.isExcludedByDefault }.isEmpty)

        #expect(throws: HomeSceneError.sensitiveKindExcluded(.lock)) {
            try sandbox.select(LightChange(isOn: true), for: FictionalHome.frontLock)
        }
        #expect(throws: HomeSceneError.sensitiveKindExcluded(.door)) {
            try sandbox.select(LightChange(isOn: true), for: FictionalHome.patioDoor)
        }
        #expect(throws: HomeSceneError.sensitiveKindExcluded(.alarm)) {
            try sandbox.select(LightChange(isOn: true), for: FictionalHome.entryAlarm)
        }
        #expect(throws: HomeSceneError.sensitiveKindExcluded(.heating)) {
            try sandbox.select(LightChange(isOn: true), for: FictionalHome.hallThermostat)
        }

        try sandbox.select(LightChange(isOn: true, brightness: 70), for: FictionalHome.livingLamp)
        let proposal = try sandbox.preview()
        #expect(proposal.selected.count == 1)
        #expect(proposal.excluded.count == 4)
        #expect(proposal.excluded.map(\.accessory.kind) == [.lock, .door, .alarm, .heating])
        #expect(proposal.summary.contains("excluded by default"))
    }

    @Test func aDisconnectedLampDoesNotMarkTheWholeSceneSuccessful() async throws {
        let (sandbox, backend, _) = lab(hallwayReachable: false)
        _ = try await sandbox.refreshHome()
        try sandbox.select(LightChange(isOn: true, brightness: 90), for: FictionalHome.livingLamp)
        try sandbox.select(LightChange(isOn: false, brightness: 10), for: FictionalHome.hallwayLamp)
        let proposal = try sandbox.preview()
        #expect(proposal.selected.count == 2)

        let (report, receipt) = try await sandbox.commit(through: backend, requestID: RequestID())
        #expect(!report.sceneSucceeded)
        #expect(report.outcomes.count == 2)
        #expect(report.outcomes.contains { $0.didSucceed && $0.accessoryID == FictionalHome.livingLamp })
        #expect(report.outcomes.contains {
            if case .failed(let id, let detail) = $0 {
                return id == FictionalHome.hallwayLamp && detail.contains("disconnected")
            }
            return false
        })
        #expect(report.explanation.contains("did not succeed"))
        #expect(receipt.status == .committed)
        #expect(receipt.admitted.adapter == .appUI)
        let item = try #require(await backend.item(FictionalHome.item))
        #expect(item.note.value.contains("Scene did not succeed"))
        #expect(item.note.value.contains("disconnected"))
    }

    @Test func allReachableLightsCanSucceed() async throws {
        let (sandbox, backend, _) = lab(hallwayReachable: true)
        _ = try await sandbox.refreshHome()
        try sandbox.select(LightChange(isOn: true, brightness: 55), for: FictionalHome.livingLamp)
        try sandbox.select(LightChange(isOn: false), for: FictionalHome.hallwayLamp)
        let (report, receipt) = try await sandbox.commit(through: backend, requestID: RequestID())
        #expect(report.sceneSucceeded)
        #expect(report.outcomes.filter { !$0.didSucceed }.isEmpty)
        #expect(receipt.status == .committed)
        let home = try await sandbox.refreshHome()
        #expect(home.accessory(FictionalHome.livingLamp)?.isOn == true)
        #expect(home.accessory(FictionalHome.livingLamp)?.brightness == 55)
        #expect(home.accessory(FictionalHome.hallwayLamp)?.isOn == false)
    }

    @Test func revokedHomePermissionStopsLiveMode() async throws {
        let source = ScriptedPermissionSource(permissions: [.authorized, .denied], hallwayReachable: true)
        let sandbox = HomeSceneSandbox(source: source)
        let backend = ServiceBackend(service: OperationService(store: InMemoryOperationStore()))

        let granted = try await sandbox.requestLiveAccess()
        #expect(granted == .authorized)
        #expect(sandbox.route == .live)
        let live = try await sandbox.refreshHome()
        #expect(!live.isSimulated)

        source.revokeTo(.denied)
        await #expect(throws: HomeSceneError.permissionRevoked(.denied)) {
            try await sandbox.refreshHome()
        }
        #expect(sandbox.route == .simulated)

        try sandbox.select(LightChange(isOn: true), for: FictionalHome.livingLamp)
        // Commit after revoke while still thinking live would fail; route already simulated.
        let (report, _) = try await sandbox.commit(through: backend, requestID: RequestID())
        #expect(report.proposal.route == .simulated)
        #expect(report.sceneSucceeded)

        let denied = try await sandbox.requestLiveAccess()
        #expect(denied == .denied)
        #expect(sandbox.route == .simulated)
    }

    @Test func fictionalFallbackRecordsThroughOperationService() async throws {
        let (sandbox, backend, _) = lab()
        _ = try await sandbox.refreshHome()
        #expect(sandbox.route == .simulated)
        #expect(sandbox.platformGate.contains("fictional home") || sandbox.platformGate.contains("HomeKit"))
        try sandbox.select(LightChange(isOn: true), for: FictionalHome.livingLamp)
        let (report, receipt) = try await sandbox.commit(through: backend, requestID: RequestID())
        #expect(report.sceneSucceeded)
        #expect(receipt.admitted.adapter == .appUI)
        if case .createItem(let draft) = receipt.admitted.operation {
            #expect(draft.id == FictionalHome.item)
        } else {
            Issue.record("Expected createItem receipt")
        }
        await #expect(throws: HomeSceneError.emptySelection) {
            try await sandbox.commit(through: backend, requestID: RequestID())
        }
    }

    @Test func emptySelectionAndInvalidBrightnessAreRefused() async throws {
        let (sandbox, backend, _) = lab()
        _ = try await sandbox.refreshHome()
        await #expect(throws: HomeSceneError.emptySelection) {
            try await sandbox.commit(through: backend, requestID: RequestID())
        }
        #expect(throws: HomeSceneError.invalidInput("Brightness must be between 0 and 100.")) {
            try sandbox.select(LightChange(brightness: 140), for: FictionalHome.livingLamp)
        }
        #expect(try await backend.item(FictionalHome.item) == nil)
    }

    @Test func cancellationBeforeCommitChangesNothingInTheLab() async throws {
        let (sandbox, _, _) = lab()
        _ = try await sandbox.refreshHome()
        try sandbox.select(LightChange(isOn: true), for: FictionalHome.livingLamp)
        let cancelled = CancelledBackend()
        await #expect(throws: HomeSceneError.cancelled) {
            try await sandbox.commit(through: cancelled, requestID: RequestID())
        }
        let home = try await sandbox.refreshHome()
        #expect(home.accessory(FictionalHome.livingLamp)?.isOn == false)
    }

    @Test func resetDemoRestoresOnlyTheFixtureNote() async throws {
        let (sandbox, backend, _) = lab(hallwayReachable: true)
        _ = try await sandbox.refreshHome()
        try sandbox.select(LightChange(isOn: true), for: FictionalHome.livingLamp)
        _ = try await sandbox.commit(through: backend, requestID: RequestID())
        let before = try #require(await backend.item(FictionalHome.item))
        #expect(before.note.value.contains("Scene succeeded"))

        let receipt = try await sandbox.resetDemo(through: backend, requestID: RequestID())
        #expect(receipt?.status == .committed)
        let after = try #require(await backend.item(FictionalHome.item))
        #expect(after.note.value == FictionalHome.sealedNote)
        #expect(sandbox.route == .simulated)
        let home = try await sandbox.refreshHome()
        #expect(home.accessory(FictionalHome.livingLamp)?.isOn == false)
        #expect(home.accessory(FictionalHome.livingLamp)?.brightness == 40)
    }

    @Test func liveRouteIsUnavailableOnTheFictionalSource() async throws {
        await #expect(throws: HomeSceneError.liveUnavailable("Live HomeKit is not linked in this CoreLocal build. Use the fictional home.")) {
            try await FictionalHomeSource().homes(on: .live)
        }
    }
    @Test func duplicateCommitReplaysWithoutChangingTheSceneAgain() async throws {
        let (sandbox, backend, _) = lab()
        _ = try await sandbox.refreshHome()
        try sandbox.select(LightChange(isOn: true), for: FictionalHome.livingLamp)
        let request = RequestID()
        let first = try await sandbox.commit(through: backend, requestID: request)
        let second = try await sandbox.commit(through: backend, requestID: request)
        #expect(first.receipt.operationID == second.receipt.operationID)
        #expect(first.report == second.report)
        let item = try #require(await backend.item(FictionalHome.item))
        #expect(item.note.value.contains("Scene succeeded"))
    }

    @Test func incompleteOutcomeSetCannotSucceed() async throws {
        let (sandbox, _, _) = lab(hallwayReachable: true)
        _ = try await sandbox.refreshHome()
        try sandbox.select(LightChange(isOn: true), for: FictionalHome.livingLamp)
        try sandbox.select(LightChange(isOn: false), for: FictionalHome.hallwayLamp)
        let report = SceneCommitReport(proposal: try sandbox.preview(), outcomes: [.succeeded(FictionalHome.livingLamp, "Changed")])
        #expect(!report.sceneSucceeded)
    }

    @Test func fictionalAccessRequestKeepsFallbackUsable() async throws {
        let (sandbox, _, _) = lab()
        #expect(try await sandbox.requestLiveAccess() == .denied)
        #expect(sandbox.route == .simulated)
        #expect(try await sandbox.refreshHome().isSimulated)
    }

    @Test func deniedCommitCannotChangeLampState() async throws {
        let (sandbox, backend, _) = lab()
        var denied = backend
        denied.actor = ActorScope(adapter: .modelTool, grants: Set(Permission.allCases))
        _ = try await sandbox.refreshHome()
        try sandbox.select(LightChange(isOn: true), for: FictionalHome.livingLamp)
        do {
            _ = try await sandbox.commit(through: denied, requestID: RequestID())
            Issue.record("Model tool committed")
        } catch {
            guard case .operation(.unauthorized) = error else {
                Issue.record("Expected unauthorized, got \(error)")
                return
            }
        }
        #expect(try await sandbox.refreshHome().accessory(FictionalHome.livingLamp)?.isOn == false)
        #expect(try await backend.item(FictionalHome.item) == nil)
    }

    @Test func changedHomeRequiresAnotherPreview() async throws {
        let (sandbox, backend, source) = lab()
        let home = try await sandbox.refreshHome()
        try sandbox.select(LightChange(isOn: true), for: FictionalHome.livingLamp)
        _ = try await source.apply(LightChange(brightness: 15), to: home.accessory(FictionalHome.livingLamp)!, in: home, previewOnly: false)
        await #expect(throws: HomeSceneError.invalidInput("The home changed after preview. Refresh and review the changes again.")) {
            try await sandbox.commit(through: backend, requestID: RequestID())
        }
        #expect(try await backend.item(FictionalHome.item) == nil)
    }

    @Test func duplicateCommitIsAuthorizedAgain() async throws {
        let (sandbox, backend, _) = lab()
        _ = try await sandbox.refreshHome()
        try sandbox.select(LightChange(isOn: true), for: FictionalHome.livingLamp)
        let request = RequestID()
        _ = try await sandbox.commit(through: backend, requestID: request)
        var denied = backend
        denied.actor = ActorScope(adapter: .modelTool, grants: Set(Permission.allCases))
        do {
            _ = try await sandbox.commit(through: denied, requestID: request)
            Issue.record("Model tool replayed a commit")
        } catch {
            guard case .operation(.unauthorized) = error else {
                Issue.record("Expected unauthorized, got \(error)")
                return
            }
        }
    }

    @Test func duplicateRequestCannotCommitDifferentSelection() async throws {
        let (sandbox, backend, _) = lab()
        _ = try await sandbox.refreshHome()
        try sandbox.select(LightChange(isOn: true), for: FictionalHome.livingLamp)
        let request = RequestID()
        _ = try await sandbox.commit(through: backend, requestID: request)
        try sandbox.select(LightChange(isOn: false), for: FictionalHome.livingLamp)
        await #expect(throws: HomeSceneError.operation(.requestIDReused(request))) {
            try await sandbox.commit(through: backend, requestID: request)
        }
        #expect(try await sandbox.refreshHome().accessory(FictionalHome.livingLamp)?.isOn == true)
    }

}
