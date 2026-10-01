import Foundation
import ScreeningRoom
import ScreeningRoomPlayback
import Testing
@testable import NativeLab

/// LAB-031 inside the built iPhone app: the clips are in its bundle, the build declares the audio
/// background mode Picture in Picture needs, and a screening plays the test card, keeps its
/// captions through the theater, and fails the two unplayable clips with their real errors. Uses
/// a temporary folder for the resume point and neither activates the audio session nor registers
/// remote commands.
@MainActor
@Suite(.serialized) struct ScreeningRoomPhoneTests {
    @Test func theIPhoneAppCarriesThePlaybackItNeeds() async throws {
        for clip in ScreeningClips.all {
            let url = try #require(BundledClips.url(for: clip), "\(clip.fileName) is not in the app")
            #expect(url.path.hasPrefix(Bundle.main.bundlePath))
        }
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        #expect(modes == ["audio"])
        #expect(ScreeningRoomHost.resumeFolder.lastPathComponent == "ScreeningRoom")

        let folder = FileManager.default.temporaryDirectory.appending(path: "ScreeningRoomPhoneTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = ScreeningRoomModel(store: FileResumePointStore(folder: folder), integratesWithSystem: false)
        await model.start()
        #expect(model.phase == .ready)
        #expect(model.readiness.platform == "iOS")
        await model.perform(.selectCaption(.track("en-sdh")))
        await model.perform(.present(.theater))
        model.surfaceDidChange(to: .fullScreen)
        model.surfaceDidChange(to: .theater)
        await model.perform(.present(.inline))
        #expect(model.player.selectedCaption == .track("en-sdh"))

        await model.open(ScreeningClips.unknownCodec)
        #expect(model.phase == .failed(.unsupportedCodec(codes: ["lab0"])))
        await model.open(ScreeningClips.truncated)
        #expect(model.phase == .failed(.unreadable(code: -11829)))
        model.invalidate()
    }
}
