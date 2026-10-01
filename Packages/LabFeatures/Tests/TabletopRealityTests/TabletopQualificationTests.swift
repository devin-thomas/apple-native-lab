import Foundation
import LabDomain
import LabSupport
import Testing
@testable import TabletopReality

// LAB-023-B: the qualification of Tabletop Reality's fixture path. Each suite proves one
// acceptance criterion or boundary over the planner, the gate, the scene description, and the one
// operation service, from a clean in-memory store with `GrantAuthorizationPolicy`, as the hosts
// compose it. Nothing here runs RealityKit, ARKit, a camera, or a view.

// MARK: - The complete interaction

/// LAB-023-B step 1: the showcase script that `Packages/LabDemo` replays as evidence
/// (`Fixtures/showcase/tabletop-reality/`), run here through the tabletop's own planner from a
/// clean store. The script states every operation in full; this checks that the planner builds
/// exactly those operations from what a person does (Set Out Starter Scene, a click on the table,
/// Move Left, Turn Left, Remove, its undo, and Place on Table), and that the script asks for
/// approval exactly where the hosts issue a grant.
///
/// LabFeatures does not depend on LabDemo, so the script is read as plain JSON.
@Suite struct TabletopShowcaseReplayTests {
    let kit = try! TabletopKit.bundled()

    @Test func theShowcaseSeedIsTheDemoSeed() throws {
        let showcase = try Data(contentsOf: TabletopFixtures.showcase.appending(path: "seed.json"))
        let demo = try Data(contentsOf: TabletopFixtures.root.appending(path: "demo/seed.json"))
        #expect(showcase == demo)
    }

    @Test func theScriptApprovesExactlyTheChangesThatNeedAGrant() throws {
        let steps = try ShowcaseStep.load()
        let approved = Set(steps.compactMap(\.approves))
        let destructive = Set(steps.filter { step in
            guard let kind = step.operationKind else { return false }
            return GrantRequirement.sensitiveCommits.requiresGrant(kind, from: .appUI)
        }.map(\.id))
        #expect(approved == destructive)
        #expect(approved == ["reset", "remove-lighthouse", "reset-again"])
    }

    @Test func thePlannerBuildsTheScriptsOperationsAndTheLabEndsAsTheReplayDoes() async throws {
        let steps = try ShowcaseStep.load()
        let lab = try await QualifiedLab.seeded()
        func planner() async throws -> TabletopPlanner {
            TabletopPlanner(kit: kit, anchors: try await lab.anchors(), tracking: .virtualScene)
        }
        func scripted(_ id: String) throws -> DomainOperation { try #require(steps.first { $0.id == id }?.operation, "\(id)") }

        // Set Out Starter Scene on the empty table: the script's four placements, IDs aside.
        let starter = try await planner().setOutStarter()
        let placements = try ["place-windmill", "place-cottage", "place-pine", "place-lantern"].map(scripted)
        #expect(starter.map(Self.withoutID) == placements.map(Self.withoutID))
        for operation in placements { try await lab.commit(operation) }

        // A click at (300, -200) with the Lighthouse chosen, then Move Left and Turn Left.
        let lighthouse = try #require(scripted("place-lighthouse").target.flatMap(Self.anchorID))
        #expect(try await planner().place(try FixtureKey("lighthouse"), x: 300, z: -200, id: lighthouse) == (try scripted("place-lighthouse")))
        try await lab.commit(try scripted("place-lighthouse"))
        #expect(try await planner().nudge(lighthouse, .left) == (try scripted("move-lighthouse")))
        try await lab.commit(try scripted("move-lighthouse"))
        #expect(try await planner().turn(lighthouse, by: TabletopPlanner.turnStep) == (try scripted("turn-lighthouse")))
        try await lab.commit(try scripted("turn-lighthouse"))

        // Remove, and the receipt's undo.
        #expect(try await planner().remove(lighthouse) == (try scripted("remove-lighthouse")))
        let removed = try await lab.commit(try scripted("remove-lighthouse"))
        let undo = try #require(removed.undo)
        try await lab.commit(undo)
        #expect(try await lab.anchors().first { $0.id == lighthouse }?.pose == (try AnchorPose(x: 280, z: -200, yaw: 15)))

        // The person's own collection and item, then Reset Demo.
        try await lab.commit(try scripted("create-collection"))
        try await lab.commit(try scripted("create-item"))
        let reset = try await lab.commit(.resetDemo(seed: try TabletopFixtures.demoSeed()))
        #expect(reset.removed.count == 5 && reset.removed.allSatisfy { $0.kind == .anchor })
        #expect(try await lab.anchors().isEmpty)

        // Place on Table on the empty table: the Lantern at the center, as the script's last step.
        let last = try scripted("place-after-reset")
        let id = try #require(last.target.flatMap(Self.anchorID))
        #expect(try await planner().placeAtFreeSpot(try FixtureKey("lantern"), id: id) == last)
        try await lab.commit(last)
        #expect(try await lab.anchors().map(\.title.value) == ["Lantern"])
        #expect(try await lab.userItems().map(\.title.value) == ["Table sketch"])
    }

    static func withoutID(_ operation: DomainOperation) -> String {
        guard case .placeAnchor(let draft) = operation else { return "\(operation)" }
        return "\(draft.fixture) \(draft.title.value) \(draft.pose)"
    }

    static func anchorID(_ reference: EntityReference) -> AnchorID? {
        if case .anchor(let id) = reference { id } else { nil }
    }
}

// MARK: - Acceptance: tracking loss suspends precision interactions

/// Tracking loss suspends precision interactions: under every untrustworthy status, no placement,
/// move, turn, or starter scene reaches the service, the store, or the receipt list; selecting,
/// the list, removal, and Clear Table still work; and when tracking returns, everything does.
@Suite struct TrackingLossQualification {
    let kit = try! TabletopKit.bundled()

    static let untrustworthy: [TrackingStatus] = [.notStarted, .interrupted, .notAvailable]
        + TrackingStatus.LimitedReason.allCases.map { .limited($0) }

    @Test(arguments: untrustworthy)
    func noPrecisionRequestReachesTheStoreWhileTrackingIsLost(status: TrackingStatus) async throws {
        let lab = try await QualifiedLab.seeded()
        try await lab.commit(try TabletopPlanner(kit: kit, anchors: [], tracking: .normal).place(try FixtureKey("cottage"), x: 0, z: 0))
        let anchors = try await lab.anchors()
        let cottage = try #require(anchors.first)
        let before = await lab.snapshot()
        let lost = TabletopPlanner(kit: kit, anchors: anchors, tracking: status)

        var refused = 0
        let requests: [() throws(TabletopError) -> Any] = [
            { () throws(TabletopError) in try lost.place(try! FixtureKey("pine"), x: 300, z: 0) },
            { () throws(TabletopError) in try lost.placeAtFreeSpot(try! FixtureKey("pine")) },
            { () throws(TabletopError) in try lost.nudge(cottage.id, .right, by: .fine) },
            { () throws(TabletopError) in try lost.move(cottage.id, toX: 100, z: 0) },
            { () throws(TabletopError) in try lost.turn(cottage.id, by: -15) },
            { () throws(TabletopError) in try lost.setOutStarter() },
        ]
        for request in requests {
            do {
                _ = try request()
                Issue.record("a precision request was planned under \(status)")
            } catch {
                #expect(error == .trackingSuspended(status))
                #expect(error.message.hasSuffix("Placing, moving, and turning wait until tracking is normal. Nothing was changed."))
                refused += 1
            }
        }
        #expect(refused == 6)
        #expect(await lab.snapshot() == before, "nothing reached the store; the table is as it was")

        // Removing and clearing do not depend on a pose, and keep their undo.
        let removal = try await lab.commit(try lost.remove(cottage.id))
        #expect(removal.removed == [.anchor(cottage.id)] && removal.undo != nil)
        try await lab.commit(try #require(removal.undo))
        #expect(try lost.clear().count == 1)
        #expect(InteractionGate.allows(.select, under: status))

        // Tracking back to normal: precision interactions run again.
        let back = TabletopPlanner(kit: kit, anchors: try await lab.anchors(), tracking: .normal)
        try await lab.commit(try back.nudge(cottage.id, .right, by: .fine))
        #expect(try await lab.anchors().first?.pose.x == 5)
    }

    /// The labeled replay drives the same gate step by step: placing is refused at exactly the
    /// steps whose status is untrustworthy, and the stalled advice appears before it recovers.
    @Test func theReplaysStepsGateExactlyTheUntrustworthyOnes() throws {
        let replay = TrackingReplay.standard
        let planner = { (status: TrackingStatus) in TabletopPlanner(kit: kit, anchors: [], tracking: status) }
        let placed = replay.steps.map { (try? planner($0.status).placeAtFreeSpot(try! FixtureKey("lantern"))) != nil }
        #expect(placed == replay.steps.map { $0.status.allowsPrecision })
        #expect(placed == [false, true, false, false, false, true])
        #expect(replay.title == "Tracking loss and recovery")
        for status in Self.untrustworthy {
            #expect(status.guidance.contains("Placing and moving") || status.guidance.contains("virtual table"), "\(status)")
        }
    }
}

// MARK: - Acceptance: a reset destroys only lab-owned anchors

/// A reset destroys only lab-owned anchors: in the store, Reset Demo removes every anchor and
/// leaves the person's own and imported data untouched; in a live session, the adapter removes
/// exactly the anchors it named, never a plane, a system anchor, or a lookalike.
@Suite struct ResetScopeQualification {
    let kit = try! TabletopKit.bundled()

    @Test func resetDemoRemovesEveryAnchorAndNothingThePersonOwns() async throws {
        let lab = try await QualifiedLab.seeded()
        let mine = CollectionDraft(title: "Imports")
        try await lab.commit(.createCollection(draft: mine))
        let imported = ItemDraft(
            in: mine.id, title: "Glaze test", note: try ItemNote("Brought in from a file."),
            extras: try ItemExtras(json: #"{"portableObject":{"version":1,"note":"text","document":{"kind":"collection-item"}}}"#)
        )
        try await lab.commit(.createItem(draft: imported))
        let before = try await lab.userItems()
        // A full table: every starter object, then the other fixtures at free spots.
        for operation in try TabletopPlanner(kit: kit, anchors: [], tracking: .virtualScene).setOutStarter() {
            try await lab.commit(operation)
        }
        for key in ["lighthouse", "water-tower"] {
            let planner = TabletopPlanner(kit: kit, anchors: try await lab.anchors(), tracking: .virtualScene)
            try await lab.commit(try planner.placeAtFreeSpot(try FixtureKey(key)))
        }
        let placed = try await lab.anchors()
        #expect(placed.count == 6)

        let reset = try await lab.commit(.resetDemo(seed: try TabletopFixtures.demoSeed()))
        #expect(Set(reset.removed) == Set(placed.map(\.reference)))
        #expect(reset.changes.isEmpty, "the samples already matched the seed")
        #expect(reset.summary == "Reset the demo to its original 3 collections and 12 items: cleared 6 placed objects.")
        #expect(try await lab.anchors().isEmpty)
        #expect(try await lab.userItems() == before, "the person's own and imported items are unchanged")
        #expect(try await lab.service.findCollection(mine.id, as: QualifiedLab.appUI).namespace == .user)
    }

    /// A removal names one anchor and its revision, so it can never reach an item or collection,
    /// and an anchor is never in the person's namespace.
    @Test func everyTabletopRemovalNamesOnlyALabOwnedAnchor() throws {
        let anchors = try kit.starter.enumerated().map { index, placement in
            LabAnchor(id: AnchorID(rawValue: uuid(index + 1)), fixture: placement.fixture,
                      title: kit.fixture(placement.fixture)!.title, pose: try AnchorPose(x: placement.x, z: placement.z, yaw: placement.yaw))
        }
        let planner = TabletopPlanner(kit: kit, anchors: anchors, tracking: .limited(.relocalizing))
        let removals = try planner.clear() + [try planner.remove(anchors[0].id)]
        for operation in removals {
            guard case .removeAnchor = operation, case .anchor = operation.target else {
                Issue.record("\(operation) is not an anchor removal")
                continue
            }
        }
        #expect(anchors.allSatisfy { $0.namespace == .demo })
    }

    /// The live adapter's removal list over many session anchors: only names with the lab's exact
    /// prefix are removed, in session order.
    @Test func aLiveResetPicksOnlyTheLabsNamedAnchors() {
        let names: [String?] = [
            nil, "", LabAnchorNames.tableOrigin, "nativelab.tabletop", "nativelab.tabletopx", "NATIVELAB.TABLETOP.table-origin",
            "nativelab.tabletop.", "nativelab.tabletop.objects.windmill", " nativelab.tabletop.table-origin", "plane",
            "ARPlaneAnchor", "com.example.marker", "nativelab.other.table-origin", "nativelab.tabletop.table-origin\u{0}",
        ]
        let anchors = names.enumerated().map { SessionAnchorRecord(identifier: uuid(100 + $0.offset), name: $0.element) }
        let removed = LabAnchorNames.removals(from: anchors)
        let expected = anchors.filter { ($0.name ?? "").hasPrefix("nativelab.tabletop.") }.map(\.identifier)
        #expect(removed == expected)
        #expect(removed == [uuid(102), uuid(106), uuid(107), uuid(113)])
        #expect(LabAnchorNames.removals(from: anchors.filter { !LabAnchorNames.isLabOwned($0.name) }).isEmpty)
    }
}

// MARK: - Acceptance: the accessibility list exposes every meaningful object

/// An accessibility list exposes every meaningful object: the table and every anchor, each once,
/// in the store's order, with a name, a place, and a description, for every fixture, at every
/// heading, at the table's edges, at capacity, and for an object this build's kit does not draw.
@Suite struct SceneListQualification {
    let kit = try! TabletopKit.bundled()

    @Test func aFullTableListsTheTableAndEveryObjectOnceWithWords() throws {
        var anchors: [LabAnchor] = []
        var planner = TabletopPlanner(kit: kit, anchors: [], tracking: .virtualScene)
        let keys = kit.fixtures.map(\.key)
        while anchors.count < TabletopPlanner.capacity {
            let key = keys[anchors.count % keys.count]
            guard case .placeAnchor(let draft) = try planner.placeAtFreeSpot(key, id: AnchorID(rawValue: uuid(anchors.count + 1))) else {
                Issue.record("not a placement")
                return
            }
            anchors.append(LabAnchor(id: draft.id, fixture: draft.fixture, title: draft.title, pose: draft.pose))
            planner = TabletopPlanner(kit: kit, anchors: anchors, tracking: .virtualScene)
        }
        let entries = SceneDescription.entries(kit: kit, anchors: anchors)
        #expect(entries.count == 13)
        #expect(entries.first?.subject == .table && entries.first?.value == "90 cm by 60 cm, 12 objects")
        #expect(entries.dropFirst().map(\.subject) == anchors.map { .anchor($0.id) })
        #expect(Set(entries.map(\.id)).count == entries.count, "each object once")
        for entry in entries {
            #expect(!entry.label.isEmpty && !entry.value.isEmpty && !entry.detail.isEmpty, "\(entry.label)")
        }
        for (entry, anchor) in zip(entries.dropFirst(), anchors) {
            #expect(entry.label == anchor.title.value)
            #expect(entry.detail == kit.fixture(anchor.fixture)?.summary)
        }
    }

    @Test func everyHeadingAndEdgeReadsInWords() throws {
        for yaw in 0..<360 {
            let words = SceneDescription.heading(yaw)
            #expect(words.hasPrefix("facing "), "\(yaw)")
            #expect(yaw == 0 ? !words.contains("turned") : words.hasSuffix("turned \(yaw)°"), "\(yaw)")
        }
        #expect(SceneDescription.position(of: try AnchorPose(x: -410, z: 260)) == "41 cm left of center, 26 cm toward you, facing you")
        #expect(SceneDescription.position(of: try AnchorPose(x: 4, z: -4)) == "centered left to right, centered front to back, facing you")
        #expect(SceneDescription.position(of: try AnchorPose(x: 5, z: -5, yaw: 90))
                == "0.5 cm right of center, 0.5 cm away from you, facing right, turned 90°")
    }

    @Test func anEmptyTableAndAnUnknownObjectAreStillListed() throws {
        #expect(SceneDescription.entries(kit: kit, anchors: []).map(\.value) == ["90 cm by 60 cm, 0 objects"])
        let stranger = LabAnchor(id: AnchorID(rawValue: uuid(1)), fixture: try FixtureKey("ferry"), title: "Ferry", pose: .origin)
        let entries = SceneDescription.entries(kit: kit, anchors: [stranger])
        #expect(entries.map(\.label) == ["Oak table", "Ferry"])
        #expect(entries[0].value == "90 cm by 60 cm, 1 object")
        #expect(entries[1].detail == "An object this build's kit does not draw.")
    }
}

// MARK: - Denial, duplicates, stale state, and cancellation

@Suite struct TabletopBoundaryQualification {
    let kit = try! TabletopKit.bundled()

    /// Denial: the model tool may propose a placement but never commit one; a removal needs a
    /// grant for exactly that anchor; a refused request changes nothing.
    @Test func deniedRequestsChangeNothing() async throws {
        let lab = try await QualifiedLab.seeded()
        let planner = TabletopPlanner(kit: kit, anchors: [], tracking: .virtualScene)
        let place = try planner.place(try FixtureKey("pine"), x: 0, z: 0)
        let modelTool = ActorScope(adapter: .modelTool, grants: Set(Permission.allCases))
        #expect(try await lab.service.propose(place, as: modelTool).summary == "Place “Pine Tree”.")
        await #expect(throws: OperationError.self) {
            try await lab.service.perform(OperationRequest(id: RequestID(), operation: place, actor: modelTool))
        }
        #expect(try await lab.anchors().isEmpty)

        try await lab.commit(place)
        let other = try planner.place(try FixtureKey("lantern"), x: 300, z: 0)
        try await lab.commit(other)
        let anchors = try await lab.anchors()
        let pine = try #require(anchors.first { $0.title.value == "Pine Tree" })
        let lantern = try #require(anchors.first { $0.title.value == "Lantern" })
        let removePine = try TabletopPlanner(kit: kit, anchors: anchors, tracking: .virtualScene).remove(pine.id)
        let removeLantern = try TabletopPlanner(kit: kit, anchors: anchors, tracking: .virtualScene).remove(lantern.id)

        // No grant, then a grant for the other anchor: both refused.
        await #expect(throws: OperationError.self) {
            try await lab.service.perform(OperationRequest(id: RequestID(), operation: removePine, actor: QualifiedLab.appUI))
        }
        let wrong = try lab.ledger.issue(for: removeLantern, to: .appUI, lifetime: .seconds(30))
        await #expect(throws: OperationError.self) {
            try await lab.service.perform(OperationRequest(id: RequestID(), operation: removePine, actor: QualifiedLab.appUI))
        }
        lab.ledger.revoke(wrong.id)
        #expect(try await lab.anchors() == anchors)
    }

    /// Duplicates: a retry under the same request ID returns the first receipt and commits once;
    /// the same placement under a new request is refused as existing.
    @Test func aRetryCommitsOnceAndADuplicatePlacementIsRefused() async throws {
        let lab = try await QualifiedLab.seeded()
        let place = try TabletopPlanner(kit: kit, anchors: [], tracking: .virtualScene).place(try FixtureKey("windmill"), x: 0, z: 0)
        let request = RequestID()
        let first = try await lab.commit(place, requestID: request)
        let after = await lab.snapshot()
        let retry = try await lab.commit(place, requestID: request)
        #expect(retry == first, "the stored receipt, with the same operation ID")
        #expect(await lab.store.receipt(for: request) == first)
        #expect(await lab.snapshot() == after)
        await #expect(throws: TabletopError.refused(.ruleViolation(.alreadyExists(place.target!)))) {
            try await lab.commit(place)
        }
        #expect(try await lab.anchors().count == 1)
    }

    /// Stale state: a move, a turn, or a removal planned from a snapshot that another window has
    /// since changed is a conflict receipt that changes nothing; removing an object already gone
    /// is refused.
    @Test func staleRequestsAreConflictsNotOverwrites() async throws {
        let lab = try await QualifiedLab.seeded()
        try await lab.commit(try TabletopPlanner(kit: kit, anchors: [], tracking: .virtualScene).place(try FixtureKey("cottage"), x: 0, z: 0))
        let seen = try await lab.anchors()
        let cottage = try #require(seen.first)
        let stalePlanner = TabletopPlanner(kit: kit, anchors: seen, tracking: .virtualScene)

        // Another window turns it.
        try await lab.commit(try stalePlanner.turn(cottage.id, by: 15))
        let current = try await lab.anchors()
        for operation in [try stalePlanner.nudge(cottage.id, .left), try stalePlanner.turn(cottage.id, by: -15), try stalePlanner.remove(cottage.id)] {
            let receipt = try await lab.commit(operation)
            #expect(receipt.conflict?.current == Revision(rawValue: 2), "\(operation)")
            #expect(receipt.changes.isEmpty && receipt.removed.isEmpty && receipt.undo == nil)
            #expect(try await lab.anchors() == current)
        }

        // Another window removes it.
        try await lab.commit(try TabletopPlanner(kit: kit, anchors: current, tracking: .virtualScene).remove(cottage.id))
        await #expect(throws: TabletopError.self) {
            try await lab.commit(try TabletopPlanner(kit: kit, anchors: current, tracking: .virtualScene).remove(cottage.id))
        }
        #expect(throws: TabletopError.unknownAnchor(cottage.id)) {
            try TabletopPlanner(kit: kit, anchors: [], tracking: .virtualScene).remove(cottage.id)
        }
    }

    /// Cancellation: Set Out Starter Scene stops between commits and keeps what it finished, each
    /// with its receipt; a cancel before the first commit changes nothing.
    @Test func aCancelledStarterSceneKeepsWhatItFinished() async throws {
        let lab = try await QualifiedLab.seeded()
        let operations = try TabletopPlanner(kit: kit, anchors: [], tracking: .virtualScene).setOutStarter()
        let task = Task {
            var committed = 0
            return try await SequentialRun.perform(operations) { operation throws(TabletopError) in
                let receipt = try await lab.commit(operation)
                committed += 1
                if committed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
                return receipt
            }
        }
        await #expect(throws: TabletopError.cancelled(completed: 1)) { try await task.value }
        #expect(try await lab.anchors().map(\.title.value) == ["Windmill"])
        #expect(TabletopError.cancelled(completed: 1).message == "Stopped after 1 of the changes. Each one has its receipt.")

        let before = await lab.snapshot()
        let early = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SequentialRun.perform(operations) { operation throws(TabletopError) in try await lab.commit(operation) }
        }
        await #expect(throws: TabletopError.cancelled(completed: 0)) { try await early.value }
        #expect(await lab.snapshot() == before)
        #expect(TabletopError.cancelled(completed: 0).message == "Stopped. Nothing was changed.")
    }
}

// MARK: - Support

/// The repository's fixtures, read from the checkout.
enum TabletopFixtures {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent() // TabletopRealityTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LabFeatures
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository
        .appending(path: "Fixtures", directoryHint: .isDirectory)
    static let showcase = root.appending(path: "showcase/tabletop-reality", directoryHint: .isDirectory)

    /// `Fixtures/demo/seed.json`, the seed the app commits on its first run.
    static func demoSeed() throws -> DemoSeed {
        struct File: Decodable {
            struct Collection: Decodable { let id: UUID; let title: String }
            struct Item: Decodable { let id: UUID; let collection: UUID; let title: String; let note: String }
            let seedVersion: Int
            let collections: [Collection]
            let items: [Item]
        }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: root.appending(path: "demo/seed.json")))
        return try DemoSeed(
            version: file.seedVersion,
            collections: try file.collections.map { CollectionDraft(id: CollectionID(rawValue: $0.id), title: try EntityTitle($0.title)) },
            items: try file.items.map {
                ItemDraft(id: ItemID(rawValue: $0.id), in: CollectionID(rawValue: $0.collection),
                          title: try EntityTitle($0.title), note: try ItemNote($0.note))
            }
        )
    }
}

/// One step of `Fixtures/showcase/tabletop-reality/script.json`, with the operation it states.
struct ShowcaseStep {
    let id: String
    let approves: String?
    let operation: DomainOperation?
    let operationKind: OperationKind?

    static func load() throws -> [ShowcaseStep] {
        let data = try Data(contentsOf: TabletopFixtures.showcase.appending(path: "script.json"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let steps = try #require(object["steps"] as? [[String: Any]])
        return try steps.map(Self.init)
    }

    init(_ step: [String: Any]) throws {
        id = try need(step["id"] as? String)
        approves = step["approve"] as? String
        func uuid(_ value: Any?) throws -> UUID { try need((value as? String).flatMap(UUID.init(uuidString:))) }
        func pose(_ entry: [String: Any]) throws -> AnchorPose {
            try AnchorPose(x: try need(entry["x"] as? Int), y: entry["y"] as? Int ?? 0, z: try need(entry["z"] as? Int),
                           yaw: try need(entry["yaw"] as? Int))
        }
        if let entry = step["placeAnchor"] as? [String: Any] {
            operation = .placeAnchor(draft: AnchorDraft(
                id: AnchorID(rawValue: try uuid(entry["id"])), fixture: try FixtureKey(try need(entry["fixture"] as? String)),
                title: try EntityTitle(try need(entry["title"] as? String)), pose: try pose(entry)
            ))
        } else if let entry = step["moveAnchor"] as? [String: Any] {
            operation = .moveAnchor(id: AnchorID(rawValue: try uuid(entry["id"])),
                                    expected: try need(Revision(rawValue: try need(entry["expected"] as? Int))), pose: try pose(entry))
        } else if let entry = step["removeAnchor"] as? [String: Any] {
            operation = .removeAnchor(id: AnchorID(rawValue: try uuid(entry["id"])),
                                      expected: try need(Revision(rawValue: try need(entry["expected"] as? Int))))
        } else if let entry = step["createCollection"] as? [String: Any] {
            operation = .createCollection(draft: CollectionDraft(
                id: CollectionID(rawValue: try uuid(entry["id"])), title: try EntityTitle(try need(entry["title"] as? String))
            ))
        } else if let entry = step["createItem"] as? [String: Any] {
            operation = .createItem(draft: ItemDraft(
                id: ItemID(rawValue: try uuid(entry["id"])), in: CollectionID(rawValue: try uuid(entry["collection"])),
                title: try EntityTitle(try need(entry["title"] as? String)), note: try ItemNote(entry["note"] as? String ?? "")
            ))
        } else {
            operation = nil
        }
        if step["resetDemo"] != nil {
            operationKind = .resetDemo
        } else if step["undo"] != nil {
            // The undo of a removal is a placement, which needs no grant.
            operationKind = .placeAnchor
        } else {
            operationKind = operation?.kind
        }
    }
}

/// A missing or mistyped field in the showcase script.
struct ShowcaseFieldMissing: Error {}

private func need<Value>(_ value: Value?) throws -> Value {
    guard let value else { throw ShowcaseFieldMissing() }
    return value
}

/// An in-memory lab with the host's rules: `OperationService` over `GrantAuthorizationPolicy`, and
/// a grant issued only for a person's press, for exactly the operation, as `LabDataService` does.
struct QualifiedLab {
    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    let store = InMemoryOperationStore()
    let ledger = GrantLedger()
    let service: OperationService

    init() {
        service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
    }

    /// A lab after the host's first run: Reset Demo with the app's seed.
    static func seeded() async throws -> QualifiedLab {
        let lab = QualifiedLab()
        try await lab.commit(.resetDemo(seed: try TabletopFixtures.demoSeed()))
        return lab
    }

    @discardableResult
    func commit(_ operation: DomainOperation, requestID: RequestID = RequestID()) async throws(TabletopError) -> ActionReceipt {
        var grant: GrantID?
        if GrantRequirement.sensitiveCommits.requiresGrant(operation.kind, from: .appUI) {
            grant = try? ledger.issue(for: operation, to: .appUI, lifetime: .seconds(30)).id
        }
        defer { if let grant { ledger.revoke(grant) } }
        do {
            return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: Self.appUI))
        } catch {
            throw .refused(error)
        }
    }

    func anchors() async throws -> [LabAnchor] { try await service.findAnchors(as: Self.appUI) }

    /// Everything the store holds, ordered by ID, to compare before and after.
    func snapshot() async -> String {
        func sorted<T>(_ values: [T], _ key: (T) -> UUID) -> [T] { values.sorted { key($0).uuidString < key($1).uuidString } }
        let collections = sorted(await store.collections()) { $0.id.rawValue }
        let items = sorted(await store.items(in: nil)) { $0.id.rawValue }
        let anchors = sorted(await store.anchors()) { $0.id.rawValue }
        return "\(collections)\n\(items)\n\(anchors)"
    }

    func userItems() async throws -> [LabItem] {
        let filter = try ItemFilter(includeArchived: true, limit: ItemFilter.allowedLimits.upperBound)
        return try await service.findItems(filter, as: Self.appUI).filter { $0.namespace == .user }
    }
}
