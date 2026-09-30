import AVFoundation
import Foundation
import LabDomain
import ScreeningRoom
@testable import ScreeningRoomPlayback
import Testing

/// LAB-031: the model drives a real `AVPlayer` over the bundled test card. The session decides;
/// the player follows. Signals are delivered as the audio session and the player views deliver
/// them, so these prove the rules and the player together, not the system's own notifications.
@MainActor
@Suite(.serialized) struct ScreeningRoomModelTests {
    private func startedModel(_ store: any ResumePointStore = MemoryResumePointStore()) async -> ScreeningRoomModel {
        let model = ScreeningRoomModel(store: store, integratesWithSystem: false)
        await model.start()
        return model
    }

    @Test func theFirstRunOpensTheTestCardInThePlayer() async throws {
        let model = await startedModel()
        #expect(model.phase == .ready)
        #expect(model.state.clip == ScreeningClips.testCard.id)
        #expect(model.state.duration == 10)
        #expect(model.player.player.currentItem != nil)
        #expect(model.receipts.first?.command == .open(ScreeningClips.testCard.id))
        #expect(model.player.selectedCaption == .off)
    }

    @Test func captionSelectionSurvivesEveryPresentationChangeInThePlayerItself() async throws {
        let model = await startedModel()
        await model.perform(.selectCaption(.track("es")))
        #expect(model.player.selectedCaption == .track("es"))
        let item = model.player.player.currentItem

        await model.perform(.present(.theater))
        for surface: PlaybackSurface in [.fullScreen, .pictureInPicture, .theater, .inline] {
            model.surfaceDidChange(to: surface)
            #expect(model.state.surface == surface)
            #expect(model.state.caption == .track("es"))
            #expect(model.player.selectedCaption == .track("es"), "the player lost the caption on the way to \(surface)")
        }
        #expect(model.player.player.currentItem === item, "no presentation change reloads the item")
    }

    @Test func aCaptionChosenInTheSystemMenuReachesTheSession() async throws {
        let model = await startedModel()
        let opened = try #require(model.player.opened)
        let item = try #require(model.player.player.currentItem)
        item.select(opened.captionOptions["en-sdh"], in: try #require(opened.captionGroup))
        // The system menu posts this notification; the player turns it into a signal.
        let deadline = Date.now.addingTimeInterval(2)
        while model.state.caption != .track("en-sdh"), Date.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.state.caption == .track("en-sdh"))
    }

    @Test func theScreeningResumesAtTheSamePositionAndCaptions() async throws {
        let store = MemoryResumePointStore()
        let first = await startedModel(store)
        await first.perform(.seek(to: 6))
        await first.perform(.selectCaption(.track("en-sdh")))
        await first.perform(.present(.theater))
        first.invalidate()

        let second = await startedModel(store)
        #expect(second.state.position == 6)
        #expect(second.state.caption == .track("en-sdh"))
        #expect(second.state.surface == .inline)
        #expect(second.player.selectedCaption == .track("en-sdh"))
        #expect(await settles { abs(second.player.currentSeconds - 6) < 0.1 })
        #expect(second.notice == .init(message: "Resumed Test Card at 0:06 with English (SDH).", isProblem: false))
    }

    @Test func anInterruptionPausesThePlayerAndItsEndResumesIt() async throws {
        let model = await startedModel()
        await model.perform(.selectCaption(.track("es")))
        await model.perform(.play)
        #expect(model.player.player.rate != 0)

        // The player reports the system's pause with its interruption reason.
        model.player.rateChanged(reason: .audioSessionInterrupted)
        #expect(model.state.interruption == .init(wasPlaying: true))
        #expect(model.player.player.rate == 0)

        model.handle(AudioSessionSignals.interruption(type: 0, options: 1)!)
        #expect(model.state.isPlaying)
        #expect(model.player.player.rate != 0)
        #expect(model.player.selectedCaption == .track("es"))
        model.invalidate()
    }

    @Test func aLostOutputPausesAndStaysPaused() async throws {
        let model = await startedModel()
        await model.perform(.play)
        model.handle(AudioSessionSignals.routeChange(reason: 2))
        #expect(!model.state.isPlaying)
        #expect(model.player.player.rate == 0)
        #expect(model.state.lastRouteChange == .oldDeviceUnavailable)
        model.handle(AudioSessionSignals.routeChange(reason: 1))
        #expect(model.player.player.rate == 0, "a new output does not start playback")
    }

    @Test func anUnplayableClipShowsItsErrorAndTheTestCardStillPlays() async throws {
        let model = await startedModel()
        await model.open(ScreeningClips.unknownCodec)
        #expect(model.phase == .failed(.unsupportedCodec(codes: ["lab0"])))
        #expect(model.player.player.currentItem == nil, "nothing is handed to the player")
        #expect(await model.perform(.play) == nil)
        #expect(model.notice?.isProblem == true)
        #expect(model.notice?.message.contains("No decoder on this device supports this clip's format (lab0)") == true)

        await model.open(ScreeningClips.truncated)
        #expect(model.phase == .failed(.unreadable(code: -11829)))

        await model.open(ScreeningClips.testCard)
        #expect(model.phase == .ready)
        #expect(await model.perform(.play)?.status == .applied)
        model.invalidate()
    }

    @Test func resetRemovesOnlyTheResumePointAndReturnsToTheStart() async throws {
        let store = MemoryResumePointStore()
        let model = await startedModel(store)
        await model.perform(.seek(to: 4))
        await model.perform(.selectCaption(.track("es")))
        #expect(store.load() == .found(ResumePoint(clip: ScreeningClips.testCard.id, position: 4, caption: .track("es"))))

        await model.reset()
        #expect(store.load() == .none)
        #expect(model.state.position == 0)
        #expect(model.player.selectedCaption == .off)
        #expect(model.receipts.first?.command == .forgetResumePoint)
    }

    @Test func aDamagedResumePointIsReportedAndIgnored() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("screening-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileResumePointStore(folder: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not a resume point".utf8).write(to: store.file)

        let model = await startedModel(store)
        #expect(model.notice?.isProblem == true)
        #expect(model.state.position == 0)
        #expect(model.phase == .ready)
    }

    @Test func theCompanionLinkSteersButCannotReset() async throws {
        let model = await startedModel()
        let link = model.companionLink
        let seen = try await link.snapshot()
        let receipt = try await link.send(.skip(by: 5), requestID: RequestID(), seen: seen.revision)
        #expect(receipt.adapter == .authorizedPeer)
        #expect(receipt.source == .companion)
        #expect(await settles { abs(model.player.currentSeconds - 5) < 0.1 }, "the companion's command reached the player")

        await #expect(throws: ScreeningError.self) {
            try await link.send(.forgetResumePoint, requestID: RequestID(), seen: nil)
        }
        #expect(model.state.position == 5)
    }

    @Test func readinessNamesEveryCapabilityOnThisPlatform() {
        let readiness = PlaybackReadiness.current
        #expect(readiness.lines.map(\.title) == [
            PlaybackReadiness.playbackTitle, PlaybackReadiness.pictureInPictureTitle, PlaybackReadiness.airPlayTitle,
            PlaybackReadiness.audioSessionTitle, PlaybackReadiness.nowPlayingTitle,
        ])
        #expect(readiness.status(of: PlaybackReadiness.playbackTitle) == .available)
        #expect(readiness.requestableSurfaces == [.inline, .theater])
        #if os(macOS)
        #expect(readiness.status(of: PlaybackReadiness.audioSessionTitle) == .notApplicable)
        #endif
    }
}

/// Waits up to two seconds for an asynchronous player change, such as a seek, to land.
@MainActor
func settles(_ condition: () -> Bool) async -> Bool {
    let deadline = Date.now.addingTimeInterval(2)
    while !condition() {
        guard Date.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}
