import CryptoKit
import Foundation
import LabDomain
@testable import LocalConstellation
@testable import PeerSession
import Synchronization
import Testing

// MARK: - Step 1: the complete fixture interaction, replayed from a clean state

/// LAB-019-B step 1: the whole show from a clean in-memory store, replayed twice with fixed keys,
/// clocks, message IDs, session, and epochs, so the two replays must agree byte for byte on
/// everything but the pairing codes and handshake keys, which are random by design.
///
/// The interaction: an unpaired device is refused; a controller and a display pair with the code;
/// the controller moves the show and points; its start request is held, allowed, and committed
/// as the authorized peer; a cue command based on an older revision is refused and reconciled;
/// a pause request is declined; the display walks out of range, goes stale, then disconnected,
/// and rejoins without a code; Reset Demo pauses the show and leaves the person's own collection
/// alone; and the conductor restarts in a new epoch, refusing a command from before. Fixture path:
/// the in-process loopback, which carries the sealed frames a network would.
@Suite(.timeLimit(.minutes(1))) struct ConstellationInteractionReplay {
    @Test func twoReplaysFromCleanStoresAgreeOnEveryEnvelopeAndOutcome() async throws {
        let first = try await InteractionReplay().run()
        let second = try await InteractionReplay().run()
        #expect(first.transcript.count == second.transcript.count)
        for (one, other) in zip(first.transcript, second.transcript) where one != other {
            Issue.record("The replays differ: \(one) | \(other)")
        }
        #expect(first.fingerprint == second.fingerprint)
        // The fingerprint goes into the evidence log; print it where the command's output shows it.
        print("LAB-019 interaction replay: \(first.transcript.count) lines, fingerprint sha256:\(first.fingerprint)")
    }

    @Test func theReplayShowsEveryAcceptanceBehavior() async throws {
        let lines = try await InteractionReplay().run().transcript
        func has(_ text: String) -> Bool { lines.contains(text) }
        #expect(has("open: cue 1 of 6, Blue hour, paused, never started, revision 0"), "\(lines)")
        #expect(has("stranger: refused pairing-required, no snapshot, 2 frames, 0 sealed"))
        #expect(has("pinned at the conductor: Living room TV display, Pocket phone controller"))
        #expect(has("next: applied at revision 1; display shows cue 2 of 6, Lanterns"))
        #expect(has("pointer: display shows 0.3, 0.7 from 2 samples"))
        #expect(has("ask to start: received, nothing stored"))
        #expect(has("allow: applied at revision 2; receipt authorized-peer setSession running, session revision 1; display running"))
        #expect(has("stale next: stale, 'Based on revision 2, but the state is at 3. Nothing changed.'; controller reconciled to cue 4 at revision 3; conductor still at cue 4"))
        #expect(has("ask to pause: declined, refused; store running at revision 1"))
        #expect(has("out of range 3 s: display Stale, roster Stale; controller Live"))
        #expect(has("out of range 9 s: display Disconnected, roster Disconnected; controller Live"))
        #expect(has("rejoin: display Live without a code, 1 reconnection, cue 4 of 6, Northern arc, running"))
        #expect(has("reset demo: show paused at session revision 2; Field notes unchanged at revision 1; display paused"))
        #expect(has("restart: queued next wrong-epoch; controller Live in epoch 20; display Disconnected, 'The conductor ended the session.'"))
    }
}

/// One replay of the interaction. Every identity, clock, message ID, session ID, and epoch is
/// fixed; only the handshake's ephemeral keys, and so the pairing codes, are random.
final class InteractionReplay: Sendable {
    struct Outcome: Sendable {
        let transcript: [String]
        let fingerprint: String
    }

    static let sessionID = LiveSessionID(rawValue: UUID(uuidString: "0C0C0019-0000-4000-8000-000000000001")!)

    let backend = ServiceShowBackend.inMemory()
    let sheet = try! CueSheet.bundled()
    let clock = ManualPeerClock(start: PeerInstant(nanoseconds: 1_000_000_000))
    let conductorIdentity = InteractionReplay.identity(0x19, "Studio Mac")
    let conductorTrust = InMemoryTrustStore()
    let controllerWire = WireCapture()
    let displayWire = WireCapture()

    static func identity(_ byte: UInt8, _ name: String) -> LocalIdentity {
        LocalIdentity(privateKey: try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: byte, count: 32)), name: name)
    }

    /// Message IDs counted per device, so each replay uses the same ones.
    static func messageIDs(_ device: UInt8) -> @Sendable () -> MessageID {
        let counter = Mutex<UInt32>(0)
        return {
            let next = counter.withLock { value in
                value += 1
                return value
            }
            return MessageID(rawValue: UUID(uuidString: String(format: "%08X-0019-4000-8000-%012X", UInt32(device), next))!)
        }
    }

    func startHost(on hub: LoopbackHub, epoch: UInt32) async -> ShowHost {
        let host = await ShowHost(
            configuration: .init(
                identity: conductorIdentity, trust: conductorTrust, clock: clock, sessionID: Self.sessionID,
                epoch: SessionEpoch(rawValue: epoch), makeMessageID: Self.messageIDs(UInt8(epoch))
            ),
            sheet: sheet, backend: backend
        )
        await host.conductor.listen(on: hub)
        return host
    }

    func run() async throws -> Outcome {
        var lines: [String] = []
        var hub = LoopbackHub(hostLabel: "Studio Mac")
        var host = await startHost(on: hub, epoch: 19)
        let controller = Client<Constellation>(configuration: .init(
            identity: Self.identity(0x20, "Pocket phone"), role: .controller, trust: InMemoryTrustStore(), clock: clock,
            makeMessageID: Self.messageIDs(0x20), wireRecord: { [controllerWire] in controllerWire.append($0) }
        ))
        let display = Client<Constellation>(configuration: .init(
            identity: Self.identity(0x21, "Living room TV"), role: .display, trust: InMemoryTrustStore(), clock: clock,
            makeMessageID: Self.messageIDs(0x21), wireRecord: { [displayWire] in displayWire.append($0) }
        ))

        // 0. A clean store: the show opens at the first cue, never started.
        let opening = await host.conductor.state
        lines.append("open: \(Self.describe(opening.snapshot)), never started, revision \(opening.revision)")

        // 1. A device the conductor never paired asks to rejoin.
        let strangerTrust = InMemoryTrustStore()
        await strangerTrust.pin(PinnedPeer(identity: conductorIdentity.identity, roles: [.conductor], pinnedAt: .now))
        let stranger = Client<Constellation>(configuration: .init(
            identity: Self.identity(0x22, "Unpaired device"), role: .display, trust: strangerTrust, clock: clock
        ))
        let strangerFrames = WireCapture()
        let (strangerEnd, hostEnd) = LoopbackConnection.pair("Unpaired device", "Studio Mac", tap: { strangerFrames.appendBytes($0) })
        await host.conductor.accept(hostEnd)
        var refusal = "joined"
        do { try await stranger.resume(over: strangerEnd, to: conductorIdentity.id) } catch {
            if case .refused(let reason, _) = error { refusal = "refused \(reason.rawValue)" } else { refusal = "failed" }
        }
        let strangerState = await stranger.state
        let sealed = strangerFrames.rawFrames.filter { $0.count > 4 && $0[4] == FrameCodec.Kind.sealed.rawValue }.count
        lines.append("stranger: \(refusal), \(strangerState.snapshot == nil ? "no snapshot" : "a snapshot"), \(strangerFrames.rawFrames.count) frames, \(sealed) sealed")

        // 2. The controller and the display pair with the code the conductor shows.
        _ = try await pair(controller, host: host, hub: hub)
        let displayEnds = try await pair(display, host: host, hub: hub)
        let pins = await conductorTrust.all().map { "\($0.identity.name) \($0.roles.map(\.rawValue).sorted().joined())" }.sorted()
        lines.append("pinned at the conductor: \(pins.joined(separator: ", "))")

        // 3. The controller moves the show.
        let next = await controller.send(.next)
        let moved = try await finished(next, on: controller)
        try await until { await display.state.snapshot?.cue == 1 }
        let shown = try #require(await display.state.snapshot)
        lines.append("next: \(moved.disposition.rawValue) at revision \(moved.revision); display shows cue \(shown.cue + 1) of \(shown.cueCount), \(shown.cueTitle)")

        // 4. Pointer samples: replaceable, newest only.
        await controller.publish(Pointer(x: 0.25, y: 0.75))
        await controller.publish(Pointer(x: 0.3, y: 0.7))
        let pointer = try await eventually { () -> SampleBody<Pointer>? in
            let newest = await display.state.samples.values.first
            return newest?.streamSequence == 2 ? newest : nil
        }
        lines.append("pointer: display shows \(pointer.sample.x), \(pointer.sample.y) from \(pointer.streamSequence) samples")

        // 5. Start: the controller asks, the conductor's person allows, the operation service commits.
        let ask = await controller.send(.start)
        _ = try await eventually { [host] in await host.conductor.state.pending.first }
        let held = try await eventually { () -> CommandResult? in
            if case .received(let result) = await controller.state.commands.first(where: { $0.id == ask })?.stage { result } else { nil }
        }
        let storedBefore = try await backend.showSession()
        lines.append("ask to start: \(held.disposition.rawValue), \(storedBefore == nil ? "nothing stored" : "stored")")
        let allowed = await host.allow(ask)
        let started = try await finished(ask, on: controller)
        try await until { await display.state.snapshot?.isRunning == true }
        let receipt = try #require(allowed.receipt)
        let operation = receipt.admitted.operation == .setSession(id: LocalConstellation.showSessionID, expected: nil, running: true) ? "setSession running" : "other"
        lines.append("allow: \(started.disposition.rawValue) at revision \(started.revision); receipt \(receipt.admitted.adapter.rawValue) \(operation), session revision \(receipt.changes.first?.newRevision.rawValue ?? 0); display running")

        // 6. A stale command: the conductor moves while its frames to the controller are lost.
        let controllerLink = try #require(controllerConnections.withLock { $0 })
        controllerLink.host.setFaults(LoopbackFaults(partitioned: true))
        _ = await host.move(.goTo(cue: 3))
        controllerLink.host.setFaults(LoopbackFaults())
        let stale = await controller.send(.next)
        let staleResult = try await finished(stale, on: controller)
        try await until { await controller.state.snapshot?.cue == 3 }
        let reconciled = await controller.state
        let conductorCue = await host.conductor.state.snapshot.cue
        lines.append("stale next: \(staleResult.disposition.rawValue), '\(staleResult.summary)'; controller reconciled to cue \((reconciled.snapshot?.cue ?? -1) + 1) at revision \(reconciled.revision ?? -1); conductor still at cue \(conductorCue + 1)")

        // 7. A pause request, declined.
        let pause = await controller.send(.pause)
        _ = try await eventually { [host] in await host.conductor.state.pending.first }
        _ = await host.decline(pause)
        let declined = try await finished(pause, on: controller)
        let stored = try #require(try await backend.showSession())
        lines.append("ask to pause: declined, \(declined.disposition.rawValue); store \(stored.isRunning ? "running" : "paused") at revision \(stored.revision.rawValue)")

        // 8. The display walks out of range. Nothing is closed; both sides notice only by silence,
        // while the controller keeps answering the conductor's probes.
        displayEnds.joiner.setFaults(LoopbackFaults(partitioned: true))
        displayEnds.host.setFaults(LoopbackFaults(partitioned: true))
        for second in 1...9 {
            try await passOneSecond(host: host, controller: controller, display: display)
            if second == 3 || second == 9 {
                let roster = await host.conductor.state.peers
                let tv = roster.first { $0.role == .display }?.presence.title ?? "absent"
                let phone = roster.first { $0.role == .controller }?.presence.title ?? "absent"
                let shownPhase = await display.state.phase.title
                lines.append("out of range \(second) s: display \(shownPhase), roster \(tv); controller \(phone)")
            }
        }

        // 9. Back in range: the display rejoins with the pinned identities, without a code.
        try await display.resume(over: hub.dial(from: "Living room TV"))
        try await until { await display.state.phase == .live }
        let rejoined = await display.state
        lines.append("rejoin: display \(rejoined.phase.title) without a code, \(rejoined.reconnections) reconnection, \(rejoined.snapshot.map(Self.describe) ?? "nothing")")

        // 10. Reset Demo, beside a collection of the person's own.
        let person = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
        let notesID = CollectionID(rawValue: UUID(uuidString: "0C0C0019-0000-4000-8000-0000000000F1")!)
        _ = try await backend.service.perform(OperationRequest(
            id: RequestID(), operation: .createCollection(draft: CollectionDraft(id: notesID, title: try EntityTitle("Field notes"))), actor: person
        ))
        let notesBefore = try await backend.service.findCollection(notesID, as: person)
        let seed = try DemoSeed(version: 1, collections: [CollectionDraft(
            id: CollectionID(rawValue: UUID(uuidString: "0C0C0019-0000-4000-8000-0000000000D1")!), title: try EntityTitle("Demo shelf")
        )], items: [])
        let reset = DomainOperation.resetDemo(seed: seed)
        let grant = try backend.ledger.issue(for: reset, to: .appUI)
        _ = try await backend.service.perform(OperationRequest(id: RequestID(), operation: reset, actor: person))
        backend.ledger.revoke(grant.id)
        await host.syncFromStore()
        try await until { await display.state.snapshot?.isRunning == false }
        let afterReset = try #require(try await backend.showSession())
        let notesAfter = try await backend.service.findCollection(notesID, as: person)
        let displayRunning = await display.state.snapshot?.isRunning == true
        lines.append("reset demo: show \(afterReset.isRunning ? "running" : "paused") at session revision \(afterReset.revision.rawValue); Field notes \(notesAfter == notesBefore ? "unchanged" : "changed") at revision \(notesAfter.revision.rawValue); display \(displayRunning ? "running" : "paused")")

        // 11. The conductor relaunches in a new epoch. A command the controller queued before is refused.
        await controller.vanish()
        // The conductor notices first, so its goodbye goes to the display alone.
        try await until { [host] in
            if case .disconnected = await host.conductor.state.peers.first(where: { $0.role == .controller })?.presence { true } else { false }
        }
        let early = await controller.send(.next)
        await host.conductor.stop()
        hub.stop()
        try await until { if case .disconnected = await display.state.phase { true } else { false } }
        hub = LoopbackHub(hostLabel: "Studio Mac")
        host = await startHost(on: hub, epoch: 20)
        try await controller.resume(over: hub.dial(from: "Pocket phone"))
        let wrongEpoch = try await finished(early, on: controller)
        let afterRestart = await controller.state
        let displayPhase = await display.state.phase
        let displayReason = if case .disconnected(let reason) = displayPhase { reason } else { displayPhase.title }
        lines.append("restart: queued next \(wrongEpoch.disposition.rawValue); controller \(afterRestart.phase.title) in epoch \(afterRestart.epoch?.rawValue ?? 0); display \(displayPhase.title), '\(displayReason)'")

        // Every envelope the joiners sent and received, except clock probes, whose order within a
        // second depends on which side's task ran first.
        for (name, capture) in [("controller", controllerWire), ("display", displayWire)] {
            for record in capture.all where !record.kind.hasPrefix("clock-") {
                let digest = SHA256.hash(data: record.plaintext).prefix(8).map { String(format: "%02x", $0) }.joined()
                lines.append("wire \(name) \(record.direction.rawValue) \(record.kind) \(record.channel.rawValue) #\(record.sequence) \(record.frameBytes) bytes \(digest)")
            }
        }
        await controller.shutdown()
        await display.shutdown()
        await stranger.shutdown()
        await host.conductor.stop()

        let fingerprint = SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        return Outcome(transcript: lines, fingerprint: fingerprint)
    }

    /// The controller's two ends, kept when it pairs, so step 6 can lose the conductor's frames.
    let controllerConnections = Mutex<(joiner: LoopbackConnection, host: LoopbackConnection)?>(nil)

    private func pair(_ client: Client<Constellation>, host: ShowHost, hub: LoopbackHub) async throws -> (joiner: LoopbackConnection, host: LoopbackConnection) {
        await host.conductor.openPairing()
        let ends = hub.dialBothEnds(from: client.identity.name)
        if client.role == .controller { controllerConnections.withLock { $0 = ends } }
        async let joined: Void = client.pair(over: ends.joiner)
        let request = try await eventually { [host] in await host.conductor.state.pairingRequest }
        _ = try await eventually { await client.state.codePrompt }
        await client.submitCode(request.code.description)
        await host.conductor.answerPairing(allow: true)
        try await joined
        try await until { await client.state.phase == .live }
        return ends
    }

    /// One second for every device. The conductor probes both joiners, and the controller, still
    /// in range, answers and probes back; the display hears nothing.
    private func passOneSecond(host: ShowHost, controller: Client<Constellation>, display: Client<Constellation>) async throws {
        clock.advance(by: .seconds(1))
        let pongs = controllerWire.count(kind: "clock-pong", .received)
        let pings = controllerWire.count(kind: "clock-ping", .received)
        await display.tick()
        await host.conductor.tick()
        try await until { controllerWire.count(kind: "clock-ping", .received) == pings + 1 }
        await controller.tick()
        try await until { controllerWire.count(kind: "clock-pong", .received) == pongs + 1 }
    }

    private func finished(_ id: MessageID, on client: Client<Constellation>) async throws -> CommandResult {
        try await eventually {
            if case .finished(let result) = await client.state.commands.first(where: { $0.id == id })?.stage { result } else { nil }
        }
    }

    static func describe(_ snapshot: ShowSnapshot?) -> String {
        guard let snapshot else { return "nothing" }
        return "cue \(snapshot.cue + 1) of \(snapshot.cueCount), \(snapshot.cueTitle), \(snapshot.isRunning ? "running" : "paused")"
    }
}

/// Wire records and raw bytes from one device's links.
final class WireCapture: Sendable {
    private let records = Mutex<[WireRecord]>([])
    private let bytes = Mutex<[Data]>([])

    func append(_ record: WireRecord) { records.withLock { $0.append(record) } }
    func appendBytes(_ data: Data) { bytes.withLock { $0.append(data) } }
    var all: [WireRecord] { records.withLock { $0 } }
    var rawFrames: [Data] { bytes.withLock { $0 } }

    func count(kind: String, _ direction: WireRecord.Direction) -> Int {
        records.withLock { $0.filter { $0.kind == kind && $0.direction == direction }.count }
    }
}

// MARK: - Steps 2 and 3: acceptance, denial, cancellation, stale and duplicate state, reset

/// LAB-019-B steps 2 and 3 on the show itself: the conductor's `ShowHost` over an in-memory
/// operation service, a controller, and a display, with a manual clock. Fixture path.
@Suite(.timeLimit(.minutes(1))) struct ConstellationQualification {
    // MARK: A stale command is ignored or explicitly reconciled

    /// A peer's start, held while the person at the conductor pressed Start there first, is
    /// answered "already running" when allowed: reconciled with one receipt, not committed twice.
    @Test func aHeldStartOvertakenAtTheConductorIsReconciledNotCommittedTwice() async throws {
        let stage = await Stage()
        try await stage.pair(stage.controller)
        let ask = await stage.controller.send(.start)
        _ = try await eventually { await stage.host.conductor.state.pending.first }
        let own = await stage.host.setRunning(true)
        #expect(own.receipt?.admitted.adapter == .appUI)

        let outcome = await stage.host.allow(ask)
        #expect(outcome.receipt == nil, "nothing more was committed")
        let result = try await stage.finished(ask, on: stage.controller)
        #expect(result.disposition == .unchanged && result.summary == "The show is already running.")
        let session = try #require(try await stage.backend.showSession())
        #expect(session.isRunning && session.revision == .initial)
    }

    /// Allow pressed twice, or after the request expired, commits nothing more.
    @Test func allowingTwiceOrTooLateCommitsAtMostOnce() async throws {
        let stage = await Stage()
        try await stage.pair(stage.controller)
        let ask = await stage.controller.send(.start)
        _ = try await eventually { await stage.host.conductor.state.pending.first }
        #expect(await stage.host.allow(ask).receipt != nil)
        let again = await stage.host.allow(ask)
        #expect(again.receipt == nil && again.message == "That request is no longer waiting.")
        #expect(try await stage.backend.showSession()?.revision == .initial)
        try await until { await stage.controller.state.snapshot?.isRunning == true }

        // A pause nobody answers expires after 30 seconds; a late Allow finds nothing. (The phone,
        // silent as long, is disconnected in the same tick; the contract suite shows a held
        // command's answer reaching a joiner that rejoins.)
        let pause = await stage.controller.send(.pause)
        _ = try await eventually { await stage.host.conductor.state.pending.first }
        stage.clock.advance(by: .seconds(31))
        await stage.host.conductor.tick()
        #expect(await stage.host.conductor.state.pending.isEmpty)
        #expect(await stage.host.conductor.state.events.map(\.text).contains("A held command expired unanswered."))
        let late = await stage.host.allow(pause)
        #expect(late.receipt == nil && late.message == "That request is no longer waiting.")
        let session = try #require(try await stage.backend.showSession())
        #expect(session.isRunning && session.revision == .initial)
    }

    // MARK: An unpaired peer sees no session data

    /// A device whose pairing the person at the conductor denied, or whose person typed another
    /// code, receives only handshake frames and pins nothing; neither side pins the other.
    @Test func aDeniedOrMistypedPairingSharesNothing() async throws {
        let stage = await Stage()
        for denial in ["deny", "wrong code"] {
            await stage.host.conductor.openPairing()
            let frames = WireCapture()
            let (joinerEnd, hostEnd) = LoopbackConnection.pair("phone", "conductor", tap: { frames.appendBytes($0) })
            await stage.host.conductor.accept(hostEnd)
            let controller = stage.controller
            let joining = Task { () async -> HandshakeFailure? in
                do { try await controller.pair(over: joinerEnd); return nil } catch { return error as? HandshakeFailure }
            }
            let request = try await eventually { await stage.host.conductor.state.pairingRequest }
            _ = try await eventually { await stage.controller.state.codePrompt }
            if denial == "deny" {
                // The conductor's person denies while the phone's person is still typing; the
                // phone learns it when it sends its confirmation.
                await stage.host.conductor.answerPairing(allow: false)
                await stage.controller.submitCode(request.code.description)
            } else {
                let wrong = String(format: "%06d", (Int(request.code.digits)! + 1) % 1_000_000)
                await stage.controller.submitCode(wrong)
            }
            let failure = await joining.value
            let expected: HandshakeFailure = denial == "deny" ? .refused(.notApproved, theirOffer: Constellation.offer) : .refusedLocally(.codeMismatch)
            #expect(failure == expected, "\(denial)")
            #expect(frames.rawFrames.allSatisfy { $0.count > 4 && $0[4] == FrameCodec.Kind.handshake.rawValue }, "\(denial): not one sealed frame")
            #expect(await stage.controller.state.snapshot == nil)
            #expect(await stage.controller.state.host == nil)
            #expect(await stage.host.conductor.state.peers.isEmpty)
            try await until { await stage.host.conductor.state.pairingRequest == nil }
        }
    }

    /// A forgotten controller is told to pair again before any session data, and its held start
    /// should go with it. Today the request stays, and Allow still commits it as the authorized
    /// peer (see `PeerSessionContractQualification.forgettingAPeerWithdrawsItsHeldCommands`).
    @Test func aForgottenControllerSeesNothingAndItsHeldStartShouldNotCommit() async throws {
        let stage = await Stage()
        try await stage.pair(stage.controller)
        let ask = await stage.controller.send(.start)
        _ = try await eventually { await stage.host.conductor.state.pending.first }
        await stage.host.conductor.forget(stage.controller.identity.id)
        try await until { if case .disconnected = await stage.controller.state.phase { true } else { false } }
        #expect(await stage.controller.state.host == nil, "the conductor's goodbye unpinned it on the phone too")

        let outcome = await stage.host.allow(ask)
        let stored = try await stage.backend.showSession()
        withKnownIssue("LAB-019-B finding: Forget leaves the peer's held start waiting, and Allow commits it") {
            #expect(outcome.receipt == nil)
            #expect(stored == nil)
        }
    }

    // MARK: A disconnected client visibly becomes stale

    /// When the conductor ends the session, a display says so in words, rather than going on
    /// showing the last cue as if it were current.
    @Test func aDisplayWhoseConductorStoppedSaysSo() async throws {
        let stage = await Stage()
        try await stage.pair(stage.display)
        await stage.host.conductor.stop()
        try await until { if case .disconnected = await stage.display.state.phase { true } else { false } }
        #expect(await stage.display.state.phase == .disconnected(reason: "The conductor ended the session."))
        #expect(await stage.display.state.snapshot?.cueTitle == "Blue hour", "the last state is kept, marked disconnected")
    }

    // MARK: Cancellation

    /// The person at the device gives up while the conductor shows Allow: the conductor's prompt
    /// goes away, and nothing is pinned on either side.
    @Test func cancellingOnTheDeviceWithdrawsTheConductorsPrompt() async throws {
        let stage = await Stage()
        await stage.host.conductor.openPairing()
        let connection = stage.hub.dial(from: "phone")
        let controller = stage.controller
        let joining = Task { () async -> HandshakeFailure? in
            do { try await controller.pair(over: connection); return nil } catch { return error as? HandshakeFailure }
        }
        _ = try await eventually { await stage.host.conductor.state.pairingRequest }
        _ = try await eventually { await stage.controller.state.codePrompt }
        await stage.controller.cancelCode()
        #expect(await joining.value == HandshakeFailure.refusedLocally(.notApproved))
        try await until { await stage.host.conductor.state.pairingRequest == nil }
        #expect(await stage.host.conductor.state.peers.isEmpty)
        #expect(await stage.controller.state.host == nil)
    }

    // MARK: Reset without touching the person's data

    /// Start Over in the simulation forgets every pairing and keeps the show's stored state;
    /// Reset Demo pauses the show and leaves a collection and an item of the person's own as
    /// they were.
    @MainActor
    @Test func startOverAndResetDemoLeaveThePersonsDataAlone() async throws {
        let backend = ServiceShowBackend.inMemory()
        let person = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
        let notes = CollectionDraft(title: try EntityTitle("Field notes"))
        _ = try await backend.service.perform(OperationRequest(id: RequestID(), operation: .createCollection(draft: notes), actor: person))
        let item = ItemDraft(in: notes.id, title: try EntityTitle("Graphite stick"), note: try ItemNote("Soft, smudges."))
        _ = try await backend.service.perform(OperationRequest(id: RequestID(), operation: .createItem(draft: item), actor: person))
        let notesBefore = try await backend.service.findCollection(notes.id, as: person)
        let itemBefore = try await backend.service.findItem(item.id, as: person)

        let simulation = ConstellationSimulation(backend: backend, storeDescription: "memory", sheet: try CueSheet.bundled())
        await simulation.start()
        await simulation.conductorSetRunning(true)
        #expect(try await backend.showSession()?.isRunning == true)
        await simulation.reset()
        #expect(simulation.controller?.host == nil && simulation.display?.host == nil, "every pairing forgotten")
        #expect(try await backend.showSession()?.isRunning == true, "Start Over keeps the stored show")
        #expect(simulation.conductor?.snapshot.isRunning == true)

        let seed = try DemoSeed(version: 1, collections: [CollectionDraft(title: try EntityTitle("Demo shelf"))], items: [])
        let reset = DomainOperation.resetDemo(seed: seed)
        let grant = try backend.ledger.issue(for: reset, to: .appUI)
        let receipt = try await backend.service.perform(OperationRequest(id: RequestID(), operation: reset, actor: person))
        backend.ledger.revoke(grant.id)
        #expect(receipt.changes.map(\.entity).contains(.session(LocalConstellation.showSessionID)))
        #expect(try await backend.showSession()?.isRunning == false)
        await simulation.syncFromStore()
        try await until { await MainActor.run { simulation.conductor?.snapshot.isRunning == false } }
        #expect(try await backend.service.findCollection(notes.id, as: person) == notesBefore)
        #expect(try await backend.service.findItem(item.id, as: person) == itemBefore)
        await simulation.stop()
    }

    // MARK: The wire

    /// Every Local Constellation payload is one flat object, so the format's key check reaches
    /// every key a peer can send (a nested object would be checked only by its own decoder).
    @Test func everyPayloadIsFlatSoTheFormatChecksEveryKey() throws {
        let sheet = try CueSheet.bundled()
        let commands: [ShowCommand] = [.next, .previous, .goTo(cue: 2), .start, .pause]
        var objects: [[String: Any]] = []
        for payload in commands.map({ try? JSONEncoder().encode($0) }) + [
            try? JSONEncoder().encode(Pointer(x: 0.5, y: 0.5)),
            try? JSONEncoder().encode(sheet.openingSnapshot(session: nil)),
        ] {
            let data = try #require(payload)
            objects.append(try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any]))
        }
        for object in objects {
            #expect(object.values.allSatisfy { !($0 is [String: Any]) && !($0 is [Any]) }, "\(object)")
        }
    }
}
