import Foundation
import LabDomain
import PortableObjects
import TabletopReality
import Testing
@testable import NativeLab

/// LAB-023-B step 3 in the sandboxed Mac host: two windows on one table, a stale move, a removal
/// another window already made, a cancelled Clear Table, and Reset Demo beside an imported object,
/// through `TabletopSession` and `LabLibrary` on fresh SQLite stores. Each window has its own
/// session, as `MainWindowState` gives it one.
@MainActor
@Suite struct TabletopQualificationHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "TabletopQualificationHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func library(_ name: String) async throws -> LabLibrary {
        let directory = folder.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        return library
    }

    private func window(on library: LabLibrary) async throws -> TabletopSession {
        let session = TabletopSession()
        await session.start(in: library)
        try #require(session.phase == .ready)
        return session
    }

    /// Stale state: window B still shows the Windmill where it was when window A moves it. B's move
    /// is a conflict receipt that changes nothing, and B then shows A's move.
    @Test func aMoveFromAWindowThatShowsAnOlderTableIsAConflict() async throws {
        let library = try await library("stale")
        let a = try await window(on: library)
        let b = try await window(on: library)
        a.fixtureToPlace = try FixtureKey("windmill")
        let placed = try #require(await a.placeAtFreeSpot(in: library))
        await b.refresh(in: library)
        let windmill = try #require(b.anchors.first)
        b.selectedAnchorID = windmill.id

        _ = try #require(await a.nudge(.right, in: library))
        let stale = try #require(await b.nudge(.left, in: library))
        #expect(stale.receipt.conflict?.current == Revision(rawValue: 2))
        #expect(stale.receipt.changes.isEmpty && stale.receipt.undo == nil)
        #expect(b.anchors.first?.pose == (try AnchorPose(x: 20, z: 0)), "B refreshed to A's move")
        #expect(b.selectedAnchorID == windmill.id, "the selection survives, the object is still there")
        #expect(placed.receipt.status == .committed)
    }

    /// Duplicate state: both windows press Remove on the same object. The first commits; the
    /// second is refused, says the object is gone, and clears its selection.
    @Test func twoWindowsRemovingOneObjectRemoveItOnce() async throws {
        let library = try await library("duplicate")
        let a = try await window(on: library)
        let b = try await window(on: library)
        a.fixtureToPlace = try FixtureKey("lantern")
        _ = try #require(await a.placeAtFreeSpot(in: library))
        await b.refresh(in: library)
        let lantern = try #require(b.anchors.first)
        b.selectedAnchorID = lantern.id

        let first = try #require(await a.remove(in: library))
        #expect(first.receipt.removed == [.anchor(lantern.id)])
        let receipts = library.receipts.count
        #expect(await b.remove(in: library) == nil)
        #expect(b.message == "That object is no longer on the table.")
        #expect(b.anchors.isEmpty && b.selectedAnchorID == nil)
        #expect(library.receipts.count == receipts)
    }

    /// Cancellation: Stop during Clear Table leaves every finished removal with its receipt and the
    /// rest on the table; Reset Demo afterwards removes what is left.
    @Test func stoppingClearTableKeepsWhatItFinished() async throws {
        let library = try await library("cancel")
        let session = try await window(on: library)
        session.setOutStarter(in: library)
        try await TabletopHostEvidenceTests.waitUntil { !session.isRunningList }
        #expect(session.anchors.count == 4)

        let before = library.receipts.count
        session.clearTable(in: library)
        session.cancelList()
        try await TabletopHostEvidenceTests.waitUntil { !session.isRunningList }
        let removed = library.receipts.count - before
        #expect(removed < 4, "Stop ended the run before every removal")
        #expect(session.anchors.count == 4 - removed)
        #expect(session.message == (removed == 0 ? "Stopped. Nothing was changed." : "Stopped after \(removed) of the changes. Each one has its receipt."))
        #expect(library.receipts.prefix(removed).allSatisfy { $0.receipt.admitted.operation.kind == .removeAnchor })

        let reset = try #require(await library.resetDemo())
        #expect(reset.receipt.removed.count == 4 - removed)
    }

    /// Reset without touching imported user data: an object imported through Portable Objects and
    /// a table of objects; Reset Demo removes the objects and leaves the import byte-identical.
    @Test func resetDemoLeavesAnImportedObjectAndItsDocumentAlone() async throws {
        let lab = try await PortableHostLab.make("imported", in: folder)
        await lab.session.openSample(library: lab.library)
        _ = try #require(await lab.session.commit(library: lab.library))
        let imported = try #require(lab.session.entry(PortableHostLab.sampleID)?.item)
        let document = try #require(lab.session.exportPreview(for: PortableHostLab.sampleID)).object.data

        let table = try await window(on: lab.library)
        table.setOutStarter(in: lab.library)
        try await TabletopHostEvidenceTests.waitUntil { !table.isRunningList }
        #expect(table.anchors.count == 4)

        let reset = try #require(await lab.library.resetDemo())
        #expect(reset.receipt.removed.count == 4 && reset.receipt.removed.allSatisfy { $0.kind == .anchor })
        await table.refresh(in: lab.library)
        #expect(table.anchors.isEmpty)
        await lab.session.load(lab.library)
        #expect(lab.session.entry(PortableHostLab.sampleID)?.item == imported)
        #expect(lab.session.exportPreview(for: PortableHostLab.sampleID)?.object.data == document)
    }

    /// The route names its deciding gate on the Mac, and the session never offers the camera there;
    /// the replay is refused while another source drives tracking.
    @Test func theMacNeverOffersTheCameraAndTheReplayWaitsForTheVirtualTable() async throws {
        let library = try await library("route")
        let session = try await window(on: library)
        let route = try #require(session.route)
        #expect(!route.offersLiveStart)
        #expect(route.summary.contains("iOS"), "\(route.summary)")
        session.liveTrackingChanged(.normal)
        session.startReplay()
        #expect(session.trackingSource == .live, "a replay never replaces live tracking")
        session.liveEnded()
        session.startReplay()
        #expect(session.trackingSource == .replay)
        session.stopReplay()
    }
}
