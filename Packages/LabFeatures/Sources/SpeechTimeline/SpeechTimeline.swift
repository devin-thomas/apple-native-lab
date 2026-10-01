import LabDomain
import LabSupport

/// LAB-013 Speech Timeline: speech becomes a transcript whose segments keep the media time they
/// came from, so a person can scrub the audio and the text together.
///
/// Recognition runs on this device only, through `SpeechAnalyzer` and `SpeechTranscriber`. There
/// is no server route and no other route when the on-device transcriber is unavailable: the person
/// chooses the fallback, importing a caption file or annotating by hand. The recognizer's
/// provisional text is kept apart from its finalized segments, and a correction changes a
/// segment's text, never its time.
///
/// Recording asks for the microphone only after the person presses Record, through the lab's one
/// permission path (`PermissionStager`). Saving a transcript is a domain operation, committed as
/// the app UI with a receipt. A model download starts only from its own button.
public enum SpeechTimeline {
    public static let experimentID = "LAB-013"

    /// The explicit step that may ask for the microphone. Nothing else in the experiment does.
    public static let recordAction = FeatureAction(
        capability: .microphone, experimentID: experimentID, title: "Record speech"
    )

    static let diagnosticSubject = DiagnosticSubject("LAB-013")
}

/// The experiment's own bounds, checked before any text or time reaches the timeline.
public enum SpeechTimelineLimits {
    /// The longest media the timeline accepts, in milliseconds (three hours).
    public static let mediaDuration = 3 * 60 * 60 * 1_000
    /// Characters in one segment's text.
    public static let segmentText = 500
    /// Finalized segments in one timeline.
    public static let segments = 2_000
    /// Word timings kept per segment.
    public static let wordsPerSegment = 200
    /// Bytes of a caption file or an exported timeline read back.
    public static let documentBytes = 256 * 1_024
    /// Bytes of an audio file offered to the transcriber (50 MB).
    public static let audioBytes = 50 * 1_024 * 1_024
}
