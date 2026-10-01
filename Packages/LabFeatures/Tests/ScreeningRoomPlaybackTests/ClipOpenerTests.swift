import AVFoundation
import Foundation
import ScreeningRoom
@testable import ScreeningRoomPlayback
import Testing

/// LAB-031 acceptance: an unplayable clip shows a real error. These open the bundled fixtures with
/// AVFoundation itself; no failure here is simulated.
@MainActor
@Suite struct ClipOpenerTests {
    @Test func theTestCardOpensWithBothCaptionTracks() async throws {
        let opened = try await ClipOpener.open(ScreeningClips.testCard).get()
        #expect(opened.duration == 10)
        let group = try #require(opened.captionGroup)
        // The file has four legible options: each track, and a forced-only variant of each.
        #expect(group.options.count == 4)
        #expect(Set(opened.captionOptions.keys) == ["en-sdh", "es"])
        #expect(group.allowsEmptySelection, "captions can be turned off")
        #expect(group.defaultOption == nil, "neither track is on by default")
        let sdh = try #require(opened.captionOptions["en-sdh"])
        #expect(sdh.hasMediaCharacteristic(.transcribesSpokenDialogForAccessibility))
        #expect(opened.choice(for: nil) == .off)
        #expect(opened.choice(for: sdh) == .track("en-sdh"))
    }

    @Test func anUnknownCodecIsAFormatError() async {
        let result = await ClipOpener.open(ScreeningClips.unknownCodec)
        #expect(result.failure == .unsupportedCodec(codes: ["lab0"]))
        #expect(ScreeningClips.unknownCodec.expectation == .fails(.unsupportedCodec(codes: ["lab0"])))
    }

    @Test func aTruncatedFileCannotBeOpened() async {
        let result = await ClipOpener.open(ScreeningClips.truncated)
        #expect(result.failure == .unreadable(code: -11829))
    }

    @Test func aClipMissingFromTheBuildSaysSo() async {
        let absent = MediaAsset(id: MediaAssetID("absent"), title: "Absent", resourceName: "absent", fileExtension: "mov",
                                duration: nil, captions: [], expectation: .plays)
        #expect(await ClipOpener.open(absent).failure == .missingResource(name: "absent.mov"))
    }

    @Test func captionsMatchByLanguageAndSDHNotByName() {
        let clip = ScreeningClips.testCard
        typealias Facts = CaptionMatcher.Facts
        #expect(CaptionMatcher.trackID(for: Facts(languageTag: "en", isSDH: true, isForcedOnly: false), in: clip) == "en-sdh")
        #expect(CaptionMatcher.trackID(for: Facts(languageTag: "en-US", isSDH: true, isForcedOnly: false), in: clip) == "en-sdh")
        #expect(CaptionMatcher.trackID(for: Facts(languageTag: "ES", isSDH: false, isForcedOnly: false), in: clip) == "es")
        #expect(CaptionMatcher.trackID(for: Facts(languageTag: "es", isSDH: false, isForcedOnly: true), in: clip) == nil)
        #expect(CaptionMatcher.trackID(for: Facts(languageTag: "en", isSDH: false, isForcedOnly: false), in: clip) == nil)
        #expect(CaptionMatcher.trackID(for: Facts(languageTag: nil, isSDH: false, isForcedOnly: false), in: clip) == nil)
        #expect(FourCharacterCode(0x6C61_6230).text == "lab0")
        #expect(FourCharacterCode(0x0000_0001).text == "0x00000001")
    }

    @Test func audioSessionNotificationsBecomeSignals() {
        #expect(AudioSessionSignals.interruption(type: 1, options: 0) == .interruptionBegan)
        #expect(AudioSessionSignals.interruption(type: 0, options: 1) == .interruptionEnded(shouldResume: true))
        #expect(AudioSessionSignals.interruption(type: 0, options: 0) == .interruptionEnded(shouldResume: false))
        #expect(AudioSessionSignals.interruption(type: 7, options: 1) == nil)
        #expect(AudioSessionSignals.routeChange(reason: 2) == .routeChanged(.oldDeviceUnavailable))
        #expect(AudioSessionSignals.routeChange(reason: 1) == .routeChanged(.newDeviceAvailable))
        #expect(AudioSessionSignals.routeChange(reason: 3) == .routeChanged(.other))
        #if os(iOS) || os(tvOS)
        // The raw numbers are the SDK's own.
        #expect(AVAudioSession.InterruptionType.began.rawValue == 1)
        #expect(AVAudioSession.InterruptionType.ended.rawValue == 0)
        #expect(AVAudioSession.InterruptionOptions.shouldResume.rawValue == 1)
        #expect(AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue == 1)
        #expect(AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue == 2)
        #endif
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let failure) = self { failure } else { nil }
    }
}
