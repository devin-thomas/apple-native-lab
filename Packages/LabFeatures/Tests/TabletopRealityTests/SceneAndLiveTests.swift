import Foundation
import LabDomain
import Testing
@testable import TabletopReality

/// The accessible description names every object; the live adapter's policies (reset scope,
/// relocalization recovery, map consent) hold without a camera.
@Suite struct SceneAndLiveTests {
    let kit = try! TabletopKit.bundled()

    // MARK: The accessibility list

    @Test func theListNamesTheTableAndEveryAnchorIncludingOnesTheKitDoesNotDraw() throws {
        let anchors = [
            LabAnchor(id: AnchorID(rawValue: uuid(1)), fixture: try FixtureKey("windmill"), title: "Windmill",
                      pose: try AnchorPose(x: -240, z: -60, yaw: 90)),
            LabAnchor(id: AnchorID(rawValue: uuid(2)), fixture: try FixtureKey("from-a-newer-kit"), title: "Ferry",
                      pose: try AnchorPose(x: 0, z: 125)),
        ]
        let entries = SceneDescription.entries(kit: kit, anchors: anchors)
        #expect(entries.map(\.subject) == [.table, .anchor(anchors[0].id), .anchor(anchors[1].id)])
        #expect(entries[0].label == "Oak table" && entries[0].value == "90 cm by 60 cm, 2 objects")
        #expect(entries[1].value == "24 cm left of center, 6 cm away from you, facing right, turned 90°")
        #expect(entries[1].detail.hasPrefix("A round stone windmill"))
        #expect(entries[2].value == "centered left to right, 12.5 cm toward you, facing you")
        #expect(entries[2].detail == "An object this build's kit does not draw.")
    }

    @Test(arguments: [(0, "facing you"), (45, "facing front right, turned 45°"), (180, "facing away, turned 180°"),
                      (270, "facing left, turned 270°"), (340, "facing you, turned 340°")])
    func headingsReadAsTheNearestEighthOfATurn(yaw: Int, expected: String) {
        #expect(SceneDescription.heading(yaw) == expected)
    }

    // MARK: Reset scope in a live session

    @Test func aResetRemovesOnlyTheLabsOwnSessionAnchors() {
        let origin = SessionAnchorRecord(identifier: uuid(10), name: LabAnchorNames.tableOrigin)
        let plane = SessionAnchorRecord(identifier: uuid(11), name: nil)
        let foreign = SessionAnchorRecord(identifier: uuid(12), name: "someone-else.marker")
        let lookalike = SessionAnchorRecord(identifier: uuid(13), name: "nativelab.tabletop")
        let older = SessionAnchorRecord(identifier: uuid(14), name: LabAnchorNames.prefix + "table-origin")
        #expect(LabAnchorNames.removals(from: [plane, origin, foreign, lookalike, older]) == [uuid(10), uuid(14)])
        #expect(LabAnchorNames.removals(from: [plane, foreign]).isEmpty)
    }

    // MARK: Relocalization

    @Test func relocalizingLongerThanThePatienceOffersRecoveryAndNormalTrackingEndsIt() {
        var watch = RelocalizationWatch(patience: .seconds(20))
        let start = ContinuousClock.now
        #expect(watch.observe(.normal, at: start) == .none)
        #expect(watch.observe(.limited(.relocalizing), at: start) == .searching(elapsed: .zero))
        #expect(watch.observe(.limited(.relocalizing), at: start + .seconds(19)) == .searching(elapsed: .seconds(19)))
        #expect(watch.observe(.interrupted, at: start + .seconds(21)) == .stalled(elapsed: .seconds(21)))

        watch.keepLooking(at: start + .seconds(21))
        #expect(watch.observe(.limited(.relocalizing), at: start + .seconds(30)) == .searching(elapsed: .seconds(9)))
        #expect(watch.observe(.normal, at: start + .seconds(31)) == .recovered)
        #expect(!watch.isSearching)
        #expect(watch.observe(.normal, at: start + .seconds(32)) == .none)
    }

    @Test func theReplayLosesTrackingStallsAndRecoversWhileTheGateFollowsIt() {
        let replay = TrackingReplay.standard
        #expect(replay.totalDuration == .seconds(15))
        var watch = RelocalizationWatch(patience: TrackingReplay.replayPatience)
        let start = ContinuousClock.now
        var elapsed: Duration = .zero
        var advice: [RelocalizationWatch.Advice] = []
        var placeAllowed: [Bool] = []
        for step in replay.steps {
            // Sample the start and the end of each step, as a running replay would.
            advice.append(watch.observe(step.status, at: start + elapsed))
            elapsed += step.duration
            advice.append(watch.observe(step.status, at: start + elapsed - .milliseconds(1)))
            placeAllowed.append(InteractionGate.allows(.place, under: step.status))
        }
        #expect(placeAllowed == [false, true, false, false, false, true])
        #expect(advice.contains { if case .stalled = $0 { true } else { false } })
        #expect(advice.contains(.recovered))
        #expect(replay.steps.last?.status == .normal)
    }

    // MARK: Saving the table map

    @Test func aMapIsOfferedOnlyLiveWithATableNormalTrackingAndAMappedArea() {
        #expect(MappingPolicy.decision(isLive: true, tracking: .normal, mapping: .mapped, hasTable: true) == .ready)
        #expect(MappingPolicy.decision(isLive: true, tracking: .normal, mapping: .extending, hasTable: true).canSave)
        #expect(!MappingPolicy.decision(isLive: false, tracking: .virtualScene, mapping: .mapped, hasTable: true).canSave)
        #expect(MappingPolicy.decision(isLive: true, tracking: .normal, mapping: .mapped, hasTable: false) == .notYet("Place the table first."))
        #expect(!MappingPolicy.decision(isLive: true, tracking: .limited(.relocalizing), mapping: .mapped, hasTable: true).canSave)
        #expect(!MappingPolicy.decision(isLive: true, tracking: .normal, mapping: .limited, hasTable: true).canSave)
        #expect(MappingPolicy.consentMessage.contains("no camera images"))
        #expect(MappingPolicy.consentMessage.contains("stays on this device"))
    }
}
