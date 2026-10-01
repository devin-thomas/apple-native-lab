import Foundation
import ScreeningRoom
import ScreeningRoomPlayback
import Testing
@testable import NativeLabTV

/// LAB-031 inside the built Apple TV app: the clips are in its bundle, the test card opens in the
/// tvOS player, and the unplayable clips fail with their real errors. Uses a temporary folder for
/// the resume point and observes no audio session.
@MainActor
@Suite(.serialized) struct ScreeningRoomTVTests {
    @Test func theAppleTVAppCarriesAndPlaysTheTestCard() async throws {
        for clip in ScreeningClips.all {
            let url = try #require(BundledClips.url(for: clip), "\(clip.fileName) is not in the app")
            #expect(url.path.hasPrefix(Bundle.main.bundlePath))
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: "ScreeningRoomTVTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = ScreeningRoomModel(store: FileResumePointStore(folder: folder), integratesWithSystem: false)
        await model.start()
        #expect(model.phase == .ready)
        #expect(model.readiness.platform == "tvOS")
        await model.perform(.selectCaption(.track("es")))
        await model.perform(.present(.theater))
        model.surfaceDidChange(to: .pictureInPicture)
        model.surfaceDidChange(to: .theater)
        await model.perform(.present(.inline))
        #expect(model.player.selectedCaption == .track("es"))

        await model.open(ScreeningClips.unknownCodec)
        #expect(model.phase == .failed(.unsupportedCodec(codes: ["lab0"])))
        await model.open(ScreeningClips.truncated)
        #expect(model.phase == .failed(.unreadable(code: -11829)))
        model.invalidate()
    }

    @Test func theResumePointLivesInCaches() {
        #expect(TVScreening.resumeFolder.lastPathComponent == "ScreeningRoom")
        #expect(TVScreening.resumeFolder.deletingLastPathComponent().lastPathComponent == "Caches")
        // LAB-019 Local Constellation is the other module this Apple TV build runs.
        #expect(TVHost.runnableExperiments == [ScreeningRoom.experimentID, "LAB-019"])
    }
}
