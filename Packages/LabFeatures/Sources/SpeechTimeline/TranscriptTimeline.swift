import Foundation

/// One result from a recognizer, in the media time of the audio it heard.
public enum RecognizerUpdate: Hashable, Sendable {
    /// A guess for audio the recognizer may still revise. It replaces the previous guess.
    case provisional(range: MediaTimeRange, text: String)
    /// Text the recognizer will not revise, with word times when it reported them.
    case final(range: MediaTimeRange, text: String, words: [TimedWord])
}

/// What applying an update did, for tests and diagnostics.
public enum UpdateOutcome: Hashable, Sendable {
    case provisionalShown
    /// The provisional text was empty; the previous guess was cleared.
    case provisionalCleared
    /// A guess for audio already finalized. It was dropped, so no finalized words are shown twice.
    case staleProvisionalDropped
    case finalized(SegmentID)
    /// The same final result delivered again. Nothing changed.
    case duplicateFinalIgnored
    /// A final result that overlaps a different finalized segment. It was refused.
    case overlappingFinalRefused
    /// An empty final result. It closes the provisional text and adds nothing.
    case emptyFinalIgnored
    /// The timeline already holds `SpeechTimelineLimits.segments` segments.
    case segmentLimitReached
}

/// Why the timeline refused a change. Every case leaves the timeline as it was.
public enum TimelineError: Error, Hashable, Sendable {
    case invalidRange
    case mediaTooLong
    case emptyText
    case textTooLong(limit: Int)
    case controlCharacters
    case tooManySegments(limit: Int)
    /// The range overlaps an existing segment.
    case overlaps(SegmentID)
    case unknownSegment(SegmentID)

    public var message: String {
        switch self {
        case .invalidRange: "A segment must end after it starts, at or after 0:00."
        case .mediaTooLong: "The timeline accepts media up to 3 hours long."
        case .emptyText: "A segment needs some text."
        case .textTooLong(let limit): "A segment holds at most \(limit) characters."
        case .controlCharacters: "A segment is one line of text without control characters."
        case .tooManySegments(let limit): "A timeline holds at most \(limit) segments."
        case .overlaps(let id): "That time overlaps segment \(id)."
        case .unknownSegment(let id): "Segment \(id) is not in this timeline."
        }
    }
}

/// The transcript as a timeline: finalized segments in media order, and at most one provisional
/// guess after them.
///
/// Rules the type keeps, whatever order updates arrive in:
/// - Finalized segments never overlap and are sorted by start.
/// - A final result removes the provisional text it covers, so a finalized word is never also
///   shown as provisional. The recognizer then sends a new guess for whatever audio remains.
/// - A guess for audio already finalized is dropped.
/// - A correction changes a segment's text only. Its range, recognized text, and word times stay.
///
/// `revision` rises with every change a person could save, so a save can tell whether the
/// transcript changed since.
public struct TranscriptTimeline: Hashable, Sendable {
    public private(set) var segments: [TranscriptSegment] = []
    public private(set) var provisional: ProvisionalText?
    /// Media time the recognizer has finalized through. Guesses that end at or before it are stale.
    public private(set) var finalizedThroughMilliseconds = 0
    public private(set) var revision = 0
    private var nextID = 1

    public init() {}

    /// A timeline of finalized segments from a caption import or a saved export, in media order.
    /// Refuses overlapping or excess segments rather than dropping any.
    public init(segments incoming: [TranscriptSegment]) throws(TimelineError) {
        guard incoming.count <= SpeechTimelineLimits.segments else {
            throw .tooManySegments(limit: SpeechTimelineLimits.segments)
        }
        let sorted = incoming.sorted { $0.range < $1.range }
        for (earlier, later) in zip(sorted, sorted.dropFirst()) where earlier.range.overlaps(later.range) {
            throw .overlaps(earlier.id)
        }
        segments = sorted
        nextID = (incoming.map(\.id.rawValue).max() ?? 0) + 1
        finalizedThroughMilliseconds = sorted.last?.range.endMilliseconds ?? 0
    }

    public var isEmpty: Bool { segments.isEmpty && provisional == nil }

    /// Every segment's text in media order, one per line. Provisional text is never included.
    public var plainText: String { segments.map(\.text).joined(separator: "\n") }

    public var correctedCount: Int { segments.count(where: \.isCorrected) }

    /// The media time the timeline covers, through its last segment or guess.
    public var endMilliseconds: Int {
        max(segments.last?.range.endMilliseconds ?? 0, provisional?.range.endMilliseconds ?? 0)
    }

    public func segment(_ id: SegmentID) -> TranscriptSegment? {
        segments.first { $0.id == id }
    }

    /// The segment playing at `milliseconds`, or the last one that started before it, for scrubbing.
    public func segment(at milliseconds: Int) -> TranscriptSegment? {
        if let playing = segments.first(where: { $0.range.contains(milliseconds) }) { return playing }
        return segments.last { $0.range.startMilliseconds <= milliseconds }
    }

    // MARK: Recognition

    /// Applies one recognizer result. Recognition never throws: a result the rules refuse is
    /// reported in the outcome and changes nothing.
    @discardableResult
    public mutating func apply(_ update: RecognizerUpdate) -> UpdateOutcome {
        switch update {
        case .provisional(let range, let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if range.endMilliseconds <= finalizedThroughMilliseconds { return .staleProvisionalDropped }
            if trimmed.isEmpty {
                provisional = nil
                return .provisionalCleared
            }
            // A guess is display text only; it is bounded but not refused.
            provisional = ProvisionalText(range: range, text: String(trimmed.prefix(SpeechTimelineLimits.segmentText)))
            return .provisionalShown

        case .final(let range, let text, let words):
            let closesProvisional = provisional.map { $0.range.startMilliseconds < range.endMilliseconds } ?? false
            guard let validText = try? SegmentText.validated(text) else {
                if closesProvisional { provisional = nil }
                finalizedThroughMilliseconds = max(finalizedThroughMilliseconds, range.endMilliseconds)
                return .emptyFinalIgnored
            }
            if let existing = segments.first(where: { $0.range.overlaps(range) }) {
                if existing.range == range && existing.recognized == validText { return .duplicateFinalIgnored }
                return .overlappingFinalRefused
            }
            guard segments.count < SpeechTimelineLimits.segments else { return .segmentLimitReached }
            let kept = words
                .filter { range.startMilliseconds <= $0.range.startMilliseconds && $0.range.endMilliseconds <= range.endMilliseconds }
                .prefix(SpeechTimelineLimits.wordsPerSegment)
            let segment = TranscriptSegment(
                id: takeID(), range: range, text: validText, source: .onDeviceTranscriber, words: Array(kept)
            )
            insert(segment)
            if closesProvisional { provisional = nil }
            finalizedThroughMilliseconds = max(finalizedThroughMilliseconds, range.endMilliseconds)
            return .finalized(segment.id)
        }
    }

    /// Ends recognition: whatever is still provisional was never finalized, so it is removed rather
    /// than kept as if it had been.
    public mutating func discardProvisional() {
        provisional = nil
    }

    // MARK: A person's changes

    /// Replaces a segment's text. The range, the recognized text, and the word times are kept.
    public mutating func correct(_ id: SegmentID, to raw: String) throws(TimelineError) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { throw .unknownSegment(id) }
        let text = try SegmentText.validated(raw)
        guard segments[index].text != text else { return }
        segments[index].text = text
        revision += 1
    }

    /// Returns a segment to the text its source gave.
    public mutating func revert(_ id: SegmentID) throws(TimelineError) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { throw .unknownSegment(id) }
        guard segments[index].isCorrected else { return }
        segments[index].text = segments[index].recognized
        revision += 1
    }

    /// Adds a segment a person typed for a range with no segment yet (the manual fallback).
    @discardableResult
    public mutating func annotate(_ range: MediaTimeRange, text raw: String) throws(TimelineError) -> SegmentID {
        let text = try SegmentText.validated(raw)
        guard segments.count < SpeechTimelineLimits.segments else {
            throw .tooManySegments(limit: SpeechTimelineLimits.segments)
        }
        if let existing = segments.first(where: { $0.range.overlaps(range) }) { throw .overlaps(existing.id) }
        let segment = TranscriptSegment(id: takeID(), range: range, text: text, source: .manual, words: [])
        insert(segment)
        revision += 1
        return segment.id
    }

    // MARK: Internals

    private mutating func takeID() -> SegmentID {
        defer { nextID += 1 }
        return SegmentID(nextID)
    }

    private mutating func insert(_ segment: TranscriptSegment) {
        let index = segments.firstIndex { segment.range < $0.range } ?? segments.endIndex
        segments.insert(segment, at: index)
        revision += 1
    }
}
