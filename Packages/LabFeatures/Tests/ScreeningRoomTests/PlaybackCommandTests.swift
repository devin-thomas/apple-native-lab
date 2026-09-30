import Foundation
import LabDomain
@testable import ScreeningRoom
import Testing

/// LAB-031: every command is answered once per request ID with a receipt, raises the revision
/// when it changes something, and refuses invalid input without changing or recording anything.
@Suite struct PlaybackCommandTests {
    @Test func openingAndPlayingGiveReceiptsWithRevisionsAndUndo() throws {
        var session = ScreeningSession()
        let opened = try session.run(.open(ScreeningClips.testCard.id))
        #expect(opened.status == .applied)
        #expect(opened.previous == .r(1) && opened.revision == .r(2))
        #expect(opened.summary == "Opened Test Card at the start, captions off.")
        #expect(opened.adapter == .appUI && opened.source == .controls)
        #expect(session.state.clip == ScreeningClips.testCard.id)
        #expect(session.state.duration == 10)

        let played = try session.run(.play)
        #expect(played.status == .applied)
        #expect(played.undo == .pause)
        #expect(played.summary == "Played Test Card from 0:00.")
        #expect(session.state.isPlaying)

        let again = try session.run(.play)
        #expect(again.status == .unchanged)
        #expect(again.revision == played.revision)
        #expect(again.summary == "Already playing.")

        let undone = try session.run(try #require(played.undo))
        #expect(undone.status == .applied)
        #expect(!session.state.isPlaying)
        #expect(session.receipts.map(\.requestID) == [opened, played, again, undone].map(\.requestID))
    }

    @Test func seekingClampsToTheClipAndUndoesToTheOldPosition() throws {
        var session = try ScreeningSession.withTestCard()
        let forward = try session.run(.seek(to: 4.5))
        #expect(session.state.position == 4.5)
        #expect(forward.undo == .seek(to: 0))
        #expect(forward.summary == "Moved Test Card from 0:00 to 0:04.")

        try session.run(.skip(by: ScreeningRoom.skipInterval))
        #expect(session.state.position == 10, "a skip past the end stops at the end")
        try session.run(.skip(by: -100))
        #expect(session.state.position == 0)
        try session.run(.seek(to: -3))
        #expect(session.state.position == 0)
    }

    @Test func invalidInputIsRefusedAndNothingIsRecorded() throws {
        var session = try ScreeningSession.withTestCard()
        let before = session.state
        let receipts = session.receipts.count

        #expect(throws: ScreeningError.invalidTime) { try session.run(.seek(to: .nan)) }
        #expect(throws: ScreeningError.invalidTime) { try session.run(.skip(by: .infinity)) }
        #expect(throws: ScreeningError.unknownCaption("fr")) { try session.run(.selectCaption(.track("fr"))) }
        #expect(throws: ScreeningError.unknownClip(MediaAssetID("elsewhere"))) { try session.run(.open(MediaAssetID("elsewhere"))) }
        #expect(throws: ScreeningError.surfaceNotRequestable(.pictureInPicture)) { try session.run(.present(.pictureInPicture)) }
        #expect(throws: ScreeningError.surfaceNotRequestable(.external)) { try session.run(.present(.external)) }

        #expect(session.state == before)
        #expect(session.receipts.count == receipts)
    }

    @Test func nothingPlaysBeforeAClipIsOpen() {
        var session = ScreeningSession()
        #expect(throws: ScreeningError.noClip) { try session.run(.play) }
        #expect(throws: ScreeningError.noClip) { try session.run(.selectCaption(.off)) }
        #expect(session.receipts.isEmpty)
        #expect(session.state.summary == "No clip open")
    }

    @Test func aHostWithoutATheaterCannotBeAskedForOne() throws {
        var session = try ScreeningSession.withTestCard(requestableSurfaces: [.inline])
        #expect(throws: ScreeningError.surfaceNotRequestable(.theater)) { try session.run(.present(.theater)) }
        // A system surface can never be made requestable by a host.
        let generous = ScreeningSession(requestableSurfaces: Set(PlaybackSurface.allCases))
        #expect(generous.requestableSurfaces == [.inline, .theater])
    }

    @Test func aRetryReturnsTheSameReceiptAndAReusedIDIsRefused() throws {
        var session = try ScreeningSession.withTestCard()
        let id = RequestID()
        let first = try session.submit(.local(.play, id: id))
        try session.run(.pause)
        let retry = try session.submit(.local(.play, id: id))
        #expect(retry == first, "a retry answers with the original receipt")
        #expect(!session.state.isPlaying, "and does not play again")

        #expect(throws: ScreeningError.requestIDReused(id)) { try session.submit(.local(.pause, id: id)) }
    }

    @Test func aStaleCommandConflictsAndChangesNothing() throws {
        var session = try ScreeningSession.withTestCard()
        let seen = session.state.revision
        try session.run(.play)
        let stale = PlaybackRequest(command: .seek(to: 8), actor: appControls, source: .companion, expected: seen)
        let receipt = try session.submit(stale)
        #expect(receipt.status == .conflict(expected: seen, current: session.state.revision))
        #expect(!receipt.didChange)
        #expect(session.state.position == 0)
        #expect(try session.submit(stale) == receipt, "the conflict is recorded, so a retry gets the same answer")

        let current = PlaybackRequest(command: .seek(to: 8), actor: appControls, source: .companion, expected: session.state.revision)
        #expect(try session.submit(current).status == .applied)
        #expect(session.state.position == 8)
    }

    @Test func playingFromTheEndStartsOver() throws {
        var session = try ScreeningSession.withTestCard()
        try session.run(.seek(to: 10))
        try session.run(.play)
        #expect(session.state.position == 0)
        #expect(session.state.isPlaying)
    }

    @Test func aFailedClipRefusesPlaybackButCanBeReplaced() throws {
        var session = ScreeningSession()
        try session.run(.open(ScreeningClips.unknownCodec.id))
        session.observe(.failed(.unsupportedCodec(codes: ["lab0"])))
        #expect(throws: ScreeningError.clipUnavailable(.unsupportedCodec(codes: ["lab0"]))) { try session.run(.play) }
        #expect(session.resumePoint == nil, "a clip that failed is never saved to come back to")
        #expect(session.state.summary == "Unknown Codec: Format not supported")

        try session.run(.open(ScreeningClips.testCard.id))
        #expect(session.state.failure == nil)
        #expect(try session.run(.play).status == .applied)
    }

    @Test func forgettingTheResumePointReturnsToTheStart() throws {
        var session = try ScreeningSession.withTestCard()
        try session.run(.seek(to: 6))
        try session.run(.selectCaption(.track("es")))
        try session.run(.present(.theater))
        try session.run(.play)
        let reset = try session.run(.forgetResumePoint)
        #expect(reset.status == .applied)
        #expect(reset.undo == nil, "a reset is not offered as undoable")
        #expect(session.state.position == 0)
        #expect(session.state.caption == .off)
        #expect(session.state.surface == .inline)
        #expect(!session.state.isPlaying)
        #expect(session.state.clip == ScreeningClips.testCard.id)
        #expect(try session.run(.forgetResumePoint).status == .unchanged)
    }

    @Test func receiptsAreBounded() throws {
        var session = try ScreeningSession.withTestCard()
        for step in 0..<100 { try session.run(.seek(to: Double(step % 10))) }
        #expect(session.receipts.count == ScreeningSession.receiptLimit)
    }
}
