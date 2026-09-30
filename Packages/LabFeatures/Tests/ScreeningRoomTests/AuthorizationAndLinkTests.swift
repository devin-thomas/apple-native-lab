import Foundation
import LabDomain
@testable import ScreeningRoom
import Testing

/// LAB-031: playback commands are authorized with the domain's own rules (the fixed adapter
/// ceilings, then the actor's grants), and a companion controller reaches the session only
/// through the narrow link, as an authorized peer that cannot reset.
@Suite struct AuthorizationAndLinkTests {
    @Test func aPeerCanSteerButNeverReset() throws {
        var session = try ScreeningSession.withTestCard()
        let peer = ActorScope(adapter: .authorizedPeer, grants: Set(Permission.allCases))
        let play = PlaybackRequest(command: .play, actor: peer, source: .companion)
        #expect(try session.submit(play).adapter == .authorizedPeer)

        let before = session.state
        let receipts = session.receipts.count
        let reset = PlaybackRequest(command: .forgetResumePoint, actor: peer, source: .companion)
        #expect(throws: ScreeningError.unauthorized(PlaybackDenial(adapter: .authorizedPeer, required: .commitDestructive, reason: .outsideAdapterCeiling))) {
            try session.submit(reset)
        }
        #expect(session.state == before)
        #expect(session.receipts.count == receipts, "a refused command is not recorded")
        #expect(ScreeningError.unauthorized(PlaybackDenial(adapter: .authorizedPeer, required: .commitDestructive, reason: .outsideAdapterCeiling)).message
            == "Only this device's own controls can reset the screening. Nothing was changed.")
    }

    @Test func aModelToolCanOnlyRead() throws {
        var session = try ScreeningSession.withTestCard()
        let model = ActorScope(adapter: .modelTool, grants: Set(Permission.allCases))
        #expect(try session.snapshot(for: model) == session.state)
        #expect(throws: ScreeningError.unauthorized(PlaybackDenial(adapter: .modelTool, required: .commit, reason: .outsideAdapterCeiling))) {
            try session.submit(PlaybackRequest(command: .play, actor: model, source: .controls))
        }
    }

    @Test func anUngrantedActorIsRefusedEvenWithinItsCeiling() throws {
        var session = try ScreeningSession.withTestCard()
        let readOnly = ActorScope(adapter: .appUI, grants: [.read])
        #expect(throws: ScreeningError.unauthorized(PlaybackDenial(adapter: .appUI, required: .commit, reason: .notGranted))) {
            try session.submit(PlaybackRequest(command: .pause, actor: readOnly, source: .controls))
        }
        let nothing = ActorScope(adapter: .appUI, grants: [])
        #expect(throws: ScreeningError.unauthorized(PlaybackDenial(adapter: .appUI, required: .read, reason: .notGranted))) {
            try session.snapshot(for: nothing)
        }
    }

    @Test func onlyTheResetIsDestructive() {
        #expect(PlaybackCommand.Kind.allCases.filter(\.isDestructive) == [.forgetResumePoint])
        #expect(PlaybackCommand.Kind.forgetResumePoint.permission == .commitDestructive)
        #expect(PlaybackCommand.Kind.allCases.filter { $0.permission == .commit }.count == PlaybackCommand.Kind.allCases.count - 1)
    }

    @Test func theInProcessLinkRunsCommandsAsACompanionPeer() async throws {
        let conductor = SessionConductor(try .withTestCard())
        let link = InProcessScreeningLink(conductor: conductor)
        let seen = try await link.snapshot()
        #expect(seen.clip == ScreeningClips.testCard.id)

        let receipt = try await link.send(.play, requestID: RequestID(), seen: seen.revision)
        #expect(receipt.status == .applied)
        #expect(receipt.adapter == .authorizedPeer)
        #expect(receipt.source == .companion)

        // The controller still shows the revision before its own play: a second command conflicts.
        let stale = try await link.send(.seek(to: 9), requestID: RequestID(), seen: seen.revision)
        #expect(stale.status == .conflict(expected: seen.revision, current: receipt.revision))

        await #expect(throws: ScreeningError.self) {
            try await link.send(.forgetResumePoint, requestID: RequestID(), seen: nil)
        }
        #expect(await conductor.session.state.isPlaying)
    }

    @Test func theLinkCarriesNoSignals() async throws {
        // A controller can ask to pause but cannot claim an interruption or a route change: the
        // link's only operations are a snapshot and a command.
        let conductor = SessionConductor(try .withTestCard())
        let link = InProcessScreeningLink(conductor: conductor)
        _ = try await link.send(.play, requestID: RequestID(), seen: nil)
        await conductor.observe(.interruptionBegan)
        let state = try await link.snapshot()
        #expect(state.interruption == .init(wasPlaying: true))
    }
}
