import PeerSession
import SwiftUI

// Views every host shares: the display's board, the conductor's roster and requests, and a
// joiner's status. Each takes plain values and closures, so the simulation and the live path
// draw the same thing from the same states.

extension CuePalette {
    var colors: [Color] {
        switch self {
        case .dusk: [Color(red: 0.13, green: 0.18, blue: 0.42), Color(red: 0.36, green: 0.30, blue: 0.62)]
        case .amber: [Color(red: 0.55, green: 0.28, blue: 0.05), Color(red: 0.93, green: 0.62, blue: 0.20)]
        case .sea: [Color(red: 0.02, green: 0.28, blue: 0.38), Color(red: 0.16, green: 0.60, blue: 0.64)]
        case .aurora: [Color(red: 0.07, green: 0.30, blue: 0.22), Color(red: 0.45, green: 0.24, blue: 0.62)]
        case .ember: [Color(red: 0.25, green: 0.05, blue: 0.03), Color(red: 0.60, green: 0.17, blue: 0.07)]
        case .dawn: [Color(red: 0.60, green: 0.47, blue: 0.30), Color(red: 0.96, green: 0.86, blue: 0.62)]
        }
    }
}

extension Presence {
    var symbol: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .stale: "exclamationmark.triangle"
        case .disconnected: "bolt.horizontal.circle"
        }
    }
}

extension ClientPhase {
    var symbol: String {
        switch self {
        case .idle: "circle.dashed"
        case .connecting: "arrow.triangle.2.circlepath"
        case .synchronizing: "arrow.down.circle"
        case .live: "dot.radiowaves.left.and.right"
        case .stale: "exclamationmark.triangle"
        case .disconnected: "bolt.horizontal.circle"
        }
    }
}

extension ClockEstimate {
    /// "+1850.2 ms ± 0.1 ms, 4 probes"
    public var summary: String {
        let sign = offset >= .zero ? "+" : "−"
        let magnitude = offset >= .zero ? offset : .zero - offset
        return "\(sign)\(magnitude.millisecondsText) ± \(uncertainty.millisecondsText), \(sampleCount) probe\(sampleCount == 1 ? "" : "s")"
    }
}

extension CommandStage {
    public var summary: String {
        switch self {
        case .queued: "Waiting to send"
        case .sent(let attempts): attempts > 1 ? "Sent \(attempts) times, waiting for an answer" : "Sent, waiting for an answer"
        case .received(let result): "At the conductor: \(result.summary)"
        case .finished(let result): "\(result.disposition.title): \(result.summary)"
        case .expiredBeforeSending: "Never sent: it waited too long for a link. Nothing changed."
        case .queueFull: "Not queued: too many commands were waiting."
        case .withdrawn: "Withdrawn: the conductor forgot this device before answering. It will not be sent again."
        }
    }
}

extension CommandDisposition {
    public var title: String {
        switch self {
        case .received: "Received"
        case .applied: "Applied"
        case .unchanged: "Unchanged"
        case .stale: "Out of date"
        case .expired: "Expired"
        case .wrongEpoch: "From before a restart"
        case .needsSnapshot: "Messages lost"
        case .notAllowed: "Not allowed"
        case .refused: "Refused"
        case .invalid: "Invalid"
        }
    }
}

/// The display: the current cue on its palette, the controller's pointer, and a plain warning
/// when what it shows may no longer be true.
public struct ShowBoard: View {
    let snapshot: ShowSnapshot?
    let pointer: Pointer?
    let phase: ClientPhase?
    let silence: Duration?

    public init(snapshot: ShowSnapshot?, pointer: Pointer? = nil, phase: ClientPhase? = nil, silence: Duration? = nil) {
        self.snapshot = snapshot
        self.pointer = pointer
        self.phase = phase
        self.silence = silence
    }

    private var isStale: Bool {
        switch phase {
        case .stale, .disconnected, .synchronizing: true
        default: false
        }
    }

    public var body: some View {
        ZStack {
            LinearGradient(colors: snapshot?.palette.colors ?? [.gray, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let snapshot {
                VStack(spacing: 8) {
                    Text("Cue \(snapshot.cue + 1) of \(snapshot.cueCount)")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                    Text(snapshot.cueTitle)
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(snapshot.cueDetail)
                        .font(.body)
                        .multilineTextAlignment(.center)
                    Label(snapshot.isRunning ? "Running" : "Paused", systemImage: snapshot.isRunning ? "play.fill" : "pause.fill")
                        .font(.callout.weight(.semibold))
                        .padding(.top, 4)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 3)
                .padding()
            } else {
                Text("Waiting for the conductor")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            if let pointer {
                GeometryReader { proxy in
                    Circle()
                        .fill(.white.opacity(0.9))
                        .frame(width: 18, height: 18)
                        .shadow(radius: 4)
                        .position(x: proxy.size.width * pointer.x, y: proxy.size.height * pointer.y)
                }
                .accessibilityHidden(true)
            }
            if isStale {
                Color.black.opacity(0.45)
                VStack(spacing: 6) {
                    Label(phase?.title ?? "Stale", systemImage: phase?.symbol ?? "exclamationmark.triangle")
                        .font(.title3.weight(.bold))
                    Text(staleText)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var staleText: String {
        switch phase {
        case .disconnected(let reason): "\(reason) This may no longer be what the conductor shows."
        case .synchronizing: "Waiting for the conductor's current state."
        default:
            if let silence { "Nothing heard from the conductor for \(Self.seconds(silence)). This may no longer be current." }
            else { "This may no longer be current." }
        }
    }

    static func seconds(_ duration: Duration) -> String {
        String(format: "%.1f s", Double(duration.wholeNanoseconds) / 1_000_000_000)
    }

    private var accessibilityText: String {
        guard let snapshot else { return "Display. Waiting for the conductor." }
        var parts = ["Cue \(snapshot.cue + 1) of \(snapshot.cueCount), \(snapshot.cueTitle).", snapshot.cueDetail,
                     snapshot.isRunning ? "The show is running." : "The show is paused."]
        if isStale { parts.append(staleText) }
        return parts.joined(separator: " ")
    }
}

/// What the person at the conductor can do from the shared views.
public struct ConductorActions {
    public var openPairing: () -> Void
    public var answerPairing: (Bool) -> Void
    public var allow: (MessageID) -> Void
    public var decline: (MessageID) -> Void
    public var setRunning: (Bool) -> Void
    public var move: (ShowCommand) -> Void

    public init(
        openPairing: @escaping () -> Void,
        answerPairing: @escaping (Bool) -> Void,
        allow: @escaping (MessageID) -> Void,
        decline: @escaping (MessageID) -> Void,
        setRunning: @escaping (Bool) -> Void,
        move: @escaping (ShowCommand) -> Void
    ) {
        self.openPairing = openPairing
        self.answerPairing = answerPairing
        self.allow = allow
        self.decline = decline
        self.setRunning = setRunning
        self.move = move
    }
}

/// The conductor's controls: pairing, held requests, the show, and every peer's link.
public struct ConductorPanel: View {
    let state: ConductorState<Constellation>?
    let actions: ConductorActions
    /// Only the simulation knows each device's true clock offset.
    let trueOffsets: [PeerRole: Duration]

    public init(state: ConductorState<Constellation>?, actions: ConductorActions, trueOffsets: [PeerRole: Duration] = [:]) {
        self.state = state
        self.actions = actions
        self.trueOffsets = trueOffsets
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let state {
                if let request = state.pairingRequest {
                    PairingRequestCard(request: request, answer: actions.answerPairing)
                }
                ForEach(state.pending) { pending in
                    PendingRequestCard(pending: pending, allow: { actions.allow(pending.commandID) }, decline: { actions.decline(pending.commandID) })
                }
                showControls(state)
                peers(state)
                if let pairing = state.pairing {
                    Text("Pairing is open for \(ShowBoard.seconds(pairing.closesAt.since(state.now))), \(pairing.attemptsLeft) attempt\(pairing.attemptsLeft == 1 ? "" : "s") left.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Pair a Device", systemImage: "person.badge.key") { actions.openPairing() }
                        .accessibilityHint("Lets a device ask to join for two minutes. It must enter the code this conductor shows.")
                }
                Text("Session epoch \(state.epoch.description), revision \(state.revision). This device: \(state.identity.name), \(state.identity.id.shortForm).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Starting the conductor")
            }
        }
    }

    private func showControls(_ state: ConductorState<Constellation>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ShowBoard(snapshot: state.snapshot)
                .frame(minHeight: 140, maxHeight: 180)
            HStack {
                Button("Previous Cue", systemImage: "backward.fill") { actions.move(.previous) }
                    .disabled(state.snapshot.cue == 0)
                Button("Next Cue", systemImage: "forward.fill") { actions.move(.next) }
                    .disabled(state.snapshot.cue + 1 >= state.snapshot.cueCount)
            }
            if state.snapshot.isRunning {
                Button("Pause the Show", systemImage: "pause.fill") { actions.setRunning(false) }
                    .accessibilityHint("Commits through the lab's operation service and leaves a receipt.")
            } else {
                Button("Start the Show", systemImage: "play.fill") { actions.setRunning(true) }
                    .accessibilityHint("Commits through the lab's operation service and leaves a receipt.")
            }
            Text(state.snapshot.note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder private func peers(_ state: ConductorState<Constellation>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Peers").font(.headline)
            if state.peers.isEmpty {
                Text("No device has joined. Pair one to begin.")
                    .foregroundStyle(.secondary)
            }
            ForEach(state.peers) { peer in
                PeerStatusRow(peer: peer, trueOffset: trueOffsets[peer.role])
            }
        }
    }
}

/// One peer as the conductor sees it: presence, silence, clock, and link counters.
public struct PeerStatusRow: View {
    let peer: PeerStatus
    let trueOffset: Duration?

    public init(peer: PeerStatus, trueOffset: Duration? = nil) {
        self.peer = peer
        self.trueOffset = trueOffset
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(peer.identity.name, systemImage: peer.role == .display ? "tv" : "iphone")
                    .font(.body.weight(.semibold))
                Spacer()
                Label(peer.presence.title, systemImage: peer.presence.symbol)
                    .foregroundStyle(peer.presence.isLive ? Color.green : Color.orange)
            }
            Text("\(peer.role.title) · \(peer.identity.id.shortForm) · last heard \(ShowBoard.seconds(peer.silence)) ago")
            Text(peer.clock.map { "Clock offset \($0.summary)" } ?? "Clock offset: no estimate yet")
            if let trueOffset {
                Text("Simulated offset \(trueOffset.millisecondsText). Only a simulation knows this.")
            }
            Text("Gaps \(peer.counters.reliableGaps) reliable, \(peer.counters.replaceableMissing) samples lost, \(peer.counters.staleDropped) stale dropped · Reconnections \(peer.reconnections) · Admitted \(peer.admittedCommands), refused \(peer.refusedCommands)")
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
    }
}

/// The code to read out and the person's answer. Allow only after the other device says the code
/// matched: that is what makes the pairing resist a device in the middle.
public struct PairingRequestCard: View {
    let request: PairingRequest
    let answer: (Bool) -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(request.peer.name) wants to join as \(request.role.title.lowercased()).")
                .font(.headline)
            Text(request.code.description)
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .accessibilityLabel("Code \(request.code.digits.map(String.init).joined(separator: " "))")
            Text("Enter this code on \(request.peer.name). Allow only after it says the code matched. Its identity: \(request.peer.id.shortForm).")
                .font(.footnote)
            HStack {
                Button("Allow", systemImage: "checkmark") { answer(true) }
                    .buttonStyle(.borderedProminent)
                Button("Deny", systemImage: "xmark", role: .cancel) { answer(false) }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// A peer's request that needs the person at the conductor.
public struct PendingRequestCard: View {
    let pending: PendingCommand<ShowCommand>
    let allow: () -> Void
    let decline: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(pending.from.name) asks: \(pending.command.title).")
                .font(.headline)
            Text("Allowing commits the change through the lab's operation service as an authorized peer, with a grant for this change alone, and leaves a receipt.")
                .font(.footnote)
            HStack {
                Button("Allow", systemImage: "checkmark") { allow() }
                    .buttonStyle(.borderedProminent)
                Button("Decline", systemImage: "xmark") { decline() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// What a person can do on a joining device.
public struct JoinerActions {
    public var submitCode: (String) -> Void
    public var cancelCode: () -> Void
    public var send: (ShowCommand) -> Void
    public var point: (Double, Double) -> Void

    public init(
        submitCode: @escaping (String) -> Void,
        cancelCode: @escaping () -> Void,
        send: @escaping (ShowCommand) -> Void,
        point: @escaping (Double, Double) -> Void
    ) {
        self.submitCode = submitCode
        self.cancelCode = cancelCode
        self.send = send
        self.point = point
    }
}

/// A joining device: its link, the code entry while pairing, and for a controller the show's
/// controls and pointer.
public struct JoinerPanel: View {
    let state: ClientState<Constellation>?
    let actions: JoinerActions
    @State private var typed = ""

    public init(state: ClientState<Constellation>?, actions: JoinerActions) {
        self.state = state
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let state {
                Label(state.phase.title, systemImage: state.phase.symbol)
                    .font(.headline)
                    .foregroundStyle(state.phase == .live ? Color.green : Color.orange)
                if case .disconnected(let reason) = state.phase {
                    Text(reason).font(.footnote)
                }
                if let prompt = state.codePrompt {
                    codeEntry(prompt)
                }
                if state.role == .display {
                    ShowBoard(snapshot: state.snapshot, pointer: state.samples.values.first?.sample, phase: state.phase, silence: state.silence)
                        .frame(minHeight: 160, maxHeight: 220)
                } else {
                    ShowBoard(snapshot: state.snapshot, phase: state.phase, silence: state.silence)
                        .frame(minHeight: 100, maxHeight: 140)
                    controls(state)
                }
                details(state)
            } else {
                ProgressView()
            }
        }
    }

    private func codeEntry(_ prompt: CodePrompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter the code \(prompt.host.name) shows.")
                .font(.headline)
            TextField("Six digits", text: $typed)
                .font(.system(.title2, design: .monospaced))
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onSubmit { submit() }
            HStack {
                Button("Pair", systemImage: "checkmark") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(PairingCode(typed: typed) == nil)
                Button("Cancel", systemImage: "xmark") {
                    typed = ""
                    actions.cancelCode()
                }
                .buttonStyle(.bordered)
            }
            Text("If the code does not match, nothing is paired and nothing is shared. Its identity: \(prompt.host.id.shortForm).")
                .font(.footnote)
        }
        .padding()
        .background(.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    private func submit() {
        guard PairingCode(typed: typed) != nil else { return }
        actions.submitCode(typed)
        typed = ""
    }

    @ViewBuilder private func controls(_ state: ClientState<Constellation>) -> some View {
        let live = state.phase == .live || state.phase == .stale
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Previous", systemImage: "backward.fill") { actions.send(.previous) }
                Button("Next", systemImage: "forward.fill") { actions.send(.next) }
            }
            if state.snapshot?.isRunning == true {
                Button("Ask to Pause", systemImage: "pause") { actions.send(.pause) }
                    .accessibilityHint("The person at the conductor decides.")
            } else {
                Button("Ask to Start", systemImage: "play") { actions.send(.start) }
                    .accessibilityHint("The person at the conductor decides.")
            }
            PointerPad(point: actions.point)
        }
        .buttonStyle(.bordered)
        .disabled(!live && state.snapshot == nil)
    }

    @ViewBuilder private func details(_ state: ClientState<Constellation>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let host = state.host {
                Text("Conductor: \(host.name), \(host.id.shortForm)")
            }
            if let revision = state.revision, let epoch = state.epoch {
                Text("Revision \(revision), epoch \(epoch.description)")
            }
            Text(state.clock.map { "Conductor's clock \($0.summary)" } ?? "Conductor's clock: no estimate yet")
            Text("Gaps \(state.counters.reliableGaps) reliable, \(state.counters.replaceableMissing) samples lost · Reconnections \(state.reconnections)")
            ForEach(state.commands.suffix(4).reversed()) { command in
                Text("\(command.command.title): \(command.stage.summary)")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// Where the controller points. A drag sets it where dragging is available; the buttons move it
/// by a step, for the keyboard, VoiceOver, Switch Control, and the Apple TV remote.
public struct PointerPad: View {
    let point: (Double, Double) -> Void
    @State private var position = (x: 0.5, y: 0.5)

    public init(point: @escaping (Double, Double) -> Void) {
        self.point = point
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            #if !os(tvOS)
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 10)
                    .fill(.secondary.opacity(0.15))
                    .overlay {
                        Circle()
                            .fill(.tint)
                            .frame(width: 16, height: 16)
                            .position(x: proxy.size.width * position.x, y: proxy.size.height * position.y)
                    }
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        move(to: (value.location.x / max(proxy.size.width, 1), value.location.y / max(proxy.size.height, 1)))
                    })
            }
            .frame(height: 110)
            .accessibilityHidden(true)
            #endif
            HStack {
                Button("Left", systemImage: "arrow.left") { move(to: (position.x - 0.1, position.y)) }
                Button("Up", systemImage: "arrow.up") { move(to: (position.x, position.y - 0.1)) }
                Button("Down", systemImage: "arrow.down") { move(to: (position.x, position.y + 0.1)) }
                Button("Right", systemImage: "arrow.right") { move(to: (position.x + 0.1, position.y)) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            Text("Pointer at \(Int(position.x * 100))%, \(Int(position.y * 100))%. Samples are replaceable: only the newest is sent.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func move(to target: (Double, Double)) {
        position = (min(max(target.0, 0), 1), min(max(target.1, 0), 1))
        point(position.x, position.y)
    }
}

/// The conductor's recent frames: what crossed the wire, sealed, in which channel and order.
public struct WireLogList: View {
    let lines: [WireLine]

    public init(lines: [WireLine]) {
        self.lines = lines
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if lines.isEmpty {
                Text("Nothing has crossed the wire yet.").foregroundStyle(.secondary)
            }
            ForEach(lines.prefix(16)) { line in
                Label(line.text, systemImage: line.outgoing ? "arrow.up.right" : "arrow.down.left")
                    .font(.footnote.monospacedDigit())
            }
        }
    }
}

/// A session's own event log.
public struct SessionEventList: View {
    let events: [SessionEvent]

    public init(events: [SessionEvent]) {
        self.events = events
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(events.suffix(12).reversed()) { event in
                Label(event.text, systemImage: event.severity == .info ? "info.circle" : "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(event.severity == .info ? Color.secondary : Color.orange)
            }
        }
    }
}
