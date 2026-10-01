import CryptoKit
import Foundation
import LabDomain
import LabStore
import LabSupport
import TabletopReality
import Testing
@testable import NativeLab

/// LAB-023-B step 1 with its evidence: the complete Tabletop Reality fixture interaction in the
/// sandboxed Mac app, from clean state, through the host's own `TabletopSession`, `LabLibrary`, and
/// a fresh SQLite store: the route, the starter scene, a placement, a move, a turn, tracking loss,
/// a removal and its undo, the labeled replay, and Reset Demo beside the person's own data.
///
/// The test attaches an `EvidenceRecord` of what it observed, with the toolchain read from this
/// app bundle. To keep it, run the test with a result bundle and export the attachment:
///
///     xcodebuild … -scheme LabMac-Core -only-testing:LabMacTests/TabletopHostEvidenceTests \
///       -resultBundlePath <bundle> LAB_SOURCE_REVISION=<sha> test
///     xcrun xcresulttool export attachments --path <bundle> --output-path <folder>
@MainActor
@Suite struct TabletopHostEvidenceTests {
    static let check = "Tabletop Reality on the Mac's virtual table in the Mac host: the route, the starter scene, place, move, turn, tracking loss, remove and undo, the labeled replay, and Reset Demo beside the person's own data"

    @Test func theInteractionRunsFromCleanStateAndResetKeepsThePersonsData() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TabletopHostEvidenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let started = Date()

        var observations: [String] = []
        var differences: [String] = []
        func check(_ same: Bool, _ what: String) {
            #expect(same, "\(what)")
            if same { observations.append(what) } else { differences.append(what) }
        }

        // 1. The host's first run on a fresh store: the demo seed, an empty table, the Mac's route.
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let session = TabletopSession()
        await session.start(in: library)
        try #require(session.phase == .ready)
        let route = try #require(session.route)
        check(!route.offersLiveStart && route.summary.hasPrefix("The AR camera is not available here, so the table is virtual."),
              "the Mac routes to the virtual table and says why")
        check(session.tracking == .virtualScene && session.anchors.isEmpty && session.entries.map(\.label) == ["Oak table"],
              "the table starts empty, with only the table in the list")

        // 2. The person's own collection and item, which nothing on the table may touch.
        let mine = CollectionID()
        let sketch = ItemID()
        _ = try await library.submit(.createCollection(draft: CollectionDraft(id: mine, title: try EntityTitle("Field notes"))),
                                     requestID: RequestID(), authority: .userAction, names: [:])
        _ = try await library.submit(.createItem(draft: ItemDraft(id: sketch, in: mine, title: try EntityTitle("Table sketch"), note: try ItemNote("Kept."))),
                                     requestID: RequestID(), authority: .userAction, names: [:])
        let personsItem = try #require(await Self.item(sketch, in: library))

        // 3. Set Out Starter Scene: four receipts, four objects, five rows in the list.
        let before = library.receipts.count
        session.setOutStarter(in: library)
        try await Self.waitUntil { !session.isRunningList }
        check(session.anchors.map(\.title.value) == ["Cottage", "Lantern", "Pine Tree", "Windmill"], "the starter scene sets out four objects")
        check(library.receipts.count == before + 4 && library.receipts.prefix(4).allSatisfy { $0.receipt.admitted.adapter == .appUI },
              "one app-UI receipt per object")
        check(session.entries.count == 5, "the list names the table and the four objects")

        // 4. A click on the table, Move Left, Turn Left: three receipts naming the Lighthouse.
        session.fixtureToPlace = try FixtureKey("lighthouse")
        let placed = await session.place(atX: 300, z: -200, in: library)
        let lighthouse = try #require(session.selectedAnchor)
        let tapped = try AnchorPose(x: 300, z: -200)
        check(placed?.receipt.summary == "Placed “Lighthouse”." && lighthouse.pose == tapped,
              "a click at (300, -200) places and selects the Lighthouse there")
        let moved = await session.nudge(.left, in: library)
        let turned = await session.turn(clockwise: false, in: library)
        check(moved?.receipt.summary == "Moved “Lighthouse”." && turned?.receipt.summary == "Turned “Lighthouse”.",
              "Move Left and Turn Left each commit with a receipt")
        check(session.entry(for: lighthouse.id)?.value == "28 cm right of center, 20 cm away from you, facing you, turned 15°",
              "the list reads the Lighthouse's place and heading in words")

        // 5. Tracking loss: no placing, moving, or turning; removing still works, with an undo.
        let beforeLoss = library.receipts.count
        let anchorsBeforeLoss = session.anchors
        session.liveTrackingChanged(.limited(.relocalizing))
        let refusedPlace = await session.placeAtFreeSpot(in: library)
        let refusedMove = await session.nudge(.right, in: library)
        let refusedTurn = await session.turn(clockwise: true, in: library)
        check(refusedPlace == nil && refusedMove == nil && refusedTurn == nil && library.receipts.count == beforeLoss
              && session.anchors == anchorsBeforeLoss,
              "while relocalizing, place, move, and turn commit nothing")
        check(session.message == "Finding the table again. Placing, moving, and turning wait until tracking is normal. Nothing was changed.",
              "the refusal says why in a sentence")
        let removed = try #require(await session.remove(in: library))
        check(removed.receipt.removed == [.anchor(lighthouse.id)] && ReceiptPresentation(removed).removals.first?.name == "Lighthouse",
              "removing still works while relocalizing, and the receipt names the object")
        session.liveEnded()
        _ = try #require(await library.undo(removed))
        await session.refresh(in: library)
        let restoredPose = try AnchorPose(x: 280, z: -200, yaw: 15)
        check(session.anchors.first { $0.id == lighthouse.id }?.pose == restoredPose,
              "the removal's undo puts the Lighthouse back where it was, facing where it faced")

        // 6. The labeled replay pauses placing, and the virtual table comes back when it stops.
        session.startReplay()
        check(session.trackingSource == .replay && session.message?.contains("This is a recorded sequence, not a camera.") == true,
              "the replay is labeled as a recording")
        try await Self.waitUntil { session.tracking == .limited(.initializing) }
        let duringReplay = await session.placeAtFreeSpot(in: library)
        check(duringReplay == nil, "placing is refused while the replay's tracking is limited")
        session.stopReplay()
        check(session.trackingSource == .virtualScene && session.tracking == .virtualScene, "stopping the replay returns the virtual table")

        // 7. Reset Demo removes the five objects and nothing of the person's.
        let reset = try #require(await library.resetDemo())
        await session.refresh(in: library)
        check(reset.receipt.removed.count == 5 && reset.receipt.removed.allSatisfy { $0.kind == .anchor },
              "Reset Demo removes exactly the five lab-owned anchors")
        check(session.anchors.isEmpty && session.entries.map(\.label) == ["Oak table"], "the table is empty again")
        check(await Self.item(sketch, in: library) == personsItem, "the person's item is unchanged")

        // 8. Read the store directly.
        let store = try await SQLiteOperationStore(url: storeURL)
        let anchorRows = try await store.anchors()
        let items = try await store.items(in: nil)
        check(anchorRows.isEmpty, "the store holds no anchor")
        check(items.filter { $0.namespace == .user } == [personsItem], "the store holds the person's one item, unchanged")
        let demoItems = items.filter { $0.namespace == .demo }.count
        check(demoItems == 12, "the store holds the 12 demo samples")
        check(try await store.receipt(for: reset.receipt.requestID)?.status == .committed, "the store holds Reset Demo's receipt")
        let anchorReceipts = library.receipts.filter { $0.receipt.affectedEntities.contains { $0.kind == .anchor } }.count

        let seedBytes = try Data(contentsOf: try #require(Bundle.main.url(forResource: "seed", withExtension: "json")))
        let kitBytes = try Data(contentsOf: try #require(Self.bundledKit()))
        let record = try EvidenceRecord(
            subject: "LAB-023",
            check: Self.check,
            date: started,
            provenance: .current,
            execution: .fixture,
            inputs: [
                "kit:app-bundle@sha256:\(Self.sha256(kitBytes))",
                "seed:app-bundle@sha256:\(Self.sha256(seedBytes))",
            ],
            steps: [
                "xcodebuild -scheme LabMac-Core -only-testing:LabMacTests/TabletopHostEvidenceTests test",
                "A fresh SQLite store in the app container, seeded by the host's first run (Reset Demo); the TabletopSession the window uses, as the app UI",
                "The person's own collection Field notes and item Table sketch",
                "Set Out Starter Scene; Lighthouse chosen, then a click at (300, -200) mm; Move Left (20 mm); Turn Left (15°)",
                "Tracking set to relocalizing, as the live adapter reports it: Place on Table, Move Right, Turn Right; then Remove",
                "Tracking back to the virtual table; Undo on the removal's receipt",
                "Replay Tracking Loss; Place on Table while it reports Getting ready; Stop Replay",
                "Reset Demo; the store read directly",
            ],
            outcome: differences.isEmpty
                ? .passed(observed: "All \(observations.count) checks matched. The route read “\(route.summary)” Set Out Starter Scene committed 4 app-UI receipts. A click at (300, -200) placed the Lighthouse; Move Left and Turn Left left it “28 cm right of center, 20 cm away from you, facing you, turned 15°”. While tracking was relocalizing, Place on Table, Move Right, and Turn Right committed nothing and said “Finding the table again. Placing, moving, and turning wait until tracking is normal. Nothing was changed.”; Remove committed, and its undo put the Lighthouse back at (280, -200) facing 15°. The replay was labeled “not a camera” and refused a placement while limited. Reset Demo removed exactly the 5 anchors; the person's item was unchanged. \(anchorReceipts) receipts named an anchor. The store held no anchor, 1 item of the person's own, and \(demoItems) demo items.")
                : .failed(observed: "\(differences.count) of \(observations.count + differences.count) checks failed: " + differences.joined(separator: "; ") + "."),
            limitations: [
                "Fixture path: hosted tests in the sandboxed Mac app on the development Mac, on a fresh store in the app container. It supports implemented at most.",
                "The session was driven through its methods, the ones the window's controls, shortcuts, and VoiceOver actions call. No window, pointer, keyboard, or RealityKit view took part.",
                "Tracking loss was a status set as the live adapter would set it. No camera or ARKit session ran; the live AR adapter is not built for the Mac.",
                "No physical iPhone or iPad and no iOS simulator ran in this check.",
            ]
        )
        Attachment.record(try Self.json(record), named: "LAB-023-tabletop-reality-host-interaction.json")
        #expect(record.result == .passed)
        #expect(record.provenance.xcodeBuild != "unknown" && record.provenance.sdkName.hasPrefix("macosx"))
        #expect(record.supportedState == .implemented)
    }

    // MARK: Helpers

    static func item(_ id: ItemID, in library: LabLibrary) async -> LabItem? {
        guard let service = try? await library.openedService() else { return nil }
        guard let filter = try? ItemFilter(includeArchived: true, limit: ItemFilter.allowedLimits.upperBound) else { return nil }
        return try? await service.items(filter, as: LabDataService.appUI).first { $0.id == id }
    }

    /// The kit as the app bundles it, in the TabletopReality module's resource bundle.
    static func bundledKit() -> URL? {
        guard let resources = Bundle.main.resourceURL,
              let walker = FileManager.default.enumerator(at: resources, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in walker where url.lastPathComponent == "tabletop-kit.json" {
            return url
        }
        return nil
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(condition())
    }

    private static func json(_ record: EvidenceRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return String(decoding: try encoder.encode(record), as: UTF8.self) + "\n"
    }
}
