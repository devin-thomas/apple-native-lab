import AudioToolbox
import AVFAudio
import Foundation
import Testing
@testable import AudioWorkshop

/// The real AVAudioEngine and the real audio unit, in offline manual rendering: the engine renders
/// on request and never opens an audio device. Only the system's configuration-change
/// notification is simulated; the rebuild it triggers runs the real engine at the new rate.
@MainActor
@Suite struct LivePlaybackTests {
    @Test func theEngineRendersTheSameGraphAsTheOfflineProcessor() async throws {
        let kernel = try AudioKernel()
        kernel.apply(.standard)
        let output = ManualRenderingOutput(sampleRate: 44_100)
        let playback = LivePlayback(kernel: kernel, output: output)
        playback.play()
        #expect(playback.state == .playing(OutputDescription(sampleRate: 44_100, channels: 2, route: ManualRenderingOutput.route)))
        let engine = try output.render(frames: 44_100)
        let offline = try await OfflineProcessor.renderLoop(.standard, seconds: 1, sampleRate: 44_100)
        // The engine's mixer sums one input at unity, so the two differ only by rounding.
        for channel in 0..<2 {
            let difference = zip(engine.channels[channel], offline.audio.channels[channel]).map { abs($0 - $1) }.max() ?? 1
            #expect(difference < 1e-4)
        }
        #expect(kernel.stats.frames == 44_100)
        playback.stop()
        #expect(playback.state == .stopped)
    }

    @Test func aSampleRateChangeRebuildsTheGraphAndFadesBackIn() throws {
        let kernel = try AudioKernel()
        kernel.apply(try AudioGraphPreset(loop: .chords, gainDecibels: -3, filterEnabled: true, cutoffHertz: 3_000, resonance: 0.8))
        let output = ManualRenderingOutput(sampleRate: 44_100)
        let playback = LivePlayback(kernel: kernel, output: output)
        playback.play()
        _ = try output.render(frames: 22_050)
        let generation = kernel.stats.generation

        output.simulateConfigurationChange(toSampleRate: 48_000)
        #expect(playback.state == .playing(OutputDescription(sampleRate: 48_000, channels: 2, route: ManualRenderingOutput.route)))
        #expect(playback.recoveries == 1)
        #expect(output.starts == 2)
        #expect(kernel.stats.generation == generation + 1)
        #expect(kernel.stats.sampleRate == 48_000)

        let after = try output.render(frames: 48_000)
        #expect(after.sampleRate == 48_000)
        // The rebuilt graph starts from silence and ramps: no sample-to-sample jump.
        #expect(abs(after.channels[0][0]) < 0.001)
        #expect(Signal.maximumStep(after.channels[0]) < 0.05)
        #expect(Signal.rms(after.channels[0][24_000...]) > 0.02)
        // The settings survived: they live in the kernel, not in the engine.
        #expect(kernel.value(of: .gainDecibels) == -3)
        #expect(kernel.value(of: .cutoffHertz) == 3_000)
    }

    @Test func panicMuteAndBypassSurviveARecovery() throws {
        let kernel = try AudioKernel()
        let output = ManualRenderingOutput(sampleRate: 48_000)
        let playback = LivePlayback(kernel: kernel, output: output)
        playback.play()
        kernel.set(.mute, 1)
        kernel.set(.bypass, 1)
        _ = try output.render(frames: 4_800)
        output.simulateConfigurationChange(toSampleRate: 96_000)
        let after = try output.render(frames: 9_600)
        #expect(after.channels.allSatisfy { $0.allSatisfy { $0 == 0 } })
        #expect(kernel.value(of: .bypass) == 1)
    }

    @Test func recoveryThatCannotRestartSaysSoAndOfflineStillWorks() async throws {
        let kernel = try AudioKernel()
        let output = ManualRenderingOutput(sampleRate: 48_000)
        let playback = LivePlayback(kernel: kernel, output: output)
        playback.play()
        output.failingRates = [22_050]
        output.simulateConfigurationChange(toSampleRate: 22_050)
        #expect(playback.state == .failed(AudioOutputError.noOutput.message))
        #expect(playback.recoveries == 0)
        #expect(playback.lastRecovery?.hasPrefix("Could not rebuild") == true)
        // The declared fallback is unaffected.
        let offline = try await OfflineProcessor.renderLoop(.standard, seconds: 1)
        #expect(offline.audio.peak > 0)
    }

    @Test func anInterruptionStopsAndItsEndResumesOnlyWhenAsked() throws {
        let kernel = try AudioKernel()
        let output = ManualRenderingOutput(sampleRate: 48_000)
        let playback = LivePlayback(kernel: kernel, output: output)
        playback.play()
        output.simulate(.interrupted)
        #expect(playback.state == .interrupted)
        output.simulate(.interruptionEnded(shouldResume: true))
        #expect(playback.state.isPlaying)
        output.simulate(.interrupted)
        output.simulate(.interruptionEnded(shouldResume: false))
        #expect(playback.state == .stopped)
        // A change while stopped does not start playback by itself.
        output.simulateConfigurationChange(toSampleRate: 44_100)
        #expect(playback.state == .stopped)
    }

    @Test func withoutALiveOutputPlayExplainsTheFallback() throws {
        let playback = LivePlayback(kernel: try AudioKernel(), output: nil, unavailableReason: "No live audio here. Use offline processing.")
        #expect(!playback.isAvailable)
        playback.play()
        #expect(playback.state == .failed("No live audio here. Use offline processing."))
    }
}

@MainActor
@Suite struct AudioUnitTests {
    static let preset = try! AudioGraphPreset(
        loop: .noise, gainDecibels: -4.5, filterEnabled: true, cutoffHertz: 700, resonance: 1.8,
        midi: MidiMapping(controller: 1, channel: 10, lowHertz: 200, highHertz: 5_000)
    )

    @Test func theUnitIsFoundThroughTheComponentSystemWithItsParameters() async throws {
        let host = PluginHost()
        try await host.load()
        let unit = try #require(host.workshopUnit)
        #expect(unit.componentDescription.componentType == kAudioUnitType_Effect)
        #expect(unit.componentName?.contains("Workshop Filter") == true)
        let parameters = try #require(unit.parameterTree?.allParameters)
        #expect(parameters.map(\.identifier) == ["gainDecibels", "cutoffHertz", "resonance", "filterEnabled"])
        let cutoff = try #require(parameters.first { $0.identifier == "cutoffHertz" })
        #expect(cutoff.minValue == 20 && cutoff.maxValue == 20_000)
        cutoff.value = 1_234
        #expect(unit.preset.cutoffHertz == 1_234)
        unit.shouldBypassEffect = true
        #expect(unit.shouldBypassEffect)
    }

    @Test func pluginStateRoundTripsAcrossAHostReload() async throws {
        let host = PluginHost()
        try await host.load()
        let first = try #require(host.workshopUnit)
        first.apply(Self.preset)
        // Parameters are 32-bit floats in a unit, so the preset it reports is the one to compare.
        let before = first.preset
        #expect(before.loop == Self.preset.loop && before.midi == Self.preset.midi)
        #expect(abs(before.resonance - Self.preset.resonance) < 1e-6)
        let saved = try host.saveState()
        let firstIdentity = ObjectIdentifier(first)

        try await host.reload()
        let second = try #require(host.workshopUnit)
        #expect(ObjectIdentifier(second) != firstIdentity)
        #expect(host.reloads == 1)
        #expect(second.preset == before)
        let restored = try #require(second.fullState?[WorkshopAudioUnit.stateKey] as? Data)
        #expect(restored == before.canonicalJSON)
        // Saving again gives the same preset bytes a host would write into its project.
        let resaved = try #require(try PropertyListSerialization.propertyList(from: host.saveState(), format: nil) as? [String: Any])
        let original = try #require(try PropertyListSerialization.propertyList(from: saved, format: nil) as? [String: Any])
        #expect(resaved[WorkshopAudioUnit.stateKey] as? Data == original[WorkshopAudioUnit.stateKey] as? Data)
    }

    @Test func aDamagedStateLeavesTheCurrentPresetInPlace() async throws {
        let host = PluginHost()
        try await host.load()
        let unit = try #require(host.workshopUnit)
        unit.apply(Self.preset)
        let before = unit.preset
        var state = try #require(unit.fullState)
        state[WorkshopAudioUnit.stateKey] = Data(#"{"format":"native-lab-audio-preset","schemaVersion":1,"gainDecibels":99}"#.utf8)
        unit.fullState = state
        #expect(unit.preset == before)
        state[WorkshopAudioUnit.stateKey] = "not data"
        unit.fullState = state
        #expect(unit.preset == before)
    }

    @Test func theUnitProcessesTheLoopLikeTheWorkshopDoes() async throws {
        let host = PluginHost()
        try await host.load()
        try #require(host.workshopUnit).apply(Self.preset)
        let hosted = try host.render(loop: Self.preset.loop, seconds: 1)
        let offline = try await OfflineProcessor.renderLoop(Self.preset, seconds: 1)
        for channel in 0..<2 {
            let difference = zip(hosted.channels[channel], offline.audio.channels[channel]).map { abs($0 - $1) }.max() ?? 1
            #expect(difference < 1e-4)
        }
        #expect(try #require(host.workshopUnit).stats.frames == 48_000)
    }

    @Test func reloadingWithoutASavedStateIsRefused() async throws {
        let host = PluginHost()
        await #expect(throws: PluginHostError.noSavedState) { try await host.reload() }
        #expect(throws: PluginHostError.notLoaded) { try host.saveState() }
    }
}
