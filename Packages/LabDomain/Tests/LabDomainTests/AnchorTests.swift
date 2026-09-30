import Foundation
import LabDomain
import Testing

/// LAB-023 Tabletop Reality: lab-owned anchors change only through `OperationService`, with a
/// receipt and an undo, under the same adapter ceilings and grants as every other operation
/// (ADR-011, ADR-013). A removal is destructive and needs a grant; Reset Demo removes every anchor
/// and never user data.
@Suite struct AnchorTests {
    static let id = AnchorID(rawValue: uuid(800))

    private static func pose(_ x: Int, _ z: Int, yaw: Int = 0) -> AnchorPose {
        try! AnchorPose(x: x, z: z, yaw: yaw)
    }

    private static func draft(at pose: AnchorPose = pose(100, -50)) -> AnchorDraft {
        AnchorDraft(id: id, fixture: try! FixtureKey("lighthouse"), title: "Lighthouse", pose: pose)
    }

    // MARK: Values

    @Test func posesAreWholeMillimetersWithinReachAndHeadingsWrapIntoOneTurn() throws {
        #expect(try AnchorPose(x: 5_000, y: -5_000, z: 0).x == 5_000)
        #expect(throws: SpatialValidationError.outOfReach(limit: 5_000)) { try AnchorPose(x: 5_001, z: 0) }
        #expect(throws: SpatialValidationError.outOfReach(limit: 5_000)) { try AnchorPose(x: 0, y: -5_001, z: 0) }
        #expect(try AnchorPose(x: 0, z: 0, yaw: -90).yaw == 270)
        #expect(try AnchorPose(x: 0, z: 0, yaw: 725).yaw == 5)
        #expect(Self.pose(1, 2, yaw: 90).differsOnlyInYaw(from: Self.pose(1, 2)))
        #expect(!Self.pose(1, 3, yaw: 90).differsOnlyInYaw(from: Self.pose(1, 2)))
    }

    @Test func decodingRefusesAStoredPoseOrKeyThatCouldNotHaveBeenMade() throws {
        let decoder = JSONDecoder()
        #expect(throws: DecodingError.self) { try decoder.decode(AnchorPose.self, from: Data(#"{"x":0,"y":0,"z":0,"yaw":360}"#.utf8)) }
        #expect(throws: DecodingError.self) { try decoder.decode(AnchorPose.self, from: Data(#"{"x":9000,"y":0,"z":0,"yaw":0}"#.utf8)) }
        #expect(throws: DecodingError.self) { try decoder.decode(FixtureKey.self, from: Data(#""Water Tower""#.utf8)) }
        #expect(try decoder.decode(FixtureKey.self, from: Data(#""water-tower-2""#.utf8)).value == "water-tower-2")
        #expect(throws: SpatialValidationError.invalidFixtureKey) { try FixtureKey("") }
        #expect(throws: SpatialValidationError.invalidFixtureKey) { try FixtureKey(String(repeating: "a", count: 41)) }
    }

    // MARK: Operations

    @Test func placingAnAnchorCreatesItInTheDemoNamespaceWithAnUndoThatRemovesIt() async throws {
        let lab = Harness()
        #expect(try await lab.service.findAnchors(as: .appUI).isEmpty)

        let receipt = try await lab.perform(.placeAnchor(draft: Self.draft()))
        #expect(receipt.status == .committed)
        #expect(receipt.changes.map(\.entity) == [.anchor(Self.id)])
        #expect(receipt.changes.map(\.previousRevision) == [nil])
        #expect(receipt.summary == "Placed “Lighthouse”.")
        #expect(receipt.undo == .removeAnchor(id: Self.id, expected: .initial))
        let stored = try await lab.service.findAnchors(as: .appUI)
        #expect(stored == [LabAnchor(id: Self.id, fixture: try FixtureKey("lighthouse"), title: "Lighthouse", pose: Self.pose(100, -50))])
        #expect(stored.first?.namespace == .demo)

        await #expect(throws: OperationError.ruleViolation(.alreadyExists(.anchor(Self.id)))) {
            try await lab.perform(.placeAnchor(draft: Self.draft()))
        }
    }

    @Test func movingAndTurningAreNamedApartAndEachUndoMovesBack() async throws {
        let lab = Harness()
        try await lab.perform(.placeAnchor(draft: Self.draft()))

        let moved = try await lab.perform(.moveAnchor(id: Self.id, expected: .initial, pose: Self.pose(120, -50)))
        #expect(moved.summary == "Moved “Lighthouse”.")
        #expect(moved.undo == .moveAnchor(id: Self.id, expected: .r(2), pose: Self.pose(100, -50)))

        let turned = try await lab.perform(.moveAnchor(id: Self.id, expected: .r(2), pose: Self.pose(120, -50, yaw: 15)))
        #expect(turned.summary == "Turned “Lighthouse”.")

        let back = try await lab.perform(try #require(turned.undo))
        #expect(back.summary == "Turned “Lighthouse”.")
        #expect(try await lab.service.findAnchors(as: .appUI).first?.pose == Self.pose(120, -50))
        #expect(try await lab.service.findAnchors(as: .appUI).first?.revision == .r(4))

        await #expect(throws: OperationError.ruleViolation(.noChanges(.anchor(Self.id)))) {
            try await lab.perform(.moveAnchor(id: Self.id, expected: .r(4), pose: Self.pose(120, -50)))
        }
    }

    @Test func aStaleMoveGetsAConflictReceiptAndChangesNothing() async throws {
        let lab = Harness()
        try await lab.perform(.placeAnchor(draft: Self.draft()))
        try await lab.perform(.moveAnchor(id: Self.id, expected: .initial, pose: Self.pose(0, 0)))

        let stale = try await lab.perform(.moveAnchor(id: Self.id, expected: .initial, pose: Self.pose(300, 300)))
        let conflict = try #require(stale.conflict)
        #expect(conflict.entity == .anchor(Self.id) && conflict.expected == .initial && conflict.current == .r(2))
        #expect(stale.summary == "Not applied because anchor “Lighthouse” changed: expected revision 1, found 2.")
        #expect(try await lab.service.findAnchors(as: .appUI).first?.pose == Self.pose(0, 0))
        #expect(
            DomainOperation.moveAnchor(id: Self.id, expected: .initial, pose: Self.pose(1, 1)).rebased(onto: .r(2))
                == .moveAnchor(id: Self.id, expected: .r(2), pose: Self.pose(1, 1))
        )
    }

    @Test func removingIsDestructiveDeletesTheAnchorAndItsUndoPlacesTheSameAnchorAgain() async throws {
        #expect(OperationKind.removeAnchor.isDestructive)
        #expect(!OperationKind.placeAnchor.isDestructive && !OperationKind.moveAnchor.isDestructive)
        let lab = Harness()
        try await lab.perform(.placeAnchor(draft: Self.draft()))
        try await lab.perform(.moveAnchor(id: Self.id, expected: .initial, pose: Self.pose(40, 40, yaw: 30)))

        let removed = try await lab.perform(.removeAnchor(id: Self.id, expected: .r(2)))
        #expect(removed.changes.isEmpty)
        #expect(removed.removed == [.anchor(Self.id)])
        #expect(removed.summary == "Removed “Lighthouse”.")
        #expect(try await lab.service.findAnchors(as: .appUI).isEmpty)

        let restored = try await lab.perform(try #require(removed.undo))
        #expect(restored.summary == "Placed “Lighthouse”.")
        #expect(try await lab.service.findAnchors(as: .appUI).first?.pose == Self.pose(40, 40, yaw: 30))

        await #expect(throws: OperationError.notFound(.anchor(AnchorID(rawValue: uuid(801))))) {
            try await lab.perform(.removeAnchor(id: AnchorID(rawValue: uuid(801)), expected: .initial))
        }
    }

    // MARK: Authorization

    @Test func aRemovalNeedsAGrantForExactlyThatAnchorWhilePlacingAndMovingNeedNone() async throws {
        let lab = GrantedLab()
        let place = DomainOperation.placeAnchor(draft: Self.draft())
        _ = try await lab.service.perform(OperationRequest(id: RequestID(), operation: place, actor: .appUI))
        _ = try await lab.service.perform(OperationRequest(
            id: RequestID(), operation: .moveAnchor(id: Self.id, expected: .initial, pose: Self.pose(0, 0)), actor: .appUI
        ))

        let remove = DomainOperation.removeAnchor(id: Self.id, expected: .r(2))
        let refused = await #expect(throws: OperationError.self) {
            try await lab.service.perform(OperationRequest(id: RequestID(), operation: remove, actor: .appUI))
        }
        #expect(refused?.denial?.reason == .deniedByPolicy)
        #expect(try await lab.service.findAnchors(as: .appUI).count == 1)

        let grant = try lab.ledger.issue(for: remove, to: .appUI)
        #expect(grant.target == .entity(.anchor(Self.id)))
        _ = try await lab.service.perform(OperationRequest(id: RequestID(), operation: remove, actor: .appUI))
        #expect(try await lab.service.findAnchors(as: .appUI).isEmpty)
    }

    @Test func aModelToolMayReadAndProposeButNeverPlaceAnAnchor() async throws {
        let lab = Harness()
        #expect(try await lab.service.findAnchors(as: .modelTool).isEmpty)
        let proposal = try await lab.service.propose(.placeAnchor(draft: Self.draft()), as: .modelTool)
        #expect(proposal.summary == "Place “Lighthouse”.")
        let error = await #expect(throws: OperationError.self) {
            try await lab.perform(.placeAnchor(draft: Self.draft()), as: .modelTool)
        }
        #expect(error?.denial?.reason == .outsideAdapterCeiling)
        #expect(await lab.store.appliedCommits == 0)
    }

    // MARK: Reset Demo

    @Test func resetDemoRemovesEveryAnchorAndLeavesUserDataAlone() async throws {
        let lab = Harness()
        let seed = try DemoSeed(version: 1, collections: [CollectionDraft(id: CollectionID(rawValue: uuid(802)), title: "Samples")], items: [])
        _ = try await lab.perform(.resetDemo(seed: seed))
        let mine = try await lab.makeCollection("Mine")
        let item = try await lab.makeItem("Kept", in: mine)
        try await lab.perform(.placeAnchor(draft: Self.draft()))
        let second = AnchorID(rawValue: uuid(803))
        try await lab.perform(.placeAnchor(draft: AnchorDraft(
            id: second, fixture: try FixtureKey("pine"), title: "Pine", pose: Self.pose(-200, 100)
        )))

        let reset = try await lab.perform(.resetDemo(seed: seed))
        #expect(reset.removed == [.anchor(Self.id), .anchor(second)])
        #expect(reset.changes.isEmpty)
        #expect(reset.summary == "Reset the demo to its original 1 collection and 0 items: cleared 2 placed objects.")
        #expect(try await lab.service.findAnchors(as: .appUI).isEmpty)
        #expect(try await lab.item(item.id) == item)
        #expect(try await lab.collection(mine.id) == mine)

        let again = try await lab.perform(.resetDemo(seed: seed))
        #expect(again.removed.isEmpty)
        #expect(again.summary == "The demo already matched its original 1 collection and 0 items.")
    }

    @Test func anAnchorReceiptRoundTripsThroughJSON() async throws {
        let lab = Harness()
        let receipt = try await lab.perform(.placeAnchor(draft: Self.draft(at: Self.pose(-12, 34, yaw: 350))))
        let data = try JSONEncoder().encode(receipt)
        #expect(try JSONDecoder().decode(ActionReceipt.self, from: data) == receipt)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""kind":"anchor""#))
        #expect(text.contains(#""yaw":350"#))
    }
}
