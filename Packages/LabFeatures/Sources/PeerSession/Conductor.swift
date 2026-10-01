import Foundation

/// What the conductor's rules decide for one command.
public enum CommandDecision<Snapshot: WirePayload>: Sendable {
    /// Apply it: the state becomes `Snapshot` at the next revision, and every peer gets it.
    case apply(Snapshot, summary: String)
    /// Admit it, but nothing changes.
    case unchanged(summary: String)
    /// Refuse it. Nothing changes.
    case refuse(summary: String)
    /// Hold it for the person at the conductor. The sender hears `received` now; the host later
    /// calls `Conductor.resolve` with the final decision, or it expires.
    case hold(summary: String)
}

/// Who sent a command, as the conductor established it from the link, never from the message.
public struct CommandOrigin: Hashable, Sendable {
    public let peer: PeerIdentity
    public let role: PeerRole

    /// For rules under test. The conductor builds origins from the link a command arrived on.
    public init(peer: PeerIdentity, role: PeerRole) {
        self.peer = peer
        self.role = role
    }
}

/// The authoritative side of a session: it pairs peers, admits their commands, and sends the
/// state to every peer after each change.
///
/// Every command passes the same checks before the experiment's rules see it: the sender's role
/// may send it, it was issued in this epoch, it is not older than the command lifetime (measured
/// with the sender's clock estimate), the sender has not lost sequence continuity, and it is based
/// on the current revision. A replayed command ID gets its recorded answer. A stale command is
/// never applied: the sender gets `stale` and the current snapshot, and decides again.
///
/// A held command belongs to the pairing it arrived under. Forgetting a peer ends that pairing at
/// once: its pin, its links, and every request it has waiting go together, and nothing it sent
/// can be admitted or allowed again, even after the device pairs anew.
public actor Conductor<V: SessionVocabulary> {
    public struct Configuration: Sendable {
        public var identity: LocalIdentity
        public var trust: any PeerTrustStore
        public var clock: any PeerClock
        public var timing: SessionTiming
        public var sessionID: LiveSessionID
        public var epoch: SessionEpoch
        /// How many peers may hold each role at once.
        public var roleLimits: [PeerRole: Int]
        public var handshakeTimeout: Duration
        public var makeMessageID: @Sendable () -> MessageID
        /// Sees every envelope sent and received, for the wire log.
        public var wireRecord: (@Sendable (WireRecord) -> Void)?

        public init(
            identity: LocalIdentity,
            trust: any PeerTrustStore,
            clock: any PeerClock = SystemPeerClock(),
            timing: SessionTiming = .standard,
            sessionID: LiveSessionID = LiveSessionID(),
            epoch: SessionEpoch = .random(),
            roleLimits: [PeerRole: Int] = [.controller: 2, .display: 4],
            handshakeTimeout: Duration = .seconds(10),
            makeMessageID: @escaping @Sendable () -> MessageID = { MessageID() },
            wireRecord: (@Sendable (WireRecord) -> Void)? = nil
        ) {
            self.identity = identity
            self.trust = trust
            self.clock = clock
            self.timing = timing
            self.sessionID = sessionID
            self.epoch = epoch
            self.roleLimits = roleLimits
            self.handshakeTimeout = handshakeTimeout
            self.makeMessageID = makeMessageID
            self.wireRecord = wireRecord
        }
    }

    private struct LinkRecord {
        let token: UInt64
        let link: PeerLink<V>
        let identity: PeerIdentity
        let role: PeerRole
        var lastHeard: PeerInstant
        var lastProbe: PeerInstant?
        var estimator = ClockEstimator()
        var reliableIn = SequenceTracker()
        var replaceableIn = SequenceTracker()
        var counters = LinkCounters()
        var isSynchronized = false
        var sampleInFlight = false
        var queuedSample: SampleBody<V.Sample>?
    }

    private struct PeerHistory {
        var identity: PeerIdentity
        var role: PeerRole
        var links = 0
        var admitted = 0
        var refused = 0
        var replay: [MessageID: CommandResult] = [:]
        var replayOrder: [MessageID] = []
        /// The last link's state, kept after it closes so the roster still shows the peer.
        var lastHeard: PeerInstant
        var closedAt: PeerInstant?
        var lastCounters = LinkCounters()
        var lastClock: ClockEstimate?

        mutating func remember(_ result: CommandResult) {
            if replay[result.commandID] == nil { replayOrder.append(result.commandID) }
            replay[result.commandID] = result
            if replayOrder.count > 64 {
                replay[replayOrder.removeFirst()] = nil
            }
        }
    }

    private struct Pending {
        let command: PendingCommand<V.Command>
        let token: UInt64
        /// The pairing the command arrived under, or `nil` for the conductor's own.
        let pairing: UInt64?
    }

    public nonisolated let identity: PeerIdentity
    public nonisolated let sessionID: LiveSessionID
    public nonisolated let epoch: SessionEpoch
    public nonisolated let states: AsyncStream<ConductorState<V>>

    private let configuration: Configuration
    private let decide: @Sendable (V.Command, V.Snapshot, CommandOrigin) -> CommandDecision<V.Snapshot>
    private let continuation: AsyncStream<ConductorState<V>>.Continuation
    private var snapshot: V.Snapshot
    private var revision = 0
    private var links: [UInt64: LinkRecord] = [:]
    private var peers: [PeerID: PeerHistory] = [:]
    private var pending: [MessageID: Pending] = [:]
    /// Held commands a person is allowing now, through `settle`.
    private var settling: [MessageID: Pending] = [:]
    /// Forgets waiting for an Allow that began before them, by peer.
    private var settleWaiters: [PeerID: [CheckedContinuation<Void, Never>]] = [:]
    /// Each paired peer's current pairing. A peer gets a new one when it joins after a Forget.
    private var pairings: [PeerID: UInt64] = [:]
    private var lastPairing: UInt64 = 0
    /// How many Forgets have begun, and the count when each peer was last forgotten, so a
    /// handshake that overlapped a Forget of its peer is not adopted.
    private var forgets: UInt64 = 0
    private var forgottenAt: [PeerID: UInt64] = [:]
    /// Peers whose Forget is still unpinning them.
    private var revoking: [PeerID: Int] = [:]
    private var retired = RetiredCommands()
    private var pairing: (closesAt: PeerInstant, attemptsLeft: Int)?
    private var approval = PromptSlot<PairingRequest, Bool>()
    private var log = EventLog()
    private var nextToken: UInt64 = 0
    private var tasks: [Task<Void, Never>] = []
    private var stopped = false

    /// - Parameter decide: The experiment's rules for a command that passed every session check.
    public init(
        configuration: Configuration,
        initialState: V.Snapshot,
        decide: @escaping @Sendable (V.Command, V.Snapshot, CommandOrigin) -> CommandDecision<V.Snapshot>
    ) {
        self.configuration = configuration
        identity = configuration.identity.identity
        sessionID = configuration.sessionID
        epoch = configuration.epoch
        snapshot = initialState
        self.decide = decide
        (states, continuation) = AsyncStream<ConductorState<V>>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    // MARK: Accepting peers

    /// Accepts every connection the listener delivers until `stop()`.
    public func listen(on listener: any PeerListener) {
        let task = Task { [weak self] in
            for await connection in listener.connections {
                guard let self else { return }
                await self.accept(connection)
            }
        }
        tasks.append(task)
        note("Listening for peers.")
    }

    /// Runs the handshake on one connection in the background, then serves the peer.
    public func accept(_ connection: any PeerConnection) {
        guard !stopped else {
            connection.close()
            return
        }
        let handshake = HostHandshake(
            configuration: .init(
                identity: configuration.identity, offer: V.offer, trust: configuration.trust,
                stepTimeout: configuration.handshakeTimeout
            ),
            admission: .init(
                acceptsRole: { [weak self] role in await self?.hasRoom(for: role) ?? false },
                takePairingAttempt: { [weak self] in await self?.takePairingAttempt() ?? .closed },
                approve: { [weak self] request in await self?.askApproval(request) ?? false }
            )
        )
        let label = connection.remoteLabel
        let forgetsBefore = forgets
        let task = Task { [weak self] in
            do {
                let established = try await handshake.run(on: connection)
                await self?.adopt(established, forgetsBefore: forgetsBefore)
            } catch {
                await self?.handshakeFailed((error as? HandshakeFailure) ?? .disconnected, label: label)
            }
        }
        tasks.append(task)
    }

    /// Lets new devices pair for `duration`, with at most `attempts` tries.
    public func openPairing(for duration: Duration = .seconds(120), attempts: Int = 3) {
        pairing = (configuration.clock.now().advanced(by: duration), max(1, attempts))
        note("Pairing is open for \(Int(duration.components.seconds)) seconds.")
        publish()
    }

    public func closePairing() {
        pairing = nil
        approval.close(with: false)
        publish()
    }

    /// The person's answer to the open pairing request. Allow only after the other device said
    /// the code matched.
    public func answerPairing(allow: Bool) {
        approval.close(with: allow)
        publish()
    }

    /// Unpins a peer, withdraws every request it has waiting, and closes its links. It must pair
    /// again to return, and nothing it sent before can be admitted or allowed after that.
    ///
    /// Everything that decides whether the peer may act changes before this method first
    /// suspends: a frame that arrives later, an Allow pressed on a request the screen still
    /// shows, and a handshake that finishes later all find the peer forgotten. An Allow that
    /// began before the Forget is finished first; the Forget returns after it.
    public func forget(_ peer: PeerID) async {
        forgets += 1
        forgottenAt[peer] = forgets
        revoking[peer, default: 0] += 1
        pairings[peer] = nil
        var withdrawn: [CommandResult] = []
        for (id, held) in pending where held.command.from.id == peer {
            pending[id] = nil
            let result = CommandResult(
                commandID: id, disposition: .refused, revision: revision,
                summary: "Withdrawn: the conductor forgot the device that asked. Nothing changed."
            )
            retired.retire(result, from: peer)
            withdrawn.append(result)
        }
        if let history = peers.removeValue(forKey: peer) {
            // Their recorded answers stay answerable, and only answerable: never admitted again.
            for id in history.replayOrder {
                if let result = history.replay[id] { retired.retire(result, from: peer) }
            }
        }
        let closing = links.filter { $0.value.identity.id == peer }.sorted { $0.key < $1.key }.map(\.value)
        for record in closing { links[record.token] = nil }
        if !withdrawn.isEmpty { note("Withdrew \(withdrawn.count) waiting request(s) from a forgotten peer.", .notice) }
        publish()

        await configuration.trust.forget(peer)
        revoking[peer, default: 1] -= 1
        if revoking[peer] == 0 { revoking[peer] = nil }
        for record in closing {
            // The device hears its waiting requests were withdrawn, then that it was forgotten.
            for result in withdrawn.sorted(by: { $0.commandID.rawValue.uuidString < $1.commandID.rawValue.uuidString }) {
                _ = try? await record.link.send(.result(result), session: sessionID, epoch: epoch)
            }
            _ = try? await record.link.send(.goodbye(.forgotten), session: sessionID, epoch: epoch)
            await record.link.close()
        }
        while settling.values.contains(where: { $0.command.from.id == peer }) {
            await withCheckedContinuation { settleWaiters[peer, default: []].append($0) }
        }
        note("Forgot a peer. It must pair again to rejoin.")
        publish()
    }

    // MARK: Commands at the conductor

    /// A command from the person at the conductor, through the same rules as a peer's.
    @discardableResult
    public func perform(_ command: V.Command) async -> CommandResult {
        let id = configuration.makeMessageID()
        let origin = CommandOrigin(peer: identity, role: .conductor)
        let result = await judge(command, id: id, origin: origin, token: nil)
        return result
    }

    /// Finishes a held command whose answer needs nothing outside the conductor, such as a
    /// decline. `decide` sees the current state, which may have moved on since the command was
    /// held. Returns `nil` when the command is not waiting: answered, expired, withdrawn with a
    /// forgotten peer, or being allowed through `settle`.
    ///
    /// A host whose Allow commits somewhere else first (a store, through its operation service)
    /// uses `settle`, which takes the command before the commit and checks that its peer is still
    /// paired.
    @discardableResult
    public func resolve(_ id: MessageID, _ decide: @Sendable (V.Snapshot) -> CommandDecision<V.Snapshot>) async -> CommandResult? {
        guard let held = pending[id] else { return nil }
        guard isCurrent(held) else { return nil }
        pending[id] = nil
        let origin = CommandOrigin(peer: held.command.from, role: held.command.role)
        let result = await conclude(decide(snapshot), id: id, origin: origin)
        await answer(result, to: held.command.from.id, token: held.token)
        return result
    }

    /// Allows a held command whose effect is committed outside the conductor.
    ///
    /// The conductor takes the command first, so nothing else can answer it, and checks that its
    /// peer is still paired, by its own record and by the trust store. Only then does `body` run:
    /// the host commits there, and returns the decision to apply against the state at that
    /// moment. A command from a forgotten or unpaired peer is refused before `body` runs, so
    /// nothing is committed for it. A Forget that begins while `body` runs waits for it to finish.
    public func settle<Extra: Sendable>(
        _ id: MessageID,
        _ body: @Sendable (PendingCommand<V.Command>) async -> HeldDecision<V.Snapshot, Extra>
    ) async -> Result<SettledCommand<Extra>, HeldCommandRefusal> {
        guard let held = pending.removeValue(forKey: id) else {
            if settling[id] != nil { return .failure(.alreadyDeciding) }
            if retired.contains(id) { return .failure(.peerForgotten) }
            return .failure(.notWaiting)
        }
        settling[id] = held
        publish()
        let peer = held.command.from
        if let pairing = held.pairing {
            let pin = await configuration.trust.check(peer, role: held.command.role)
            let forgotten = pairings[peer.id] != pairing || revoking[peer.id] != nil
            let pinned = if case .trusted = pin { true } else { false }
            if forgotten || !pinned {
                let result = CommandResult(
                    commandID: id, disposition: .refused, revision: revision,
                    summary: "Withdrawn: the device that asked is no longer paired. Nothing changed."
                )
                retired.retire(result, from: peer.id)
                peers[peer.id]?.refused += 1
                await answer(result, to: peer.id, token: held.token)
                note("Refused to allow a request from \(peer.name): it is no longer paired.", .notice)
                finishSettling(id)
                return .failure(forgotten ? .peerForgotten : .peerNotPaired)
            }
        }
        let decision = await body(held.command)
        let origin = CommandOrigin(peer: peer, role: held.command.role)
        let result = await conclude(decision.decide(snapshot), id: id, origin: origin)
        if let pairing = held.pairing, pairings[peer.id] != pairing {
            // Forgotten while the host committed: the answer stays with the forgotten pairing.
            retired.retire(result, from: peer.id)
        }
        await answer(result, to: peer.id, token: held.token)
        finishSettling(id)
        return .success(SettledCommand(result: result, extra: decision.extra))
    }

    /// Changes the state from outside any command, such as a change another entry point made.
    public func update(_ transform: @Sendable (V.Snapshot) -> V.Snapshot?) async {
        guard let changed = transform(snapshot), changed != snapshot else { return }
        snapshot = changed
        revision += 1
        await broadcastSnapshot()
        publish()
    }

    public var state: ConductorState<V> { makeState() }

    // MARK: Time

    /// Probes clocks, updates presence, and expires held commands and pairing. Call regularly;
    /// `startTicking` does so on a timer.
    public func tick() async {
        let now = configuration.clock.now()
        for (token, record) in links {
            if case .disconnected = configuration.timing.presence(lastHeard: record.lastHeard, now: now) {
                note("\(record.identity.name) went silent and was disconnected.", .notice)
                await record.link.close()
                closeLink(token)
                continue
            }
            if record.lastProbe.map({ now.since($0) >= configuration.timing.probeInterval }) ?? true {
                links[token]?.lastProbe = now
                _ = try? await record.link.send(
                    .clockPing(ClockProbe(originatedAt: now, receivedAt: nil, answeredAt: nil)), session: sessionID, epoch: epoch
                )
            }
        }
        for (id, held) in pending where held.command.expiresAt <= now {
            // Taken, withdrawn, or answered while this loop waited on a send: not this loop's.
            guard pending.removeValue(forKey: id) != nil else { continue }
            let result = CommandResult(
                commandID: id, disposition: .expired, revision: revision,
                summary: "No one at the conductor answered in time. Nothing changed."
            )
            remember(result, for: held.command.from.id)
            await answer(result, to: held.command.from.id, token: held.token)
            note("A held command expired unanswered.", .notice)
        }
        if let window = pairing, window.closesAt <= now {
            pairing = nil
            approval.close(with: false)
            note("Pairing closed.")
        }
        publish()
    }

    /// Calls `tick()` every `interval` until `stop()`.
    public func startTicking(every interval: Duration = .milliseconds(250)) {
        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                await self?.tick()
            }
        }
        tasks.append(task)
    }

    /// Says goodbye to every peer and closes everything. The epoch ends with it.
    public func stop() async {
        stopped = true
        for (token, record) in links {
            _ = try? await record.link.send(.goodbye(.sessionEnded), session: sessionID, epoch: epoch)
            await record.link.close()
            closeLink(token)
        }
        approval.close(with: false)
        for task in tasks { task.cancel() }
        tasks.removeAll()
        note("Session ended.")
        publish()
        continuation.finish()
    }

    // MARK: Handshake admission

    private func hasRoom(for role: PeerRole) -> Bool {
        guard !stopped, let limit = configuration.roleLimits[role], limit > 0 else { return false }
        return links.values.filter { $0.role == role }.count < limit
    }

    private func takePairingAttempt() -> PairingAttemptDecision {
        guard let window = pairing, window.closesAt > configuration.clock.now() else { return .closed }
        guard window.attemptsLeft > 0 else { return .exhausted }
        pairing = (window.closesAt, window.attemptsLeft - 1)
        publish()
        return .allowed
    }

    private func askApproval(_ request: PairingRequest) async -> Bool {
        let id = approval.reserve()
        let allowed: Bool? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                    return
                }
                approval.open(id, request, continuation)
                note("\(request.peer.name) asks to pair as \(request.role.title.lowercased()). Code \(request.code).")
                publish()
            }
        } onCancel: {
            Task { await self.cancelApproval(id) }
        }
        publish()
        return allowed ?? false
    }

    private func cancelApproval(_ id: UInt64) {
        if approval.close(with: nil, id: id) {
            note("The other device ended the pairing.", .notice)
            publish()
        }
    }

    private func handshakeFailed(_ failure: HandshakeFailure, label: String) {
        switch failure {
        case .refusedLocally(.pairingRequired):
            note("An unpaired device tried to rejoin and was told to pair first. It received no session data.", .notice)
        case .refusedLocally(let reason), .refused(let reason, _):
            note("A device could not join: \(reason.explanation)", .notice)
        default:
            note("A device could not join: \(failure.explanation)", .notice)
        }
        publish()
    }

    // MARK: Serving a peer

    private func adopt(_ established: EstablishedLink, forgetsBefore: UInt64) async {
        guard !stopped else {
            established.connection.close()
            return
        }
        let link = PeerLink<V>(
            established, isHost: true, clock: configuration.clock,
            makeMessageID: configuration.makeMessageID, record: configuration.wireRecord
        )
        let peer = established.remote
        // The handshake checked the pin when it began. Check it again now it has finished, after
        // any Forget that overlapped it: what such a handshake established belongs to the
        // pairing the person ended, so the device is told to pair again and nothing it pinned
        // is kept.
        let pin = await configuration.trust.check(peer, role: established.joinerRole)
        let pinned = if case .trusted = pin { true } else { false }
        let overlapped = forgottenAt[peer.id].map { $0 > forgetsBefore } ?? false
        guard !stopped else {
            established.connection.close()
            return
        }
        if overlapped || revoking[peer.id] != nil || !pinned {
            _ = try? await link.send(.goodbye(.forgotten), session: sessionID, epoch: epoch)
            await link.close()
            if established.pairedNow, overlapped { await configuration.trust.forget(peer.id) }
            note("\(peer.name) finished joining after it was forgotten, and was told to pair again.", .notice)
            publish()
            return
        }
        if pairings[peer.id] == nil {
            lastPairing += 1
            pairings[peer.id] = lastPairing
        }
        nextToken += 1
        let token = nextToken
        let now = configuration.clock.now()
        var history = peers[peer.id] ?? PeerHistory(identity: peer, role: established.joinerRole, lastHeard: now)
        history.identity = peer
        history.role = established.joinerRole
        history.links += 1
        history.closedAt = nil
        history.lastHeard = now
        peers[peer.id] = history
        links[token] = LinkRecord(token: token, link: link, identity: peer, role: established.joinerRole, lastHeard: now)
        let verb = established.pairedNow ? "Paired" : (history.links > 1 ? "Reconnected" : "Resumed")
        note("\(verb): \(peer.name) as \(established.joinerRole.title.lowercased()).")
        // The first thing a peer receives is the whole state; it sends nothing until it has it.
        await sendSnapshot(to: token)
        publish()
        let task = Task { [weak self] in
            while let envelope = await link.receive() {
                guard let self else { return }
                await self.handle(envelope, token: token)
            }
            await self?.linkEnded(token)
        }
        tasks.append(task)
    }

    private func linkEnded(_ token: UInt64) async {
        guard let record = links[token] else { return }
        let rejections = await record.link.rejections
        if rejections.contains(.unauthenticated) {
            note("A frame from \(record.identity.name) failed authentication. The link was closed.", .problem)
        }
        note("\(record.identity.name) disconnected.", .notice)
        closeLink(token)
        publish()
    }

    private func closeLink(_ token: UInt64) {
        guard let record = links.removeValue(forKey: token) else { return }
        let now = configuration.clock.now()
        if var history = peers[record.identity.id] {
            history.closedAt = now
            history.lastHeard = record.lastHeard
            history.lastCounters = record.counters
            history.lastClock = record.estimator.estimate
            peers[record.identity.id] = history
        }
        // Held commands outlive the link: the answer goes to the peer's next link, or waits in
        // its replay record for the resend that follows a reconnect.
    }

    private func handle(_ envelope: SessionEnvelope<V>, token: UInt64) async {
        guard let link = links[token]?.link else { return }
        let rejectedCount = await link.rejections.count
        // Read the link's record after the wait: it may have closed, or its peer been forgotten,
        // while this frame was on its way. A frame from a forgotten peer is dropped here.
        guard var record = links[token] else { return }
        let now = configuration.clock.now()
        record.lastHeard = now
        record.counters.refusedFrames = rejectedCount

        guard envelope.sessionID == sessionID, envelope.sessionEpoch == epoch else {
            links[token] = record
            if case .command = envelope.message {
                await reply(.wrongEpoch, id: envelope.messageID, summary: "Sent in an earlier session. Nothing changed.", token: token)
            }
            note("Dropped a message from \(record.identity.name) sent in another session.", .notice)
            publish()
            return
        }

        var continuityLost = false
        switch envelope.channel {
        case .reliable:
            switch record.reliableIn.observe(envelope.sequence) {
            case .inOrder: break
            case .gap(let missing):
                record.counters.reliableGaps += 1
                record.isSynchronized = false
                continuityLost = true
                note("\(missing) reliable message(s) from \(record.identity.name) never arrived. Resynchronizing.", .notice)
            case .stale:
                links[token] = record
                return
            }
        case .replaceable:
            switch record.replaceableIn.observe(envelope.sequence) {
            case .inOrder: break
            case .gap(let missing): record.counters.replaceableMissing += missing
            case .stale:
                record.counters.staleDropped += 1
                links[token] = record
                return
            }
        }
        links[token] = record

        switch envelope.message {
        case .command(let issued):
            let origin = CommandOrigin(peer: record.identity, role: record.role)
            if continuityLost {
                await reply(.needsSnapshot, id: envelope.messageID,
                            summary: "Messages were lost, so this was not applied. The current state follows; send again if it still applies.",
                            token: token)
                await sendSnapshot(to: token)
            } else {
                await admit(issued, id: envelope.messageID, base: envelope.baseRevision ?? -1, origin: origin, token: token)
            }
        case .snapshotRequest(let reason):
            if reason == .sequenceGap { note("\(record.identity.name) lost messages and asked for the state.", .notice) }
            await sendSnapshot(to: token)
        case .sample(let body):
            guard V.sampleSenders.contains(record.role), body.origin == record.identity.id else {
                note("Dropped a sample \(record.identity.name) may not send.", .notice)
                break
            }
            await relay(body)
        case .clockPing(let probe):
            _ = try? await record.link.send(
                .clockPong(ClockProbe(originatedAt: probe.originatedAt, receivedAt: now, answeredAt: configuration.clock.now())),
                session: sessionID, epoch: epoch
            )
        case .clockPong(let probe):
            if let received = probe.receivedAt, let answered = probe.answeredAt {
                links[token]?.estimator.add(sent: probe.originatedAt, received: received, answered: answered, returned: now)
            }
        case .goodbye:
            note("\(record.identity.name) said goodbye.")
            await record.link.close()
            closeLink(token)
        case .result, .snapshot:
            note("Dropped a message only a conductor may send, from \(record.identity.name).", .notice)
        }
        if continuityLost {
            switch envelope.message {
            case .command, .snapshotRequest: break
            default: await sendSnapshot(to: token)
            }
        }
        publish()
    }

    private func admit(_ issued: IssuedCommand<V.Command>, id: MessageID, base: Int, origin: CommandOrigin, token: UInt64) async {
        if let recorded = retired.answer(for: id, from: origin.peer.id) {
            // Sent under a pairing the person forgot: its old answer, never admitted again.
            await answer(recorded, to: origin.peer.id, token: token)
            note("\(origin.peer.name) sent a request from before it was forgotten. It was not admitted.", .notice)
            return
        }
        if let recorded = peers[origin.peer.id]?.replay[id] {
            // A resend after a lost answer: the same answer, never a second effect.
            await answer(recorded, to: origin.peer.id, token: token)
            return
        }
        if let waiting = pending[id] ?? settling[id] {
            if waiting.command.from.id == origin.peer.id {
                await reply(.received, id: id, summary: "Still waiting for the person at the conductor.", token: token, remember: false)
            } else {
                await reply(.refused, id: id, summary: "Another device's request has that ID. Nothing changed.", token: token)
            }
            return
        }
        guard V.rolesAllowed(toSend: issued.command).contains(origin.role) else {
            await reply(.notAllowed, id: id, summary: "A \(origin.role.title.lowercased()) may not send that.", token: token)
            return
        }
        if let issuedIn = issued.issuedIn, issuedIn != epoch {
            await reply(.wrongEpoch, id: id, summary: "Issued before the conductor restarted. Nothing changed.", token: token)
            return
        }
        if let estimate = links[token]?.estimator.estimate {
            let now = configuration.clock.now()
            let age = now.since(estimate.localInstant(forRemote: issued.issuedAt))
            if age > configuration.timing.commandLifetime + estimate.uncertainty {
                await reply(.expired, id: id, summary: "Issued \(age.millisecondsText) ago, older than a command may be. Nothing changed.", token: token)
                return
            }
        }
        guard base == revision else {
            await reply(.stale, id: id, summary: "Based on revision \(base), but the state is at \(revision). Nothing changed.", token: token)
            await sendSnapshot(to: token)
            return
        }
        _ = await judge(issued.command, id: id, origin: origin, token: token)
    }

    /// Runs the rules and answers. Only here does the state change for a command.
    private func judge(_ command: V.Command, id: MessageID, origin: CommandOrigin, token: UInt64?) async -> CommandResult {
        let decision = decide(command, snapshot, origin)
        if case .hold(let summary) = decision {
            var pairing: UInt64?
            if origin.role != .conductor {
                guard let current = pairings[origin.peer.id] else {
                    let result = CommandResult(commandID: id, disposition: .refused, revision: revision, summary: "This device is no longer paired. Nothing changed.")
                    if let token { await answer(result, to: origin.peer.id, token: token) }
                    return result
                }
                pairing = current
            }
            let now = configuration.clock.now()
            let held = PendingCommand(
                commandID: id, command: command, from: origin.peer, role: origin.role,
                receivedAt: now, expiresAt: now.advanced(by: configuration.timing.approvalLifetime)
            )
            pending[id] = Pending(command: held, token: token ?? 0, pairing: pairing)
            note("\(origin.peer.name) asks: \(summary)")
            let result = CommandResult(commandID: id, disposition: .received, revision: revision, summary: summary)
            if let token { await answer(result, to: origin.peer.id, token: token) }
            publish()
            return result
        }
        let result = await conclude(decision, id: id, origin: origin)
        if let token { await answer(result, to: origin.peer.id, token: token) }
        return result
    }

    private func conclude(_ decision: CommandDecision<V.Snapshot>, id: MessageID, origin: CommandOrigin) async -> CommandResult {
        let result: CommandResult
        switch decision {
        case .apply(let next, let summary):
            if next != snapshot {
                snapshot = next
                revision += 1
                result = CommandResult(commandID: id, disposition: .applied, revision: revision, summary: summary)
            } else {
                result = CommandResult(commandID: id, disposition: .unchanged, revision: revision, summary: summary)
            }
        case .unchanged(let summary):
            result = CommandResult(commandID: id, disposition: .unchanged, revision: revision, summary: summary)
        case .refuse(let summary), .hold(let summary):
            result = CommandResult(commandID: id, disposition: .refused, revision: revision, summary: summary)
        }
        if origin.role != .conductor {
            remember(result, for: origin.peer.id)
            if result.disposition == .applied || result.disposition == .unchanged {
                peers[origin.peer.id]?.admitted += 1
            } else {
                peers[origin.peer.id]?.refused += 1
            }
        }
        note("\(origin.peer.name): \(result.summary)", result.disposition == .refused ? .notice : .info)
        if result.disposition == .applied { await broadcastSnapshot() }
        publish()
        return result
    }

    private func reply(_ disposition: CommandDisposition, id: MessageID, summary: String, token: UInt64, remember keep: Bool = true) async {
        guard let record = links[token] else { return }
        let result = CommandResult(commandID: id, disposition: disposition, revision: revision, summary: summary)
        if keep {
            remember(result, for: record.identity.id)
            peers[record.identity.id]?.refused += 1
        }
        note("\(record.identity.name): \(summary)", .notice)
        _ = try? await record.link.send(.result(result), session: sessionID, epoch: epoch)
    }

    private func remember(_ result: CommandResult, for peer: PeerID) {
        guard result.disposition.isFinal else { return }
        peers[peer]?.remember(result)
    }

    /// Sends a result to the peer on its current link, which may be a newer link than the one the
    /// command arrived on.
    private func answer(_ result: CommandResult, to peer: PeerID, token: UInt64) async {
        let target = links[token].map { ($0.token, $0.link) } ?? links.values.first { $0.identity.id == peer }.map { ($0.token, $0.link) }
        guard let (_, link) = target else { return }
        _ = try? await link.send(.result(result), session: sessionID, epoch: epoch)
    }

    private func sendSnapshot(to token: UInt64) async {
        guard let record = links[token] else { return }
        links[token]?.isSynchronized = true
        _ = try? await record.link.send(
            .snapshot(SnapshotBody(revision: revision, state: snapshot)), session: sessionID, epoch: epoch
        )
    }

    private func broadcastSnapshot() async {
        for token in links.keys.sorted() {
            await sendSnapshot(to: token)
        }
    }

    /// Sends a sample to every receiving peer. Only the newest waits: a newer sample replaces one
    /// still queued behind a send in progress.
    private func relay(_ body: SampleBody<V.Sample>) async {
        for (token, record) in links where V.sampleReceivers.contains(record.role) && record.identity.id != body.origin {
            if record.sampleInFlight {
                links[token]?.queuedSample = body
                continue
            }
            links[token]?.sampleInFlight = true
            var next: SampleBody<V.Sample>? = body
            while let sample = next {
                _ = try? await record.link.send(.sample(sample), session: sessionID, epoch: epoch)
                next = links[token]?.queuedSample
                links[token]?.queuedSample = nil
            }
            links[token]?.sampleInFlight = false
        }
    }

    /// Whether a held command's pairing is still the peer's current one.
    private func isCurrent(_ held: Pending) -> Bool {
        guard let pairing = held.pairing else { return true }
        return pairings[held.command.from.id] == pairing && revoking[held.command.from.id] == nil
    }

    private func finishSettling(_ id: MessageID) {
        guard let held = settling.removeValue(forKey: id) else { return }
        let peer = held.command.from.id
        publish()
        guard !settling.values.contains(where: { $0.command.from.id == peer }) else { return }
        for waiter in settleWaiters.removeValue(forKey: peer) ?? [] { waiter.resume() }
    }

    // MARK: State

    private func note(_ text: String, _ severity: SessionEvent.Severity = .info) {
        log.add(text, at: configuration.clock.now(), severity)
    }

    private func publish() {
        continuation.yield(makeState())
    }

    private func makeState() -> ConductorState<V> {
        let now = configuration.clock.now()
        var statuses: [PeerStatus] = []
        for (id, history) in peers {
            let record = links.values.first { $0.identity.id == id }
            let presence: Presence = if let record {
                configuration.timing.presence(lastHeard: record.lastHeard, now: now)
            } else {
                .disconnected(since: history.closedAt ?? history.lastHeard)
            }
            let lastHeard = record?.lastHeard ?? history.lastHeard
            statuses.append(PeerStatus(
                identity: history.identity, role: record?.role ?? history.role, presence: presence,
                silence: now.since(lastHeard), clock: record?.estimator.estimate ?? history.lastClock,
                counters: record?.counters ?? history.lastCounters, reconnections: max(0, history.links - 1),
                admittedCommands: history.admitted, refusedCommands: history.refused,
                isSynchronized: record?.isSynchronized ?? false
            ))
        }
        statuses.sort { ($0.role, $0.identity.name, $0.id) < ($1.role, $1.identity.name, $1.id) }
        return ConductorState(
            identity: identity, sessionID: sessionID, epoch: epoch, revision: revision, snapshot: snapshot,
            peers: statuses,
            pending: pending.values.map(\.command).sorted { $0.receivedAt < $1.receivedAt },
            pairing: pairing.map { PairingWindow(closesAt: $0.closesAt, attemptsLeft: $0.attemptsLeft) },
            pairingRequest: approval.question, events: log.events, now: now
        )
    }
}
