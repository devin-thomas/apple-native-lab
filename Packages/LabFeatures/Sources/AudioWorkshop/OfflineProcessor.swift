import AudioWorkshopDSP
import CoreAudioTypes
import Foundation
import LabDomain

/// What an offline render or file processing produced.
public struct OfflineResult: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        case loop(LoopFixture)
        case file(name: String)
    }

    public let source: Source
    public let preset: AudioGraphPreset
    public let bypassed: Bool
    public let audio: PCMAudio
    public let stats: RenderStats
    /// The processed audio as a 32-bit float WAVE file, and its SHA-256.
    public let wave: Data
    public let digest: ContentDigest

    init(source: Source, preset: AudioGraphPreset, bypassed: Bool, audio: PCMAudio, stats: RenderStats) {
        self.source = source
        self.preset = preset
        self.bypassed = bypassed
        self.audio = audio
        self.stats = stats
        wave = WaveFile.encode(audio)
        digest = ContentDigest.sha256(wave)
    }

    public var summary: String {
        let what = switch source {
        case .loop(let loop): "The \(loop.title) loop"
        case .file(let name): name
        }
        let peak = RenderStats.decibels(audio.peak).map { String(format: "%.1f dBFS", $0) } ?? "silence"
        return "\(what), \(String(format: "%.1f", audio.seconds)) s at \(Int(audio.sampleRate)) Hz, peak \(peak)."
    }

    public var suggestedFileName: String {
        switch source {
        case .loop(let loop): "Audio Workshop \(loop.title).wav"
        case .file(let name): "\((name as NSString).deletingPathExtension) processed.wav"
        }
    }
}

public enum OfflineError: Error, Hashable, Sendable {
    case cancelled
    case invalidLength
    case kernel(AudioKernelError)
    case unreadable(WaveFileRejection)
    /// The chosen file could not be opened or read at all.
    case fileUnavailable

    public var message: String {
        switch self {
        case .cancelled: "Cancelled. Nothing was rendered."
        case .invalidLength: "Offline renders are 0.1 to 30 seconds long."
        case .kernel(let error): error.message
        case .unreadable(let rejection): rejection.message
        case .fileUnavailable: "The file could not be read. Nothing was processed."
        }
    }
}

/// The declared fallback: the same kernel and graph as live playback, run faster than real time
/// into memory, with no audio device. It renders the original loop or processes a WAVE file.
///
/// Work runs off the caller's actor in blocks of `blockFrames`, checking for cancellation before
/// each block, so a cancelled render stops within one block and returns nothing.
public enum OfflineProcessor {
    public static let blockFrames = 512
    public static let seconds: ClosedRange<Double> = 0.1...30

    @concurrent
    public static func renderLoop(
        _ preset: AudioGraphPreset,
        bypassed: Bool = false,
        seconds: Double = 4,
        sampleRate: Double = AudioWorkshop.offlineSampleRate
    ) async throws(OfflineError) -> OfflineResult {
        guard Self.seconds.contains(seconds) else { throw .invalidLength }
        let frames = Int((seconds * sampleRate).rounded())
        let (audio, stats) = try run(preset: preset, bypassed: bypassed, sampleRate: sampleRate, channels: 2, frames: frames, input: nil)
        return OfflineResult(source: .loop(preset.loop), preset: preset, bypassed: bypassed, audio: audio, stats: stats)
    }

    @concurrent
    public static func process(
        _ input: PCMAudio,
        named name: String,
        preset: AudioGraphPreset,
        bypassed: Bool = false
    ) async throws(OfflineError) -> OfflineResult {
        guard input.frameCount > 0, (1...AudioKernel.maximumChannels).contains(input.channels.count) else {
            throw .unreadable(input.frameCount == 0 ? .empty : .unsupportedChannels(input.channels.count))
        }
        let (audio, stats) = try run(preset: preset, bypassed: bypassed, sampleRate: input.sampleRate,
                                     channels: input.channels.count, frames: input.frameCount, input: input)
        return OfflineResult(source: .file(name: name), preset: preset, bypassed: bypassed, audio: audio, stats: stats)
    }

    /// Reads a WAVE file's bytes and processes them.
    @concurrent
    public static func process(
        waveData data: Data,
        named name: String,
        preset: AudioGraphPreset,
        bypassed: Bool = false
    ) async throws(OfflineError) -> OfflineResult {
        let input: PCMAudio
        do { input = try WaveFile.decode(data) } catch { throw .unreadable(error) }
        return try await process(input, named: name, preset: preset, bypassed: bypassed)
    }

    private static func run(
        preset: AudioGraphPreset,
        bypassed: Bool,
        sampleRate: Double,
        channels: Int,
        frames: Int,
        input: PCMAudio?
    ) throws(OfflineError) -> (PCMAudio, RenderStats) {
        let kernel: AudioKernel
        do {
            kernel = try AudioKernel()
            kernel.apply(preset)
            kernel.set(.bypass, bypassed ? 1 : 0)
            try kernel.prepare(sampleRate: sampleRate, channels: channels)
        } catch {
            throw .kernel(error)
        }

        let block = blockFrames
        let outMemory = UnsafeMutablePointer<Float>.allocate(capacity: block * channels)
        let inMemory = UnsafeMutablePointer<Float>.allocate(capacity: block * channels)
        let outList = AudioBufferList.allocate(maximumBuffers: channels)
        let inList = AudioBufferList.allocate(maximumBuffers: channels)
        defer {
            outMemory.deallocate()
            inMemory.deallocate()
            free(outList.unsafeMutablePointer)
            free(inList.unsafeMutablePointer)
        }

        var result = Array(repeating: [Float](repeating: 0, count: frames), count: channels)
        var done = 0
        while done < frames {
            if Task.isCancelled { throw .cancelled }
            let count = min(block, frames - done)
            for channel in 0..<channels {
                let bytes = UInt32(count * MemoryLayout<Float>.size)
                outList[channel] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: outMemory + channel * block)
                inList[channel] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: inMemory + channel * block)
                if let input {
                    input.channels[channel].withUnsafeBufferPointer { source in
                        (inMemory + channel * block).update(from: source.baseAddress! + done, count: count)
                    }
                }
            }
            let handle = kernel.handle
            if input == nil {
                _ = handle.renderLoop(UInt32(count), into: outList.unsafeMutablePointer)
            } else {
                _ = handle.process(UInt32(count), from: inList.unsafePointer, into: outList.unsafeMutablePointer)
            }
            for channel in 0..<channels {
                result[channel].withUnsafeMutableBufferPointer { target in
                    (target.baseAddress! + done).update(from: outMemory + channel * block, count: count)
                }
            }
            done += count
        }
        return (PCMAudio(sampleRate: sampleRate, channels: result), kernel.stats)
    }
}
