import AppKit
import AudioWorkshop
import Foundation
import LabDomain
import SwiftUI
import Testing
@testable import NativeLab

/// LAB-029 in the sandboxed Mac host: the workshop session over the app's own library and a fresh
/// SQLite store per test, never the app's real one. Live output is AVAudioEngine's offline manual
/// rendering, so no test opens an audio device or plays a sound.
@MainActor
@Suite struct AudioWorkshopHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "AudioWorkshopHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func library(_ name: String) async throws -> LabLibrary {
        let directory = folder.appending(path: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        return library
    }

    // MARK: Navigation

    @Test func theWorkshopHasItsOwnDestinationAndCommands() throws {
        #expect(SidebarDestination(storageKey: SidebarDestination.audioWorkshop.storageKey) == .audioWorkshop)
        #expect(SidebarDestination.audioWorkshop.title == "Audio Workshop")
        let items = Self.menuItems(NSApp.mainMenu)
        func shortcut(_ title: String) -> (String, NSEvent.ModifierFlags)? {
            items.first { $0.title == title && !$0.keyEquivalent.isEmpty }
                .map { ($0.keyEquivalent, $0.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask)) }
        }
        #expect(shortcut("Audio Workshop")?.0 == "9")
        let mute = try #require(shortcut("Panic Mute Audio Workshop") ?? shortcut("Unmute Audio Workshop"))
        #expect(mute.0 == "m" && mute.1 == [.command, .shift])
        let bypass = try #require(shortcut("Bypass Audio Workshop") ?? shortcut("Stop Bypassing Audio Workshop"))
        #expect(bypass.0 == "b" && bypass.1 == [.command, .shift])
        #expect(shortcut("Play Audio Workshop") != nil || shortcut("Stop Audio Workshop") != nil)
    }

    // MARK: The safety controls, through the accessibility press action

    @Test func panicMuteAndBypassArePressableAndReachTheKernel() async throws {
        let session = AudioWorkshopSession(output: ManualRenderingOutput(sampleRate: 48_000))
        let hosted = AccessHostedView(Form { WorkshopSafetyControls(session: session) })
        defer { hosted.close() }
        let before = try await hosted.elements()
        let mute = try #require(before.first { $0.role == "AXButton" && $0.label == "Panic Mute" }, "\(before.dump)")
        #expect(mute.hint == "Silences the output within milliseconds.")
        #expect(try await hosted.press("Panic Mute"))
        #expect(session.isMuted)
        #expect(session.kernel?.value(of: .mute) == 1)
        let after = try await hosted.elements(until: { $0.contains { $0.label == "Unmute" } })
        #expect(after.contains { $0.role == "AXButton" && $0.label == "Unmute" }, "\(after.dump)")
        #expect(try await hosted.press("Play"))
        #expect(session.state.isPlaying)
        session.stop()
    }

    // MARK: Live playback and its recovery, in the app process

    @Test func playbackRecoversFromASampleRateChangeKeepingMuteAndSettings() throws {
        let output = ManualRenderingOutput(sampleRate: 44_100)
        let session = AudioWorkshopSession(output: output)
        session.set(.gainDecibels, to: -9)
        session.togglePlayback()
        #expect(session.state.isPlaying)
        _ = try output.render(frames: 4_410)
        session.panicMute()
        output.simulateConfigurationChange(toSampleRate: 48_000)
        guard case .playing(let description) = session.state else {
            Issue.record("expected playing after recovery, got \(session.state)")
            return
        }
        #expect(description.sampleRate == 48_000)
        #expect(session.playback?.recoveries == 1)
        #expect(try output.render(frames: 4_800).channels.allSatisfy { $0.allSatisfy { $0 == 0 } })
        #expect(session.kernel?.value(of: .gainDecibels) == -9)
        #expect(session.graph.first { $0.role == .output }?.detail.contains("48000 Hz") == true)
        session.stop()
    }

    // MARK: The fallback

    @Test func offlineRenderingAndFileProcessingWorkWithoutLiveOutput() async throws {
        let session = AudioWorkshopSession(output: nil)
        session.togglePlayback()
        #expect(session.state == .failed("Live audio is not available here. Render Offline and Process a WAVE File still work."))

        session.renderOffline(seconds: 1)
        await session.finishOffline()
        let rendered = try #require(session.offline)
        #expect(rendered.audio.frameCount == 48_000)

        // An original file: the render just made, written where a person might keep it.
        let file = folder.appending(path: "workshop-loop.wav")
        try rendered.wave.write(to: file)
        session.set(.cutoffHertz, to: 300)
        session.processFile(at: file)
        await session.finishOffline()
        let processed = try #require(session.offline)
        #expect(processed.source == .file(name: "workshop-loop.wav"))
        #expect(processed.digest != rendered.digest)

        try Data("not audio".utf8).write(to: folder.appending(path: "bad.wav"))
        session.processFile(at: folder.appending(path: "bad.wav"))
        await session.finishOffline()
        #expect(session.message == WaveFileRejection.notWave.message)
        #expect(session.offline == processed)
    }

    @Test func onScreenMidiMovesTheCutoffThroughTheSameParser() throws {
        let session = AudioWorkshopSession(output: nil)
        session.sendOnScreen(value: 127)
        #expect(abs(session.preset.cutoffHertz - 12_000) < 0.01)
        #expect(abs((session.kernel?.value(of: .cutoffHertz) ?? 0) - 12_000) < 0.01)
        #expect(session.midiLog.first?.event == .controlChange(channel: 1, controller: 74, value: 127))
        session.setController(21)
        session.receive([.controlChange(channel: 1, controller: 74, value: 0)], source: "Test")
        #expect(abs(session.preset.cutoffHertz - 12_000) < 0.01)
        #expect(session.midiLog.first?.cutoff == nil)
    }

    // MARK: Presets through the operation service

    @Test func aPresetIsSavedWithAReceiptListedAndLoadedBack() async throws {
        let library = try await library("presets")
        let session = AudioWorkshopSession(output: nil)
        session.setLoop(.noise)
        session.set(.gainDecibels, to: -12)
        session.presetName = "Night Noise"
        let record = try #require(await session.savePreset(library))
        #expect(record.receipt.status == .committed)
        #expect(record.receipt.admitted.adapter == .appUI)
        #expect(library.receipts.contains { $0.id == record.id })
        #expect(session.presets.map(\.title) == ["Night Noise"])

        session.resetDemo()
        #expect(session.preset == .standard)
        await session.loadPresets(library)
        let saved = try #require(session.presets.first)
        session.setMuted(true)
        session.load(saved)
        #expect(session.preset.loop == .noise && session.preset.gainDecibels == -12)
        #expect(session.isMuted, "loading a preset never unmutes")
    }

    @Test func anEmptyNameSavesNothing() async throws {
        let library = try await library("empty-name")
        let session = AudioWorkshopSession(output: nil)
        session.presetName = "  "
        #expect(await session.savePreset(library) == nil)
        #expect(session.message == "Give the preset a name.")
        #expect(library.receipts.allSatisfy { if case .createItem = $0.receipt.admitted.operation { false } else { true } })
    }

    // MARK: The plugin form, hosted in the sandboxed app

    @Test func theAudioUnitReloadsWithItsStateInTheApp() async throws {
        let session = AudioWorkshopSession(output: nil)
        session.set(.cutoffHertz, to: 640)
        await session.loadPlugin()
        #expect(session.plugin?.isLoaded == true, "\(session.pluginNote ?? "")")
        await session.reloadPlugin()
        #expect(session.pluginNote?.contains("holds the same preset") == true, "\(session.pluginNote ?? "")")
        #expect(session.plugin?.reloads == 1)
        #expect(abs((session.plugin?.workshopUnit?.preset.cutoffHertz ?? 0) - 640) < 0.01)
    }

    // MARK: Reset

    @Test func resetReturnsTheExperimentToItsFirstRunState() throws {
        let session = AudioWorkshopSession(output: ManualRenderingOutput(sampleRate: 48_000))
        session.togglePlayback()
        session.setBypassed(true)
        session.panicMute()
        session.sendOnScreen(value: 10)
        session.resetDemo()
        #expect(session.state == .stopped)
        #expect(session.preset == .standard)
        #expect(!session.isMuted && !session.isBypassed)
        #expect(session.midiLog.isEmpty && session.offline == nil)
        #expect(session.kernel?.value(of: .bypass) == 0)
    }

    private static func menuItems(_ menu: NSMenu?) -> [NSMenuItem] {
        guard let menu else { return [] }
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.update()
        return menu.items.flatMap { [$0] + menuItems($0.submenu) }
    }
}
