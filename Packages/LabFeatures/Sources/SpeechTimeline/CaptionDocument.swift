import Foundation

/// Why a caption file was refused. Nothing is imported from a refused file.
public enum CaptionError: Error, Hashable, Sendable {
    case tooLarge(limit: Int)
    case notUTF8
    /// The first line is not `WEBVTT`.
    case missingHeader
    case malformedTiming(line: Int)
    case invalidCue(line: Int, TimelineError)
    case overlappingCues(line: Int)
    case noCues
    case tooManyCues(limit: Int)

    public var message: String {
        switch self {
        case .tooLarge(let limit): "The caption file is larger than \(limit / 1_024) KB."
        case .notUTF8: "The caption file is not UTF-8 text."
        case .missingHeader: "This is not a WebVTT file: its first line must be WEBVTT."
        case .malformedTiming(let line): "Line \(line) is not a cue timing such as 00:01.000 --> 00:02.500."
        case .invalidCue(let line, let error): "The cue at line \(line) was refused. \(error.message)"
        case .overlappingCues(let line): "The cue at line \(line) overlaps the cue before it. Overlapping captions are not imported."
        case .noCues: "The caption file has no cues."
        case .tooManyCues(let limit): "The caption file has more than \(limit) cues."
        }
    }
}

/// WebVTT captions: the fallback's import and every timeline's plain caption export.
///
/// The reader is deliberately small. It takes the header, cues with an optional identifier, and
/// `NOTE`, `STYLE`, and `REGION` blocks, which it skips. Cue settings are ignored. Markup such as
/// `<v Name>` or `<i>` is removed, so a voice tag never becomes a speaker claim, and the common
/// character references are decoded. Anything it cannot read refuses the whole file.
public enum CaptionDocument {
    public struct Cue: Hashable, Sendable {
        public let range: MediaTimeRange
        public let text: String
        /// The 1-based line of the cue's timing, for messages.
        public let line: Int
    }

    public static func parse(_ data: Data) throws(CaptionError) -> [Cue] {
        guard data.count <= SpeechTimelineLimits.documentBytes else {
            throw .tooLarge(limit: SpeechTimelineLimits.documentBytes)
        }
        guard var text = String(data: data, encoding: .utf8) else { throw .notUTF8 }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let header = lines.first, header == "WEBVTT" || header.hasPrefix("WEBVTT ") || header.hasPrefix("WEBVTT\t") else {
            throw .missingHeader
        }

        var cues: [Cue] = []
        var index = 1
        // Header lines run until the first blank line.
        while index < lines.count, !lines[index].isEmpty { index += 1 }
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }
            let blockStart = index
            var block: [String] = []
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                block.append(lines[index])
                index += 1
            }
            let first = block[0]
            if first == "NOTE" || first.hasPrefix("NOTE ") || first.hasPrefix("NOTE\t") || first == "STYLE" || first == "REGION" {
                continue
            }
            // An identifier line precedes the timing when the first line has no arrow.
            let timingOffset = first.contains("-->") ? 0 : 1
            guard timingOffset < block.count, block[timingOffset].contains("-->") else {
                throw .malformedTiming(line: blockStart + 1 + timingOffset)
            }
            let lineNumber = blockStart + 1 + timingOffset
            let range = try timing(block[timingOffset], line: lineNumber)
            let payload = block[(timingOffset + 1)...].map(plainText).joined(separator: " ")
            let cueText: String
            do {
                cueText = try SegmentText.validated(payload)
            } catch {
                throw .invalidCue(line: lineNumber, error)
            }
            cues.append(Cue(range: range, text: cueText, line: lineNumber))
            guard cues.count <= SpeechTimelineLimits.segments else { throw .tooManyCues(limit: SpeechTimelineLimits.segments) }
        }
        guard !cues.isEmpty else { throw .noCues }
        let sorted = cues.sorted { $0.range < $1.range }
        for (earlier, later) in zip(sorted, sorted.dropFirst()) where earlier.range.overlaps(later.range) {
            throw .overlappingCues(line: later.line)
        }
        return sorted
    }

    /// A timeline of caption segments, each labeled as an import, never as recognition.
    public static func timeline(from cues: [Cue]) throws(TimelineError) -> TranscriptTimeline {
        let segments = cues.enumerated().map { offset, cue in
            TranscriptSegment(id: SegmentID(offset + 1), range: cue.range, text: cue.text, source: .captionImport, words: [])
        }
        return try TranscriptTimeline(segments: segments)
    }

    /// WebVTT for the timeline's finalized segments, with their current text. Provisional text is
    /// never written.
    public static func render(_ timeline: TranscriptTimeline) -> String {
        var output = "WEBVTT\n"
        for segment in timeline.segments {
            output += "\n\(segment.id.rawValue)\n"
            output += "\(MediaClock.webVTT(segment.range.startMilliseconds)) --> \(MediaClock.webVTT(segment.range.endMilliseconds))\n"
            output += escaped(segment.text) + "\n"
        }
        return output
    }

    // MARK: Internals

    private static func timing(_ line: String, line number: Int) throws(CaptionError) -> MediaTimeRange {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { throw .malformedTiming(line: number) }
        let startText = parts[0].trimmingCharacters(in: .whitespaces)
        // Cue settings follow the end time after whitespace.
        let endText = parts[1].trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
        guard let start = milliseconds(startText), let end = milliseconds(endText) else {
            throw .malformedTiming(line: number)
        }
        do {
            return try MediaTimeRange(startMilliseconds: start, endMilliseconds: end)
        } catch {
            throw .invalidCue(line: number, error)
        }
    }

    /// `[hh:]mm:ss.ttt`, with exactly three fraction digits and minutes and seconds below 60.
    static func milliseconds(_ text: String) -> Int? {
        let pieces = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard pieces.count == 2 || pieces.count == 3 else { return nil }
        let secondsPart = pieces[pieces.count - 1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard secondsPart.count == 2, secondsPart[0].count == 2, secondsPart[1].count == 3 else { return nil }
        func number(_ digits: String, maximumLength: Int = 2) -> Int? {
            guard !digits.isEmpty, digits.count <= maximumLength, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
            return Int(digits)
        }
        guard let seconds = number(secondsPart[0]), seconds < 60,
              let fraction = number(secondsPart[1], maximumLength: 3),
              let minutes = number(pieces[pieces.count - 2]), minutes < 60, pieces[pieces.count - 2].count == 2 else { return nil }
        var hours = 0
        if pieces.count == 3 {
            guard let value = number(pieces[0], maximumLength: 4), pieces[0].count >= 2 else { return nil }
            hours = value
        }
        return ((hours * 60 + minutes) * 60 + seconds) * 1_000 + fraction
    }

    /// A payload line without markup, with `&amp;`, `&lt;`, `&gt;`, and `&nbsp;` decoded.
    static func plainText(_ line: String) -> String {
        var output = ""
        var inTag = false
        for character in line {
            switch character {
            case "<": inTag = true
            case ">" where inTag: inTag = false
            default: if !inTag { output.append(character) }
            }
        }
        return output
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
