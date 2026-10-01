import Foundation
import LabDomain
import ScreeningRoom
@testable import ScreeningRoomPlayback
import Testing

/// A clean local screening with real bundled media and a file-backed resume point. System
/// events are injected; this is fixture evidence, not a physical audio or presentation run.
@MainActor
@Suite(.serialized) struct ScreeningRoomQualificationTests {
    @Test func aCleanScreeningResumesAndResetPreservesUnrelatedBytes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("screening-qualification-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let neighbor = folder.appendingPathComponent("imported-object.anlab")
        let original = Data("Original qualification sentinel. No user data.".utf8)
        try original.write(to: neighbor)
        let store = FileResumePointStore(folder: folder)
        #expect(store.load() == .none)

        let model = ScreeningRoomModel(store: store, integratesWithSystem: false)
        defer { model.invalidate() }
        await model.start()
        await model.perform(.selectCaption(.track("es")))
        await model.perform(.seek(to: 4))
        #expect(await settles { abs(model.player.currentSeconds - 4) < 0.1 })
        let item = model.player.player.currentItem
        await model.perform(.present(.theater))
        await model.perform(.present(.inline))
        #expect(model.player.player.currentItem === item)
        #expect(model.player.selectedCaption == .track("es"))
        #expect(model.state.position == 4)

        await model.perform(.play)
        model.handle(.interruptionBegan)
        await model.perform(.pause)
        model.handle(.interruptionEnded(shouldResume: true))
        #expect(!model.state.isPlaying, "the person's pause survives the interruption")
        #expect(model.player.player.rate == 0)
        #expect(model.player.selectedCaption == .track("es"))
        model.persist()
        model.invalidate()

        let resumed = ScreeningRoomModel(store: store, integratesWithSystem: false)
        defer { resumed.invalidate() }
        await resumed.start()
        #expect(resumed.phase == .ready)
        #expect(resumed.state.caption == .track("es"))
        #expect(resumed.player.selectedCaption == .track("es"))
        #expect(resumed.state.surface == .inline)
        #expect(!resumed.state.isPlaying)
        await resumed.open(ScreeningClips.unknownCodec)
        #expect(resumed.phase == .failed(.unsupportedCodec(codes: ["lab0"])))
        await resumed.open(ScreeningClips.testCard)
        #expect(resumed.phase == .ready)
        await resumed.perform(.seek(to: 3))
        await resumed.reset()
        #expect(store.load() == .none)
        #expect(resumed.state.position == 0)
        #expect(resumed.state.caption == .off)
        #expect(try Data(contentsOf: neighbor) == original)
    }
}
