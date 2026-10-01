import Foundation

/// Why on-device recognition did not run or did not finish. The person chooses what to do next;
/// nothing retries on another route.
public enum RecognitionFailure: Error, Hashable, Sendable {
    /// This platform's build has no on-device transcriber.
    case notCompiled
    /// `SpeechTranscriber.isAvailable` is false on this device.
    case transcriberUnavailable
    /// No on-device model exists for this language here.
    case unsupportedLanguage(String)
    /// The language is supported, but its model is not installed. Downloading it is a separate
    /// action the person takes.
    case modelNotInstalled(String)
    case audioUnreadable
    case audioTooLong
    case audioTooLarge
    case cancelled
    /// The analyzer failed. Only the fact is kept, never the system's error text.
    case engineFailed
    /// A model download did not finish.
    case downloadFailed

    public var message: String {
        switch self {
        case .notCompiled:
            "This build has no on-device transcriber. Import captions or annotate by hand."
        case .transcriberUnavailable:
            "On-device transcription is not available on this device (SpeechTranscriber.isAvailable is false). Import captions or annotate by hand."
        case .unsupportedLanguage(let language):
            "\(LanguageSupport.name(language)) has no on-device transcription model on this device. Import captions or annotate by hand."
        case .modelNotInstalled(let language):
            "The on-device model for \(LanguageSupport.name(language)) is not installed. Download it, or import captions or annotate by hand."
        case .audioUnreadable: "The audio could not be read. Nothing was transcribed."
        case .audioTooLong: "The audio is longer than 3 hours, so it was not transcribed."
        case .audioTooLarge: "The audio file is larger than 50 MB, so it was not transcribed."
        case .cancelled: "Transcription stopped. The segments already finalized are kept."
        case .engineFailed: "The on-device transcriber stopped with an error. The segments already finalized are kept."
        case .downloadFailed: "The model download did not finish. Nothing else changed."
        }
    }
}

/// Which languages this device can transcribe on device, and which models are installed.
public struct LanguageSupport: Hashable, Sendable {
    /// `SpeechTranscriber.isAvailable`, or `nil` when the transcriber is not compiled here.
    public let transcriberAvailable: Bool?
    /// BCP 47 identifiers with an on-device model, installed or not.
    public let supported: [String]
    /// BCP 47 identifiers whose model is installed.
    public let installed: [String]

    public init(transcriberAvailable: Bool?, supported: [String], installed: [String]) {
        self.transcriberAvailable = transcriberAvailable
        self.supported = supported.map(Self.normalized).sorted()
        self.installed = installed.map(Self.normalized).sorted()
    }

    public static let notCompiled = LanguageSupport(transcriberAvailable: nil, supported: [], installed: [])

    public enum State: Hashable, Sendable {
        case installed
        /// Supported, with the model not installed. A download is the person's choice.
        case downloadable
        case unsupported
        /// The transcriber itself is unavailable or not compiled.
        case transcriberUnavailable
    }

    public func state(for language: String) -> State {
        guard transcriberAvailable == true else { return .transcriberUnavailable }
        let identifier = Self.normalized(language)
        if installed.contains(identifier) { return .installed }
        if supported.contains(identifier) { return .downloadable }
        return .unsupported
    }

    /// One sentence naming the language's state, for the interface. Unsupported languages are
    /// named outright rather than hidden.
    public func statement(for language: String) -> String {
        let name = Self.name(language)
        return switch state(for: language) {
        case .installed: "\(name): the on-device model is installed."
        case .downloadable: "\(name): supported on this device. Its model is not installed yet."
        case .unsupported: "\(name): not supported for on-device transcription on this device."
        case .transcriberUnavailable:
            transcriberAvailable == nil
                ? "This build has no on-device transcriber."
                : "On-device transcription is not available on this device."
        }
    }

    /// "English (United States)" for "en-US", in the current locale's language.
    public static func name(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    /// Identifiers compare in BCP 47 form: "en_US" and "en-US" are the same language.
    public static func normalized(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-")
    }
}

/// Recognizes speech in an audio file, on this device.
public protocol SpeechFileRecognizing: Sendable {
    func languages() async -> LanguageSupport
    /// Transcribes the file, calling `onUpdate` with each result in order, and returns the audio's
    /// duration in milliseconds. Stops promptly when the calling task is cancelled.
    func transcribe(
        file: URL,
        language: String,
        onUpdate: @escaping @Sendable (RecognizerUpdate) async -> Void
    ) async throws(RecognitionFailure) -> Int
}

/// Downloads a language's on-device model. Called only from the person's Download action.
public protocol SpeechModelInstalling: Sendable {
    /// Reports progress from 0 to 1. Returns at once when the model is already installed.
    func install(language: String, progress: @escaping @Sendable (Double) -> Void) async throws(RecognitionFailure)
}
