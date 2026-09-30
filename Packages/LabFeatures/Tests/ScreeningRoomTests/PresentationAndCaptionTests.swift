import Foundation
import LabDomain
@testable import ScreeningRoom
import Testing

/// LAB-031 acceptance: caption selection survives a presentation change, and so does the position,
/// whether the lab's controls or the platform's own buttons move the clip.
@Suite struct PresentationAndCaptionTests {
    @Test func captionsAndPositionSurviveEveryPresentationChange() throws {
        var session = try ScreeningSession.withTestCard()
        try session.run(.selectCaption(.track("en-sdh")))
        try session.run(.seek(to: 3.5))
        try session.run(.play)

        // The lab's own theater, then the platform's full screen, Picture in Picture, and AirPlay,
        // then back to the page.
        let moved = try session.run(.present(.theater))
        #expect(moved.summary == "Moved Test Card to Theater, still at 0:03.")
        #expect(moved.undo == .present(.inline))
        for surface: PlaybackSurface in [.fullScreen, .pictureInPicture, .external, .inline] {
            let before = session.state.revision
            #expect(session.observe(.surface(surface)) == true)
            #expect(session.state.surface == surface)
            #expect(session.state.revision == before.next())
            #expect(session.state.caption == .track("en-sdh"), "captions changed on the way to \(surface)")
            #expect(session.state.position == 3.5, "position changed on the way to \(surface)")
            #expect(session.state.isPlaying)
        }
        #expect(session.state.summary == "Playing at 0:03 of 0:10 · English (SDH) · In the page")
    }

    @Test func aCaptionChosenInThePlatformMenuIsKeptLikeOneChosenHere() throws {
        var session = try ScreeningSession.withTestCard()
        #expect(session.observe(.caption(.track("es"))) == true)
        #expect(session.observe(.surface(.fullScreen)) == true)
        #expect(session.state.caption == .track("es"))
        // An option this clip does not list, such as a forced-only track, is ignored.
        #expect(session.observe(.caption(.track("es-forced"))) == false)
        #expect(session.state.caption == .track("es"))
        #expect(session.observe(.caption(.track("es"))) == false, "the same caption again changes nothing")
    }

    @Test func captionChangesUndoToThePreviousChoice() throws {
        var session = try ScreeningSession.withTestCard()
        let first = try session.run(.selectCaption(.track("en-sdh")))
        #expect(first.undo == .selectCaption(.off))
        #expect(first.summary == "English (SDH) for Test Card.")
        let second = try session.run(.selectCaption(.track("es")))
        #expect(second.undo == .selectCaption(.track("en-sdh")))
        try session.run(try #require(second.undo))
        #expect(session.state.caption == .track("en-sdh"))
        #expect(try session.run(.selectCaption(.off)).summary == "Captions off for Test Card.")
    }

    @Test func leavingASystemSurfaceIsNotUndoneToIt() throws {
        var session = try ScreeningSession.withTestCard()
        session.observe(.surface(.pictureInPicture))
        let back = try session.run(.present(.inline))
        #expect(back.undo == nil, "the lab cannot start Picture in Picture, so it offers no undo into it")
    }

    @Test func theClipsCaptionIDsAreStable() {
        #expect(ScreeningClips.testCard.captions.map(\.id) == ["en-sdh", "es"])
        #expect(ScreeningClips.testCard.captions.map(\.languageTag) == ["en", "es"])
        #expect(ScreeningClips.testCard.captions.map(\.isForDeafAndHardOfHearing) == [true, false])
        #expect(ScreeningClips.unknownCodec.captions.isEmpty)
    }
}
