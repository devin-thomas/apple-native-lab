import Foundation
#if canImport(Speech) && (os(iOS) || os(macOS))
import AVFoundation
import Speech
#endif

/// Live capture: the microphone through `AVAudioEngine`, recognized on device by `SpeechAnalyzer`
/// as it is heard.
///
/// `RecordingSession` starts it only after `RecordingGate` allowed the person's Record action. It
/// keeps no audio: buffers go to the analyzer and nowhere else, so a recording's export names the
/// recording but has no file to hash. When the audio route changes (a device connected or
/// disconnected, or the engine's configuration changed) or the system interrupts, it stops the
/// microphone, finalizes what it heard, and reports why, so the session pauses instead of ending
/// silently.
///
/// Never run on hardware by LAB-013-A: the lab's source builds declare no microphone purpose
/// string, so `RecordingGate` falls back before this is reached. See the ticket's record.
public actor OnDeviceSpeechCapture: SpeechCapturing {
    #if canImport(Speech) && (os(iOS) || os(macOS))
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var inputs: AsyncStream<AnalyzerInput>.Continuation?
    private var events: AsyncStream<CaptureEvent>.Continuation?
    private var results: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []
    #endif

    public init() {}

    public func start(language: String) async throws(RecognitionFailure) -> AsyncStream<CaptureEvent> {
        #if canImport(Speech) && (os(iOS) || os(macOS))
        guard engine == nil else { throw .engineFailed }
        let locale = try await OnDeviceSpeechRecognizer.installedLocale(for: language)
        let transcriber = OnDeviceSpeechRecognizer.transcriber(for: locale)
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw .engineFailed
        }
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw .engineFailed
        }
        #endif
        let engine = AVAudioEngine()
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat) else {
            throw .audioUnreadable
        }
        let (inputStream, inputs) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let (eventStream, events) = AsyncStream.makeStream(of: CaptureEvent.self)
        let tap = CaptureTap(converter: converter, format: analyzerFormat, inputs: inputs)
        engine.inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { buffer, _ in
            tap.convert(buffer)
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        results = Task {
            do {
                for try await result in transcriber.results {
                    if let update = OnDeviceSpeechRecognizer.update(from: result) { events.yield(.update(update)) }
                }
            } catch {
                // The session learns of the failure from `failed`, sent by whoever stops capture.
            }
        }
        do {
            try await analyzer.start(inputSequence: inputStream)
            engine.prepare()
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            inputs.finish()
            await analyzer.cancelAndFinishNow()
            results?.cancel()
            results = nil
            throw .engineFailed
        }
        self.engine = engine
        self.analyzer = analyzer
        self.inputs = inputs
        self.events = events
        observeRoute(of: engine)
        return eventStream
        #else
        throw .notCompiled
        #endif
    }

    public func stop() async {
        await finish(with: .ended)
    }

    // MARK: Internals

    /// Stops the microphone, finalizes what the analyzer heard, sends the results, then `event`.
    private func finish(with event: CaptureEvent) async {
        #if canImport(Speech) && (os(iOS) || os(macOS))
        guard let engine else { return }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        inputs?.finish()
        inputs = nil
        var closing = event
        if let analyzer {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                await analyzer.cancelAndFinishNow()
                if case .ended = event { closing = .failed(.engineFailed) }
            }
        }
        analyzer = nil
        await results?.value
        results = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        events?.yield(closing)
        events?.finish()
        events = nil
        #endif
    }

    #if canImport(Speech) && (os(iOS) || os(macOS))
    private func observeRoute(of engine: AVAudioEngine) {
        let center = NotificationCenter.default
        #if os(iOS)
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            let sentence: String? = switch reason {
            case .oldDeviceUnavailable: "the audio device in use was disconnected"
            case .newDeviceAvailable: "a new audio device was connected"
            case .routeConfigurationChange: "the audio route's configuration changed"
            default: nil
            }
            guard let sentence, let self else { return }
            Task { await self.finish(with: .routeChanged(reason: sentence)) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began, let self else { return }
            Task { await self.finish(with: .interrupted) }
        })
        #else
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            guard let self else { return }
            Task { await self.finish(with: .routeChanged(reason: "the audio device configuration changed")) }
        })
        #endif
    }
    #endif
}

#if canImport(Speech) && (os(iOS) || os(macOS))
/// Converts microphone buffers to the analyzer's format on the audio thread. The converter is used
/// only from the tap, one buffer at a time.
private final class CaptureTap: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let format: AVAudioFormat
    private let inputs: AsyncStream<AnalyzerInput>.Continuation

    init(converter: AVAudioConverter, format: AVAudioFormat, inputs: AsyncStream<AnalyzerInput>.Continuation) {
        self.converter = converter
        self.format = format
        self.inputs = inputs
    }

    func convert(_ buffer: AVAudioPCMBuffer) {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        nonisolated(unsafe) var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return }
        inputs.yield(AnalyzerInput(buffer: output))
    }
}
#endif
