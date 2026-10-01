#if os(iOS) || os(macOS)
import AudioToolbox
import AVFAudio
import Foundation
import Observation

public enum PluginHostError: Error, Hashable, Sendable {
    case notLoaded
    case instantiationFailed(String)
    case noSavedState
    case unreadableState
    case renderFailed(String)

    public var message: String {
        switch self {
        case .notLoaded: "Load the plugin first."
        case .instantiationFailed(let reason): "The plugin did not load: \(reason)"
        case .noSavedState: "Save the plugin's state before reloading it."
        case .unreadableState: "The saved plugin state could not be read. The plugin keeps its current settings."
        case .renderFailed(let reason): "The plugin did not render: \(reason)"
        }
    }
}

/// A small host for the workshop's audio unit, the way a music app hosts one: it instantiates the
/// unit through the audio component system, saves `fullState` as property-list data the way a
/// project file would, tears the unit down, instantiates a fresh one, and restores the state.
///
/// It hosts the unit in-process, registered with `WorkshopAudioUnit.registerInProcess()`. The
/// AUv3 extension serves the same class out of process to other hosts; that path needs a host app
/// and is not exercised here.
@MainActor
@Observable
public final class PluginHost {
    public private(set) var unit: AVAudioUnit?
    /// The last saved state, as the property-list bytes a host would write into its project.
    public private(set) var savedState: Data?
    public private(set) var reloads = 0

    public init() {}

    public var isLoaded: Bool { unit != nil }

    public var workshopUnit: WorkshopAudioUnit? { unit?.auAudioUnit as? WorkshopAudioUnit }

    public func load() async throws(PluginHostError) {
        WorkshopAudioUnit.registerInProcess()
        do {
            unit = try await AVAudioUnit.instantiate(with: WorkshopAudioUnit.componentDescription, options: [])
        } catch {
            throw .instantiationFailed(error.localizedDescription)
        }
    }

    public func unload() {
        unit = nil
    }

    /// Saves the unit's `fullState` as binary property-list data.
    @discardableResult
    public func saveState() throws(PluginHostError) -> Data {
        guard let unit else { throw .notLoaded }
        guard let state = unit.auAudioUnit.fullState,
              let data = try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0) else {
            throw .unreadableState
        }
        savedState = data
        return data
    }

    /// Tears the unit down, loads a fresh instance, and restores the saved state into it.
    public func reload() async throws(PluginHostError) {
        guard let savedState else { throw .noSavedState }
        guard let state = try? PropertyListSerialization.propertyList(from: savedState, format: nil) as? [String: Any] else {
            throw .unreadableState
        }
        unit = nil
        try await load()
        unit?.auAudioUnit.fullState = state
        reloads += 1
    }

    /// Plays the original loop, unprocessed, through the unit in an offline manual-rendering
    /// engine and returns what came out. No audio device is opened.
    public func render(loop: LoopFixture, seconds: Double, sampleRate: Double = AudioWorkshop.offlineSampleRate) throws(PluginHostError) -> PCMAudio {
        guard let unit else { throw .notLoaded }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw .renderFailed("no format")
        }
        let engine = AVAudioEngine()
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1_024)
        } catch {
            throw .renderFailed(error.localizedDescription)
        }
        // The source is a second kernel held in bypass, so it passes the raw loop through.
        let source: AudioKernel
        do {
            source = try AudioKernel()
            source.set(.loop, loop.kernelValue)
            source.set(.bypass, 1)
            try source.prepare(sampleRate: sampleRate, channels: 2)
        } catch {
            throw .renderFailed(error.message)
        }
        let node = EngineGraph.sourceNode(format: format, handle: source.handle)
        engine.attach(node)
        engine.attach(unit)
        engine.connect(node, to: unit, format: format)
        engine.connect(unit, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do { try engine.start() } catch { throw .renderFailed(error.localizedDescription) }
        defer {
            engine.stop()
            engine.detach(unit)
            // The source kernel stays alive until the engine that renders it has stopped.
            withExtendedLifetime(source) {}
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1_024) else {
            throw .renderFailed("no buffer")
        }
        var channels: [[Float]] = [[], []]
        var remaining = Int((seconds * sampleRate).rounded())
        while remaining > 0 {
            let count = AVAudioFrameCount(min(remaining, 1_024))
            let status: AVAudioEngineManualRenderingStatus
            do { status = try engine.renderOffline(count, to: buffer) } catch { throw .renderFailed(error.localizedDescription) }
            guard status == .success, let data = buffer.floatChannelData else { throw .renderFailed("status \(status.rawValue)") }
            for channel in 0..<2 {
                channels[channel].append(contentsOf: UnsafeBufferPointer(start: data[channel], count: Int(buffer.frameLength)))
            }
            remaining -= Int(buffer.frameLength)
        }
        return PCMAudio(sampleRate: sampleRate, channels: channels)
    }
}
#endif
