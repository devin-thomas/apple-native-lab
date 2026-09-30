import Foundation
import LabDomain
@testable import ScreeningRoom
import Testing

/// LAB-031 acceptance: audio interruptions and route changes leave the state right. An
/// interruption pauses and resumes only when the clip was playing and the system recommends it;
/// a lost output pauses and stays paused; the position and captions never move.
@Suite struct InterruptionAndRouteTests {
    private func playingSession() throws -> ScreeningSession {
        var session = try ScreeningSession.withTestCard()
        try session.run(.selectCaption(.track("en-sdh")))
        try session.run(.seek(to: 4))
        try session.run(.play)
        return session
    }

    @Test func anInterruptionPausesAndResumesWhenTheSystemRecommendsIt() throws {
        var session = try playingSession()
        #expect(session.observe(.interruptionBegan) == true)
        #expect(!session.state.isPlaying)
        #expect(session.state.interruption == .init(wasPlaying: true))
        #expect(session.state.summary.hasPrefix("Interrupted at 0:04"))

        #expect(session.observe(.interruptionEnded(shouldResume: true)) == true)
        #expect(session.state.isPlaying)
        #expect(session.state.interruption == nil)
        #expect(session.state.position == 4 && session.state.caption == .track("en-sdh"))
    }

    @Test func withoutARecommendationItStaysPaused() throws {
        var session = try playingSession()
        session.observe(.interruptionBegan)
        session.observe(.interruptionEnded(shouldResume: false))
        #expect(!session.state.isPlaying)
        #expect(session.state.interruption == nil)
    }

    @Test func aPausedClipIsNotStartedByTheEndOfAnInterruption() throws {
        var session = try ScreeningSession.withTestCard()
        session.observe(.interruptionBegan)
        #expect(session.state.interruption == .init(wasPlaying: false))
        session.observe(.interruptionEnded(shouldResume: true))
        #expect(!session.state.isPlaying)
    }

    @Test func thePlayersOwnPauseDuringAnInterruptionKeepsThePlanToResume() throws {
        var session = try playingSession()
        session.observe(.interruptionBegan)
        let revision = session.state.revision
        // The player reports that it stopped; the system did that for the interruption.
        #expect(session.observe(.playing(false)) == false)
        #expect(session.observe(.interruptionBegan) == false, "a second report of the same interruption changes nothing")
        #expect(session.state.revision == revision)
        session.observe(.interruptionEnded(shouldResume: true))
        #expect(session.state.isPlaying)
    }

    @Test func aPersonsPauseDuringAnInterruptionIsKept() throws {
        var session = try playingSession()
        session.observe(.interruptionBegan)
        try session.run(.pause)
        session.observe(.interruptionEnded(shouldResume: true))
        #expect(!session.state.isPlaying, "the person chose to stay paused")
    }

    @Test func playingDuringAnInterruptionEndsIt() throws {
        var session = try playingSession()
        session.observe(.interruptionBegan)
        try session.run(.play)
        #expect(session.state.interruption == nil)
        #expect(session.state.isPlaying)
        #expect(session.observe(.interruptionEnded(shouldResume: false)) == false, "an end with nothing interrupted changes nothing")
        #expect(session.state.isPlaying)
    }

    @Test func aLostOutputPausesAndStaysPaused() throws {
        var session = try playingSession()
        #expect(session.observe(.routeChanged(.oldDeviceUnavailable)) == true)
        #expect(!session.state.isPlaying)
        #expect(session.state.lastRouteChange == .oldDeviceUnavailable)
        #expect(session.state.position == 4 && session.state.caption == .track("en-sdh"))
        #expect(session.observe(.routeChanged(.oldDeviceUnavailable)) == false)
        #expect(!session.state.isPlaying)
    }

    @Test func aNewOutputKeepsPlaying() throws {
        var session = try playingSession()
        #expect(session.observe(.routeChanged(.newDeviceAvailable)) == true)
        #expect(session.state.isPlaying)
        session.observe(.routeChanged(.other))
        #expect(session.state.isPlaying)
        #expect(session.state.lastRouteChange == .other)
    }

    @Test func anOutputLostDuringAnInterruptionCancelsTheResume() throws {
        var session = try playingSession()
        session.observe(.interruptionBegan)
        session.observe(.routeChanged(.oldDeviceUnavailable))
        session.observe(.interruptionEnded(shouldResume: true))
        #expect(!session.state.isPlaying)
    }

    @Test func positionSamplesDoNotRaiseTheRevision() throws {
        var session = try playingSession()
        let revision = session.state.revision
        #expect(session.observe(.position(4.25)) == true)
        #expect(session.observe(.position(99)) == true)
        #expect(session.state.position == 10)
        #expect(session.observe(.position(.nan)) == false)
        #expect(session.state.revision == revision)
    }

    @Test func theEndOfTheClipIsReportedAsAStop() throws {
        var session = try playingSession()
        session.observe(.position(10))
        #expect(session.observe(.playing(false)) == true)
        #expect(!session.state.isPlaying)
        try session.run(.play)
        #expect(session.state.position == 0)
    }
}
