import LabCatalog
import ScreeningRoom
import ScreeningRoomPlayback
import SwiftUI

/// The inline player, or a note saying where the clip is when another surface shows it. Only one
/// surface holds the player at a time.
struct ScreeningPlayerArea: View {
    let model: ScreeningRoomModel

    var body: some View {
        ZStack {
            Rectangle().fill(.black)
            switch model.phase {
            case .failed(let failure):
                ContentUnavailableView {
                    Label(failure.title, systemImage: "exclamationmark.triangle")
                } description: {
                    Text("\(failure.message) \(failure.recovery)")
                }
                .foregroundStyle(.white)
                .accessibilityIdentifier("screening.failure")
            case .opening, .idle:
                ProgressView("Opening…")
                    .foregroundStyle(.white)
            case .ready:
                if !model.theaterIsOpen {
                    PlayerSurfaceView(model: model, role: .inline)
                        .accessibilityLabel("Player, \(model.clip?.title ?? "clip")")
                        .accessibilityIdentifier("screening.player")
                } else {
                    Label(model.state.surface == .theater ? "Showing in the theater" : "Showing in \(model.state.surface.title)", systemImage: "rectangle.on.rectangle")
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("screening.elsewhere")
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 12))
    }
}

/// The state in one line, and the page's notice when there is one.
struct ScreeningStatus: View {
    let model: ScreeningRoomModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.state.summary)
                .font(.headline)
                .monospacedDigit()
                .accessibilityIdentifier("screening.summary")
            if let change = model.state.lastRouteChange {
                Label(change.title, systemImage: "speaker.wave.2")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let notice = model.notice {
                HStack(alignment: .firstTextBaseline) {
                    Label(notice.message, systemImage: notice.isProblem ? "exclamationmark.circle" : "info.circle")
                        .font(.callout)
                        .foregroundStyle(notice.isProblem ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Dismiss", systemImage: "xmark") { model.dismissNotice() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
                .accessibilityIdentifier("screening.notice")
            }
        }
    }
}

/// Back, play or pause, and forward, as commands with receipts. The player's own controls do the
/// same things directly; the session hears about those as signals.
struct ScreeningTransport: View {
    let model: ScreeningRoomModel

    var body: some View {
        HStack(spacing: 16) {
            Button("Back \(Int(ScreeningRoom.skipInterval)) Seconds", systemImage: "gobackward.10") {
                run(.skip(by: -ScreeningRoom.skipInterval))
            }
            Button(model.state.isPlaying ? "Pause" : "Play", systemImage: model.state.isPlaying ? "pause.fill" : "play.fill") {
                run(model.state.isPlaying ? .pause : .play)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("screening.play")
            Button("Forward \(Int(ScreeningRoom.skipInterval)) Seconds", systemImage: "goforward.10") {
                run(.skip(by: ScreeningRoom.skipInterval))
            }
        }
        .labelStyle(.iconOnly)
        .controlSize(.large)
        .disabled(model.phase != .ready)
    }

    private func run(_ command: PlaybackCommand) {
        Task { await ScreeningAnnouncer.perform(command, in: model) }
    }
}

/// Captions off, or one of the clip's tracks. The player's own caption menu offers the same
/// choices; whichever is used, the other follows.
struct ScreeningCaptionPicker: View {
    let model: ScreeningRoomModel

    var body: some View {
        Picker("Captions", selection: Binding(
            get: { model.state.caption },
            set: { choice in Task { await ScreeningAnnouncer.perform(.selectCaption(choice), in: model) } }
        )) {
            Text("Off").tag(CaptionChoice.off)
            ForEach(model.clip?.captions ?? []) { track in
                Text(track.title).tag(CaptionChoice.track(track.id))
            }
        }
        .disabled(model.phase != .ready)
        .accessibilityIdentifier("screening.captions")
    }
}

/// Where the clip shows: the page or the theater from here; full screen, Picture in Picture, and
/// AirPlay from the player's and the system's own controls.
struct ScreeningSurfaceControls: View {
    let model: ScreeningRoomModel

    var body: some View {
        HStack(spacing: 16) {
            Button("Watch in Theater", systemImage: "rectangle.expand.vertical") {
                Task { await ScreeningAnnouncer.perform(.present(.theater), in: model) }
            }
            .disabled(model.phase != .ready || model.state.surface == .theater)
            .accessibilityIdentifier("screening.theater")
            RoutePickerButton()
                .frame(width: 32, height: 32)
                .accessibilityLabel("AirPlay")
                .help("Choose an AirPlay device in the system's picker")
        }
    }
}

/// The three bundled clips: the one to watch, and two that must fail with a real error.
struct ScreeningClipList: View {
    let model: ScreeningRoomModel

    var body: some View {
        ForEach(ScreeningClips.all) { clip in
            Button {
                Task { await model.open(clip) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(clip.title)
                        if model.state.clip == clip.id {
                            Image(systemName: "checkmark").accessibilityLabel("Open")
                        }
                    }
                    Text(Self.purpose(of: clip))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("screening.clip.\(clip.id)")
        }
    }

    static func purpose(of clip: MediaAsset) -> String {
        switch clip.expectation {
        case .plays: "Original 10-second test card with English (SDH) and Spanish captions."
        case .fails(.unsupportedCodec): "A codec no decoder claims. Opening it must show a real error."
        case .fails: "A damaged file. Opening it must show a real error."
        }
    }
}

/// What this device offers, as measured when the experiment opened.
struct ScreeningReadinessList: View {
    let readiness: PlaybackReadiness

    var body: some View {
        ForEach(readiness.lines) { line in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(line.title)
                    Spacer()
                    Text(line.status.title)
                        .foregroundStyle(line.status == .unavailable ? .red : .secondary)
                }
                Text(line.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// The session's receipts, newest first.
struct ScreeningReceiptList: View {
    let model: ScreeningRoomModel
    var limit = 8

    var body: some View {
        if model.receipts.isEmpty {
            Text("No commands yet.").foregroundStyle(.secondary)
        }
        ForEach(model.receipts.prefix(limit)) { receipt in
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.summary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(receipt.source.title) · \(receipt.adapter.rawValue) · revision \(receipt.revision.rawValue)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// A stand-in for a controller on another device, in this app, labeled as a simulation. Its
/// commands go through the same link a paired device will use (LAB-019), as an authorized peer:
/// it can steer playback, and its Reset is refused.
struct ScreeningCompanionPanel: View {
    let model: ScreeningRoomModel
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionNote("Simulated in this app: these buttons send commands as a paired companion would, through the same link and with the same limits. No other device is involved.")
            HStack(spacing: 12) {
                Button("Play") { send(.play) }
                Button("Pause") { send(.pause) }
                Button("Back 10") { send(.skip(by: -ScreeningRoom.skipInterval)) }
                Button("Reset") { send(.forgetResumePoint) }
                    .accessibilityHint("A companion is not allowed to reset. This shows the refusal.")
            }
            .buttonStyle(.bordered)
            if let result {
                Text(result)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("screening.companion.result")
            }
        }
    }

    private func send(_ command: PlaybackCommand) {
        Task {
            let link = model.companionLink
            do throws(ScreeningError) {
                let seen = try await link.snapshot()
                let receipt = try await link.send(command, requestID: .init(), seen: seen.revision)
                result = "Companion: \(receipt.summary)"
            } catch {
                result = "Companion: \(error.message)"
            }
            LabAnnouncement(text: result ?? "", priority: .normal).post()
        }
    }
}

/// Runs a command and speaks its result, so a person using VoiceOver hears what the receipt says.
@MainActor
enum ScreeningAnnouncer {
    static func perform(_ command: PlaybackCommand, in model: ScreeningRoomModel) async {
        if let receipt = await model.perform(command) {
            if receipt.didChange { LabAnnouncement(text: receipt.summary).post() }
        } else if let notice = model.notice {
            LabAnnouncement(text: notice.message, priority: .high).post()
        }
    }
}

extension View {
    /// Presents the theater when the session moves the clip there, and returns it to the page
    /// when the theater closes: a full-screen cover on iPhone and iPad, a sheet on the Mac. A
    /// system surface entered from the theater (Picture in Picture) keeps it open.
    func screeningTheater(_ model: ScreeningRoomModel) -> some View {
        modifier(ScreeningTheaterPresenter(model: model))
    }
}

private struct ScreeningTheaterPresenter: ViewModifier {
    let model: ScreeningRoomModel
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onChange(of: model.state.surface, initial: true) { _, surface in
                if surface == .theater { isPresented = true }
                if surface == .inline { isPresented = false }
            }
            .onChange(of: isPresented, initial: true) { _, open in model.theaterIsOpen = open }
            #if os(iOS)
            .fullScreenCover(isPresented: $isPresented, onDismiss: returnToPage) { theater }
            #else
            .sheet(isPresented: $isPresented, onDismiss: returnToPage) { theater }
            #endif
    }

    private var theater: some View {
        VStack(spacing: 12) {
            PlayerSurfaceView(model: model, role: .theater)
                .accessibilityIdentifier("screening.theater.player")
            HStack {
                Text(model.state.summary)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Back to Page", systemImage: "rectangle.compress.vertical") {
                    Task { await ScreeningAnnouncer.perform(.present(.inline), in: model) }
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("screening.theater.close")
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 470)
        #else
        .background(.black)
        #endif
    }

    /// A swipe or Escape closed the theater without the button.
    private func returnToPage() {
        guard model.state.surface == .theater else { return }
        Task { await ScreeningAnnouncer.perform(.present(.inline), in: model) }
    }
}
