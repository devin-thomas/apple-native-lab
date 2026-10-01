import Foundation
import LabDomain
@testable import LocalConstellation
import PeerSession
import Testing

/// LAB-019 Local Constellation: the show's fixture, rules, acceptance behaviors, and the one
/// sensitive request, which reaches the domain only through the operation service with a grant.
@Suite struct ShowTests {
    @Test func theBundledCueSheetIsOriginalAndValid() throws {
        let sheet = try CueSheet.bundled()
        #expect(sheet.cues.count == 6)
        #expect(sheet.cues.map(\.id) == ["blue-hour", "lanterns", "tide-line", "northern-arc", "ember", "first-light"])
        let opening = sheet.openingSnapshot(session: nil)
        #expect(opening.cue == 0 && opening.cueTitle == "Blue hour" && !opening.isRunning && opening.sessionRevision == nil)
    }

    @Test func aCueSheetOutsideTheFormatIsRefusedWhole() throws {
        func sheet(_ text: String) -> Result<CueSheet, CueSheetError> {
            Result { () throws(CueSheetError) -> CueSheet in try CueSheet(data: Data(text.utf8)) }
        }
        let cue = #"{"id":"a","title":"A","detail":"d","palette":"dusk"}"#
        #expect(throws: Never.self) { try sheet(#"{"format":"native-lab-cue-sheet","formatVersion":1,"title":"T","cues":[\#(cue)]}"#).get() }
        #expect(sheet(#"{"format":"native-lab-cue-sheet","formatVersion":2,"title":"T","cues":[\#(cue)]}"#).failure == .unsupportedVersion)
        #expect(sheet(#"{"format":"native-lab-cue-sheet","formatVersion":1,"title":"T","cues":[\#(cue),\#(cue)]}"#).failure == .invalid, "duplicate IDs")
        #expect(sheet(#"{"format":"native-lab-cue-sheet","formatVersion":1,"title":"T","cues":[]}"#).failure == .invalid)
        #expect(sheet(#"{"format":"native-lab-cue-sheet","formatVersion":1,"title":"T","extra":1,"cues":[\#(cue)]}"#).failure == .invalid)
        #expect(sheet(#"{"format":"native-lab-cue-sheet","formatVersion":1,"title":"T","cues":[{"id":"a","title":"A\u0007","detail":"d","palette":"dusk"}]}"#).failure == .invalid)
        #expect(sheet(#"{"format":"native-lab-cue-sheet","formatVersion":1,"title":"T","cues":[{"id":"a","title":"A","detail":"d","palette":"neon"}]}"#).failure == .invalid)
    }

    @Test func theRulesMoveWithinTheSheetAndHoldOnlyAPeersStartOrPause() throws {
        let sheet = try CueSheet.bundled()
        let rules = ShowRules(sheet: sheet)
        let peer = CommandOrigin(peer: LocalIdentity(name: "Pocket phone").identity, role: .controller)
        let conductor = CommandOrigin(peer: LocalIdentity(name: "Mac").identity, role: .conductor)
        let opening = sheet.openingSnapshot(session: nil)
        guard case .apply(let next, _) = rules.decide(.next, on: opening, from: peer) else { Issue.record("next"); return }
        #expect(next.cue == 1 && next.cueTitle == "Lanterns" && next.note == "Pocket phone moved to cue 2, Lanterns.")
        if case .unchanged = rules.decide(.previous, on: opening, from: peer) {} else { Issue.record("previous at the first cue") }
        if case .refuse = rules.decide(.goTo(cue: 6), on: opening, from: peer) {} else { Issue.record("no seventh cue") }
        if case .hold(let summary) = rules.decide(.start, on: opening, from: peer) { #expect(summary == "Start the show?") } else { Issue.record("hold") }
        if case .unchanged = rules.decide(.pause, on: opening, from: peer) {} else { Issue.record("already paused") }
        if case .refuse = rules.decide(.start, on: opening, from: conductor) {} else { Issue.record("the conductor starts through setRunning") }
    }

    @Test func aPeersStartWaitsForTheConductorAndCommitsAsAnAuthorizedPeerWithAGrant() async throws {
        let stage = await Stage()
        try await stage.pair(stage.controller)
        try await stage.pair(stage.display)
        let id = await stage.controller.send(.start)
        let pending = try await eventually { await stage.host.conductor.state.pending.first }
        #expect(pending.command == .start && pending.from.name == "Pocket phone")
        #expect(try await stage.backend.showSession() == nil, "nothing is committed while it waits")

        let outcome = await stage.host.allow(id)
        let receipt = try #require(outcome.receipt)
        #expect(receipt.admitted.adapter == .authorizedPeer)
        #expect(receipt.admitted.operation == .setSession(id: LocalConstellation.showSessionID, expected: nil, running: true))
        #expect(receipt.requestID == PeerApproval(peer: stage.controller.identity, commandID: id).requestID)
        #expect(stage.backend.ledger.liveGrants.isEmpty, "the grant was revoked when the commit returned")
        let result = try await stage.finished(id, on: stage.controller)
        #expect(result.disposition == .applied)
        try await until { await stage.display.state.snapshot?.isRunning == true }
        #expect(await stage.display.state.snapshot?.sessionRevision == 1)
        #expect(try await stage.backend.showSession()?.isRunning == true)
    }

    @Test func aDeclinedOrUnallowedRequestCommitsNothing() async throws {
        let stage = await Stage()
        try await stage.pair(stage.controller)
        let id = await stage.controller.send(.start)
        _ = try await eventually { await stage.host.conductor.state.pending.first }
        _ = await stage.host.decline(id)
        #expect(try await stage.finished(id, on: stage.controller).disposition == .refused)
        #expect(try await stage.backend.showSession() == nil)

        // The same operation, straight to the service as an authorized peer without an allowed
        // request, fails closed at the commit: no grant exists.
        let operation = DomainOperation.setSession(id: LocalConstellation.showSessionID, expected: nil, running: true)
        await #expect(throws: OperationError.self) {
            try await stage.backend.service.perform(OperationRequest(id: RequestID(), operation: operation, actor: ServiceShowBackend.peerActor))
        }
        do {
            _ = try await stage.backend.service.perform(OperationRequest(id: RequestID(), operation: operation, actor: ServiceShowBackend.peerActor))
        } catch .unauthorized(let denial) {
            #expect(denial.reason == .deniedByPolicy && denial.adapter == .authorizedPeer)
        } catch {
            Issue.record("\(error)")
        }
    }

    @Test func aResentAllowedRequestReturnsItsReceiptAndCommitsOnce() async throws {
        let stage = await Stage()
        let ends = try await stage.pair(stage.controller)
        // The answer to the start is lost, so the phone sends it again under the same ID.
        let id = await stage.controller.send(.start)
        _ = try await eventually { await stage.host.conductor.state.pending.first }
        ends.host.setFaults(LoopbackFaults(partitioned: true))
        _ = await stage.host.allow(id)
        ends.host.setFaults(LoopbackFaults())
        stage.clock.advance(by: .seconds(2))
        await stage.controller.tick()
        #expect(try await stage.finished(id, on: stage.controller).disposition == .applied)
        let session = try #require(try await stage.backend.showSession())
        #expect(session.revision == .initial, "committed once")
        let approval = PeerApproval(peer: stage.controller.identity, commandID: id)
        #expect(try await stage.backend.service.findReceipt(for: approval.requestID, as: ServiceShowBackend.conductorActor) != nil)
    }

    @Test func aStaleCueCommandIsRefusedAndTheControllerIsReconciled() async throws {
        let stage = await Stage()
        let ends = try await stage.pair(stage.controller)
        ends.host.setFaults(LoopbackFaults(partitioned: true))
        _ = await stage.host.move(.goTo(cue: 3))
        ends.host.setFaults(LoopbackFaults())
        let id = await stage.controller.send(.next)
        let result = try await stage.finished(id, on: stage.controller)
        #expect(result.disposition == .stale)
        try await until { await stage.controller.state.snapshot?.cue == 3 }
        #expect(await stage.host.conductor.state.snapshot.cue == 3, "the stale next was not applied")
    }

    @Test func theConductorsOwnStartCommitsAsAppUIAndReachesTheDisplay() async throws {
        let stage = await Stage()
        try await stage.pair(stage.display)
        let outcome = await stage.host.setRunning(true)
        #expect(outcome.receipt?.admitted.adapter == .appUI)
        try await until { await stage.display.state.snapshot?.isRunning == true }
        // Another entry point pauses the stored session; syncing brings the show along.
        let paused = DomainOperation.setSession(id: LocalConstellation.showSessionID, expected: .initial, running: false)
        _ = try await stage.backend.commit(paused, requestID: RequestID(), authority: .conductorPerson)
        await stage.host.syncFromStore()
        try await until { await stage.display.state.snapshot?.isRunning == false }
    }

    @Test func hostileWireMessagesAreRefusedBeforeAnyRule() throws {
        let files = try FileManager.default.contentsOfDirectory(at: HostileFixtures.folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(files.count == 8)
        for file in files {
            let data = try Data(contentsOf: file)
            #expect((try? SessionEnvelope<Constellation>(json: data)) == nil, "\(file.lastPathComponent) must be refused")
        }
    }

    @Test func theSnapshotCleansAndBoundsTextFromThePeer() throws {
        let hostile = ShowSnapshot(
            cue: 0, cueCount: 1, cueTitle: "Blue\u{202E} hour" + String(repeating: "!", count: 100), cueDetail: "\n\n",
            palette: .dusk, isRunning: false, sessionRevision: nil, note: "a\u{0000}b"
        )
        #expect(hostile.cueTitle.count == ShowSnapshot.maximumTitleLength)
        #expect(!hostile.cueTitle.contains("\u{202E}"))
        #expect(hostile.cueDetail.isEmpty && hostile.note == "ab")
        #expect(Pointer(x: 0.5, y: .nan).isValid == false)
        #expect(ShowCommand.goTo(cue: CueSheet.maximumCues).isValid == false)
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let failure) = self { failure } else { nil }
    }
}
