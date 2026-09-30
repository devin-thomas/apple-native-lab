import Foundation

/// The joining side of a session: a controller that sends commands and samples, or a display
/// that shows the conductor's state.
///
/// It sends nothing until it holds the conductor's snapshot, and after lost messages or a
/// reconnect it waits for a fresh one. Commands wait in a small bounded queue while the link is
/// down; one that waits longer than a command may live is never sent. A sent command without an
/// answer is sent again under the same ID, which the conductor answers from its record instead of
/// applying twice. Samples are latest-only and are dropped while the link is down.
public actor Client<V: SessionVocabulary> {
    public struct Configuration: Sendable {
        public var identity: LocalIdentity
        public var role: PeerRole
        public var trust: any PeerTrustStore
        public var clock: any PeerClock
        public var timing: SessionTiming
        public var handshakeTimeout: Duration
        /// The most commands that may wait for a link at once.
        public var queueLimit: Int
        public var makeMessageID: @Sendable () -> MessageID
        public var wireRecord: (@Sendable (WireRecord) -> Void)?

        public init(
            identity: LocalIdentity,
            role: PeerRole,
            trust: any PeerTrustStore,
            clock: any PeerClock = SystemPeerClock(),
            timing: SessionTiming = .standard,
            handshakeTimeout: Duration = .seconds(10),
            queueLimit: Int = 8,
            makeMessageID: @escaping @Sendable () -> MessageID = { MessageID() },
            wireRecord: (@Sendable (WireRecord) -> Void)? = nil
        ) {
            self.identity = identity
            self.role = role
            self.trust = trust
            self.clock = clock
            self.timing = timing
            self.handshakeTimeout = handshakeTimeout
            self.queueLimit = queueLimit
            self.makeMessageID = makeMessageID
            self.wireRecord = wireRecord
        }
    }

    public nonisolated let identity: PeerIdentity
    public nonisolated let role: PeerRole
    public nonisolated let states: AsyncStream<ClientState<V>>

    private let configuration: Configuration
    private let continuation: AsyncStream<ClientState<V>>.Continuation
    private var link: PeerLink<V>?
    private var linkToken: UInt64 = 0
    private var linkCount = 0
    private var phase: ClientPhase = .idle
    private var host: PeerIdentity?
    private var codePrompt = PromptSlot<CodePrompt, PairingCode>()
    private var sessionID: LiveSessionID?
    private var epoch: SessionEpoch?
    private var revision: Int?
    private var snapshot: V.Snapshot?
    private var isSynchronized = false
    private var lastHeard: PeerInstant?
    private var lastProbe: PeerInstant?
    private var estimator = ClockEstimator()
    private var reliableIn = SequenceTracker()
    private var replaceableIn = SequenceTracker()
    private var counters = LinkCounters()
    private var commands: [TrackedCommand<V.Command>] = []
    private var lastSent: [MessageID: PeerInstant] = [:]
    private var samples: [PeerID: SampleBody<V.Sample>] = [:]
    private var streamSequence: UInt64 = 0
    private var sampleInFlight = false
    private var queuedSample: SampleBody<V.Sample>?
    private var log = EventLog()
    private var tasks: [Task<Void, Never>] = []

    public init(configuration: Configuration) {
        self.configuration = configuration
        identity = configuration.identity.identity
        role = configuration.role
        (states, continuation) = AsyncStream<ClientState<V>>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    // MARK: Joining

    /// Pairs with a conductor for the first time. `codePrompt` in the state asks for the code the
    /// conductor shows; answer with `submitCode`.
    public func pair(over connection: any PeerConnection) async throws(HandshakeFailure) {
        let handshake = JoinerHandshake(
            identity: configuration.identity, offer: V.offer, role: role, trust: configuration.trust,
            stepTimeout: configuration.handshakeTimeout
        )
        let enterCode: @Sendable (CodePrompt) async -> PairingCode? = { [weak self] prompt in await self?.askCode(prompt) }
        try await join(connection) { () async throws(HandshakeFailure) -> EstablishedLink in
            try await handshake.run(on: connection, mode: .pair(enterCode: enterCode))
        }
    }

    /// Reconnects to the conductor this device paired with. A conductor with another identity is
    /// refused before anything is sent.
    public func resume(over connection: any PeerConnection) async throws(HandshakeFailure) {
        guard let host else { throw .refusedLocally(.pairingRequired) }
        try await resume(over: connection, to: host.id)
    }

    /// Reconnects to a conductor this device's trust store pinned, such as one paired before a
    /// relaunch by a host that keeps its pins.
    public func resume(over connection: any PeerConnection, to hostID: PeerID) async throws(HandshakeFailure) {
        guard let pinned = await configuration.trust.pinned(hostID), pinned.roles.contains(.conductor) else {
            throw .refusedLocally(.pairingRequired)
        }
        host = pinned.identity
        let handshake = JoinerHandshake(
            identity: configuration.identity, offer: V.offer, role: role, trust: configuration.trust,
            stepTimeout: configuration.handshakeTimeout
        )
        try await join(connection) { () async throws(HandshakeFailure) -> EstablishedLink in
            try await handshake.run(on: connection, mode: .resume(host: hostID))
        }
    }

    /// The code the person typed. Returns `false`, and keeps asking, if it is not six digits.
    @discardableResult
    public func submitCode(_ typed: String) -> Bool {
        guard let code = PairingCode(typed: typed) else { return false }
        codePrompt.close(with: code)
        publish()
        return true
    }

    public func cancelCode() {
        codePrompt.close(with: nil)
        publish()
    }

    /// The conductor this device paired with, if any.
    public var pairedHost: PeerIdentity? { host }

    /// Says goodbye and closes the link. Queued commands stay queued until they expire.
    public func disconnect() async {
        if let link, let sessionID, let epoch {
            _ = try? await link.send(.goodbye(.leaving), session: sessionID, epoch: epoch)
        }
        await dropLink(reason: "Disconnected on this device.")
    }

    /// Closes the link without a goodbye, as when a device leaves range. The conductor finds out
    /// only when it stops hearing from this device.
    public func vanish() async {
        await dropLink(reason: "The link was lost.")
    }

    // MARK: Sending

    /// Queues a command based on the state this device shows now, and sends it when it can.
    @discardableResult
    public func send(_ command: V.Command) async -> MessageID {
        let id = configuration.makeMessageID()
        let waiting = commands.filter { if case .queued = $0.stage { true } else { false } }.count
        var tracked = TrackedCommand(
            id: id, command: command, baseRevision: revision ?? 0, issuedAt: configuration.clock.now(),
            issuedIn: epoch, stage: .queued
        )
        if waiting >= configuration.queueLimit {
            tracked.stage = .queueFull
            note("Too many commands were waiting, so this one was not queued.", .notice)
        }
        commands.append(tracked)
        if commands.count > 24 { commands.removeFirst(commands.count - 24) }
        await flush()
        publish()
        return id
    }

    /// Offers a sample. Only the newest is kept: while one is being sent, a newer one replaces any
    /// that waits, and nothing is kept while the link is down.
    public func publish(_ sample: V.Sample) async {
        streamSequence += 1
        let body = SampleBody(origin: identity.id, sample: sample, streamSequence: streamSequence)
        guard isSynchronized, let link, let sessionID, let epoch else { return }
        if sampleInFlight {
            queuedSample = body
            return
        }
        sampleInFlight = true
        var next: SampleBody<V.Sample>? = body
        while let current = next {
            _ = try? await link.send(.sample(current), session: sessionID, epoch: epoch)
            next = queuedSample
            queuedSample = nil
        }
        sampleInFlight = false
    }

    public var state: ClientState<V> { makeState() }

    // MARK: Time

    /// Probes the conductor's clock, resends unanswered commands, expires waiting ones, and
    /// updates presence. `startTicking` calls it on a timer.
    public func tick() async {
        let now = configuration.clock.now()
        if let link, let lastHeard, case .disconnected = configuration.timing.presence(lastHeard: lastHeard, now: now) {
            await link.close()
            await dropLink(reason: "The conductor went silent.")
        }
        if let link, isSynchronized, let sessionID, let epoch,
           lastProbe.map({ now.since($0) >= configuration.timing.probeInterval }) ?? true {
            lastProbe = now
            _ = try? await link.send(.clockPing(ClockProbe(originatedAt: now, receivedAt: nil, answeredAt: nil)), session: sessionID, epoch: epoch)
        }
        for index in commands.indices {
            let age = now.since(commands[index].issuedAt)
            switch commands[index].stage {
            case .queued where age > configuration.timing.commandLifetime:
                commands[index].stage = .expiredBeforeSending
                note("A command waited \(age.millisecondsText) for a link and was never sent.", .notice)
            case .sent where age > configuration.timing.commandLifetime:
                commands[index].stage = .finished(CommandResult(
                    commandID: commands[index].id, disposition: .expired, revision: revision ?? 0,
                    summary: "No answer from the conductor in time. It may not have been applied; check the current state."
                ))
            case .sent(let attempts):
                if let sentAt = lastSent[commands[index].id], now.since(sentAt) >= configuration.timing.resendAfter, attempts < 5 {
                    await resend(index, attempts: attempts + 1)
                }
            case .received:
                // Held at the conductor. Ask again now and then under the same ID, so a final
                // answer that was lost is sent again from the conductor's record.
                if let sentAt = lastSent[commands[index].id], now.since(sentAt) >= configuration.timing.resendAfter * 2 {
                    await resend(index, attempts: 0, keepingStage: true)
                }
            default:
                break
            }
        }
        publish()
    }

    public func startTicking(every interval: Duration = .milliseconds(250)) {
        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                await self?.tick()
            }
        }
        tasks.append(task)
    }

    /// Stops the timer and the link.
    public func shutdown() async {
        await disconnect()
        for task in tasks { task.cancel() }
        tasks.removeAll()
        continuation.finish()
    }

    // MARK: Internals

    private func join(
        _ connection: any PeerConnection,
        handshake: @Sendable () async throws(HandshakeFailure) -> EstablishedLink
    ) async throws(HandshakeFailure) {
        await dropLink(reason: nil)
        phase = .connecting
        publish()
        let established: EstablishedLink
        do {
            established = try await handshake()
        } catch {
            codePrompt.close(with: nil)
            phase = .disconnected(reason: error.explanation)
            note("Could not join: \(error.explanation)", .notice)
            publish()
            throw error
        }
        adopt(established)
    }

    private func askCode(_ prompt: CodePrompt) async -> PairingCode? {
        let id = codePrompt.reserve()
        let code: PairingCode? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                    return
                }
                codePrompt.open(id, prompt, continuation)
                note("\(prompt.host.name) shows a code. Enter it here.")
                publish()
            }
        } onCancel: {
            Task { await self.cancelPrompt(id) }
        }
        publish()
        return code
    }

    private func cancelPrompt(_ id: UInt64) {
        if codePrompt.close(with: nil, id: id) { publish() }
    }

    private func adopt(_ established: EstablishedLink) {
        let link = PeerLink<V>(
            established, isHost: false, clock: configuration.clock,
            makeMessageID: configuration.makeMessageID, record: configuration.wireRecord
        )
        linkToken += 1
        linkCount += 1
        let token = linkToken
        self.link = link
        host = established.remote
        phase = .synchronizing
        isSynchronized = false
        lastHeard = configuration.clock.now()
        lastProbe = nil
        estimator.reset()
        reliableIn = SequenceTracker()
        replaceableIn = SequenceTracker()
        samples.removeAll()
        for index in commands.indices {
            // Unanswered commands wait for the new snapshot and go again under the same ID.
            if case .sent = commands[index].stage { commands[index].stage = .queued }
        }
        note(established.pairedNow ? "Paired with \(established.remote.name)." : "Rejoined \(established.remote.name).")
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
        guard token == linkToken, link != nil else { return }
        await dropLink(reason: "The connection closed.")
    }

    private func dropLink(reason: String?) async {
        guard let current = link else {
            if let reason { phase = .disconnected(reason: reason) }
            publish()
            return
        }
        link = nil
        linkToken += 1
        await current.close()
        isSynchronized = false
        sampleInFlight = false
        queuedSample = nil
        if let reason {
            phase = .disconnected(reason: reason)
            note(reason, .notice)
        }
        publish()
    }

    private func handle(_ envelope: SessionEnvelope<V>, token: UInt64) async {
        guard token == linkToken, let link else { return }
        let now = configuration.clock.now()
        lastHeard = now
        counters.refusedFrames = await link.rejections.count

        switch envelope.channel {
        case .reliable:
            switch reliableIn.observe(envelope.sequence) {
            case .inOrder:
                break
            case .gap(let missing):
                counters.reliableGaps += 1
                note("\(missing) message(s) from the conductor never arrived. Asking for the current state.", .notice)
                isSynchronized = false
                phase = .synchronizing
                if case .snapshot = envelope.message {
                    break
                }
                if let sessionID, let epoch {
                    _ = try? await link.send(.snapshotRequest(.sequenceGap), session: sessionID, epoch: epoch)
                }
            case .stale:
                return
            }
        case .replaceable:
            switch replaceableIn.observe(envelope.sequence) {
            case .inOrder: break
            case .gap(let missing): counters.replaceableMissing += missing
            case .stale:
                counters.staleDropped += 1
                return
            }
        }

        switch envelope.message {
        case .snapshot(let body):
            if let epoch, epoch != envelope.sessionEpoch {
                note("The conductor restarted. Earlier samples and clock readings were discarded.", .notice)
                estimator.reset()
                samples.removeAll()
            }
            sessionID = envelope.sessionID
            epoch = envelope.sessionEpoch
            revision = body.revision
            snapshot = body.state
            isSynchronized = true
            phase = .live
            await flush()
        case .result(let result):
            guard let index = commands.firstIndex(where: { $0.id == result.commandID }) else { break }
            commands[index].stage = result.disposition.isFinal ? .finished(result) : .received(result)
            lastSent[result.commandID] = result.disposition.isFinal ? nil : now
            if result.disposition != .applied, result.disposition != .received, result.disposition != .unchanged {
                note(result.summary, .notice)
            }
        case .sample(let body):
            guard V.sampleReceivers.contains(role) else { break }
            if let existing = samples[body.origin], existing.streamSequence >= body.streamSequence {
                counters.staleDropped += 1
            } else {
                samples[body.origin] = body
            }
        case .clockPing(let probe):
            if let sessionID, let epoch {
                _ = try? await link.send(
                    .clockPong(ClockProbe(originatedAt: probe.originatedAt, receivedAt: now, answeredAt: configuration.clock.now())),
                    session: sessionID, epoch: epoch
                )
            }
        case .clockPong(let probe):
            if let received = probe.receivedAt, let answered = probe.answeredAt {
                estimator.add(sent: probe.originatedAt, received: received, answered: answered, returned: now)
            }
        case .goodbye(let reason):
            let text = switch reason {
            case .forgotten: "The conductor forgot this device. Pair again to rejoin."
            case .sessionEnded: "The conductor ended the session."
            case .leaving: "The conductor left."
            }
            if reason == .forgotten {
                if let host { await configuration.trust.forget(host.id) }
                host = nil
            }
            await dropLink(reason: text)
        case .command, .snapshotRequest:
            note("Dropped a message only a joiner sends.", .notice)
        }
        publish()
    }

    /// Sends every queued command, oldest first, once the link is synchronized.
    private func flush() async {
        guard isSynchronized, link != nil else { return }
        let now = configuration.clock.now()
        for index in commands.indices {
            guard case .queued = commands[index].stage else { continue }
            if now.since(commands[index].issuedAt) > configuration.timing.commandLifetime {
                commands[index].stage = .expiredBeforeSending
                continue
            }
            await resend(index, attempts: 1)
        }
    }

    private func resend(_ index: Int, attempts: Int, keepingStage: Bool = false) async {
        guard let link, let sessionID, let epoch, commands.indices.contains(index) else { return }
        let tracked = commands[index]
        if !keepingStage { commands[index].stage = .sent(attempts: attempts) }
        lastSent[tracked.id] = configuration.clock.now()
        do {
            try await link.send(
                .command(IssuedCommand(command: tracked.command, issuedAt: tracked.issuedAt, issuedIn: tracked.issuedIn)),
                session: sessionID, epoch: epoch, baseRevision: tracked.baseRevision, messageID: tracked.id
            )
        } catch {
            if let current = commands.firstIndex(where: { $0.id == tracked.id }) { commands[current].stage = .queued }
        }
    }

    private func note(_ text: String, _ severity: SessionEvent.Severity = .info) {
        log.add(text, at: configuration.clock.now(), severity)
    }

    private func publish() {
        continuation.yield(makeState())
    }

    private func makeState() -> ClientState<V> {
        let now = configuration.clock.now()
        var shown = phase
        if case .live = phase, let lastHeard, case .stale = configuration.timing.presence(lastHeard: lastHeard, now: now) {
            shown = .stale
        }
        return ClientState(
            identity: identity, role: role, phase: shown, host: host, codePrompt: codePrompt.question,
            sessionID: sessionID, epoch: epoch, revision: revision, snapshot: snapshot,
            silence: lastHeard.map { now.since($0) }, commands: commands, samples: samples,
            clock: estimator.estimate, counters: counters, reconnections: max(0, linkCount - 1),
            events: log.events, now: now
        )
    }
}
