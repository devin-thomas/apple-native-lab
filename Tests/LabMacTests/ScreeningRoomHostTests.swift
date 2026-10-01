import AppKit
import CryptoKit
import Foundation
import ScreeningRoom
import ScreeningRoomPlayback
import Testing
@testable import NativeLab

/// LAB-031 in the sandboxed Mac host: the built app carries the original clips byte for byte, the
/// experiment has its window destination and menu command, and a screening in the app plays the
/// test card, keeps its captions through the theater, and resumes from its own file. Each test
/// uses a fresh folder, never the app's own resume point, and registers no remote commands.
@MainActor
@Suite(.serialized) struct ScreeningRoomHostTests {
    @Test func theBuiltAppCarriesTheOriginalClips() throws {
        let records = try BundledClips.records()
        for clip in ScreeningClips.all {
            let url = try #require(BundledClips.url(for: clip), "\(clip.fileName) is not in the app")
            #expect(url.path.hasPrefix(Bundle.main.bundlePath), "\(clip.fileName) is not inside the built app")
            let hash = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            #expect(records.first { $0.file == clip.fileName }?.sha256 == hash)
        }
    }

    @Test func theScreeningRoomHasAMenuCommandWithCommand9() throws {
        func items(_ menu: NSMenu?) -> [NSMenuItem] {
            guard let menu else { return [] }
            menu.delegate?.menuNeedsUpdate?(menu)
            menu.update()
            return menu.items.flatMap { [$0] + items($0.submenu) }
        }
        let item = try #require(items(NSApp.mainMenu).first { $0.title == ScreeningRoom.title && !$0.keyEquivalent.isEmpty })
        #expect(item.keyEquivalent == "9")
        #expect(item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == .command)
    }

    @Test func theWindowRemembersTheDestination() {
        #expect(SidebarDestination.screeningRoom.storageKey == "screening-room")
        #expect(SidebarDestination(storageKey: "screening-room") == .screeningRoom)
        #expect(SidebarDestination.screeningRoom.title == "Native Screening Room")
    }

    @Test func theResumePointLivesInTheExperimentsOwnFolder() {
        let folder = ScreeningRoomHost.resumeFolder
        #expect(folder.lastPathComponent == "ScreeningRoom")
        #expect(folder.deletingLastPathComponent().lastPathComponent == "Application Support")
    }

    @Test func aScreeningInTheAppKeepsCaptionsThroughTheTheaterAndResumes() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ScreeningRoomHostTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileResumePointStore(folder: folder)
        let model = ScreeningRoomModel(store: store, integratesWithSystem: false)
        await model.start()
        #expect(model.phase == .ready)
        #expect(model.readiness.platform == "macOS")

        await model.perform(.selectCaption(.track("en-sdh")))
        await model.perform(.seek(to: 3))
        await model.perform(.present(.theater))
        model.surfaceDidChange(to: .fullScreen)
        model.surfaceDidChange(to: .theater)
        await model.perform(.present(.inline))
        #expect(model.state.caption == .track("en-sdh"))
        #expect(model.player.selectedCaption == .track("en-sdh"))
        #expect(model.state.position == 3)
        model.invalidate()

        let reopened = ScreeningRoomModel(store: store, integratesWithSystem: false)
        await reopened.start()
        #expect(reopened.state.position == 3)
        #expect(reopened.player.selectedCaption == .track("en-sdh"))
        reopened.invalidate()
    }
}
