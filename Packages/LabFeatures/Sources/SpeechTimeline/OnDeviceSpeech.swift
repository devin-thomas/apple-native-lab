import Foundation
// Guarded by platform as well as `canImport`, the rule LabSupport's probes follow: the lab uses
// Speech on iOS and macOS only, and the tvOS policy marks it unsupported.
#if canImport(Speech) && (os(iOS) || os(macOS))
import AVFoundation
import CoreMedia
import Speech
#endif

/// Transcribes files with `SpeechAnalyzer` and `SpeechTranscriber`, on this device only.
///
/// It checks the transcriber, the language, and the installed model again for every file, and
/// fails with the reason rather than trying any other route. It never downloads a model: that is
/// `OnDeviceModelInstaller`, which only the person's Download action calls. Transcribing a file
/// needs no permission prompt; the analyzer ran in a test process whose speech-recognition
/// authorization was never requested (LAB-013-A notes).
public struct OnDeviceSpeechRecognizer: SpeechFileRecognizing {
    public init() {}

    /// Whether this platform's build includes the on-device transcriber.
    public static var isCompiled: Bool {
        #if canImport(Speech) && (os(iOS) || os(macOS))
        true
        #else
        false
        #endif
    }

    public func languages() async -> LanguageSupport {
        #if canImport(Speech) && (os(iOS) || os(macOS))
        guard SpeechTranscriber.isAvailable else {
            return LanguageSupport(transcriberAvailable: false, supported: [], installed: [])
        }
        let supported = await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
        let installed = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
        return LanguageSupport(transcriberAvailable: true, supported: supported, installed: installed)
        #else
        return .notCompiled
        #endif
    }

    public func transcribe(
        file: URL,
        language: String,
        onUpdate: @escaping @Sendable (RecognizerUpdate) async -> Void
    ) async throws(RecognitionFailure) -> Int {
        #if canImport(Speech) && (os(iOS) || os(macOS))
        let locale = try await Self.installedLocale(for: language)
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw .audioUnreadable }
        guard size <= SpeechTimelineLimits.audioBytes else { throw .audioTooLarge }
        let duration: Int
        do {
            let audio = try AVAudioFile(forReading: file)
            let seconds = Double(audio.length) / audio.processingFormat.sampleRate
            guard seconds.isFinite, seconds > 0 else { throw RecognitionFailure.audioUnreadable }
            duration = Int((seconds * 1_000).rounded())
        } catch let failure as RecognitionFailure {
            throw failure
        } catch {
            throw .audioUnreadable
        }
        guard duration <= SpeechTimelineLimits.mediaDuration else { throw .audioTooLong }

        let transcriber = Self.transcriber(for: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for try await result in transcriber.results {
                            if let update = Self.update(from: result) { await onUpdate(update) }
                        }
                    }
                    group.addTask {
                        // Opened here so the non-Sendable file never crosses a task boundary.
                        let audio = try AVAudioFile(forReading: file)
                        if let end = try await analyzer.analyzeSequence(from: audio) {
                            try await analyzer.finalizeAndFinish(through: end)
                        } else {
                            await analyzer.cancelAndFinishNow()
                        }
                    }
                    try await group.waitForAll()
                }
            } onCancel: {
                Task { await analyzer.cancelAndFinishNow() }
            }
        } catch {
            if Task.isCancelled || error is CancellationError { throw .cancelled }
            throw .engineFailed
        }
        if Task.isCancelled { throw .cancelled }
        return duration
        #else
        throw .notCompiled
        #endif
    }

    #if canImport(Speech) && (os(iOS) || os(macOS))
    /// The transcriber the experiment uses: volatile results for the provisional text, and audio
    /// time ranges on every run of text for word times.
    static func transcriber(for locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
    }

    /// The supported locale equivalent to `language`, if its model is installed. Checked for
    /// every request.
    static func installedLocale(for language: String) async throws(RecognitionFailure) -> Locale {
        guard SpeechTranscriber.isAvailable else { throw .transcriberUnavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            throw .unsupportedLanguage(language)
        }
        let identifier = locale.identifier(.bcp47)
        let installed = await SpeechTranscriber.installedLocales
        guard installed.contains(where: { $0.identifier(.bcp47) == identifier }) else {
            throw .modelNotInstalled(identifier)
        }
        return locale
    }

    /// A lab update for one transcriber result, in whole milliseconds. A result whose time range
    /// is not valid media time is skipped.
    static func update(from result: SpeechTranscriber.Result) -> RecognizerUpdate? {
        guard let range = mediaRange(result.range) else { return nil }
        let text = String(result.text.characters)
        guard result.isFinal else { return .provisional(range: range, text: text) }
        var words: [TimedWord] = []
        for run in result.text.runs {
            guard let timeRange = run.audioTimeRange, let wordRange = mediaRange(timeRange) else { continue }
            let word = String(result.text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
            if !word.isEmpty { words.append(TimedWord(range: wordRange, text: word)) }
        }
        return .final(range: range, text: text, words: words)
    }

    static func mediaRange(_ range: CMTimeRange) -> MediaTimeRange? {
        guard range.isValid, range.start.isNumeric, range.end.isNumeric else { return nil }
        return try? MediaTimeRange(startSeconds: range.start.seconds, endSeconds: range.end.seconds)
    }
    #endif
}

/// Downloads a language's on-device model through `AssetInventory`. The system fetches the asset;
/// the lab starts it only from the person's Download action and shows its progress.
public struct OnDeviceModelInstaller: SpeechModelInstalling {
    public init() {}

    public func install(language: String, progress: @escaping @Sendable (Double) -> Void) async throws(RecognitionFailure) {
        #if canImport(Speech) && (os(iOS) || os(macOS))
        guard SpeechTranscriber.isAvailable else { throw .transcriberUnavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            throw .unsupportedLanguage(language)
        }
        let transcriber = OnDeviceSpeechRecognizer.transcriber(for: locale)
        let request: AssetInstallationRequest?
        do {
            request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
        } catch {
            throw .downloadFailed
        }
        guard let request else {
            progress(1)
            return
        }
        let observer = Task {
            while !Task.isCancelled {
                progress(request.progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { observer.cancel() }
        do {
            try await request.downloadAndInstall()
        } catch {
            if Task.isCancelled { throw .cancelled }
            throw .downloadFailed
        }
        progress(1)
        #else
        throw .notCompiled
        #endif
    }
}
