#if os(iOS) || os(macOS)
import AVFAudio
import Foundation

/// The graph's AVAudioEngine form: an `AVAudioSourceNode` whose render block is one call into the
/// C kernel, connected to the engine's main mixer.
enum EngineGraph {
    /// Builds the source node outside any actor, so its render block carries no actor isolation:
    /// a block formed in a main-actor method would be checked for the main actor on the audio
    /// thread. The block captures only the kernel's pointer.
    nonisolated static func sourceNode(format: AVAudioFormat, handle: KernelHandle) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, output in
            handle.renderLoop(frameCount, into: output)
        }
    }

    /// Attaches a source node for the kernel and connects it to the main mixer.
    static func build(_ engine: AVAudioEngine, format: AVAudioFormat, kernel: AudioKernel) -> AVAudioSourceNode {
        let source = sourceNode(format: format, handle: kernel.handle)
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        return source
    }
}

/// Live output through the system's current audio route.
///
/// It only plays: it never opens an input, so it asks for no microphone permission. When the
/// engine reports a configuration change (a new route or sample rate), the engine has already
/// stopped; the output reports it and `LivePlayback` rebuilds the graph for the new format.
@MainActor
public final class EngineOutput: AudioOutput {
    public var events: (@MainActor (AudioOutputEvent) -> Void)?
    private var engine: AVAudioEngine?
    private var observers: [any NSObjectProtocol] = []
    /// The kernel stays referenced until the engine that renders it has stopped.
    private var rendering: AudioKernel?

    public init() {}

    public func start(rendering kernel: AudioKernel) throws(AudioOutputError) -> OutputDescription {
        stop()
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // Playback only, mixed with other apps' audio, so starting the workshop never silences them.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            throw .startFailed(error.localizedDescription)
        }
        #endif
        let engine = AVAudioEngine()
        let hardware = engine.outputNode.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0 else { throw .noOutput }
        let channels = min(Int(hardware.channelCount), AudioKernel.maximumChannels)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: hardware.sampleRate, channels: AVAudioChannelCount(channels)) else {
            throw .noOutput
        }
        do { try kernel.prepare(sampleRate: format.sampleRate, channels: channels) } catch { throw .kernel(error) }
        _ = EngineGraph.build(engine, format: format, kernel: kernel)
        observe(engine)
        engine.prepare()
        do { try engine.start() } catch {
            removeObservers()
            throw .startFailed(error.localizedDescription)
        }
        self.engine = engine
        rendering = kernel
        return OutputDescription(sampleRate: format.sampleRate, channels: channels, route: Self.routeName())
    }

    public func stop() {
        engine?.stop()
        engine = nil
        rendering = nil
        removeObservers()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func observe(_ engine: AVAudioEngine) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.events?(.configurationChanged) }
        })
        #if os(iOS)
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            MainActor.assumeIsolated {
                switch type {
                case .began: self?.events?(.interrupted)
                case .ended: self?.events?(.interruptionEnded(shouldResume: options?.contains(.shouldResume) ?? false))
                default: break
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.events?(.configurationChanged) }
        })
        #endif
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private static func routeName() -> String {
        #if os(iOS)
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "Current output"
        #else
        "System output"
        #endif
    }
}

/// The same engine graph in AVAudioEngine's offline manual rendering mode: the engine renders on
/// request, as fast as the caller asks, and never opens an audio device. Tests use it to run the
/// real engine, source node, and kernel together, and to rebuild the graph at a new sample rate.
///
/// Manual rendering is enabled before anything else touches the engine, so its output node is
/// never connected to hardware.
@MainActor
public final class ManualRenderingOutput: AudioOutput {
    public var events: (@MainActor (AudioOutputEvent) -> Void)?
    public private(set) var sampleRate: Double
    public let channels: Int
    /// The route name reported by `start`, so tests can tell offline from live.
    public static let route = "Offline manual rendering"
    private var engine: AVAudioEngine?
    private var rendering: AudioKernel?
    /// How many times `start` succeeded.
    public private(set) var starts = 0
    /// Rates at which `start` should fail, to exercise recovery giving up.
    public var failingRates: Set<Double> = []

    public init(sampleRate: Double, channels: Int = 2) {
        self.sampleRate = sampleRate
        self.channels = channels
    }

    public func start(rendering kernel: AudioKernel) throws(AudioOutputError) -> OutputDescription {
        stop()
        guard !failingRates.contains(sampleRate) else { throw .noOutput }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels)) else {
            throw .noOutput
        }
        let engine = AVAudioEngine()
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: AVAudioFrameCount(AudioKernel.maximumFrames))
        } catch {
            throw .startFailed(error.localizedDescription)
        }
        do { try kernel.prepare(sampleRate: sampleRate, channels: channels) } catch { throw .kernel(error) }
        _ = EngineGraph.build(engine, format: format, kernel: kernel)
        engine.prepare()
        do { try engine.start() } catch { throw .startFailed(error.localizedDescription) }
        self.engine = engine
        rendering = kernel
        starts += 1
        return OutputDescription(sampleRate: sampleRate, channels: channels, route: Self.route)
    }

    public func stop() {
        engine?.stop()
        engine = nil
        rendering = nil
    }

    /// Renders `frames` frames through the running engine.
    public func render(frames: Int) throws(AudioOutputError) -> PCMAudio {
        guard let engine, let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: AVAudioFrameCount(frames)) else {
            throw .noOutput
        }
        var channelsOut = Array(repeating: [Float](), count: channels)
        var remaining = frames
        while remaining > 0 {
            let count = AVAudioFrameCount(min(remaining, Int(engine.manualRenderingMaximumFrameCount)))
            let status: AVAudioEngineManualRenderingStatus
            do { status = try engine.renderOffline(count, to: buffer) } catch { throw .startFailed(error.localizedDescription) }
            guard status == .success, let data = buffer.floatChannelData else { throw .startFailed("render status \(status.rawValue)") }
            for channel in 0..<channels {
                channelsOut[channel].append(contentsOf: UnsafeBufferPointer(start: data[channel], count: Int(buffer.frameLength)))
            }
            remaining -= Int(buffer.frameLength)
        }
        return PCMAudio(sampleRate: sampleRate, channels: channelsOut)
    }

    /// Acts as the system would when the route's sample rate changes: the engine stops, and the
    /// output reports a configuration change. Only the notification is simulated; the rebuild
    /// that follows runs the real engine at the new rate.
    public func simulateConfigurationChange(toSampleRate rate: Double) {
        engine?.stop()
        sampleRate = rate
        events?(.configurationChanged)
    }

    public func simulate(_ event: AudioOutputEvent) {
        events?(event)
    }
}
#endif
