import Foundation
import LabDomain
import LabSupport
import PointInspect
import Testing
@testable import NativeLab

/// Simulator session replay on a fresh local store; no picker, camera, or touch interaction.
@MainActor
@Suite struct PointInspectQualificationPhoneTests {
    @Test func fixtureFieldsCommitAndResetPreservesTheRecord() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PointInspectQualification-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = LabLibrary(locateStore: { folder.appending(path: LabStoreLocation.fileName) })
        await library.start()
        try #require(library.phase == .ready)
        let session = PointInspectSession()
        session.prepare(library: library)
        session.replayFixture()
        #expect(session.status.contains("Fixture replay"))
        let fixtureURL = try #require(Bundle.main.url(forResource: "swatch-card", withExtension: "png"))
        let image = try SelectedImage(data: Data(contentsOf: fixtureURL), origin: .fixtureReplay)
        print("LAB-012 bundled image: \(image.evidence.byteCount) bytes, SHA-256 \(image.evidence.digest)")
        let before = library.receipts.count
        session.title = "Original swatch"
        session.body = "Green and blue, typed by the reviewer"
        await session.useFields()
        #expect(session.badge == "Manual fields (not a model)")
        #expect(library.receipts.count == before)
        await session.apply()
        #expect(session.status.hasPrefix("Saved in Inspections"))
        #expect(library.receipts.count == before + 2)
        print("LAB-012 simulator host: \(DeviceSnapshot.current.platform) \(DeviceSnapshot.current.modelIdentifier) \(ProcessInfo.processInfo.operatingSystemVersionString), SDK \(BuildProvenance.current.sdkName)")
        let service = try await library.openedService()
        let filter = try ItemFilter(collectionID: PointInspect.collectionID, includeArchived: false, limit: 20)
        let saved = try await service.items(filter, as: LabDataService.appUI)
        try #require(saved.count == 1)
        #expect(saved[0].namespace == .user)
        #expect(saved[0].note.value.contains(image.evidence.digest))
        #expect(await library.resetDemo() != nil)
        let after = try await service.items(filter, as: LabDataService.appUI)
        #expect(after == saved)
    }
}
