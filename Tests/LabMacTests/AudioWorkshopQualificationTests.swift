import AudioWorkshop
import Foundation
import LabDomain
import LabStore
import LabSupport
import Testing
@testable import NativeLab

/// Clean-store qualification, with no audio device or MIDI client. The same replay runs inside
/// the Mac host and the iPhone simulator; the engine is real, its route event is injected.
@MainActor
@Suite("Audio Workshop host qualification", .serialized)
struct AudioWorkshopQualificationTests {
    @Test func graphFallbackPresetAndPluginReplay() async throws {
        let started = Date()
        let folder = FileManager.default.temporaryDirectory.appending(path: "AudioWorkshopQualification-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        let output = ManualRenderingOutput(sampleRate: 44_100)
        let session = AudioWorkshopSession(output: output)
        defer { session.resetDemo() }
        #expect(session.preset == .standard && session.state == .stopped)
        session.setLoop(.noise)
        session.set(.gainDecibels, to: -12)
        session.sendOnScreen(value: 64)
        let preset = session.preset
        session.togglePlayback()
        #expect(session.state.isPlaying)
        #expect(try output.render(frames: 4_410).peak > 0)
        session.setBypassed(true)
        session.panicMute()
        _ = try output.render(frames: 4_410)
        output.simulateConfigurationChange(toSampleRate: 96_000)
        #expect(session.state.isPlaying)
        #expect(session.playback?.recoveries == 1)
        #expect(session.stats.sampleRate == 96_000)
        #expect(try output.render(frames: 9_600).channels.allSatisfy { $0.allSatisfy { $0 == 0 } })
        #expect(session.preset == preset && session.isMuted && session.isBypassed)
        session.stop()
        session.setBypassed(false)

        session.renderOffline(seconds: 0.1)
        await session.finishOffline()
        let rendered = try #require(session.offline)
        #expect(rendered.audio.frameCount == 4_800 && rendered.audio.peak > 0)
        let source = folder.appending(path: "original-loop.wav")
        try rendered.wave.write(to: source)
        session.set(.cutoffHertz, to: 300)
        session.processFile(at: source)
        await session.finishOffline()
        let processed = try #require(session.offline)
        #expect(processed.digest != rendered.digest)
        #expect(try Data(contentsOf: source) == rendered.wave)
        let bad = folder.appending(path: "invalid.wav")
        try Data("not audio".utf8).write(to: bad)
        session.processFile(at: bad)
        await session.finishOffline()
        #expect(session.offline == processed)
        #expect(session.message == WaveFileRejection.notWave.message)

        session.presetName = "Original Noise"
        let receipt = try #require(await session.savePreset(library))
        #expect(receipt.receipt.status == .committed && receipt.receipt.admitted.adapter == .appUI)
        let saved = try #require(session.presets.first)
        let store = try await SQLiteOperationStore(url: url)
        let item = try #require(try await store.item(saved.id))
        #expect(item.namespace == .user)
        let requests = PresetStore(backend: LibraryPresetBackend(library: library))
        let request = try PresetSaveRequest(named: "Retry Once", preset: preset)
        let first = try await requests.save(request)
        let retry = try await requests.save(request)
        #expect(first == retry)
        #expect(try await requests.presets().count == 2)

        await session.loadPlugin()
        #expect(session.plugin?.isLoaded == true, "\(session.pluginNote ?? "")")
        let pluginBefore = try #require(session.plugin?.workshopUnit?.preset)
        await session.reloadPlugin()
        #expect(session.plugin?.reloads == 1)
        #expect(session.plugin?.workshopUnit?.preset == pluginBefore)
        session.resetDemo()
        #expect(session.preset == .standard && session.state == .stopped)
        #expect(session.offline == nil && session.midiLog.isEmpty)
        #expect(!session.isMuted && !session.isBypassed && session.plugin?.isLoaded == false)
        #expect(try Data(contentsOf: source) == rendered.wave)
        #expect(try await store.item(saved.id) == item)
        #expect(await library.resetDemo() != nil)
        #expect(try await store.item(saved.id) == item)
        await session.loadPresets(library)
        session.panicMute()
        session.load(saved)
        #expect(session.isMuted && session.preset == saved.preset)

        let fallback = AudioWorkshopSession(output: nil)
        fallback.togglePlayback()
        #expect(!fallback.state.isPlaying)
        fallback.sendOnScreen(value: 127)
        #expect(abs(fallback.preset.cutoffHertz - 12_000) < 0.01)
        fallback.renderOffline(seconds: 0.1)
        await fallback.finishOffline()
        #expect(fallback.offline?.audio.frameCount == 4_800)
        fallback.resetDemo()

        #if os(iOS)
        let execution = try Execution(observing: .current)
        #expect(execution.path == .simulator)
        let name = "audio-workshop-iphone-simulator-host.json"
        #else
        let execution = Execution.fixture
        let name = "audio-workshop-mac-host.json"
        #endif
        let record = try EvidenceRecord(
            subject: "LAB-029", check: "Clean graph, offline file, preset, recovery, and in-process plugin replay",
            date: started, provenance: .current, execution: execution,
            inputs: ["preset@sha256:\(ContentDigest.sha256(preset.canonicalJSON).hex)",
                     "original-loop.wav@sha256:\(rendered.digest.hex)",
                     "invalid.wav@sha256:\(ContentDigest.sha256(Data("not audio".utf8)).hex)"],
            steps: ["Start a fresh SQLite library and workshop; original noise, gain -12 dB, on-screen CC 74 value 64",
                    "Manually render the real engine at 44100 Hz; mute and bypass; inject change to 96000 Hz; render silence and inspect settings",
                    "Render 0.1 seconds offline; write original WAVE; process with cutoff 300 Hz; refuse invalid WAVE retaining last result",
                    "Save preset through app UI; retry an identical request; inspect user namespace and receipts",
                    "Load the in-process unit, save state, reload and compare; reset workshop and library; compare preset item and source file",
                    "Unavailable output: on-screen MIDI and offline render still complete"],
            outcome: .passed(observed: "Real manual-rendering engine recovered once at 96 kHz retaining mute, bypass and settings. File processing retained original bytes and refused invalid input. Presets committed with app-UI receipts; retry returned one receipt and one item. In-process unit reloaded with the same preset. Both resets preserved user preset and original WAVE. Unavailable-output fallback completed."),
            limitations: ["Hosted session calls, not rendered UI or file dialogs; no physical device, speaker, microphone, or MIDI source.",
                          "Configuration change injected; not a real output-route change, interruption, or media-services reset.",
                          "Plugin registered in-process; AUv3 extension and third-party host not loaded.",
                          "Realtime C compile-time enforcement is separate; no runtime allocation/deadline trace. Offline render does not apply live panic mute."])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        Attachment.record(String(decoding: try encoder.encode(record), as: UTF8.self), named: name)
        #expect(record.supportedState == .implemented)
    }
}
