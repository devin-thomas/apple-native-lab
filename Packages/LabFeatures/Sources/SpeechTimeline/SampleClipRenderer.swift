import Foundation
import Synchronization
#if canImport(AVFoundation) && (os(iOS) || os(macOS))
import AVFoundation
#endif

/// Speaks the sample script with this device's speech synthesizer into an audio file, so the
/// experiment has original speech to transcribe without committing audio or opening a microphone.
///
/// The clip is labeled as synthesized wherever it appears. It lives in the experiment's own
/// folder, which Reset Demo removes.
public enum SampleClipRenderer {
    public static var isCompiled: Bool {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        true
        #else
        false
        #endif
    }

    /// The longest a rendering may take before it is abandoned. In an iOS 27.0 simulator, speaking
    /// the four-line script took about 9 seconds, and a first run's whole test took 34.
    public static let timeLimit: Duration = .seconds(60)

    /// Writes the lines, spoken in order, to a CAF file at `url`, replacing any file there, and
    /// returns the clip's duration in milliseconds.
    public static func render(_ lines: [String], language: String, to url: URL) async throws(SampleClipError) -> Int {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard !lines.isEmpty else { throw .noScript }
        guard let voice = AVSpeechSynthesisVoice(language: language) else { throw .noVoice(language) }
        try? FileManager.default.removeItem(at: url)
        let writer = ClipWriter(url: url)
        let utterance = AVSpeechUtterance(string: lines.joined(separator: " "))
        utterance.voice = voice
        let outcome = await writer.write(utterance, limit: timeLimit)
        switch outcome {
        case .success(let frames, let sampleRate):
            guard frames > 0, sampleRate > 0 else {
                try? FileManager.default.removeItem(at: url)
                throw .renderFailed
            }
            return Int((Double(frames) / sampleRate * 1_000).rounded())
        case .failure:
            try? FileManager.default.removeItem(at: url)
            throw .renderFailed
        }
        #else
        throw .notCompiled
        #endif
    }
}

public enum SampleClipError: Error, Hashable, Sendable {
    case notCompiled
    case noScript
    /// This device has no speech synthesizer voice for the language.
    case noVoice(String)
    case renderFailed

    public var message: String {
        switch self {
        case .notCompiled: "This build cannot synthesize the sample clip."
        case .noScript: "The sample script is missing from this build."
        case .noVoice(let language): "This device has no voice for \(LanguageSupport.name(language)), so the sample clip cannot be spoken. Import audio or captions instead."
        case .renderFailed: "The sample clip could not be written. Nothing was kept."
        }
    }
}

#if canImport(AVFoundation) && (os(iOS) || os(macOS))
/// Collects the synthesizer's buffers into one file. The synthesizer calls back on its own queue;
/// the lock keeps the file and the continuation to one writer.
private final class ClipWriter: @unchecked Sendable {
    enum Outcome: Sendable {
        case success(frames: Int64, sampleRate: Double)
        case failure
    }

    private struct State {
        var file: AVAudioFile?
        var frames: Int64 = 0
        var sampleRate: Double = 0
        var failed = false
        var continuation: CheckedContinuation<Outcome, Never>?
        var finished: Outcome?
    }

    private let url: URL
    private let synthesizer = AVSpeechSynthesizer()
    private let state = Mutex(State())

    init(url: URL) { self.url = url }

    func write(_ utterance: AVSpeechUtterance, limit: Duration) async -> Outcome {
        let timer = Task { [weak self] in
            try? await Task.sleep(for: limit)
            if !Task.isCancelled { self?.complete(.failure) }
        }
        defer { timer.cancel() }
        return await withCheckedContinuation { continuation in
            let ready: Outcome? = state.withLock { state in
                if let finished = state.finished { return finished }
                state.continuation = continuation
                return nil
            }
            if let ready {
                continuation.resume(returning: ready)
                return
            }
            synthesizer.write(utterance) { [self] buffer in receive(buffer) }
        }
    }

    private func receive(_ buffer: AVAudioBuffer) {
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 {
            let outcome: Outcome = state.withLock { state in
                state.failed || state.file == nil ? .failure : .success(frames: state.frames, sampleRate: state.sampleRate)
            }
            complete(outcome)
            return
        }
        state.withLock { state in
            guard !state.failed, state.finished == nil else { return }
            do {
                if state.file == nil {
                    state.file = try AVAudioFile(
                        forWriting: url, settings: pcm.format.settings,
                        commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved
                    )
                    state.sampleRate = pcm.format.sampleRate
                }
                try state.file?.write(from: pcm)
                state.frames += Int64(pcm.frameLength)
            } catch {
                state.failed = true
            }
        }
    }

    private func complete(_ outcome: Outcome) {
        let waiting: CheckedContinuation<Outcome, Never>? = state.withLock { state in
            guard state.finished == nil else { return nil }
            state.finished = outcome
            // Closing the file flushes it before the caller reads it.
            state.file = nil
            defer { state.continuation = nil }
            return state.continuation
        }
        waiting?.resume(returning: outcome)
    }
}
#endif
