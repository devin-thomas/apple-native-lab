import AVFoundation
import ScreeningRoom
import ScreeningRoomPlayback
import SwiftUI

/// The one screening this Apple TV runs (LAB-031), shared by every visit to the page so the
/// resume point and Picture in Picture outlive it. tvOS keeps no Application Support folder, so
/// the resume point lives in Caches, which the system may clear; the page then starts over.
@MainActor
enum TVScreening {
    static let model = ScreeningRoomModel(store: FileResumePointStore(folder: resumeFolder))

    static var resumeFolder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ScreeningRoom", isDirectory: true)
    }
}

/// Native Screening Room on Apple TV: a preview of the clip beside focusable controls. Watch in
/// Theater opens the system player full screen, where the Siri Remote, the caption menu, and
/// Picture in Picture are the system's; Menu returns here with the same position and captions.
struct ScreeningRoomScreen: View {
    let model: ScreeningRoomModel
    @State private var showsTheater = false
    @State private var isConfirmingReset = false

    var body: some View {
        HStack(alignment: .top, spacing: 64) {
            VStack(alignment: .leading, spacing: 28) {
                preview
                Text(model.state.summary)
                    .font(.headline)
                    .monospacedDigit()
                    .accessibilityIdentifier("screening.summary")
                if let notice = model.notice {
                    SymbolLabel(title: notice.message, systemImage: notice.isProblem ? "exclamationmark.circle" : "info.circle")
                        .font(.callout)
                        .foregroundStyle(notice.isProblem ? .red : .secondary)
                        .accessibilityIdentifier("screening.notice")
                }
            }
            .frame(width: 860)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    controls
                    captions
                    clips
                    FocusCard(identifier: "screening.readiness") {
                        VStack(alignment: .leading, spacing: 12) {
                            CardHeading(title: "On this Apple TV")
                            ForEach(model.readiness.lines) { line in
                                Text("\(line.title): \(line.status.title). \(line.detail)")
                            }
                        }
                    }
                    FocusCard(identifier: "screening.receipts") {
                        VStack(alignment: .leading, spacing: 12) {
                            CardHeading(title: "Receipts")
                            if model.receipts.isEmpty { Text("No commands yet.") }
                            ForEach(model.receipts.prefix(4)) { receipt in
                                Text("\(receipt.summary) (\(receipt.source.title), revision \(receipt.revision.rawValue))")
                            }
                        }
                    }
                    Button("Reset Screening…", role: .destructive) { isConfirmingReset = true }
                        .accessibilityIdentifier("screening.reset")
                }
                .padding(32)
            }
        }
        .font(.callout)
        .padding(.horizontal, 80)
        .padding(.top, 24)
        .navigationTitle(ScreeningRoom.title)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screening.screen")
        .task { await model.start() }
        .onChange(of: model.state.surface, initial: true) { _, surface in
            if surface == .theater { showsTheater = true }
            if surface == .inline { showsTheater = false }
        }
        .onChange(of: showsTheater, initial: true) { _, open in model.theaterIsOpen = open }
        .fullScreenCover(isPresented: $showsTheater, onDismiss: returnToPage) {
            PlayerSurfaceView(model: model, role: .theater)
                .ignoresSafeArea()
                .accessibilityIdentifier("screening.theater.player")
        }
        .confirmationDialog("Reset the screening?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("Reset Screening", role: .destructive) { Task { await model.reset() } }
        } message: {
            Text("The Test Card returns to the start with captions off, and the saved resume point is removed. Nothing else changes.")
        }
        .onDisappear { model.persist() }
    }

    @ViewBuilder private var preview: some View {
        ZStack {
            Rectangle().fill(.black)
            switch model.phase {
            case .failed(let failure):
                VStack(spacing: 16) {
                    SymbolLabel(title: failure.title, systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text("\(failure.message) \(failure.recovery)")
                        .multilineTextAlignment(.center)
                }
                .padding(40)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("screening.failure")
            case .ready where !model.theaterIsOpen:
                PlayerPreview(player: model.player.player)
                    .accessibilityHidden(true)
            case .ready:
                Text("Showing in the theater")
            case .idle, .opening:
                ProgressView()
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 24))
    }

    /// Play or pause and the two skips as symbols in one row, with Watch in Theater below them:
    /// the column is too narrow for four titled buttons side by side.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 24) {
                Button(model.state.isPlaying ? "Pause" : "Play", systemImage: model.state.isPlaying ? "pause.fill" : "play.fill") {
                    run(model.state.isPlaying ? .pause : .play)
                }
                .accessibilityIdentifier("screening.play")
                Button("Back 10 Seconds", systemImage: "gobackward.10") { run(.skip(by: -ScreeningRoom.skipInterval)) }
                Button("Forward 10 Seconds", systemImage: "goforward.10") { run(.skip(by: ScreeningRoom.skipInterval)) }
            }
            .labelStyle(.iconOnly)
            Button("Watch in Theater", systemImage: "play.rectangle") { run(.present(.theater)) }
                .accessibilityIdentifier("screening.theater")
        }
        .disabled(model.phase != .ready)
    }

    private var captions: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeading(title: "Captions")
            HStack(spacing: 24) {
                captionButton("Off", choice: .off)
                ForEach(model.clip?.captions ?? []) { track in
                    captionButton(track.title, choice: .track(track.id))
                }
            }
        }
        .disabled(model.phase != .ready)
    }

    private func captionButton(_ title: String, choice: CaptionChoice) -> some View {
        let selected = model.state.caption == choice
        return Button(title, systemImage: selected ? "checkmark.circle.fill" : "circle") {
            run(.selectCaption(choice))
        }
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityIdentifier("screening.caption.\(choice.trackID ?? "off")")
    }

    private var clips: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeading(title: "Clips")
            VStack(alignment: .leading, spacing: 20) {
                ForEach(ScreeningClips.all) { clip in
                    Button(clip.title, systemImage: model.state.clip == clip.id ? "checkmark.circle.fill" : "film") {
                        Task { await model.open(clip) }
                    }
                    .accessibilityIdentifier("screening.clip.\(clip.id)")
                }
            }
        }
    }

    private func run(_ command: PlaybackCommand) {
        Task { await model.perform(command) }
    }

    /// Menu closed the theater: the clip is back in the page.
    private func returnToPage() {
        guard model.state.surface == .theater else { return }
        run(.present(.inline))
    }
}

/// The clip's picture without controls, so it never takes focus. The theater has the controls.
private struct PlayerPreview: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}
