import AudioWorkshopDSP
import CoreAudioTypes
import Foundation

/// The C kernel, owned from Swift.
///
/// Parameters and counters are atomics in the kernel, so any thread may set a parameter or read
/// the stats at any time, including during a render. `prepare` resets the render state and must
/// not run while a render callback might: the output that owns the kernel stops rendering first.
/// That contract, not a lock, is why the class is `@unchecked Sendable`.
///
/// Render callbacks never touch this object. They capture a `KernelHandle`, a plain pointer, and
/// call straight into C, so the audio thread does no Swift reference counting and no allocation.
/// The kernel must outlive every callback that holds its handle; each output keeps it until its
/// engine has stopped.
public final class AudioKernel: @unchecked Sendable {
    private let pointer: OpaquePointer

    public init() throws(AudioKernelError) {
        guard let pointer = AWKKernelCreate() else { throw .outOfMemory }
        self.pointer = pointer
    }

    deinit { AWKKernelDestroy(pointer) }

    /// The most frames one render call processes; larger calls render silence.
    public static let maximumFrames = Int(AWK_MAX_FRAMES)
    public static let maximumChannels = Int(AWK_MAX_CHANNELS)

    /// The pointer render callbacks capture.
    public var handle: KernelHandle { KernelHandle(pointer: pointer) }

    /// Resets the filters and ramps for a rate and channel count, fades the output in from silence,
    /// rewinds the loop, and clears the counters. Call only while no render callback can run.
    public func prepare(sampleRate: Double, channels: Int) throws(AudioKernelError) {
        guard (1...Self.maximumChannels).contains(channels),
              AWKKernelPrepare(pointer, sampleRate, UInt32(channels)) else {
            throw .unsupportedFormat(sampleRate: sampleRate, channels: channels)
        }
    }

    /// Rewinds the loop to its first sample. Call only while no render callback can run.
    public func rewind() { AWKKernelRewind(pointer) }

    public func set(_ parameter: WorkshopParameter, _ value: Double) {
        AWKKernelSetParameter(pointer, parameter.kernelParameter, Float(value))
    }

    public func value(of parameter: WorkshopParameter) -> Double {
        Double(AWKKernelParameter(pointer, parameter.kernelParameter))
    }

    /// Sets every parameter a preset holds. Bypass and mute are session controls, not preset
    /// content, so loading a preset never unmutes or un-bypasses anything.
    public func apply(_ preset: AudioGraphPreset) {
        set(.loop, preset.loop.kernelValue)
        set(.gainDecibels, preset.gainDecibels)
        set(.filterEnabled, preset.filterEnabled ? 1 : 0)
        set(.cutoffHertz, preset.cutoffHertz)
        set(.resonance, preset.resonance)
    }

    public var stats: RenderStats {
        var raw = AWKStats()
        AWKKernelReadStats(pointer, &raw)
        return RenderStats(raw)
    }
}

/// What a render callback captures: the kernel's address and nothing that is reference counted.
public struct KernelHandle: @unchecked Sendable {
    fileprivate let pointer: OpaquePointer

    /// Renders the original loop through the graph. Realtime-safe: straight into C.
    @inline(__always)
    public func renderLoop(_ frameCount: UInt32, into output: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        AWKKernelRenderLoop(pointer, frameCount, output)
    }

    /// Processes input through the graph; `input` and `output` may be the same list.
    @inline(__always)
    public func process(
        _ frameCount: UInt32,
        from input: UnsafePointer<AudioBufferList>?,
        into output: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        AWKKernelProcess(pointer, frameCount, input, output)
    }
}

public enum AudioKernelError: Error, Hashable, Sendable {
    case outOfMemory
    case unsupportedFormat(sampleRate: Double, channels: Int)

    public var message: String {
        switch self {
        case .outOfMemory:
            "The audio kernel could not be created."
        case .unsupportedFormat(let rate, let channels):
            "The audio kernel cannot run at \(Int(rate)) Hz with \(channels) channels. It supports 8 to 384 kHz and one or two channels."
        }
    }
}

/// Counters from the render callbacks since the last prepare. No audio, only numbers.
public struct RenderStats: Hashable, Sendable {
    public var callbacks: UInt64
    public var frames: UInt64
    public var oversizedCalls: UInt64
    public var clippedSamples: UInt64
    public var nonFiniteSamples: UInt64
    public var lastPeak: Float
    public var maximumPeak: Float
    public var sampleRate: Double
    public var channels: Int
    /// How many times the kernel has been prepared: each start and each recovery adds one.
    public var generation: Int
    public var currentLevel: Float

    public static let zero = RenderStats(AWKStats())

    init(_ raw: AWKStats) {
        callbacks = raw.callbacks
        frames = raw.frames
        oversizedCalls = raw.oversizedCalls
        clippedSamples = raw.clippedSamples
        nonFiniteSamples = raw.nonFiniteSamples
        lastPeak = raw.lastPeak
        maximumPeak = raw.maximumPeak
        sampleRate = raw.sampleRate
        channels = Int(raw.channels)
        generation = Int(raw.generation)
        currentLevel = raw.currentLevel
    }

    /// Seconds of audio rendered since the last prepare.
    public var renderedSeconds: Double { sampleRate > 0 ? Double(frames) / sampleRate : 0 }

    /// A peak level in dBFS, or `nil` for silence.
    public static func decibels(_ level: Float) -> Double? {
        level > 0 ? 20 * log10(Double(level)) : nil
    }
}

extension WorkshopParameter {
    var kernelParameter: AWKParameter {
        switch self {
        case .gainDecibels: AWKParameterGainDecibels
        case .cutoffHertz: AWKParameterCutoffHertz
        case .resonance: AWKParameterResonance
        case .filterEnabled: AWKParameterFilterEnabled
        case .bypass: AWKParameterBypass
        case .mute: AWKParameterMute
        case .loop: AWKParameterLoop
        }
    }
}
