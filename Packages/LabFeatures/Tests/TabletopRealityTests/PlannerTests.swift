import Foundation
import LabDomain
import Testing
@testable import TabletopReality

/// Placement rules and the tracking gate, over plain snapshots. Nothing here commits.
@Suite struct PlannerTests {
    let kit = try! TabletopKit.bundled()

    func key(_ raw: String) -> FixtureKey { try! FixtureKey(raw) }

    func anchor(_ raw: String, _ x: Int, _ z: Int, yaw: Int = 0, id: Int, revision: Int = 1) -> LabAnchor {
        let fixture = kit.fixture(key(raw))
        return LabAnchor(
            id: AnchorID(rawValue: uuid(id)), fixture: key(raw), title: fixture?.title ?? (try! EntityTitle(raw)),
            pose: try! AnchorPose(x: x, z: z, yaw: yaw), revision: Revision(rawValue: revision)!
        )
    }

    func planner(_ anchors: [LabAnchor] = [], tracking: TrackingStatus = .virtualScene) -> TabletopPlanner {
        TabletopPlanner(kit: kit, anchors: anchors, tracking: tracking)
    }

    // MARK: Tracking gate

    static let suspended: [TrackingStatus] = [.notStarted, .interrupted, .notAvailable]
        + TrackingStatus.LimitedReason.allCases.map { .limited($0) }

    @Test(arguments: suspended)
    func trackingLossSuspendsEveryPrecisionInteractionAndNothingElse(status: TrackingStatus) throws {
        let windmill = anchor("windmill", 0, 0, id: 1)
        let lab = planner([windmill], tracking: status)
        #expect(throws: TabletopError.trackingSuspended(status)) { try lab.place(key("pine"), x: 300, z: 0) }
        #expect(throws: TabletopError.trackingSuspended(status)) { try lab.placeAtFreeSpot(key("pine")) }
        #expect(throws: TabletopError.trackingSuspended(status)) { try lab.nudge(windmill.id, .left) }
        #expect(throws: TabletopError.trackingSuspended(status)) { try lab.move(windmill.id, toX: 100, z: 0) }
        #expect(throws: TabletopError.trackingSuspended(status)) { try lab.turn(windmill.id, by: 15) }
        #expect(throws: TabletopError.trackingSuspended(status)) { try lab.setOutStarter() }
        // Removing, clearing, and selecting do not depend on a precise pose.
        #expect(try lab.remove(windmill.id) == .removeAnchor(id: windmill.id, expected: .initial))
        #expect(try lab.clear().count == 1)
        #expect(InteractionGate.allows(.select, under: status))
        #expect(!status.allowsPrecision)
    }

    @Test(arguments: [TrackingStatus.virtualScene, .normal])
    func trustworthyTrackingAllowsEveryInteraction(status: TrackingStatus) {
        for interaction in TabletopInteraction.allCases {
            #expect(InteractionGate.allows(interaction, under: status))
        }
    }

    // MARK: Placement

    @Test func placingChecksTheKitTheTableEdgesAndOtherObjects() throws {
        let cottage = anchor("cottage", 0, 0, id: 1)
        let lab = planner([cottage])
        let placed = try lab.place(key("pine"), x: 300, z: 100, yaw: 400, id: AnchorID(rawValue: uuid(9)))
        guard case .placeAnchor(let draft) = placed else { Issue.record("not a placement"); return }
        let expected = try AnchorPose(x: 300, z: 100, yaw: 40)
        #expect(draft.title.value == "Pine Tree" && draft.pose == expected)

        // Pine radius 40, table half-width 450: x 410 touches the edge, 411 passes it.
        #expect(throws: Never.self) { try lab.place(key("pine"), x: 410, z: 0) }
        #expect(throws: TabletopError.outsideTable) { try lab.place(key("pine"), x: 411, z: 0) }
        #expect(throws: TabletopError.outsideTable) { try lab.place(key("pine"), x: 0, z: -261) }
        // Cottage radius 70 plus pine radius 40: centers closer than 110 overlap.
        #expect(throws: TabletopError.overlaps("Cottage")) { try lab.place(key("pine"), x: 109, z: 0) }
        #expect(throws: Never.self) { try lab.place(key("pine"), x: 110, z: 0) }
        #expect(throws: TabletopError.unknownFixture(key("rocket"))) { try lab.place(key("rocket"), x: 0, z: 0) }
    }

    @Test func theTableHoldsAtMostItsCapacity() throws {
        let full = (0..<TabletopPlanner.capacity).map { anchor("lantern", -400 + $0 * 70, 0, id: 100 + $0) }
        #expect(throws: TabletopError.tableFull(limit: 12)) { try planner(full).place(key("lantern"), x: 0, z: 200) }
    }

    @Test func aFreeSpotIsTheSameEveryTimeAndNearestTheCenter() throws {
        let empty = try planner().placeAtFreeSpot(key("windmill"), id: AnchorID(rawValue: uuid(1)))
        #expect(empty == .placeAnchor(draft: AnchorDraft(
            id: AnchorID(rawValue: uuid(1)), fixture: key("windmill"), title: "Windmill", pose: try AnchorPose(x: 0, z: 0)
        )))
        let taken = planner([anchor("windmill", 0, 0, id: 1)])
        let first = try taken.placeAtFreeSpot(key("pine"), id: AnchorID(rawValue: uuid(2)))
        let again = try taken.placeAtFreeSpot(key("pine"), id: AnchorID(rawValue: uuid(2)))
        #expect(first == again)
        guard case .placeAnchor(let draft) = first else { Issue.record("not a placement"); return }
        let distance = (draft.pose.x * draft.pose.x + draft.pose.z * draft.pose.z)
        #expect(distance >= 105 * 105 && distance < 140 * 140)
    }

    @Test func aTableWithNoRoomSaysSo() throws {
        // A 200 mm table with one 60 mm-radius stone in the middle leaves no spot for another.
        let small = try TabletopKit.decode(Data("""
            {"format": "native-lab-tabletop-kit", "version": 1, "title": "Small",
             "table": {"title": "Stool", "width": 200, "depth": 200, "thickness": 20, "color": "oak"},
             "fixtures": [{"key": "stone", "title": "Stone", "summary": "A round stone.", "radius": 60,
                           "parts": [{"shape": "sphere", "size": [100, 100, 100], "offset": [0, 50, 0], "color": "stone"}]}],
             "starter": []}
            """.utf8))
        let first = try TabletopPlanner(kit: small, anchors: [], tracking: .virtualScene).placeAtFreeSpot(key("stone"))
        guard case .placeAnchor(let draft) = first else { Issue.record("not a placement"); return }
        let placed = LabAnchor(id: draft.id, fixture: draft.fixture, title: draft.title, pose: draft.pose)
        #expect(throws: TabletopError.noRoom("Stone")) {
            try TabletopPlanner(kit: small, anchors: [placed], tracking: .virtualScene).placeAtFreeSpot(key("stone"))
        }
    }

    // MARK: Moving and turning

    @Test func nudgingKeepsTheHeadingAndStopsAtEdgesAndNeighbors() throws {
        let pine = anchor("pine", 400, 0, yaw: 30, id: 1, revision: 3)
        let lantern = anchor("lantern", 400, 80, id: 2)
        let lab = planner([pine, lantern])
        #expect(try lab.nudge(pine.id, .left, by: .coarse) == .moveAnchor(id: pine.id, expected: .r(3), pose: try AnchorPose(x: 300, z: 0, yaw: 30)))
        #expect(try lab.nudge(pine.id, .awayFromYou, by: .fine) == .moveAnchor(id: pine.id, expected: .r(3), pose: try AnchorPose(x: 400, z: -5, yaw: 30)))
        #expect(throws: TabletopError.outsideTable) { try lab.nudge(pine.id, .right) }
        #expect(throws: TabletopError.overlaps("Lantern")) { try lab.nudge(pine.id, .towardYou) }
        #expect(throws: TabletopError.unknownAnchor(AnchorID(rawValue: uuid(3)))) { try lab.nudge(AnchorID(rawValue: uuid(3)), .left) }
        // Moving to where it already is conflicts with nothing, including itself.
        #expect(try lab.move(pine.id, toX: 400, z: 0) == .moveAnchor(id: pine.id, expected: .r(3), pose: pine.pose))
    }

    @Test func turningWrapsWithinOneTurnAndKeepsThePlace() throws {
        let windmill = anchor("windmill", -100, 50, yaw: 350, id: 1)
        let lab = planner([windmill])
        #expect(try lab.turn(windmill.id, by: 15) == .moveAnchor(id: windmill.id, expected: .initial, pose: try AnchorPose(x: -100, z: 50, yaw: 5)))
        #expect(try lab.turn(windmill.id, by: -360) == .moveAnchor(id: windmill.id, expected: .initial, pose: windmill.pose))
    }

    // MARK: Clearing and the starter scene

    @Test func clearingNamesOnlyTheLabOwnedAnchorsOnTheTable() throws {
        let anchors = [anchor("pine", 0, 0, id: 1, revision: 2), anchor("cottage", 200, 0, id: 2)]
        #expect(try planner(anchors).clear() == [
            .removeAnchor(id: anchors[0].id, expected: .r(2)), .removeAnchor(id: anchors[1].id, expected: .initial),
        ])
        #expect(try planner().clear().isEmpty)
    }

    @Test func theStarterSceneSkipsTakenSpotsAndRefusesWhenAllAreTaken() throws {
        let onWindmillSpot = anchor("cottage", -240, -60, id: 1)
        let operations = try planner([onWindmillSpot]).setOutStarter()
        #expect(operations.count == 3)
        let titles = operations.compactMap { operation -> String? in
            if case .placeAnchor(let draft) = operation { draft.title.value } else { nil }
        }
        #expect(titles == ["Cottage", "Pine Tree", "Lantern"])

        let blockers = kit.starter.enumerated().map { anchor("lantern", $0.element.x, $0.element.z, id: 10 + $0.offset) }
        #expect(throws: TabletopError.starterBlocked) { try planner(blockers).setOutStarter() }
    }
}

func uuid(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
}

extension Revision {
    static func r(_ value: Int) -> Revision { Revision(rawValue: value)! }
}

extension EntityTitle: @retroactive ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { try! self.init(value) }
}
