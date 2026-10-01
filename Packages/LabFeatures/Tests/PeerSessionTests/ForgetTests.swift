import Foundation
@testable import PeerSession
import Synchronization
import Testing

/// Forget ends a pairing at once: the pin, the links, and every request the peer has waiting go
/// together, and nothing from that pairing can be admitted or allowed afterwards, by a person
/// at the conductor, a late frame, a handshake already under way, or the same device after it
/// pairs again. LAB-019-B found that Forget left held requests waiting and Allow committed them;
/// these are its negative cases. Fixture path: the `Tally` vocabulary over the loopback, manual
/// clocks.
@Suite(.timeLimit(.minutes(1))) struct PeerSessionForget {
    // MARK: Forget, then Allow

    /// Forget withdraws every waiting request with the pin and the link. The conductor's list
    /// empties at once, and the device hears that each request was withdrawn before it hears it
    /// was forgotten.
    @Test func forgetWithdrawsEveryWaitingRequestAndTellsTheDevice() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        let first = await rig.controller.send(.ask(40))
        let second = await rig.controller.send(.ask(41))
        try await until { await rig.conductor.state.pending.count == 2 }

        await rig.conductor.forget(rig.controller.identity.id)
        let state = await rig.conductor.state
        #expect(state.pending.isEmpty)
        #expect(state.peers.isEmpty)
        #expect(await rig.conductorTrust.all().isEmpty)
        for id in [first, second] {
            let result = try await finishedResult(id, on: rig.controller)
            #expect(result.disposition == .refused)
            #expect(result.summary == "Withdrawn: the conductor forgot the device that asked. Nothing changed.")
        }
        try await until { await rig.controller.state.host == nil }
        #expect(state.snapshot.value == 0 && state.revision == 0)
    }

    /// The person at the conductor presses Allow on a request the screen still showed when the
    /// device was forgotten. The conductor refuses it with the reason before the host's commit
    /// runs; resolving it finds nothing; an ID it never held is refused as not waiting.
    @Test func anAllowAfterForgetIsRefusedWithItsReasonAndCommitsNothing() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        let asked = await rig.controller.send(.ask(40))
        let shown = try await eventually { await rig.conductor.state.pending.first }
        await rig.conductor.forget(rig.controller.identity.id)

        let commits = Count()
        let allowed = await rig.conductor.settle(shown.commandID) { _ in
            commits.add()
            return HeldDecision { _ in .apply(Tally.Snapshot(value: 40), summary: "Allowed.") }
        }
        #expect(allowed.refusal == .peerForgotten)
        #expect(allowed.refusal?.explanation == "The device that asked was forgotten, so its request was withdrawn. Nothing changed.")
        #expect(commits.value == 0, "the host's commit never ran")
        #expect(await rig.conductor.resolve(asked) { _ in .apply(Tally.Snapshot(value: 40), summary: "Allowed.") } == nil)

        let unknown = await rig.conductor.settle(MessageID()) { _ in
            commits.add()
            return HeldDecision { _ in .apply(Tally.Snapshot(value: 40), summary: "Allowed.") }
        }
        #expect(unknown.refusal == .notWaiting)
        #expect(commits.value == 0)
        #expect(await rig.conductor.state.snapshot.value == 0)
    }

    /// A request still waits, but the trust store no longer pins its device (a host reset its
    /// store without telling the conductor). Allow is refused before the commit runs.
    @Test func anAllowForADeviceTheTrustStoreNoLongerPinsIsRefused() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        let asked = await rig.controller.send(.ask(40))
        _ = try await eventually { await rig.conductor.state.pending.first }
        await rig.conductorTrust.forget(rig.controller.identity.id)

        let commits = Count()
        let allowed = await rig.conductor.settle(asked) { _ in
            commits.add()
            return HeldDecision { _ in .apply(Tally.Snapshot(value: 40), summary: "Allowed.") }
        }
        #expect(allowed.refusal == .peerNotPaired)
        #expect(commits.value == 0)
        let result = try await finishedResult(asked, on: rig.controller)
        #expect(result.disposition == .refused)
        #expect(result.summary == "Withdrawn: the device that asked is no longer paired. Nothing changed.")
        #expect(await rig.conductor.state.snapshot.value == 0)
    }

    // MARK: Forget, then a late frame

    /// A request the device sent before the Forget reaches the conductor only after the Forget
    /// began (it waited in the receiving side's buffers). It is dropped: never held, never
    /// answered, never allowable.
    @Test func aRequestThatArrivesAfterForgetBeganIsDropped() async throws {
        let rig = GatedRig()
        let phone = rig.client("Pocket phone")
        let hostEnd = try await rig.pair(phone)
        hostEnd.hold()
        let late = await phone.send(.ask(40))
        try await until { hostEnd.heldFrames == 1 }

        await rig.trust.closeGate()
        let forgetting = Task { await rig.conductor.forget(phone.identity.id) }
        try await until { await rig.trust.forgetIsWaiting }
        let opened = rig.receivedCommands
        hostEnd.release()
        try await until { rig.receivedCommands == opened + 1 }
        // The conductor's link opened the late frame after the Forget began; give the session
        // time to act on it, as the unfixed conductor did by holding it.
        try await Task.sleep(for: .milliseconds(100))
        #expect(await rig.conductor.state.pending.isEmpty)
        await rig.trust.openGate()
        await forgetting.value

        #expect(await rig.conductor.state.pending.isEmpty)
        let allowed = await rig.conductor.settle(late) { _ in HeldDecision { _ in .apply(Tally.Snapshot(value: 40), summary: "Allowed.") } }
        #expect(allowed.refusal == .notWaiting, "it was never held")
        #expect(await rig.conductor.state.snapshot.value == 0)
        try await until { await phone.state.commands.first { $0.id == late }?.stage == .withdrawn }
    }

    /// A resume whose handshake passed the pin check before the Forget unpinned the device, and
    /// finished after, is not adopted: the device is told to pair again before any session data.
    @Test func aResumeThatFinishesWhileForgetIsUnpinningIsNotAdopted() async throws {
        let rig = GatedRig()
        let phone = rig.client("Pocket phone")
        try await rig.pair(phone)
        await phone.vanish()
        try await until { await rig.conductor.state.peers.first?.presence.isLive == false }

        await rig.trust.closeGate()
        let forgetting = Task { await rig.conductor.forget(phone.identity.id) }
        try await until { await rig.trust.forgetIsWaiting }
        let snapshotsBefore = rig.sentSnapshots
        try await phone.resume(over: rig.listener.dial(from: "phone again").joiner)
        try await until { await phone.state.host == nil }
        #expect(await phone.state.phase == .disconnected(reason: "The conductor forgot this device. Pair again to rejoin."))
        #expect(rig.sentSnapshots == snapshotsBefore, "no session data reached it")
        #expect(await rig.conductor.state.peers.isEmpty)
        await rig.trust.openGate()
        await forgetting.value
        #expect(await rig.trust.all().isEmpty)
        #expect(await rig.conductor.state.events.map(\.text).contains("Pocket phone finished joining after it was forgotten, and was told to pair again."))
    }

    // MARK: Forget, pair again, replay

    /// The forgotten device pairs again. It does not send its withdrawn request under the new
    /// pairing, and a copy of that request under its old ID (from a device that kept its queue)
    /// gets the withdrawn answer and is never held. A new request from the new pairing is held
    /// and allowed as usual.
    @Test func aDeviceThatPairsAgainCannotReplayARequestFromBeforeItWasForgotten() async throws {
        let rig = Rig()
        let key = LocalIdentity(name: "Pocket phone")
        let ids = MessageIDQueue()
        let makePhone = {
            Client<Tally>(configuration: .init(
                identity: key, role: .controller, trust: InMemoryTrustStore(), clock: rig.controllerClock,
                handshakeTimeout: .seconds(5), makeMessageID: ids.next
            ))
        }
        let phone = makePhone()
        try await rig.pair(phone, label: "phone")
        let asked = await phone.send(.ask(40))
        _ = try await eventually { await rig.conductor.state.pending.first }
        await rig.conductor.forget(key.id)
        #expect(try await finishedResult(asked, on: phone).summary == "Withdrawn: the conductor forgot the device that asked. Nothing changed.")

        // The same device pairs again, and its clock runs past every resend interval.
        let commandsBefore = rig.receivedCommands
        try await rig.pair(phone, label: "phone again")
        for _ in 1...4 {
            rig.advance(.seconds(1))
            await phone.tick()
        }
        #expect(rig.receivedCommands == commandsBefore, "nothing from the old pairing was sent")
        #expect(await rig.conductor.state.pending.isEmpty)
        await phone.disconnect()

        // A copy of the device that kept the old request replays it under its old ID.
        let restored = makePhone()
        try await rig.pair(restored, label: "phone restored")
        ids.push(asked)
        #expect(await restored.send(.ask(40)) == asked)
        let replayed = try await finishedResult(asked, on: restored)
        #expect(replayed.disposition == .refused)
        #expect(replayed.summary == "Withdrawn: the conductor forgot the device that asked. Nothing changed.")
        #expect(await rig.conductor.state.pending.isEmpty)
        let allowed = await rig.conductor.settle(asked) { _ in HeldDecision { _ in .apply(Tally.Snapshot(value: 40), summary: "Allowed.") } }
        #expect(allowed.refusal == .peerForgotten)
        #expect(await rig.conductor.state.snapshot.value == 0)

        // The new pairing works: a new request is held and allowed.
        let fresh = await restored.send(.ask(41))
        _ = try await eventually { await rig.conductor.state.pending.first { $0.commandID == fresh } }
        let settled = await rig.conductor.settle(fresh) { _ in HeldDecision { _ in .apply(Tally.Snapshot(value: 41), summary: "Allowed.") } }
        #expect(try settled.get().result.disposition == .applied)
        #expect(try await finishedResult(fresh, on: restored).disposition == .applied)
    }

    // MARK: Allow racing Forget

    /// An Allow whose commit is under way when the Forget begins finishes first, and the Forget
    /// returns after it: the commit started while the device was paired. A second Allow while
    /// the first runs is refused, and so is one after both.
    @Test func anAllowThatBeganBeforeForgetFinishesFirst() async throws {
        let rig = Rig()
        try await rig.pair(rig.controller, label: "phone")
        let asked = await rig.controller.send(.ask(40))
        _ = try await eventually { await rig.conductor.state.pending.first }
        let gate = Gate()
        let order = Order()
        let allowing = Task {
            await rig.conductor.settle(asked) { _ in
                await gate.wait()
                order.append("committed")
                return HeldDecision { _ in .apply(Tally.Snapshot(value: 40), summary: "Allowed.") }
            }
        }
        try await until { await gate.isWaiting }
        #expect(await rig.conductor.state.pending.isEmpty, "taken while it is decided")

        let forgetting = Task {
            await rig.conductor.forget(rig.controller.identity.id)
            order.append("forgotten")
        }
        try await until { await rig.conductorTrust.all().isEmpty }
        let second = await rig.conductor.settle(asked) { _ in HeldDecision { _ in .apply(Tally.Snapshot(value: 99), summary: "Again.") } }
        #expect(second.refusal == .alreadyDeciding)
        #expect(order.all.isEmpty, "the Forget waits for the Allow under way")

        await gate.open()
        let settled = try await allowing.value.get()
        await forgetting.value
        #expect(order.all == ["committed", "forgotten"])
        #expect(settled.result.disposition == .applied)
        #expect(await rig.conductor.state.snapshot.value == 40)
        let late = await rig.conductor.settle(asked) { _ in HeldDecision { _ in .apply(Tally.Snapshot(value: 99), summary: "Again.") } }
        #expect(late.refusal == .peerForgotten)
        #expect(await rig.conductor.state.snapshot.value == 40)
    }

    /// Allow and Forget pressed at the same moment, many times over. Each time exactly one of two
    /// things happens: the commit ran and the change applied, or the Allow was refused as
    /// forgotten and the commit never ran. Never a commit the conductor then refused, and
    /// nothing waiting afterwards.
    @Test func anAllowRacingForgetCommitsCompletelyOrNotAtAll() async throws {
        var outcomes: [String: Int] = [:]
        for _ in 1...30 {
            let rig = Rig()
            try await rig.pair(rig.controller, label: "phone")
            let asked = await rig.controller.send(.ask(40))
            _ = try await eventually { await rig.conductor.state.pending.first }
            let commits = Count()
            async let allowed = rig.conductor.settle(asked) { _ in
                commits.add()
                return HeldDecision { _ in .apply(Tally.Snapshot(value: 40), summary: "Allowed.") }
            }
            async let forgot: Void = rig.conductor.forget(rig.controller.identity.id)
            let (outcome, _) = await (allowed, forgot)
            let value = await rig.conductor.state.snapshot.value
            switch outcome {
            case .success(let settled):
                #expect(commits.value == 1 && settled.result.disposition == .applied && value == 40)
                outcomes["allowed first", default: 0] += 1
            case .failure(let refusal):
                #expect(commits.value == 0 && refusal == .peerForgotten && value == 0)
                outcomes["forgotten first", default: 0] += 1
            }
            #expect(await rig.conductor.state.pending.isEmpty)
            #expect(await rig.conductorTrust.all().isEmpty)
        }
        print("LAB-019 Allow racing Forget, 30 runs: \(outcomes.sorted { $0.key < $1.key })")
    }
}

extension Result where Failure == HeldCommandRefusal {
    var refusal: HeldCommandRefusal? {
        if case .failure(let refusal) = self { refusal } else { nil }
    }
}

// MARK: - Test doubles

/// A counter a `@Sendable` closure can bump.
final class Count: Sendable {
    private let count = Mutex(0)
    func add() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

/// Words in the order things happened.
final class Order: Sendable {
    private let words = Mutex<[String]>([])
    func append(_ word: String) { words.withLock { $0.append(word) } }
    var all: [String] { words.withLock { $0 } }
}

/// A host's commit in progress: it waits until the test opens the gate.
actor Gate {
    private var waiter: CheckedContinuation<Void, Never>?
    private var isOpen = false
    var isWaiting: Bool { waiter != nil }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}

/// Message IDs for a client: the queued ones first, then new ones.
final class MessageIDQueue: Sendable {
    private let queued = Mutex<[MessageID]>([])
    func push(_ id: MessageID) { queued.withLock { $0.append(id) } }
    var next: @Sendable () -> MessageID {
        { [self] in queued.withLock { $0.isEmpty ? MessageID() : $0.removeFirst() } }
    }
}

/// A trust store whose `forget` can be held at its start, so a test can act while a Forget is
/// unpinning a peer.
actor GatedTrustStore: PeerTrustStore {
    private let pins = InMemoryTrustStore()
    private var closed = false
    private var waiter: CheckedContinuation<Void, Never>?
    var forgetIsWaiting: Bool { waiter != nil }

    func closeGate() { closed = true }

    func openGate() {
        closed = false
        waiter?.resume()
        waiter = nil
    }

    func pin(_ peer: PinnedPeer) async { await pins.pin(peer) }
    func check(_ identity: PeerIdentity, role: PeerRole) async -> PinCheck { await pins.check(identity, role: role) }
    func pinned(_ id: PeerID) async -> PinnedPeer? { await pins.pinned(id) }
    func all() async -> [PinnedPeer] { await pins.all() }

    func forget(_ id: PeerID) async {
        if closed { await withCheckedContinuation { waiter = $0 } }
        await pins.forget(id)
    }
}

/// The conductor's end of a loopback connection whose incoming frames can be held back, as a
/// network's receive buffers can hold a frame the sender sent before a Forget.
final class HeldBackConnection: PeerConnection {
    private struct State {
        var holding = false
        var held: [Data] = []
    }

    let incoming: AsyncThrowingStream<Data, any Error>
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    private let inner: LoopbackConnection
    private let state = Mutex(State())

    init(_ inner: LoopbackConnection) {
        self.inner = inner
        (incoming, continuation) = AsyncThrowingStream<Data, any Error>.makeStream(bufferingPolicy: .unbounded)
        Task { [inner, continuation, weak self] in
            do {
                for try await frame in inner.incoming { self?.forward(frame) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    private func forward(_ frame: Data) {
        let passes = state.withLock { state in
            if state.holding { state.held.append(frame) }
            return !state.holding
        }
        if passes { continuation.yield(frame) }
    }

    var remoteLabel: String { inner.remoteLabel }
    func send(_ frame: Data) async throws(TransportError) { try await inner.send(frame) }
    func close() { inner.close() }

    func hold() { state.withLock { $0.holding = true } }
    var heldFrames: Int { state.withLock { $0.held.count } }

    func release() {
        let frames = state.withLock { state in
            state.holding = false
            defer { state.held.removeAll() }
            return state.held
        }
        for frame in frames { continuation.yield(frame) }
    }
}

final class HeldBackListener: PeerListener {
    let connections: AsyncStream<any PeerConnection>
    private let continuation: AsyncStream<any PeerConnection>.Continuation

    init() {
        (connections, continuation) = AsyncStream<any PeerConnection>.makeStream()
    }

    func dial(from label: String) -> (joiner: LoopbackConnection, host: HeldBackConnection) {
        let (joiner, host) = LoopbackConnection.pair(label, "conductor")
        let held = HeldBackConnection(host)
        continuation.yield(held)
        return (joiner, held)
    }

    func stop() { continuation.finish() }
}

/// A conductor whose trust store can hold a Forget and whose connections can hold back frames.
struct GatedRig {
    let trust = GatedTrustStore()
    let listener = HeldBackListener()
    let clock = ManualPeerClock(start: PeerInstant(nanoseconds: 5_000_000_000))
    let conductorIdentity = LocalIdentity(name: "Studio Mac")
    let wire = WireLog()
    let conductor: Conductor<Tally>

    init() {
        conductor = Conductor(
            configuration: .init(
                identity: conductorIdentity, trust: trust, clock: clock, epoch: SessionEpoch(rawValue: 7),
                handshakeTimeout: .seconds(5), wireRecord: { [wire] in wire.append($0) }
            ),
            initialState: Tally.Snapshot(value: 0),
            decide: Tally.decide
        )
        conductor.listenNow(on: listener)
    }

    func client(_ name: String) -> Client<Tally> {
        Client(configuration: .init(
            identity: LocalIdentity(name: name), role: .controller, trust: InMemoryTrustStore(),
            clock: ManualPeerClock(start: PeerInstant(nanoseconds: 900_000_000_000)), handshakeTimeout: .seconds(5)
        ))
    }

    /// Pairs `client` with the code, as `Rig.pair` does, and returns the conductor's end.
    func pair(_ client: Client<Tally>) async throws -> HeldBackConnection {
        await conductor.openPairing()
        let ends = listener.dial(from: client.identity.name)
        async let joined: Void = client.pair(over: ends.joiner)
        let request = try await eventually { await conductor.state.pairingRequest }
        _ = try await eventually { await client.state.codePrompt }
        #expect(await client.submitCode(request.code.digits))
        await conductor.answerPairing(allow: true)
        try await joined
        _ = try await eventually { await client.state.phase == .live ? true : nil }
        return ends.host
    }

    var receivedCommands: Int { wire.all.filter { $0.direction == .received && $0.kind == "command" }.count }
    var sentSnapshots: Int { wire.all.filter { $0.direction == .sent && $0.kind == "snapshot" }.count }
}

extension Rig {
    /// Commands the conductor's links opened, from every peer.
    var receivedCommands: Int { wire.all.filter { $0.direction == .received && $0.kind == "command" }.count }
}
