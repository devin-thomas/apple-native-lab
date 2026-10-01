import Foundation
import LabDomain
import RealityKit
import TabletopReality
import Testing
@testable import NativeLab

/// LAB-023 in the sandboxed Mac host: the virtual table's session changes lab-owned anchors only
/// through `LabLibrary`, `LabDataService`, and the one `OperationService`, with receipts in the
/// library's list; tracking loss suspends precision interactions; Reset Demo removes only
/// anchors and demo samples; and the RealityKit scene mirrors the store. Each test uses a fresh
/// store, never the app's own.
@MainActor
@Suite struct TabletopHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "TabletopHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func started() async throws -> (LabLibrary, TabletopSession) {
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let session = TabletopSession()
        await session.start(in: library)
        try #require(session.phase == .ready)
        return (library, session)
    }

    @Test func theMacRoutesToTheVirtualTableAndSaysWhy() async throws {
        let (_, session) = try await started()
        let route = try #require(session.route)
        #expect(!route.offersLiveStart)
        #expect(route.summary.contains("The AR camera is not available here"))
        #expect(session.tracking == .virtualScene)
        #expect(session.anchors.isEmpty)
        #expect(session.entries.map(\.label) == ["Oak table"])
    }

    @Test func everyChangeIsOneAppUIReceiptInTheLibrarysList() async throws {
        let (library, session) = try await started()
        let before = library.receipts.count

        session.setOutStarter(in: library)
        try await waitUntil { !session.isRunningList }
        #expect(session.anchors.map(\.title.value) == ["Cottage", "Lantern", "Pine Tree", "Windmill"])
        #expect(library.receipts.count == before + 4)
        #expect(library.receipts.prefix(4).allSatisfy { $0.receipt.admitted.adapter == .appUI })
        #expect(session.entries.count == 5)

        // A tap on the table places the chosen object there, and selects it.
        session.fixtureToPlace = try FixtureKey("lighthouse")
        let placed = try #require(await session.place(atX: 300, z: -200, in: library))
        #expect(placed.receipt.summary == "Placed “Lighthouse”.")
        let lighthouse = try #require(session.selectedAnchor)
        #expect(lighthouse.pose == (try AnchorPose(x: 300, z: -200)))

        let moved = try #require(await session.nudge(.left, in: library))
        #expect(moved.receipt.summary == "Moved “Lighthouse”.")
        let turned = try #require(await session.turn(clockwise: false, in: library))
        #expect(turned.receipt.summary == "Turned “Lighthouse”.")
        #expect(session.selectedAnchor?.pose == (try AnchorPose(x: 280, z: -200, yaw: 15)))

        // Removing is destructive: the host issues its grant for exactly this removal.
        let removed = try #require(await session.remove(in: library))
        #expect(removed.receipt.removed == [.anchor(lighthouse.id)])
        #expect(ReceiptPresentation(removed).removals.first?.name == "Lighthouse")
        #expect(session.selectedAnchorID == nil)

        // Its receipt's undo places the same object again, where it was.
        _ = try #require(await library.undo(removed))
        await session.refresh(in: library)
        #expect(session.anchors.first { $0.id == lighthouse.id }?.pose == (try AnchorPose(x: 280, z: -200, yaw: 15)))
    }

    @Test func trackingLossSuspendsPrecisionInteractionsButNotRemoval() async throws {
        let (library, session) = try await started()
        _ = try #require(await session.placeAtFreeSpot(in: library))
        let receipts = library.receipts.count

        session.liveTrackingChanged(.limited(.excessiveMotion))
        #expect(session.availability(of: .place, in: library).allowed == false)
        #expect(await session.placeAtFreeSpot(in: library) == nil)
        #expect(await session.nudge(.right, in: library) == nil)
        #expect(await session.turn(clockwise: true, in: library) == nil)
        #expect(session.message?.hasPrefix("Moving too fast.") == true)
        #expect(library.receipts.count == receipts)

        // Removing does not depend on a precise pose.
        #expect(await session.remove(in: library) != nil)
        #expect(session.anchors.isEmpty)

        session.liveEnded()
        #expect(session.tracking == .virtualScene)
        #expect(session.availability(of: .place, in: library).allowed)
    }

    @Test func theReplayIsLabeledAndSuspendsPlacingWhileTrackingIsLost() async throws {
        let (library, session) = try await started()
        session.startReplay()
        #expect(session.trackingSource == .replay)
        #expect(session.message?.contains("not a camera") == true)
        try await waitUntil { session.tracking == .limited(.initializing) }
        #expect(await session.placeAtFreeSpot(in: library) == nil)
        session.stopReplay()
        #expect(session.trackingSource == .virtualScene && session.tracking == .virtualScene)
        #expect(await session.placeAtFreeSpot(in: library) != nil)
    }

    @Test func resetDemoRemovesOnlyTheLabsAnchorsAndDemoSamples() async throws {
        let (library, session) = try await started()
        session.setOutStarter(in: library)
        try await waitUntil { !session.isRunningList }
        #expect(session.anchors.count == 4)
        let collections = library.collections.map(\.collection.id)

        let reset = try #require(await library.resetDemo())
        #expect(reset.receipt.removed.allSatisfy { $0.kind == .anchor })
        #expect(reset.receipt.removed.count == 4)
        await session.refresh(in: library)
        #expect(session.anchors.isEmpty)
        #expect(library.collections.map(\.collection.id) == collections)
    }

    @Test func theSceneHasOneEntityPerAnchorAndMarksOnlyTheSelection() async throws {
        let (library, session) = try await started()
        session.setOutStarter(in: library)
        try await waitUntil { !session.isRunningList }
        let kit = try #require(session.kit)
        let controller = TabletopSceneController()
        controller.build(kit: kit, drawsTable: true)
        let selected = try #require(session.anchors.first)
        controller.sync(kit: kit, anchors: session.anchors, selection: selected.id)

        let objects = controller.root.children.filter { $0.name.hasPrefix(TabletopSceneController.objectPrefix) }
        #expect(objects.count == 4)
        for object in objects {
            let id = try #require(TabletopSceneController.anchorID(of: object))
            let part = try #require(object.children.first)
            #expect(TabletopSceneController.anchorID(of: part) == id)
            #expect(object.components.has(CollisionComponent.self) && object.components.has(InputTargetComponent.self))
            #expect(object.findEntity(named: "selection")?.isEnabled == (id == selected.id))
            let anchor = try #require(session.anchors.first { $0.id == id })
            #expect(abs(object.position.x - Float(anchor.pose.x) / 1_000) < 0.0001)
        }
        let table = try #require(controller.root.findEntity(named: TabletopSceneController.tableName))
        #expect(TabletopSceneController.isTable(table))
        let point = controller.tablePoint(fromScene: [0.1234, 0, -0.05])
        #expect(point.x == 123 && point.z == -50)

        // Removing an anchor removes its entity.
        controller.sync(kit: kit, anchors: Array(session.anchors.dropFirst()), selection: nil)
        #expect(controller.root.children.filter { $0.name.hasPrefix(TabletopSceneController.objectPrefix) }.count == 3)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(condition())
    }
}
