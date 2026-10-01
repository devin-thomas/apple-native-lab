import AudioWorkshop
import LabCatalog
import SwiftUI
import UniformTypeIdentifiers

// MARK: Safety controls

/// Play or Stop, Panic Mute, and Bypass: the controls that must always be in reach. The iPhone
/// pins them to the bottom of the page; the Mac keeps them at the top of the workshop and in the
/// Lab menu with keyboard shortcuts.
struct WorkshopSafetyControls: View {
    let session: AudioWorkshopSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
        layout {
            Button {
                session.togglePlayback()
            } label: {
                Label(session.state.isPlaying ? "Stop" : "Play", systemImage: session.state.isPlaying ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityHint(session.state.isPlaying ? "Stops live playback." : "Plays the original loop through the graph.")

            Button(role: session.isMuted ? nil : .destructive) {
                session.setMuted(!session.isMuted)
            } label: {
                Label(session.isMuted ? "Unmute" : "Panic Mute", systemImage: session.isMuted ? "speaker.wave.2" : "speaker.slash.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(session.isMuted ? .accentColor : .red)
            .accessibilityInputLabels(session.isMuted ? ["Unmute"] : ["Panic Mute", "Mute", "Silence"])
            .accessibilityHint(session.isMuted ? "Fades the output back in." : "Silences the output within milliseconds.")

            Toggle(isOn: Binding(get: { session.isBypassed }, set: { session.setBypassed($0) })) {
                Label("Bypass", systemImage: "arrow.triangle.branch")
            }
            .toggleStyle(.button)
            .accessibilityHint("Plays the loop without the filter and gain.")
        }
        .controlSize(.large)
    }
}

/// The playback state in words, with the last recovery.
struct WorkshopStateLine: View {
    let session: AudioWorkshopSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(stateText, systemImage: session.isMuted ? "speaker.slash" : "waveform")
                .font(.headline)
            if let recovery = session.playback?.lastRecovery {
                Text(recovery).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var stateText: String {
        let muted = session.isMuted ? ", muted" : ""
        let bypassed = session.isBypassed ? ", bypassed" : ""
        switch session.state {
        case .playing(let output): return "Playing on \(output.summary)\(muted)\(bypassed)"
        case .failed(let reason): return "Live audio unavailable. \(reason)"
        default: return "\(session.state.title)\(muted)\(bypassed)"
        }
    }
}

// MARK: The graph

/// Every stage in signal order, with whether it is shaping the sound right now.
struct WorkshopGraphSection: View {
    let session: AudioWorkshopSession

    var body: some View {
        Section("Graph") {
            ForEach(session.graph) { node in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: Self.symbol(node.role))
                        .foregroundStyle(node.isActive ? Color.accentColor : .secondary)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.title).font(.body.weight(.semibold))
                        Text(node.detail).font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Text(node.isActive ? "Active" : "Inactive")
                        .font(.caption)
                        .foregroundStyle(node.isActive ? .primary : .secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(node.spokenSummary)
            }
        }
    }

    static func symbol(_ role: GraphNode.Role) -> String {
        switch role {
        case .source: "waveform"
        case .filter: "line.3.horizontal.decrease"
        case .gain: "dial.medium"
        case .bypass: "arrow.triangle.branch"
        case .mute: "speaker.slash"
        case .limiter: "rectangle.compress.vertical"
        case .output: "hifispeaker"
        }
    }
}

/// Counters from the render callbacks, read from the kernel's atomics four times a second while
/// playing. Stopped, nothing renders, so the numbers are read only when the view updates.
struct WorkshopStatsSection: View {
    let session: AudioWorkshopSession

    var body: some View {
        Section("Render stats") {
            TimelineView(.periodic(from: .now, by: session.state.isPlaying ? 0.25 : 3_600)) { _ in
                let stats = session.stats
                LabeledContent("Callbacks", value: "\(stats.callbacks)")
                LabeledContent("Rendered", value: String(format: "%.1f s at %d Hz", stats.renderedSeconds, Int(stats.sampleRate)))
                LabeledContent("Peak", value: RenderStats.decibels(stats.lastPeak).map { String(format: "%.1f dBFS", $0) } ?? "Silent")
                LabeledContent("Graph builds", value: "\(stats.generation), recoveries \(session.playback?.recoveries ?? 0)")
                LabeledContent("Limited samples", value: "\(stats.clippedSamples)")
                LabeledContent("Refused calls", value: "\(stats.oversizedCalls)")
            }
            SectionNote("The render callback is C that clang checks never allocates, locks, or blocks. These numbers are atomics it writes; reading them never stops the audio.")
        }
    }
}

// MARK: Sound

struct WorkshopSoundSection: View {
    let session: AudioWorkshopSession

    var body: some View {
        Section("Sound") {
            Picker("Loop", selection: Binding(get: { session.preset.loop }, set: { session.setLoop($0) })) {
                ForEach(LoopFixture.allCases) { loop in Text(loop.title).tag(loop) }
            }
            Text(session.preset.loop.detail).font(.footnote).foregroundStyle(.secondary)

            ParameterSlider(title: "Gain", value: binding(.gainDecibels), range: -60...6, step: 0.5,
                            text: AudioGraphPreset.decibelText(session.preset.gainDecibels))
            Toggle("Low-pass filter", isOn: Binding(get: { session.preset.filterEnabled }, set: { session.set(.filterEnabled, to: $0 ? 1 : 0) }))
            ParameterSlider(title: "Cutoff", value: cutoffPosition, range: 0...1, step: 0.005,
                            text: AudioGraphPreset.hertzText(session.preset.cutoffHertz))
            ParameterSlider(title: "Resonance", value: binding(.resonance), range: 0.5...8, step: 0.1,
                            text: String(format: "Q %.1f", session.preset.resonance))
        }
    }

    private func binding(_ parameter: WorkshopParameter) -> Binding<Double> {
        Binding(get: {
            switch parameter {
            case .gainDecibels: session.preset.gainDecibels
            case .resonance: session.preset.resonance
            default: session.preset.cutoffHertz
            }
        }, set: { session.set(parameter, to: $0) })
    }

    /// The cutoff on a logarithmic slider: each step is the same musical interval.
    private var cutoffPosition: Binding<Double> {
        Binding(get: { log(session.preset.cutoffHertz / 20) / log(1_000) },
                set: { session.set(.cutoffHertz, to: 20 * pow(1_000, $0)) })
    }
}

/// A labeled slider whose value is spoken in its own units.
struct ParameterSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(title, value: text)
            Slider(value: $value, in: range, step: step) { Text(title) }
                .accessibilityValue(text)
        }
    }
}

// MARK: MIDI

struct WorkshopMidiSection: View {
    let session: AudioWorkshopSession

    var body: some View {
        Section("MIDI") {
            Text(session.preset.midi.summary + ".").font(.footnote).foregroundStyle(.secondary)
            Stepper(value: Binding(get: { Int(session.preset.midi.controller) }, set: { session.setController($0) }),
                    in: 0...Int(MidiMapping.controllers.upperBound)) {
                LabeledContent("Mapped controller", value: "CC \(session.preset.midi.controller)")
            }
            VStack(alignment: .leading, spacing: 2) {
                LabeledContent("On-screen controller", value: "\(Int(session.onScreenValue))")
                // Moving it sends a message; a message from a MIDI source only moves it.
                Slider(value: Binding(get: { session.onScreenValue }, set: { session.sendOnScreen(value: Int($0.rounded())) }),
                       in: 0...127, step: 1) { Text("On-screen controller") }
                    .accessibilityValue("\(Int(session.onScreenValue)) of 127, cutoff \(AudioGraphPreset.hertzText(session.preset.cutoffHertz))")
            }
            HStack {
                ForEach([0, 64, 127], id: \.self) { value in
                    Button("Send \(value)") { session.sendOnScreen(value: value) }
                        .accessibilityLabel("Send controller value \(value)")
                }
            }
            .buttonStyle(.bordered)
            Toggle("Listen to MIDI Sources", isOn: Binding(get: { session.isListeningToMidi }, set: { session.setListening($0) }))
            if session.isListeningToMidi {
                Text(session.midiSources.isEmpty ? "No MIDI source is connected." : "Listening to \(session.midiSources.joined(separator: ", ")).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if session.midiLog.isEmpty {
                Text("No MIDI messages yet.").foregroundStyle(.secondary)
            } else {
                ForEach(session.midiLog) { entry in
                    Text(entry.line).font(.footnote.monospaced())
                }
            }
        }
    }
}

// MARK: Offline, the declared fallback

struct WorkshopOfflineSection: View {
    let session: AudioWorkshopSession
    @State private var isImporting = false
    @State private var isExporting = false

    var body: some View {
        Section("Offline processing") {
            Button("Render the Loop Offline", systemImage: "waveform.badge.plus") { session.renderOffline() }
                .disabled(session.isRendering)
            Button("Process a WAVE File…", systemImage: "doc.badge.gearshape") { isImporting = true }
                .disabled(session.isRendering)
            if session.isRendering {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Rendering…")
                    Spacer()
                    Button("Cancel") { session.cancelOffline() }
                }
            }
            if let result = session.offline {
                Text(result.summary)
                LabeledContent("SHA-256", value: String(result.digest.hex.prefix(16)) + "…")
                    .font(.footnote)
                Button("Export WAVE File…", systemImage: "square.and.arrow.up") { isExporting = true }
            }
            SectionNote("Offline processing runs the same graph without an audio device: the original loop, or a mono or stereo WAVE file you choose. It never records.")
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.wav]) { result in
            if case .success(let url) = result { session.processFile(at: url) }
        }
        .fileExporter(isPresented: $isExporting, document: session.offline.map { WaveDocument(data: $0.wave) },
                      contentType: .wav, defaultFilename: session.offline?.suggestedFileName) { _ in }
    }
}

/// A rendered WAVE file for the export dialog.
struct WaveDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.wav]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: Presets and the plugin form

struct WorkshopPresetsSection: View {
    let session: AudioWorkshopSession
    var onReceipt: (ReceiptRecord) -> Void = { _ in }
    @Environment(LabLibrary.self) private var library

    var body: some View {
        @Bindable var session = session
        Section("Presets") {
            TextField("Preset name", text: $session.presetName)
            Button("Save Preset", systemImage: "square.and.arrow.down") {
                Task {
                    if let record = await session.savePreset(library) {
                        onReceipt(record)
                        LabAnnouncement(text: "Saved \(session.presetName). \(record.receipt.summary)").post()
                    }
                }
            }
            .disabled(!library.canAct)
            if let save = session.lastSave {
                Text(save.receipt.summary).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(session.presets) { saved in
                HStack {
                    VStack(alignment: .leading) {
                        Text(saved.title)
                        Text(saved.preset?.summary ?? "Cannot be loaded: \(Self.reason(saved))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Load") { session.load(saved) }
                        .disabled(saved.preset == nil)
                        .accessibilityLabel("Load \(saved.title)")
                }
            }
            SectionNote("Saving adds an item to your \(AudioWorkshop.presetCollectionTitle) collection with a receipt. Presets are yours: Reset Demo keeps them. Bypass and mute are never saved.")
        }
        .task { await session.loadPresets(library) }
    }

    static func reason(_ saved: SavedPreset) -> String {
        if case .failure(let rejection) = saved.content { rejection.message } else { "" }
    }
}

struct WorkshopPluginSection: View {
    let session: AudioWorkshopSession

    var body: some View {
        Section("Plugin form") {
            if session.plugin?.isLoaded == true {
                Button("Save State and Reload Plugin", systemImage: "arrow.clockwise") { Task { await session.reloadPlugin() } }
            } else {
                Button("Load the Audio Unit", systemImage: "puzzlepiece.extension") { Task { await session.loadPlugin() } }
            }
            if let note = session.pluginNote {
                Text(note).font(.footnote)
            }
            SectionNote(Self.note)
        }
    }

    static var note: String {
        #if os(iOS)
        "The same filter ships as an AUv3 effect, \(WorkshopAudioUnit.componentName), in the Native Lab build with system surfaces. Here the app hosts it itself: Reload saves its state, loads a new instance, and restores it."
        #else
        "The app hosts the filter as an audio unit in-process: Reload saves its state, loads a new instance, and restores it. The AUv3 extension is built for iPhone and iPad."
        #endif
    }
}

// MARK: The page

/// The whole workshop on one page, for iPhone and iPad. The safety controls stay pinned below.
struct AudioWorkshopPage: View {
    var session = AudioWorkshopSession.shared

    var body: some View {
        Form {
            Section {
                WorkshopStateLine(session: session)
                if let message = session.message {
                    Text(message).font(.footnote)
                }
            }
            WorkshopGraphSection(session: session)
            WorkshopSoundSection(session: session)
            WorkshopMidiSection(session: session)
            WorkshopOfflineSection(session: session)
            WorkshopStatsSection(session: session)
            WorkshopPresetsSection(session: session)
            WorkshopPluginSection(session: session)
            Section {
                Button("Reset Workshop", systemImage: "arrow.counterclockwise") { session.resetDemo() }
            } footer: {
                Text("Stops playback and returns the graph, MIDI log, and render to their first-run state. Saved presets stay.")
            }
        }
        .navigationTitle(AudioWorkshop.title)
        #if os(iOS)
        .safeAreaInset(edge: .bottom) {
            PinnedActionBar { WorkshopSafetyControls(session: session) }
        }
        #endif
    }
}

/// The experiment's entry on its catalog page: iPhone and iPad push the workshop, and the Mac
/// shows it in the frontmost window (also in the sidebar and with Command-9).
struct AudioWorkshopLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == AudioWorkshop.experimentID {
            #if os(macOS)
            Button {
                window?.destination = .audioWorkshop
            } label: {
                Label("Open \(AudioWorkshop.title)", systemImage: AudioWorkshop.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .disabled(window == nil)
            .help("Show the experiment in this window (⌘9)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            NavigationLink {
                AudioWorkshopPage()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Open \(AudioWorkshop.title)", systemImage: AudioWorkshop.symbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .accessibilityHint("Opens the experiment.")
            #endif
        }
    }
}
