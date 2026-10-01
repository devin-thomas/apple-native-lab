import Foundation
import LabDomain
import LabSupport
import Testing
@testable import TabletopReality

/// The tabletop's requests end in the one operation service: authorized, recorded with receipts,
/// conflict-checked against the snapshot they were planned from, and cancellable between commits.
@Suite struct TabletopOperationTests {
    let kit = try! TabletopKit.bundled()
    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    struct Lab {
        let ledger = GrantLedger()
        let service: OperationService

        init() {
            service = OperationService(store: InMemoryOperationStore(), policy: GrantAuthorizationPolicy(ledger: ledger))
        }

        /// Commits as the app UI, issuing a grant for exactly this operation when it needs one,
        /// the way the host does after a person presses a control.
        func commit(_ operation: DomainOperation) async throws(TabletopError) -> ActionReceipt {
            var grant: GrantID?
            if operation.kind.isDestructive { grant = try? ledger.issue(for: operation, to: .appUI, lifetime: .seconds(30)).id }
            defer { if let grant { ledger.revoke(grant) } }
            do {
                return try await service.perform(OperationRequest(id: RequestID(), operation: operation, actor: appUI))
            } catch {
                throw .refused(error)
            }
        }

        func anchors() async throws -> [LabAnchor] { try await service.findAnchors(as: appUI) }
    }

    @Test func settingOutTheStarterSceneCommitsOneReceiptPerObject() async throws {
        let lab = Lab()
        let operations = try TabletopPlanner(kit: kit, anchors: [], tracking: .virtualScene).setOutStarter()
        let receipts = try await SequentialRun.perform(operations, commit: lab.commit)
        #expect(receipts.map(\.summary) == ["Placed “Windmill”.", "Placed “Cottage”.", "Placed “Pine Tree”.", "Placed “Lantern”."])
        #expect(try await lab.anchors().map(\.title.value) == ["Cottage", "Lantern", "Pine Tree", "Windmill"])
    }

    @Test func aNudgePlannedFromAStaleSnapshotBecomesAConflictNotAnOverwrite() async throws {
        let lab = Lab()
        _ = try await lab.commit(try TabletopPlanner(kit: kit, anchors: [], tracking: .virtualScene).place(try FixtureKey("pine"), x: 0, z: 0))
        let seen = try await lab.anchors()
        let pine = try #require(seen.first)

        // Another window moves the pine after this one read it.
        _ = try await lab.commit(try TabletopPlanner(kit: kit, anchors: seen, tracking: .virtualScene).nudge(pine.id, .right))
        let stale = try await lab.commit(try TabletopPlanner(kit: kit, anchors: seen, tracking: .virtualScene).nudge(pine.id, .left))
        #expect(stale.conflict?.current == .r(2))
        #expect(try await lab.anchors().first?.pose.x == 20)
    }

    @Test func removingNeedsItsGrantAndItsUndoPutsTheObjectBack() async throws {
        let lab = Lab()
        _ = try await lab.commit(try TabletopPlanner(kit: kit, anchors: [], tracking: .virtualScene).place(try FixtureKey("cottage"), x: 100, z: 50, yaw: 90))
        let cottage = try #require(try await lab.anchors().first)
        let remove = try TabletopPlanner(kit: kit, anchors: [cottage], tracking: .limited(.excessiveMotion)).remove(cottage.id)

        // Without a grant the policy refuses: a removal is destructive (ADR-013).
        await #expect(throws: OperationError.self) {
            try await lab.service.perform(OperationRequest(id: RequestID(), operation: remove, actor: Self.appUI))
        }
        let receipt = try await lab.commit(remove)
        #expect(receipt.removed == [.anchor(cottage.id)])
        #expect(try await lab.anchors().isEmpty)
        _ = try await lab.commit(try #require(receipt.undo))
        #expect(try await lab.anchors() == [cottage])
    }

    @Test func clearingStopsBetweenCommitsWhenCancelledAndKeepsWhatItFinished() async throws {
        let lab = Lab()
        _ = try await SequentialRun.perform(try TabletopPlanner(kit: kit, anchors: [], tracking: .virtualScene).setOutStarter(), commit: lab.commit)
        let removals = try TabletopPlanner(kit: kit, anchors: try await lab.anchors(), tracking: .virtualScene).clear()
        #expect(removals.count == 4)

        let task = Task {
            var committed = 0
            return try await SequentialRun.perform(removals) { operation throws(TabletopError) in
                let receipt = try await lab.commit(operation)
                committed += 1
                if committed == 2 { withUnsafeCurrentTask { $0?.cancel() } }
                return receipt
            }
        }
        await #expect(throws: TabletopError.cancelled(completed: 2)) { try await task.value }
        #expect(try await lab.anchors().count == 2)
    }

    @Test func aRefusedCommitStopsTheRunAndReportsTheRefusal() async throws {
        let lab = Lab()
        let place = try TabletopPlanner(kit: kit, anchors: [], tracking: .virtualScene).place(try FixtureKey("pine"), x: 0, z: 0)
        _ = try await lab.commit(place)
        // The same placement again names an anchor that now exists.
        await #expect(throws: TabletopError.refused(.ruleViolation(.alreadyExists(place.target!)))) {
            try await SequentialRun.perform([place, place], commit: lab.commit)
        }
    }

    // MARK: The route

    @Test func theMacAndASimulatorOrUnsupportedDeviceGetTheVirtualTableWithTheirReason() async {
        let mac = await CapabilityRegistry(platform: .macOS, source: FakeSource()).report(for: .worldTracking)
        let macRoute = TabletopRoute(report: mac)
        #expect(!macRoute.offersLiveStart)
        #expect(macRoute.summary.contains("ARWorldTrackingConfiguration is iOS-only"))

        let simulator = await CapabilityRegistry(platform: .iOS, source: FakeSource(isSimulator: true, supportsWorldTracking: false)).report(for: .worldTracking)
        let simulatorRoute = TabletopRoute(report: simulator)
        #expect(!simulatorRoute.offersLiveStart)
        #expect(simulatorRoute.summary.contains("isSupported is false"))
    }

    @Test func aSourceBuildWithoutTheCameraPurposeStringNeverOffersTheCamera() async {
        let report = await CapabilityRegistry(platform: .iOS, source: FakeSource(supportsWorldTracking: true, purposeStrings: false)).report(for: .worldTracking)
        let route = TabletopRoute(report: report)
        #expect(!route.offersLiveStart)
        #expect(route.summary.contains("NSCameraUsageDescription"))
    }

    @Test func aSupportedDeviceOffersTheCameraOnlyThroughAnExplicitAction() async {
        let undetermined = await CapabilityRegistry(platform: .iOS, source: FakeSource(supportsWorldTracking: true)).report(for: .worldTracking)
        #expect(TabletopRoute(report: undetermined) == .afterPermission)
        let allowed = await CapabilityRegistry(platform: .iOS, source: FakeSource(supportsWorldTracking: true, camera: .authorized)).report(for: .worldTracking)
        #expect(TabletopRoute(report: allowed) == .live)
        let declined = await CapabilityRegistry(platform: .iOS, source: FakeSource(supportsWorldTracking: true, camera: .denied)).report(for: .worldTracking)
        #expect(!TabletopRoute(report: declined).offersLiveStart)
        #expect(TabletopRoute.startAction.capability == .worldTracking && TabletopRoute.startAction.experimentID == "LAB-023")
    }
}

/// A capability source with fixed readings. It never prompts or touches a sensor.
struct FakeSource: CapabilitySource {
    var isSimulator = false
    var supportsWorldTracking = false
    var purposeStrings = true
    var camera: PermissionStatus = .notDetermined

    func permissionStatus(_ permission: PermissionKind) -> PermissionStatus { permission == .camera ? camera : .notDetermined }
    func hasCaptureDevice(_ kind: CaptureDeviceKind) -> Bool? { true }
    func speechTranscription() async -> SpeechTranscriptionReading { fatalError("not read") }
    func languageModel() -> LanguageModelReading { fatalError("not read") }
    func worldTracking() -> WorldTrackingReading? { WorldTrackingReading(worldTracking: supportsWorldTracking, sceneReconstruction: false) }
    func ultraWideband() -> UltraWidebandReading? { nil }
    func entitlement(_ key: String) -> EntitlementReading { .present }
    func declaresPurposeString(_ key: String) -> Bool { purposeStrings }
}
