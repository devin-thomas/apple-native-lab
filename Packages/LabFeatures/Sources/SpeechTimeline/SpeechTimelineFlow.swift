import Foundation
import LabDomain

/// The result of transcribing one file: the timeline as far as it got, and why it stopped if it
/// did not finish.
public struct TranscriptionRun: Hashable, Sendable {
    public let timeline: TranscriptTimeline
    /// The audio's duration, when the recognizer read the file.
    public let durationMilliseconds: Int?
    /// `nil` when the whole file was transcribed.
    public let failure: RecognitionFailure?
    /// How many provisional guesses were shown, and how many were dropped as stale.
    public let provisionalShown: Int
    public let staleDropped: Int
    /// Final results refused because they overlapped a different segment, or repeated one.
    public let refusedFinals: Int
}

/// Transcribing a file into a timeline, on device, off the main actor.
///
/// `onChange` receives the timeline after every result, so a view can show provisional text
/// improving as it arrives. When the calling task is cancelled the recognizer stops, provisional
/// text is removed, and the finalized segments are returned. Diagnostics hold counts, durations,
/// and outcome categories only: never the transcript, the language's text, or the file.
public struct SpeechTimelineFlow: Sendable {
    private let recognizer: any SpeechFileRecognizing
    private let diagnostics: DiagnosticsLog?

    public init(recognizer: any SpeechFileRecognizing, diagnostics: DiagnosticsLog? = nil) {
        self.recognizer = recognizer
        self.diagnostics = diagnostics
    }

    public func languages() async -> LanguageSupport {
        await recognizer.languages()
    }

    public func transcribe(
        file: URL,
        language: String,
        onChange: @escaping @Sendable (TranscriptTimeline) async -> Void = { _ in }
    ) async -> TranscriptionRun {
        let clock = ContinuousClock()
        let start = clock.now
        let box = TimelineBox()
        var duration: Int?
        var failure: RecognitionFailure?
        do {
            duration = try await recognizer.transcribe(file: file, language: language) { update in
                let timeline = await box.apply(update)
                await onChange(timeline)
            }
            if Task.isCancelled { failure = .cancelled }
        } catch {
            failure = Task.isCancelled ? .cancelled : error
        }
        let run = await box.finish(duration: duration, failure: failure)
        await onChange(run.timeline)
        let counts: [DiagnosticName: Int] = [
            "segments": run.timeline.segments.count,
            "provisional": run.provisionalShown,
            "stale": run.staleDropped,
            "refused": run.refusedFinals,
        ]
        let outcome: DiagnosticOutcome = switch failure {
        case nil: .succeeded
        case .cancelled?: .cancelled
        case .notCompiled?, .transcriberUnavailable?, .unsupportedLanguage?, .modelNotInstalled?: .rejected
        default: .failed
        }
        let category: DiagnosticCategory? = switch failure {
        case nil: nil
        case .cancelled?: .cancelled
        case .notCompiled?, .transcriberUnavailable?, .unsupportedLanguage?, .modelNotInstalled?: .unavailable
        case .audioTooLong?, .audioTooLarge?: .tooLarge
        case .audioUnreadable?: .malformedData
        default: .other
        }
        diagnostics?.record(
            "speech.transcribe", outcome: outcome, subject: SpeechTimeline.diagnosticSubject,
            category: category, duration: clock.now - start, counts: counts
        )
        return run
    }
}

/// Owns the timeline while results arrive from the recognizer's task.
private actor TimelineBox {
    private var timeline = TranscriptTimeline()
    private var provisionalShown = 0
    private var staleDropped = 0
    private var refusedFinals = 0

    func apply(_ update: RecognizerUpdate) -> TranscriptTimeline {
        switch timeline.apply(update) {
        case .provisionalShown: provisionalShown += 1
        case .staleProvisionalDropped: staleDropped += 1
        case .overlappingFinalRefused, .duplicateFinalIgnored, .segmentLimitReached: refusedFinals += 1
        case .provisionalCleared, .finalized, .emptyFinalIgnored: break
        }
        return timeline
    }

    func finish(duration: Int?, failure: RecognitionFailure?) -> TranscriptionRun {
        // Text never finalized is not kept, whether the run finished or stopped.
        timeline.discardProvisional()
        return TranscriptionRun(
            timeline: timeline, durationMilliseconds: duration, failure: failure,
            provisionalShown: provisionalShown, staleDropped: staleDropped, refusedFinals: refusedFinals
        )
    }
}
