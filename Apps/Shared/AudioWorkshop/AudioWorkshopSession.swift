import AudioWorkshop
import Foundation
import LabDomain
import Observation

/// One MIDI message the workshop received, for the on-screen log.
struct MidiLogEntry: Identifiable, Hashable {
    let id = UUID()
    let event: MidiEvent
    let source: String
    /// The cutoff the message set, or `nil` when it was not the mapped controller.
    let cutoff: Double?

    var line: String {
        let effect = cutoff.map { "cutoff \(AudioGraphPreset.hertzText($0))" } ?? "not mapped"
        return "\(event.description) from \(source): \(effect)"
    }
}

/// The app's Audio Workshop (LAB-029): one kernel, its live playback, the offline fallback, MIDI,
/// presets, and the in-process plugin host. One per process, because the audio output is.
///
/// Every control writes the kernel's atomics directly, so a change reaches the audio thread
/// without a lock. The only change to the lab's data is saving a preset, which goes through
/// `LabLibrary` and `OperationService` with a receipt.
@MainActor
@Observable
final class AudioWorkshopSession {
    static let shared = AudioWorkshopSession()

    static let pendingNote = "Nothing is playing. Play starts the original loop through the graph; Panic Mute silences it at once."
    static let logLimit = 12

    let kernel: AudioKernel?
    let playback: LivePlayback?
    let plugin: PluginHost?

    private(set) var preset = AudioGraphPreset.standard
    private(set) var isBypassed = false
    private(set) var isMuted = false

    /// The on-screen controller's position, 0 to 127. Moving it sends the mapped controller.
    private(set) var onScreenValue: Double = Double(MidiMapping.standard.value(forCutoff: AudioGraphPreset.standard.cutoffHertz))
    private(set) var midiLog: [MidiLogEntry] = []
    private(set) var midiSources: [String] = []
    private(set) var isListeningToMidi = false
    @ObservationIgnored private var midiInput: MidiInput?

    private(set) var offline: OfflineResult?
    private(set) var isRendering = false
    @ObservationIgnored private var renderTask: Task<Void, Never>?

    private(set) var presets: [SavedPreset] = []
    private(set) var lastSave: ReceiptRecord?
    @ObservationIgnored private var pendingSave: PresetSaveRequest?
    var presetName = "My Preset"

    private(set) var pluginNote: String?
    /// A message for the person, shown near the control that caused it.
    private(set) var message: String?

    init(output: (any AudioOutput)? = AudioWorkshopSession.liveOutput()) {
        do {
            let kernel = try AudioKernel()
            kernel.apply(.standard)
            self.kernel = kernel
            playback = LivePlayback(kernel: kernel, output: output,
                                    unavailableReason: "Live audio is not available here. Render Offline and Process a WAVE File still work.")
        } catch {
            kernel = nil
            playback = nil
            message = error.message
        }
        plugin = PluginHost()
    }

    static func liveOutput() -> (any AudioOutput)? { EngineOutput() }

    // MARK: Safety controls, always reachable

    var state: PlaybackState { playback?.state ?? .failed(message ?? "The audio kernel is unavailable.") }

    func togglePlayback() {
        guard let playback else { return }
        if playback.state.isPlaying || playback.state == .recovering { playback.stop() } else { playback.play() }
    }

    func stop() { playback?.stop() }

    /// Silences the output within milliseconds. Only Unmute, pressed by a person, clears it.
    func panicMute() { setMuted(true) }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        kernel?.set(.mute, muted ? 1 : 0)
    }

    func setBypassed(_ bypassed: Bool) {
        isBypassed = bypassed
        kernel?.set(.bypass, bypassed ? 1 : 0)
    }

    // MARK: The graph

    func set(_ parameter: WorkshopParameter, to value: Double) {
        preset.set(parameter, to: value)
        kernel?.apply(preset)
        if parameter == .cutoffHertz { onScreenValue = Double(preset.midi.value(forCutoff: preset.cutoffHertz)) }
    }

    func setLoop(_ loop: LoopFixture) {
        preset.setLoop(loop)
        kernel?.apply(preset)
    }

    func setController(_ controller: Int) {
        preset.setMidi(preset.midi.with(controller: UInt8(clamping: controller)))
    }

    var graph: [GraphNode] {
        let output: GraphOutput = if case .playing(let description) = state { .live(description) } else { .offline }
        return AudioGraph.nodes(preset: preset, bypassed: isBypassed, muted: isMuted, output: output)
    }

    var stats: RenderStats { kernel?.stats ?? .zero }

    // MARK: MIDI

    /// The on-screen controls send the same MIDI 1.0 bytes a hardware controller would, through
    /// the same parser and mapping.
    func sendOnScreen(value: Int) {
        onScreenValue = Double(min(max(value, 0), 127))
        let event = MidiEvent.controlChange(channel: preset.midi.channel ?? 1, controller: preset.midi.controller,
                                            value: UInt8(clamping: value))
        var parser = MidiByteParser()
        receive(parser.feed(event.bytes), source: "On-screen controls")
    }

    func receive(_ events: [MidiEvent], source: String) {
        for event in events {
            let cutoff = preset.midi.cutoff(for: event)
            if let cutoff {
                preset.set(.cutoffHertz, to: cutoff)
                kernel?.set(.cutoffHertz, cutoff)
                if source != "On-screen controls", case .controlChange(_, _, let value) = event { onScreenValue = Double(value) }
            }
            midiLog.insert(MidiLogEntry(event: event, source: source, cutoff: cutoff), at: 0)
        }
        if midiLog.count > Self.logLimit { midiLog.removeLast(midiLog.count - Self.logLimit) }
    }

    func setListening(_ listening: Bool) {
        if listening {
            let input = midiInput ?? MidiInput { [weak self] events, source in
                Task { @MainActor in self?.receive(events, source: source) }
            }
            midiInput = input
            do {
                midiSources = try input.start()
                isListeningToMidi = true
                message = midiSources.isEmpty ? "Listening, but no MIDI source is connected. The on-screen controls send the same messages." : nil
            } catch {
                isListeningToMidi = false
                message = error.message
            }
        } else {
            midiInput?.stop()
            isListeningToMidi = false
            midiSources = []
        }
    }

    // MARK: Offline processing, the declared fallback

    func renderOffline(seconds: Double = 4) {
        let preset = preset
        let bypassed = isBypassed
        run { () async throws(OfflineError) -> OfflineResult in
            try await OfflineProcessor.renderLoop(preset, bypassed: bypassed, seconds: seconds)
        }
    }

    /// Processes a WAVE file the person chose. It is read off the main actor, once, within its
    /// security scope, and refused before reading when it is larger than the reader allows.
    func processFile(at url: URL) {
        let preset = preset
        let bypassed = isBypassed
        run { () async throws(OfflineError) -> OfflineResult in
            let limit = WaveFile.Limits().maximumBytes
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data: Data
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= limit else { throw OfflineError.unreadable(.tooLarge(limit: limit)) }
                data = try Data(contentsOf: url)
            } catch let error as OfflineError {
                throw error
            } catch {
                throw .fileUnavailable
            }
            return try await OfflineProcessor.process(waveData: data, named: url.lastPathComponent, preset: preset, bypassed: bypassed)
        }
    }

    func cancelOffline() {
        renderTask?.cancel()
    }

    private func run(_ work: @escaping @Sendable () async throws(OfflineError) -> OfflineResult) {
        renderTask?.cancel()
        isRendering = true
        message = nil
        renderTask = Task {
            do throws(OfflineError) {
                let result = try await work()
                offline = result
            } catch {
                message = error.message
            }
            isRendering = false
        }
    }

    /// Waits for the current offline work, for tests.
    func finishOffline() async {
        await renderTask?.value
    }

    // MARK: Presets, through the operation service

    func loadPresets(_ library: LabLibrary) async {
        do {
            presets = try await PresetStore(backend: LibraryPresetBackend(library: library)).presets()
        } catch {
            message = error.message
        }
    }

    /// Saves the current graph as a preset. A retry after a failure reuses the same request, so
    /// it can never save a second copy.
    @discardableResult
    func savePreset(_ library: LabLibrary) async -> ReceiptRecord? {
        let request: PresetSaveRequest
        if let pendingSave, pendingSave.preset == preset, pendingSave.title.value == presetName.trimmingCharacters(in: .whitespacesAndNewlines) {
            request = pendingSave
        } else {
            do { request = try PresetSaveRequest(named: presetName, preset: preset) } catch {
                message = error.message
                return nil
            }
        }
        pendingSave = request
        do {
            let receipt = try await PresetStore(backend: LibraryPresetBackend(library: library)).save(request)
            pendingSave = nil
            message = nil
            lastSave = library.receipt(id: receipt.operationID)
            await loadPresets(library)
            return lastSave
        } catch {
            message = error.message
            return nil
        }
    }

    func load(_ saved: SavedPreset) {
        guard let loaded = saved.preset else {
            if case .failure(let rejection) = saved.content { message = rejection.message }
            return
        }
        preset = loaded
        kernel?.apply(loaded)
        presetName = saved.title
        onScreenValue = Double(loaded.midi.value(forCutoff: loaded.cutoffHertz))
        message = "Loaded \(saved.title). Bypass and mute are unchanged."
    }

    // MARK: The plugin form, hosted in-process

    func loadPlugin() async {
        guard let plugin else { return }
        do {
            try await plugin.load()
            plugin.workshopUnit?.apply(preset)
            pluginNote = "Loaded \(WorkshopAudioUnit.componentName) with the current graph's settings."
        } catch {
            pluginNote = error.message
        }
    }

    /// Saves the unit's state, tears it down, loads a fresh one, restores the state, and reports
    /// whether the restored unit holds the same preset.
    func reloadPlugin() async {
        guard let plugin, let before = plugin.workshopUnit?.preset else {
            pluginNote = PluginHostError.notLoaded.message
            return
        }
        do {
            let bytes = try plugin.saveState()
            try await plugin.reload()
            let after = plugin.workshopUnit?.preset
            pluginNote = after == before
                ? "Reloaded from \(bytes.count) bytes of saved state. The new instance holds the same preset."
                : "Reloaded, but the new instance's preset differs. \(after?.summary ?? "")"
        } catch {
            pluginNote = error.message
        }
    }

    // MARK: Reset

    /// Returns the experiment to its first-run state: stopped, the standard graph, no log, no
    /// render, no plugin. Saved presets are the person's data and stay.
    func resetDemo() {
        renderTask?.cancel()
        playback?.stop()
        setListening(false)
        preset = .standard
        kernel?.apply(.standard)
        setBypassed(false)
        setMuted(false)
        onScreenValue = Double(MidiMapping.standard.value(forCutoff: AudioGraphPreset.standard.cutoffHertz))
        midiLog = []
        offline = nil
        isRendering = false
        plugin?.unload()
        pluginNote = nil
        presetName = "My Preset"
        pendingSave = nil
        message = "The workshop is back to its first-run state. Saved presets were kept."
    }
}

/// The preset store's way into the host: reads and commits go through `LabLibrary` and
/// `LabDataService` as the app UI, so a save is authorized and listed with its receipt.
struct LibraryPresetBackend: PresetBackend {
    let library: LabLibrary

    private func service() async throws(PresetStoreError) -> LabDataService {
        do { return try await library.openedService() } catch {
            switch error {
            case .unavailable(let reason): throw .unavailable(reason: reason)
            case .refused(let refusal): throw .refused(refusal)
            }
        }
    }

    func collection(_ id: CollectionID) async throws(PresetStoreError) -> LabCollection? {
        let service = try await service()
        do {
            return try await service.collection(id, as: LabDataService.appUI)
        } catch .notFound {
            return nil
        } catch {
            throw .refused(error)
        }
    }

    func items(in collection: CollectionID) async throws(PresetStoreError) -> [LabItem] {
        let service = try await service()
        let filter = try! ItemFilter(collectionID: collection, includeArchived: true, limit: ItemFilter.allowedLimits.upperBound)
        do { return try await service.items(filter, as: LabDataService.appUI) } catch { throw .refused(error) }
    }

    func commit(_ operation: DomainOperation, requestID: RequestID, names: [EntityReference: String]) async throws(PresetStoreError) -> ActionReceipt {
        do {
            return try await library.submit(operation, requestID: requestID, authority: .userAction, names: names).receipt
        } catch {
            switch error {
            case .unavailable(let reason): throw .unavailable(reason: reason)
            case .refused(let refusal): throw .refused(refusal)
            }
        }
    }
}
