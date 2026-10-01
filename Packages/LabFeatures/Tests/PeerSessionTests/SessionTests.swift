import Foundation
@testable import PeerSession
import Testing

/// LAB-019: a conductor, a controller, and a display over the loopback, with manual clocks. Every
/// acceptance behavior of the session layer is exercised here: stale commands, unpaired peers,
/// silence becoming stale, reconnection, sequence gaps, replaceable samples, epochs, and clocks.
@Suite struct SessionTests {
    @Test func pairedPeersGetTheWholeStateFirstAndCommandsApply() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        try await rig.pair(rig.display, label: "tv")
        let id = await rig.controller.send(.add(3))
        try await until { await rig.display.state.snapshot?.value == 3 }
        // The snapshot reaches every peer before the sender's own answer does.
        try await until {
            if case .finished = await rig.controller.state.commands.first(where: { $0.id == id })?.stage { true } else { false }
        }
        let command = try #require(await rig.controller.state.commands.first { $0.id == id })
        guard case .finished(let result) = command.stage else { Issue.record("\(command.stage)"); return }
        #expect(result.disposition == .applied && result.revision == 1)
        #expect(await rig.conductor.state.revision == 1)

        // The first envelope each joiner received was the snapshot; nothing came before it.
        for log in [rig.controllerWire, rig.displayWire] {
            #expect(log.all.first { $0.direction == .received }?.kind == "snapshot")
            #expect(log.all.first?.direction == .received, "a joiner sends nothing before the snapshot")
        }
    }

    @Test func aStaleCommandIsRefusedWithTheCurrentStateAndNothingChanges() async throws {
        let rig = Rig()
        let ends = try await rig.pair(rig.controller, label: "phone")
        // The conductor's frames stop reaching the phone, and the conductor moves on.
        ends.host.setFaults(LoopbackFaults(partitioned: true))
        await rig.conductor.perform(.set(10))
        ends.host.setFaults(LoopbackFaults())
        #expect(await rig.controller.state.revision == 0, "the phone still shows revision 0")

        let id = await rig.controller.send(.add(1))
        try await until {
            if case .finished = await rig.controller.state.commands.first(where: { $0.id == id })?.stage { true } else { false }
        }
        let stage = await rig.controller.state.commands.first { $0.id == id }?.stage
        guard case .finished(let result) = stage else { Issue.record("\(String(describing: stage))"); return }
        #expect(result.disposition == .stale)
        #expect(result.summary == "Based on revision 0, but the state is at 1. Nothing changed.")
        // Reconciled: the phone now shows the current state, which the stale command did not change.
        try await until { await rig.controller.state.revision == 1 }
        #expect(await rig.controller.state.snapshot?.value == 10)
        #expect(await rig.conductor.state.snapshot.value == 10)
        #expect(await rig.controller.state.counters.reliableGaps == 1, "the dropped snapshot showed as a gap")
    }

    @Test func aResentCommandIsAnsweredFromTheRecordAndAppliedOnce() async throws {
        let rig = Rig()
        let ends = try await rig.pair(rig.controller, label: "phone")
        ends.host.setFaults(LoopbackFaults(partitioned: true))
        let id = await rig.controller.send(.add(1))
        try await until { await rig.conductor.state.snapshot.value == 1 }
        ends.host.setFaults(LoopbackFaults())
        rig.advance(.seconds(1))
        await rig.controller.tick()
        try await until {
            if case .finished = await rig.controller.state.commands.first(where: { $0.id == id })?.stage { true } else { false }
        }
        #expect(await rig.conductor.state.snapshot.value == 1, "applied once")
        #expect(await rig.conductor.state.revision == 1)
        let admitted = await rig.conductor.state.peers.first?.admittedCommands
        #expect(admitted == 1)
    }

    @Test func cancellingTheCodePromptRefusesThePairingAndPinsNothing() async throws {
        let rig = Rig()
        await rig.conductor.openPairing()
        let connection = rig.hub.dial(from: "phone")
        let controller = rig.controller
        let joining = Task { () async -> HandshakeFailure? in
            do { try await controller.pair(over: connection); return nil } catch { return error as? HandshakeFailure }
        }
        _ = try await eventually { await rig.conductor.state.pairingRequest }
        _ = try await eventually { await rig.controller.state.codePrompt }
        await rig.controller.cancelCode()
        #expect(await joining.value == HandshakeFailure.refusedLocally(.notApproved))
        try await until { await rig.conductor.state.pairingRequest == nil }
        #expect(await rig.conductorTrust.all().isEmpty)
        #expect(await rig.controller.state.host == nil)
    }

    @Test func aDisplayMayNotSendCommands() async throws {
        let rig = Rig()
        try await rig.pair(rig.display, label: "tv")
        let id = await rig.display.send(.add(1))
        try await until {
            if case .finished(let result) = await rig.display.state.commands.first(where: { $0.id == id })?.stage {
                result.disposition == .notAllowed
            } else { false }
        }
        #expect(await rig.conductor.state.snapshot.value == 0)
    }

    @Test func aSilentClientBecomesStaleThenDisconnectedOnBothSides() async throws {
        let rig = Rig()
        let ends = try await rig.pair(rig.controller, label: "phone")
        await rig.tickAll()
        // Let both clock probes complete, so no late answer counts as hearing from the peer.
        try await until { await rig.conductor.state.peers.first?.clock != nil }
        try await until { await rig.controller.state.clock != nil }
        #expect(await rig.conductor.state.peers.first?.presence == .live)
        // Out of range: nothing crosses in either direction, but no one closed anything.
        ends.joiner.setFaults(LoopbackFaults(partitioned: true))
        ends.host.setFaults(LoopbackFaults(partitioned: true))
        rig.advance(.seconds(3))
        await rig.tickAll()
        let peer = try #require(await rig.conductor.state.peers.first)
        guard case .stale = peer.presence else { Issue.record("\(peer.presence)"); return }
        #expect(peer.silence == .seconds(3))
        #expect(await rig.controller.state.phase == .stale)

        rig.advance(.seconds(6))
        await rig.tickAll()
        guard case .disconnected = try #require(await rig.conductor.state.peers.first).presence else {
            Issue.record("expected disconnected"); return
        }
        guard case .disconnected = await rig.controller.state.phase else { Issue.record("expected disconnected"); return }
        // The roster keeps the peer, visibly disconnected, rather than silently removing it.
        #expect(await rig.conductor.state.peers.count == 1)
    }

    @Test func aReconnectingClientResynchronizesBeforeItsQueuedCommandGoes() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        await rig.controller.vanish()
        try await until { if case .disconnected = await rig.conductor.state.peers.first?.presence { true } else { false } }
        let id = await rig.controller.send(.add(2))
        #expect(await rig.controller.state.commands.first { $0.id == id }?.stage == .queued)

        try await rig.controller.resume(over: rig.hub.dial(from: "phone again"))
        try await until { await rig.conductor.state.snapshot.value == 2 }
        #expect(await rig.controller.state.reconnections == 1)
        #expect(await rig.conductor.state.peers.first?.reconnections == 1)
        #expect(await rig.conductor.state.peers.first?.presence == .live)
    }

    @Test func lostReliableMessagesForceASnapshotBeforeAnythingIsAdmitted() async throws {
        let rig = Rig()
        let ends = try await rig.pair(rig.controller, label: "phone")
        ends.joiner.setFaults(LoopbackFaults(dropNext: 1))
        let lost = await rig.controller.send(.add(1))
        let next = await rig.controller.send(.add(2))
        try await until {
            if case .finished = await rig.controller.state.commands.first(where: { $0.id == next })?.stage { true } else { false }
        }
        guard case .finished(let result) = await rig.controller.state.commands.first(where: { $0.id == next })?.stage else { return }
        #expect(result.disposition == .needsSnapshot)
        #expect(await rig.conductor.state.snapshot.value == 0, "nothing was admitted after the gap")
        #expect(await rig.conductor.state.peers.first?.counters.reliableGaps == 1)

        // The lost command was never answered, so it goes again under its own ID and is admitted.
        rig.advance(.seconds(1))
        await rig.controller.tick()
        try await until { await rig.conductor.state.snapshot.value == 1 }
        if case .finished(let first) = await rig.controller.state.commands.first(where: { $0.id == lost })?.stage {
            #expect(first.disposition == .applied)
        }
    }

    @Test func samplesAreReplaceableAndLossIsCounted() async throws {
        let rig = Rig()
        let ends = try await rig.pair(rig.controller, label: "phone")
        try await rig.pair(rig.display, label: "tv")
        await rig.controller.publish(Tally.Sample(level: 0.1))
        ends.joiner.setFaults(LoopbackFaults(dropNext: 1))
        await rig.controller.publish(Tally.Sample(level: 0.2))
        await rig.controller.publish(Tally.Sample(level: 0.3))
        try await until { await rig.display.state.samples[rig.controller.identity.id]?.sample.level == 0.3 }
        #expect(await rig.conductor.state.peers.first { $0.role == .controller }?.counters.replaceableMissing == 1)
        #expect(await rig.display.state.samples[rig.controller.identity.id]?.streamSequence == 3)
    }

    @Test func aCommandThatWaitedTooLongIsNeverSent() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        await rig.controller.vanish()
        let id = await rig.controller.send(.add(5))
        rig.advance(.seconds(6))
        await rig.controller.tick()
        #expect(await rig.controller.state.commands.first { $0.id == id }?.stage == .expiredBeforeSending)
        try await rig.controller.resume(over: rig.hub.dial(from: "phone again"))
        try await until { await rig.controller.state.phase == .live }
        #expect(await rig.conductor.state.snapshot.value == 0)
    }

    @Test func theConductorMeasuresCommandAgeWithTheClockEstimate() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        await rig.conductor.tick()
        try await until { await rig.conductor.state.peers.first?.clock != nil }
        let estimate = try #require(await rig.conductor.state.peers.first?.clock)
        // The phone's clock reads 895 s ahead of the conductor's; manual clocks give an exact reading.
        #expect(estimate.offset == .seconds(895))
        #expect(estimate.uncertainty == .zero)
        // The phone's clock stalls while the conductor's runs on: its commands look 6 s old.
        rig.conductorClock.advance(by: .seconds(6))
        let id = await rig.controller.send(.add(1))
        try await until {
            if case .finished(let result) = await rig.controller.state.commands.first(where: { $0.id == id })?.stage {
                result.disposition == .expired
            } else { false }
        }
        #expect(await rig.conductor.state.snapshot.value == 0)
    }

    @Test func theControllerEstimatesTheConductorsClockToo() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        await rig.controller.tick()
        try await until { await rig.controller.state.clock != nil }
        #expect(await rig.controller.state.clock?.offset == .seconds(-895))
    }

    @Test func aCommandFromBeforeARestartIsRefusedForItsEpoch() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        await rig.controller.vanish()
        let id = await rig.controller.send(.add(1))
        await rig.conductor.stop()

        // The conductor relaunches: same identity and pins, a new epoch.
        let hub = LoopbackHub(hostLabel: "conductor")
        let restarted = Conductor<Tally>(
            configuration: .init(identity: rig.conductorIdentity, trust: rig.conductorTrust, clock: rig.conductorClock, epoch: SessionEpoch(rawValue: 8)),
            initialState: Tally.Snapshot(value: 0), decide: Tally.decide
        )
        restarted.listenNow(on: hub)
        try await rig.controller.resume(over: hub.dial(from: "phone again"))
        try await until {
            if case .finished = await rig.controller.state.commands.first(where: { $0.id == id })?.stage { true } else { false }
        }
        guard case .finished(let result) = await rig.controller.state.commands.first(where: { $0.id == id })?.stage else { return }
        #expect(result.disposition == .wrongEpoch)
        #expect(await restarted.state.snapshot.value == 0)
        #expect(await rig.controller.state.epoch == SessionEpoch(rawValue: 8))
    }

    @Test func aHeldCommandWaitsForThePersonAndExpiresUnanswered() async throws {
        let rig = Rig(timing: SessionTiming(approvalLifetime: .seconds(3)))
        try await rig.pair(rig.controller, label: "phone")
        let asked = await rig.controller.send(.ask(40))
        let pending = try await eventually { await rig.conductor.state.pending.first }
        #expect(pending.from.name == "Pocket phone" && pending.command == .ask(40))
        // The phone hears that the conductor received it and is waiting.
        try await until {
            if case .received = await rig.controller.state.commands.first(where: { $0.id == asked })?.stage { true } else { false }
        }
        await rig.conductor.resolve(asked) { _ in .apply(Tally.Snapshot(value: 40), summary: "Allowed: set to 40.") }
        try await until { await rig.controller.state.snapshot?.value == 40 }

        let ignored = await rig.controller.send(.ask(5))
        _ = try await eventually { await rig.conductor.state.pending.first }
        rig.advance(.seconds(4))
        await rig.conductor.tick()
        try await until {
            if case .finished(let result) = await rig.controller.state.commands.first(where: { $0.id == ignored })?.stage {
                result.disposition == .expired
            } else { false }
        }
        #expect(await rig.conductor.state.snapshot.value == 40)
    }

    @Test func anUnpairedPeerSeesNoSessionData() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        await rig.controller.send(.add(7))
        try await until { await rig.conductor.state.snapshot.value == 7 }

        // A stranger that knows the conductor's identity, but whom the conductor never paired.
        let strangerTrust = InMemoryTrustStore()
        await strangerTrust.pin(PinnedPeer(identity: rig.conductorIdentity.identity, roles: [.conductor], pinnedAt: .now))
        let stranger = Client<Tally>(configuration: .init(identity: LocalIdentity(name: "Stranger"), role: .display, trust: strangerTrust))
        let frames = WireLog()
        let (joinerEnd, hostEnd) = LoopbackConnection.pair("stranger", "conductor", tap: { frames.appendBytes($0) })
        await rig.conductor.accept(hostEnd)
        await #expect(throws: HandshakeFailure.refused(.pairingRequired, theirOffer: Tally.offer)) {
            try await strangerResume(stranger, over: joinerEnd, host: rig.conductorIdentity.identity)
        }
        let seen = await stranger.state
        #expect(seen.snapshot == nil && seen.revision == nil && seen.sessionID == nil)
        #expect(frames.rawFrames.allSatisfy { $0[4] == FrameCodec.Kind.handshake.rawValue }, "not one sealed frame")
        #expect(frames.rawFrames.count == 2)
        let events = await rig.conductor.state.events.map(\.text)
        #expect(events.contains { $0.contains("unpaired device tried to rejoin") })

        // Forgetting a paired peer closes its link, and it too must pair again.
        await rig.conductor.forget(rig.controller.identity.id)
        try await until { if case .disconnected = await rig.controller.state.phase { true } else { false } }
        await #expect(throws: HandshakeFailure.self) { try await rig.controller.resume(over: rig.hub.dial(from: "phone")) }
    }

    /// Resumes a client that has the host pinned but has never paired in this process.
    func strangerResume(_ client: Client<Tally>, over connection: any PeerConnection, host: PeerIdentity) async throws {
        try await client.resume(over: connection, to: host.id)
    }
}
