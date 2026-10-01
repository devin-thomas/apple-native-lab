import Foundation
@testable import PeerSession
import Testing

/// LAB-019-B: the reusable `PeerSession` contract, qualified for the experiments that build on it
/// (a Watch relay, Together Mode, Television Stage, Aware Link, and others). Each test states one
/// rule of the live session envelope in docs/DATA_CONTRACTS.md, or one limit of it that a later
/// vocabulary or transport must know about, and checks it with the `Tally` vocabulary over the
/// loopback with manual clocks. Fixture path: no network, no device.
///
/// One test recorded behavior the contract did not want, as a known issue: Forget left the
/// forgotten peer's held commands waiting. It now passes (the fix is in `Conductor.forget` and
/// `Conductor.settle`; its negative cases are in `PeerSessionForget`). Two more record limits a
/// later experiment must design around: a command queued before any snapshot is judged against
/// revision 0, and the conductor's age check starts with a link's first clock round trip.
@Suite(.timeLimit(.minutes(1))) struct PeerSessionContractQualification {
    // MARK: Stale and duplicate commands

    /// A command a person issued while the link was down carries the revision they saw. If the
    /// conductor moved on meanwhile, the reconnect delivers the current snapshot first, and the
    /// command is refused as stale with that snapshot: reconciled, never applied.
    @Test func aCommandQueuedOfflineAgainstAnOlderRevisionIsRefusedAsStaleAfterTheReconnect() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        await rig.controller.vanish()
        try await until { await rig.conductor.state.peers.first?.presence.isLive == false }
        let id = await rig.controller.send(.add(1))
        await rig.conductor.perform(.set(10))

        try await rig.controller.resume(over: rig.hub.dial(from: "phone again"))
        let result = try await finishedResult(id, on: rig.controller)
        #expect(result.disposition == .stale)
        #expect(result.summary == "Based on revision 0, but the state is at 1. Nothing changed.")
        let conductor = await rig.conductor.state
        let controller = await rig.controller.state
        #expect(conductor.snapshot.value == 10 && conductor.revision == 1)
        #expect(controller.snapshot?.value == 10 && controller.revision == 1)
    }

    /// Eight commands wait for a link; a ninth is not queued. After the reconnect every queued
    /// command still names the revision its person saw, so the first applies and the other seven
    /// are refused as stale: one effect, never eight.
    @Test func theQueueHoldsEightAndEachQueuedCommandIsJudgedOnItsOwnRevision() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        await rig.controller.vanish()
        var ids: [MessageID] = []
        for _ in 1...9 { ids.append(await rig.controller.send(.add(1))) }
        let stages = await rig.controller.state.commands.map(\.stage)
        #expect(stages.prefix(8).allSatisfy { $0 == .queued })
        #expect(stages.last == .queueFull)

        try await rig.controller.resume(over: rig.hub.dial(from: "phone again"))
        var dispositions: [CommandDisposition] = []
        for id in ids.prefix(8) { dispositions.append(try await finishedResult(id, on: rig.controller).disposition) }
        #expect(dispositions == [.applied] + Array(repeating: .stale, count: 7))
        #expect(await rig.conductor.state.snapshot.value == 1)
    }

    /// A command whose answer was lost goes again under its own ID after a reconnect, and the
    /// conductor answers from its record: the same result, never a second effect.
    @Test func aReplayedCommandIDIsAnsweredFromTheRecordAcrossAReconnect() async throws {
        let rig = Rig()
        let ends = try await rig.pair(rig.controller, label: "phone")
        ends.host.setFaults(LoopbackFaults(partitioned: true))
        let id = await rig.controller.send(.add(2))
        try await until { await rig.conductor.state.snapshot.value == 2 }
        await rig.controller.vanish()

        try await rig.controller.resume(over: rig.hub.dial(from: "phone again"))
        let result = try await finishedResult(id, on: rig.controller)
        #expect(result.disposition == .applied && result.revision == 1)
        #expect(await rig.conductor.state.snapshot.value == 2, "applied once")
        #expect(await rig.conductor.state.peers.first?.admittedCommands == 1)
    }

    /// A command held for the person at the conductor outlives the link it came on. Its answer
    /// goes to the peer's next link; if that answer is lost too, the joiner's periodic re-ask
    /// under the same ID gets it from the record.
    @Test func aHeldCommandOutlivesItsLinkAndItsLostAnswerIsRecovered() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        let asked = await rig.controller.send(.ask(40))
        _ = try await eventually { await rig.conductor.state.pending.first }
        try await until {
            if case .received = await rig.controller.state.commands.first(where: { $0.id == asked })?.stage { true } else { false }
        }
        await rig.controller.vanish()
        let ends = rig.hub.dialBothEnds(from: "phone again")
        try await rig.controller.resume(over: ends.joiner)

        // The person allows it while the conductor's frames to the phone are lost.
        ends.host.setFaults(LoopbackFaults(partitioned: true))
        let resolved = await rig.conductor.resolve(asked) { _ in .apply(Tally.Snapshot(value: 40), summary: "Allowed: set to 40.") }
        #expect(resolved?.disposition == .applied)
        ends.host.setFaults(LoopbackFaults())
        #expect(await rig.controller.state.commands.first { $0.id == asked }?.stage.isFinal == false)

        rig.advance(.seconds(2))
        await rig.controller.tick()
        let result = try await finishedResult(asked, on: rig.controller)
        #expect(result.disposition == .applied && result.revision == 1)
        let conductor = await rig.conductor.state
        #expect(conductor.snapshot.value == 40 && conductor.revision == 1)
    }

    // MARK: What a paired peer may say

    /// A paired controller's link checks every envelope against the identity and role the
    /// handshake fixed: one that claims another sender or the conductor's role is dropped and
    /// counted, and the link stays open. What only a conductor sends, and a sample naming another
    /// origin, are dropped by the conductor. None of it reaches the state or another peer.
    @Test func aPairedPeerCannotSpeakForAnotherPeerOrAsTheConductor() async throws {
        let rig = Rig()
        try await rig.pair(rig.display, label: "tv")
        let raw = try await RawJoiner.join(rig)

        try await raw.send(.command(raw.issued(.set(99))), base: 0, claiming: rig.display.identity.id, sequence: 1)
        try await raw.send(.command(raw.issued(.set(98))), base: 0, role: .conductor, sequence: 1)
        try await raw.send(.snapshot(SnapshotBody(revision: 9, state: Tally.Snapshot(value: 500))))
        try await raw.send(.sample(SampleBody(origin: rig.display.identity.id, sample: Tally.Sample(level: 0.5), streamSequence: 1)))
        let id = MessageID()
        try await raw.send(.command(raw.issued(.add(1))), base: 0, id: id)

        let result = try await raw.result(for: id)
        #expect(result.disposition == .applied && result.revision == 1, "the link stayed open")
        #expect(await rig.conductor.state.snapshot.value == 1)
        let status = try #require(await rig.conductor.state.peers.first { $0.identity.name == raw.name })
        #expect(status.counters.refusedFrames == 2, "two impersonating envelopes")
        let events = await rig.conductor.state.events.map(\.text)
        #expect(events.contains("Dropped a message only a conductor may send, from \(raw.name)."))
        #expect(events.contains("Dropped a sample \(raw.name) may not send."))
        try await until { await rig.display.state.snapshot?.value == 1 }
        #expect(await rig.display.state.samples.isEmpty, "no sample was relayed")
    }

    /// A sealed frame sent a second time reuses its counter. It is refused as unauthenticated and
    /// the link is closed: a recorded frame cannot be replayed into a session.
    @Test func aReplayedSealedFrameClosesTheLinkAndAppliesNothingTwice() async throws {
        let rig = Rig()
        let raw = try await RawJoiner.join(rig)
        let id = MessageID()
        let frame = try await raw.send(.command(raw.issued(.add(1))), base: 0, id: id)
        #expect(try await raw.result(for: id).disposition == .applied)

        try await raw.resend(frame)
        try await until { await rig.conductor.state.peers.first?.presence.isLive == false }
        #expect(await rig.conductor.state.snapshot.value == 1)
        let events = await rig.conductor.state.events.map(\.text)
        #expect(events.contains("A frame from \(raw.name) failed authentication. The link was closed."))
    }

    /// A display receives the state and the controller's samples, never another peer's commands
    /// or their answers; a controller receives no samples.
    @Test func eachRoleReceivesOnlyWhatItsRoleIsFor() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        try await rig.pair(rig.display, label: "tv")
        let added = await rig.controller.send(.add(3))
        _ = try await finishedResult(added, on: rig.controller)
        let asked = await rig.controller.send(.ask(9))
        _ = try await eventually { await rig.conductor.state.pending.first }
        await rig.conductor.resolve(asked) { _ in .refuse(summary: "Declined.") }
        await rig.controller.publish(Tally.Sample(level: 0.4))
        try await until { await rig.display.state.samples.isEmpty == false }
        await rig.tickAll()
        try await until { await rig.display.state.clock != nil }

        let displayKinds = Set(rig.displayWire.all.filter { $0.direction == .received }.map(\.kind))
        #expect(displayKinds.isSubset(of: ["snapshot", "sample", "clock-ping", "clock-pong"]), "\(displayKinds.sorted())")
        #expect(displayKinds.contains("sample"))
        let controllerKinds = Set(rig.controllerWire.all.filter { $0.direction == .received }.map(\.kind))
        #expect(controllerKinds.contains("result") && !controllerKinds.contains("sample"), "\(controllerKinds.sorted())")
    }

    // MARK: Pairing and trust

    /// Pairing closes by itself when its window ends. A device that asks afterwards is refused
    /// before any challenge, and nothing is pinned.
    @Test func pairingClosesByItselfAfterItsWindow() async throws {
        let rig = Rig()
        await rig.conductor.openPairing()
        #expect(await rig.conductor.state.pairing?.attemptsLeft == 3)
        rig.advance(.seconds(121))
        await rig.conductor.tick()
        #expect(await rig.conductor.state.pairing == nil)
        await #expect(throws: HandshakeFailure.refused(.pairingClosed, theirOffer: Tally.offer)) {
            try await rig.controller.pair(over: rig.hub.dial(from: "late phone"))
        }
        #expect(await rig.conductorTrust.all().isEmpty)
        #expect(await rig.controller.state.host == nil)
    }

    /// A device paired as a display that asks to resume as a controller is told to pair, before
    /// any session data, like a device never paired.
    @Test func aPeerPairedForOneRoleCannotResumeAsAnother() async throws {
        let rig = Rig()
        let tvKey = LocalIdentity(name: "Living room TV")
        await rig.conductorTrust.pin(PinnedPeer(identity: tvKey.identity, roles: [.display], pinnedAt: .now))
        let trust = InMemoryTrustStore()
        await trust.pin(PinnedPeer(identity: rig.conductorIdentity.identity, roles: [.conductor], pinnedAt: .now))
        let asController = Client<Tally>(configuration: .init(identity: tvKey, role: .controller, trust: trust, clock: rig.displayClock))
        await #expect(throws: HandshakeFailure.refused(.pairingRequired, theirOffer: Tally.offer)) {
            try await asController.resume(over: rig.hub.dial(from: "tv as controller"), to: rig.conductorIdentity.id)
        }
        let seen = await asController.state
        #expect(seen.snapshot == nil && seen.sessionID == nil && seen.revision == nil)
    }

    /// Forget unpins a peer and closes its link, and its held commands go with it, so that no one
    /// at the conductor can allow a request from a device they just forgot.
    @Test func forgettingAPeerWithdrawsItsHeldCommands() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        let asked = await rig.controller.send(.ask(40))
        _ = try await eventually { await rig.conductor.state.pending.first }
        await rig.conductor.forget(rig.controller.identity.id)
        #expect(await rig.conductorTrust.all().isEmpty)

        #expect(await rig.conductor.state.pending.isEmpty)
        let late = await rig.conductor.resolve(asked) { _ in .apply(Tally.Snapshot(value: 40), summary: "Allowed.") }
        #expect(late == nil, "a forgotten peer's request is no longer waiting")
        let allowed = await rig.conductor.settle(asked) { _ in HeldDecision { _ in .apply(Tally.Snapshot(value: 40), summary: "Allowed.") } }
        #expect(allowed.refusal == .peerForgotten)
        #expect(await rig.conductor.state.snapshot.value == 0)
    }

    // MARK: Limits a later vocabulary must know

    /// A command a person queues before the joiner has held any snapshot names revision 0 and no
    /// epoch. It applies if the conductor is still at revision 0 and is refused as stale
    /// otherwise. Local Constellation's controls stay disabled until a snapshot arrives; a later
    /// experiment's must too.
    @Test func aCommandQueuedBeforeAnySnapshotIsJudgedAgainstRevisionZero() async throws {
        let moved = Rig()
        await moved.conductor.perform(.set(5))
        let early = await moved.controller.send(.add(1))
        let tracked = try #require(await moved.controller.state.commands.first { $0.id == early })
        #expect(tracked.baseRevision == 0 && tracked.issuedIn == nil)
        try await moved.pair(moved.controller, label: "phone")
        #expect(try await finishedResult(early, on: moved.controller).disposition == .stale)
        #expect(await moved.conductor.state.snapshot.value == 5)

        // At revision 0 the same command applies, though its person saw no state.
        let fresh = Rig()
        let unseen = await fresh.controller.send(.add(1))
        try await fresh.pair(fresh.controller, label: "phone")
        #expect(try await finishedResult(unseen, on: fresh.controller).disposition == .applied)
    }

    /// The conductor measures a command's age with the clock estimate of its link, which needs
    /// one probe round trip and is discarded with each new link. Until then the joiner's own
    /// 5-second check bounds a command's age: commands flushed right after a reconnect rely on it.
    @Test func theConductorJudgesAgeOnlyOnceTheLinkHasAClockEstimate() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        #expect(await rig.conductor.state.peers.first?.clock == nil, "no probe has completed")
        // The phone's clock stalls while the conductor's runs on: with an estimate this command
        // would be refused as expired (theConductorMeasuresCommandAgeWithTheClockEstimate).
        rig.conductorClock.advance(by: .seconds(10))
        let id = await rig.controller.send(.add(1))
        #expect(try await finishedResult(id, on: rig.controller).disposition == .applied)
    }

    /// The format checks the keys of the envelope, its payload, and the vocabulary's command,
    /// sample, and snapshot objects. An object nested inside one of those is checked only by its
    /// own decoder, and a synthesized `Decodable` ignores unknown keys. A vocabulary with nested
    /// objects must decode them strictly itself; Local Constellation's payloads are flat.
    @Test func keyCheckingCoversTheVocabularysOwnObjectsButNotObjectsNestedInThem() throws {
        let snapshot = Nested.Snapshot(lead: .init(name: "a"), parts: [.init(name: "b")])
        let envelope = SessionEnvelope<Nested>(
            protocolVersion: 1, sessionID: LiveSessionID(), sessionEpoch: SessionEpoch(rawValue: 3), messageID: MessageID(),
            senderPeerID: LocalIdentity(name: "Mac").id, role: .conductor, sequence: 1, sentAt: PeerInstant(nanoseconds: 1),
            baseRevision: nil, message: .snapshot(SnapshotBody(revision: 1, state: snapshot))
        )
        func decodes(_ edit: (inout [String: Any]) -> Void) throws -> Bool {
            var object = try #require(try JSONSerialization.jsonObject(with: envelope.json) as? [String: Any])
            var payload = try #require(object["payload"] as? [String: Any])
            var state = try #require(payload["state"] as? [String: Any])
            edit(&state)
            payload["state"] = state
            object["payload"] = payload
            return (try? SessionEnvelope<Nested>(json: JSONSerialization.data(withJSONObject: object))) != nil
        }
        #expect(try decodes { _ in })
        #expect(try !decodes { $0["grant"] = "commit" }, "the snapshot object's own keys are checked")
        #expect(try decodes { state in
            state["lead"] = ["name": "a", "grant": "commit"]
        }, "an object inside the snapshot is not")
        #expect(try decodes { state in
            state["parts"] = [["name": "b", "path": "/etc"]]
        }, "nor an object inside an array")
    }

    // MARK: Transports

    /// What every `PeerConnection` must do, shown on the loopback: whole frames in order up to the
    /// limit, oversize and empty frames refused at the sender, and a close that finishes the other
    /// side and makes further sends fail. A later transport (a Watch relay, Wi-Fi Aware) owes the
    /// same, and `PeerSessionNetworkTests` checks the Network framework adapter over TCP.
    @Test func theLoopbackMeetsTheConnectionContractEveryTransportOwes() async throws {
        let (a, b) = LoopbackConnection.pair("a", "b")
        let frames = [Data([0x01]), Data(repeating: 0x5A, count: FrameCodec.maximumFrameBytes), Data("last".utf8)]
        for frame in frames { try await a.send(frame) }
        var iterator = b.incoming.makeAsyncIterator()
        var received: [Data] = []
        for _ in frames { if let frame = try await iterator.next() { received.append(frame) } }
        #expect(received == frames)
        await #expect(throws: TransportError.frame(.tooLarge(FrameCodec.maximumFrameBytes + 1))) {
            try await a.send(Data(count: FrameCodec.maximumFrameBytes + 1))
        }
        await #expect(throws: TransportError.frame(.empty)) { try await a.send(Data()) }
        a.close()
        #expect(try await iterator.next() == nil, "closing one end finishes the other's frames")
        await #expect(throws: TransportError.closed) { try await b.send(Data([0x01])) }
    }
}

// MARK: - Support

/// The final answer to `id` on `client`.
func finishedResult(_ id: MessageID, on client: Client<Tally>) async throws -> CommandResult {
    try await eventually {
        if case .finished(let result) = await client.state.commands.first(where: { $0.id == id })?.stage { result } else { nil }
    }
}

/// A controller the conductor pinned, driven by hand: the test numbers and seals each envelope
/// itself, so it can send what a well-behaved `Client` never would. It receives through a real
/// `PeerLink`, which opens frames with its own copy of the receiving key.
actor RawJoiner {
    nonisolated let name: String
    private let identity: LocalIdentity
    private let link: PeerLink<Tally>
    private let connection: any PeerConnection
    private var channel: SecureChannel
    private var next: [Channel: UInt64] = [.reliable: 1, .replaceable: 1]
    private var session = LiveSessionID()
    private var epoch = SessionEpoch(rawValue: 0)
    private var results: [MessageID: CommandResult] = [:]

    private init(name: String, identity: LocalIdentity, established: EstablishedLink) {
        self.name = name
        self.identity = identity
        link = PeerLink<Tally>(established, isHost: false, clock: ManualPeerClock())
        connection = established.connection
        channel = established.channel
    }

    /// Pins a new controller at the rig's conductor, as an earlier pairing would have, and resumes.
    static func join(_ rig: Rig, name: String = "Hand-driven phone") async throws -> RawJoiner {
        let identity = LocalIdentity(name: name)
        await rig.conductorTrust.pin(PinnedPeer(identity: identity.identity, roles: [.controller], pinnedAt: .now))
        let trust = InMemoryTrustStore()
        await trust.pin(PinnedPeer(identity: rig.conductorIdentity.identity, roles: [.conductor], pinnedAt: .now))
        let handshake = JoinerHandshake(identity: identity, offer: Tally.offer, role: .controller, trust: trust, stepTimeout: .seconds(5))
        let established = try await handshake.run(on: rig.hub.dial(from: name), mode: .resume(host: rig.conductorIdentity.id))
        let joiner = RawJoiner(name: name, identity: identity, established: established)
        try await joiner.readSnapshot()
        return joiner
    }

    private func readSnapshot() async throws {
        let envelope = try #require(await link.receive())
        guard case .snapshot = envelope.message else { throw TimedOut() }
        session = envelope.sessionID
        epoch = envelope.sessionEpoch
    }

    func issued(_ command: Tally.Command) -> IssuedCommand<Tally.Command> {
        IssuedCommand(command: command, issuedAt: PeerInstant(nanoseconds: 0), issuedIn: epoch)
    }

    /// Seals and sends one envelope. `sequence`, when given, is used without advancing the
    /// channel's count, for an envelope the conductor's link drops before it counts.
    @discardableResult
    func send(
        _ message: SessionMessage<Tally>,
        base: Int? = nil,
        id: MessageID = MessageID(),
        claiming sender: PeerID? = nil,
        role: PeerRole = .controller,
        sequence fixed: UInt64? = nil
    ) async throws -> Data {
        let sequence = fixed ?? next[message.channel, default: 1]
        if fixed == nil { next[message.channel] = sequence + 1 }
        let envelope = SessionEnvelope<Tally>(
            protocolVersion: 1, sessionID: session, sessionEpoch: epoch, messageID: id, senderPeerID: sender ?? identity.id,
            role: role, sequence: sequence, sentAt: PeerInstant(nanoseconds: 0), baseRevision: base, message: message
        )
        let frame = try channel.seal(envelope.json)
        try await connection.send(frame)
        return frame
    }

    /// Sends exact bytes again.
    func resend(_ frame: Data) async throws {
        try await connection.send(frame)
    }

    /// Reads until the conductor's final answer to `id`.
    func result(for id: MessageID) async throws -> CommandResult {
        while results[id]?.disposition.isFinal != true {
            guard let envelope = await link.receive() else { throw TimedOut() }
            if case .result(let result) = envelope.message { results[result.commandID] = result }
        }
        return try #require(results[id])
    }
}

/// A vocabulary whose snapshot holds nested objects, for the key-checking limit.
enum Nested: SessionVocabulary {
    struct Part: Codable, Hashable, Sendable {
        let name: String
    }

    struct Snapshot: WirePayload {
        let lead: Part
        let parts: [Part]
        static let wireKeys: Set<String> = ["lead", "parts"]
        var isValid: Bool { parts.count <= 4 }
    }

    typealias Command = Tally.Command
    typealias Sample = Tally.Sample

    static let offer = ProtocolOffer(name: "native-lab.nested", versions: 1...1)
    static func rolesAllowed(toSend command: Command) -> Set<PeerRole> { [.controller] }
    static let sampleSenders: Set<PeerRole> = []
    static let sampleReceivers: Set<PeerRole> = []
}
