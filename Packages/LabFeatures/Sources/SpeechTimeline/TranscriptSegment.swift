import Foundation

/// A segment's number within its timeline, assigned in order as segments are added. Stable for the
/// life of the timeline and kept by an export.
public struct SegmentID: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public let rawValue: Int

    public init(_ rawValue: Int) { self.rawValue = rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: SegmentID, rhs: SegmentID) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String { "#\(rawValue)" }
}

/// Where a segment's time and first text came from. Shown beside every segment, so a caption
/// import or a hand annotation is never read as recognition.
public enum SegmentSource: String, Hashable, Sendable, Codable, CaseIterable {
    /// `SpeechTranscriber` on this device.
    case onDeviceTranscriber = "on-device-transcriber"
    /// A caption file the person imported (the fallback).
    case captionImport = "caption-import"
    /// A range and text the person entered (the fallback).
    case manual

    public var label: String {
        switch self {
        case .onDeviceTranscriber: "On-device transcription"
        case .captionImport: "Imported caption (not recognition)"
        case .manual: "Annotated by hand (not recognition)"
        }
    }
}

/// One word's media time inside a finalized segment, as the recognizer reported it.
public struct TimedWord: Hashable, Sendable, Codable {
    public let range: MediaTimeRange
    public let text: String

    public init(range: MediaTimeRange, text: String) {
        self.range = range
        self.text = text
    }
}

/// A finalized span of the transcript.
///
/// Its range and its recognized text are fixed when it is made. A correction replaces `text` only,
/// so the segment still points at the same moment of the original media, and `recognized` keeps
/// what the source first said.
public struct TranscriptSegment: Hashable, Sendable, Codable, Identifiable {
    public let id: SegmentID
    public let range: MediaTimeRange
    /// The current text: the recognized text, or a person's correction of it.
    public internal(set) var text: String
    /// The text as the source first gave it. Never changed.
    public let recognized: String
    public let source: SegmentSource
    /// Word times from the recognizer, in order. Empty for captions and annotations. A correction
    /// keeps them, because they describe the audio, not the corrected text.
    public let words: [TimedWord]

    init(id: SegmentID, range: MediaTimeRange, text: String, source: SegmentSource, words: [TimedWord]) {
        self.id = id
        self.range = range
        self.text = text
        self.recognized = text
        self.source = source
        self.words = words
    }

    public var isCorrected: Bool { text != recognized }

    private enum CodingKeys: String, CodingKey {
        case id, range, text, recognized, source, words
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SegmentID.self, forKey: .id)
        range = try container.decode(MediaTimeRange.self, forKey: .range)
        source = try container.decode(SegmentSource.self, forKey: .source)
        words = try container.decodeIfPresent([TimedWord].self, forKey: .words) ?? []
        do {
            text = try SegmentText.validated(try container.decode(String.self, forKey: .text))
            recognized = try SegmentText.validated(try container.decode(String.self, forKey: .recognized))
        } catch let error as TimelineError {
            throw DecodingError.dataCorruptedError(forKey: .text, in: container, debugDescription: error.message)
        }
        guard words.count <= SpeechTimelineLimits.wordsPerSegment,
              words.allSatisfy({ range.startMilliseconds <= $0.range.startMilliseconds && $0.range.endMilliseconds <= range.endMilliseconds }) else {
            throw DecodingError.dataCorruptedError(forKey: .words, in: container, debugDescription: "Word times must lie inside the segment.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(range, forKey: .range)
        try container.encode(text, forKey: .text)
        try container.encode(recognized, forKey: .recognized)
        try container.encode(source, forKey: .source)
        if !words.isEmpty { try container.encode(words, forKey: .words) }
    }
}

/// The recognizer's current guess for audio it has not finalized. Shown apart from the segments and
/// never saved, exported, or corrected.
public struct ProvisionalText: Hashable, Sendable {
    public let range: MediaTimeRange
    public let text: String

    public init(range: MediaTimeRange, text: String) {
        self.range = range
        self.text = text
    }
}

/// Text checks shared by recognition, captions, annotations, and corrections.
enum SegmentText {
    /// Trims surrounding whitespace, then requires 1 to `segmentText` characters and no control
    /// characters, line breaks included: a segment is one line.
    static func validated(_ raw: String) throws(TimelineError) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .emptyText }
        guard text.count <= SpeechTimelineLimits.segmentText else { throw .textTooLong(limit: SpeechTimelineLimits.segmentText) }
        guard !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw .controlCharacters
        }
        return text
    }
}
