import LabSupport

/// What a live capture reports, in the media time of its own run (each run starts at zero).
public enum CaptureEvent: Hashable, Sendable {
    case update(RecognizerUpdate)
    /// The audio route changed, such as headphones or a microphone being disconnected, and capture
    /// stopped. The capture finalized what it had heard before reporting this.
    case routeChanged(reason: String)
    /// The system interrupted capture, such as for a call.
    case interrupted
    /// Capture ended after `stop()`.
    case ended
    case failed(RecognitionFailure)
}

/// Captures from the microphone and recognizes on device. Only `RecordingSession` starts one, and
/// only after `RecordingGate` allowed it for the person's Record action.
public protocol SpeechCapturing: Sendable {
    /// Starts capture. Events arrive in order; the stream finishes after `ended`, `routeChanged`,
    /// `interrupted`, or `failed`.
    func start(language: String) async throws(RecognitionFailure) -> AsyncStream<CaptureEvent>
    /// Stops capture and releases the microphone. Final results for audio already heard arrive
    /// before `ended`.
    func stop() async
}

/// Whether the person's Record press may open the microphone.
public enum RecordingDecision: Hashable, Sendable {
    /// Start capture. When `systemAsks` is true, the system shows its own prompt as capture starts.
    case record(systemAsks: Bool)
    /// Do not open the microphone. `reason` names why, in the lab's words; `fallback` is the
    /// documented alternate route.
    case fallback(reason: String, fallback: FallbackRoute)
}

/// Staging the microphone for the Record action, through the lab's one permission path.
///
/// `PermissionStager` never prompts from launch, probes, or the readiness screen, and this gate
/// calls it only from `decide()`, which only the Record action calls. A denied, restricted, or
/// undeclared permission falls back without asking again.
public struct RecordingGate: Sendable {
    private let stager: PermissionStager

    public init(stager: PermissionStager) {
        self.stager = stager
    }

    public func decide() async -> RecordingDecision {
        let outcome = await stager.request(for: SpeechTimeline.recordAction)
        switch outcome {
        case .notRequired, .granted:
            return .record(systemAsks: false)
        case .systemAsksOnUse:
            return .record(systemAsks: true)
        case .fallback(let route, let reason):
            return .fallback(reason: Self.sentence(reason), fallback: route)
        }
    }

    static func sentence(_ reason: FallbackReason) -> String {
        switch reason {
        case .denied: "Microphone access was declined earlier. The lab does not ask again."
        case .restricted: "Microphone access is restricted on this device."
        case .declinedNow: "Microphone access was declined."
        case .missingPurposeString(let key): "This build does not declare \(key), so the lab does not ask for the microphone."
        case .missingEntitlement(let key): "This build is not signed with \(key), so the sandbox would refuse the microphone."
        case .unknownStatus: "The microphone permission could not be read, so the lab does not ask."
        }
    }
}

/// A recording's lifecycle over one timeline, kept apart from any view.
///
/// Each capture run starts at media time zero; the session moves its results after the timeline's
/// end, so a recording resumed after a route change or an interruption continues the same
/// timeline. A route change or an interruption pauses the session and says so: every finalized
/// segment is kept, and whatever was still provisional is removed and counted rather than kept as
/// if it were final.
public struct RecordingSession: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case idle
        case recording
        case paused(PauseReason)
        /// The last run failed. The segments are kept.
        case failed(RecognitionFailure)
    }

    public enum PauseReason: Hashable, Sendable {
        case stoppedByPerson
        case routeChanged(String)
        case interrupted
    }

    public private(set) var state: State = .idle
    /// Runs started in this session.
    public private(set) var runs = 0
    /// Where the current run's media time zero falls on the timeline.
    public private(set) var offsetMilliseconds = 0
    /// Provisional text removed because capture stopped before finalizing it, across all runs.
    public private(set) var discardedProvisionals = 0

    public init() {}

    public var isRecording: Bool { state == .recording }

    /// Starts a run after the gate allowed it. The run's time begins at the timeline's end.
    public mutating func beginRun(on timeline: TranscriptTimeline) {
        runs += 1
        offsetMilliseconds = max(timeline.finalizedThroughMilliseconds, timeline.endMilliseconds)
        state = .recording
    }

    /// Applies one event to the timeline and moves the session's state.
    @discardableResult
    public mutating func handle(_ event: CaptureEvent, timeline: inout TranscriptTimeline) -> UpdateOutcome? {
        switch event {
        case .update(let update):
            guard state == .recording, let shifted = shift(update) else { return nil }
            return timeline.apply(shifted)
        case .routeChanged(let reason):
            close(&timeline)
            state = .paused(.routeChanged(reason))
        case .interrupted:
            close(&timeline)
            state = .paused(.interrupted)
        case .ended:
            close(&timeline)
            if state == .recording { state = .paused(.stoppedByPerson) }
        case .failed(let failure):
            close(&timeline)
            state = .failed(failure)
        }
        return nil
    }

    /// One sentence for the state, naming what was kept.
    public func summary(segments: Int) -> String {
        let kept = segments == 1 ? "1 segment kept" : "\(segments) segments kept"
        let dropped = discardedProvisionals == 0 ? "" : " Unfinished text was removed \(discardedProvisionals == 1 ? "once" : "\(discardedProvisionals) times") because it was never finalized."
        return switch state {
        case .idle: "Not recording. The microphone opens only when you press Record."
        case .recording: "Recording on this device. \(kept)."
        case .paused(.stoppedByPerson): "Recording stopped. \(kept).\(dropped)"
        case .paused(.routeChanged(let reason)): "Recording paused because the audio route changed: \(reason). \(kept).\(dropped) Resume continues the same timeline."
        case .paused(.interrupted): "Recording paused by a system interruption. \(kept).\(dropped) Resume continues the same timeline."
        case .failed(let failure): "\(failure.message) \(kept)."
        }
    }

    private mutating func close(_ timeline: inout TranscriptTimeline) {
        if timeline.provisional != nil {
            discardedProvisionals += 1
            timeline.discardProvisional()
        }
    }

    private func shift(_ update: RecognizerUpdate) -> RecognizerUpdate? {
        switch update {
        case .provisional(let range, let text):
            guard let moved = try? range.shifted(by: offsetMilliseconds) else { return nil }
            return .provisional(range: moved, text: text)
        case .final(let range, let text, let words):
            guard let moved = try? range.shifted(by: offsetMilliseconds) else { return nil }
            let movedWords = words.compactMap { word in
                (try? word.range.shifted(by: offsetMilliseconds)).map { TimedWord(range: $0, text: word.text) }
            }
            return .final(range: moved, text: text, words: movedWords)
        }
    }
}
