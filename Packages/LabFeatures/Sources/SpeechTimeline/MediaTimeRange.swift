/// A span of the original media, in whole milliseconds from its start.
///
/// Every range is checked when it is made: it starts at or after zero, ends after it starts, and
/// ends within `SpeechTimelineLimits.mediaDuration`. The recognizer reports `CMTime` values; the
/// adapter rounds them to milliseconds once, so the same audio always gives the same ranges.
public struct MediaTimeRange: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let startMilliseconds: Int
    public let endMilliseconds: Int

    public init(startMilliseconds: Int, endMilliseconds: Int) throws(TimelineError) {
        guard startMilliseconds >= 0, endMilliseconds > startMilliseconds else {
            throw .invalidRange
        }
        guard endMilliseconds <= SpeechTimelineLimits.mediaDuration else { throw .mediaTooLong }
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
    }

    /// A range from seconds, as the recognizer and caption files give them.
    public init(startSeconds: Double, endSeconds: Double) throws(TimelineError) {
        guard startSeconds.isFinite, endSeconds.isFinite else { throw .invalidRange }
        let limit = Double(SpeechTimelineLimits.mediaDuration) / 1_000
        guard startSeconds <= limit, endSeconds <= limit else { throw .mediaTooLong }
        try self.init(
            startMilliseconds: Int((startSeconds * 1_000).rounded()),
            endMilliseconds: Int((endSeconds * 1_000).rounded())
        )
    }

    public var durationMilliseconds: Int { endMilliseconds - startMilliseconds }

    /// Whether `milliseconds` falls in the range. The end is exclusive, so adjacent ranges never
    /// both contain a point.
    public func contains(_ milliseconds: Int) -> Bool {
        milliseconds >= startMilliseconds && milliseconds < endMilliseconds
    }

    public func overlaps(_ other: MediaTimeRange) -> Bool {
        startMilliseconds < other.endMilliseconds && other.startMilliseconds < endMilliseconds
    }

    /// The same span moved later by `offset` milliseconds, such as a recording resumed after a
    /// route change continuing the one timeline.
    public func shifted(by offset: Int) throws(TimelineError) -> MediaTimeRange {
        try MediaTimeRange(startMilliseconds: startMilliseconds + offset, endMilliseconds: endMilliseconds + offset)
    }

    public static func < (lhs: MediaTimeRange, rhs: MediaTimeRange) -> Bool {
        (lhs.startMilliseconds, lhs.endMilliseconds) < (rhs.startMilliseconds, rhs.endMilliseconds)
    }

    public var description: String {
        "\(MediaClock.format(startMilliseconds))–\(MediaClock.format(endMilliseconds))"
    }
}

extension MediaTimeRange: Codable {
    private enum CodingKeys: String, CodingKey {
        case startMilliseconds = "startMs"
        case endMilliseconds = "endMs"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let start = try container.decode(Int.self, forKey: .startMilliseconds)
        let end = try container.decode(Int.self, forKey: .endMilliseconds)
        do {
            try self.init(startMilliseconds: start, endMilliseconds: end)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .endMilliseconds, in: container, debugDescription: "Not a valid media range."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startMilliseconds, forKey: .startMilliseconds)
        try container.encode(endMilliseconds, forKey: .endMilliseconds)
    }
}

/// Media times written for people and for caption files.
public enum MediaClock {
    /// "1:05.2" style: minutes, seconds, and tenths, with hours when there are any.
    public static func format(_ milliseconds: Int) -> String {
        let clamped = max(0, milliseconds)
        let tenths = (clamped / 100) % 10
        let seconds = (clamped / 1_000) % 60
        let minutes = (clamped / 60_000) % 60
        let hours = clamped / 3_600_000
        let secondsText = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        if hours > 0 {
            let minutesText = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours):\(minutesText):\(secondsText).\(tenths)"
        }
        return "\(minutes):\(secondsText).\(tenths)"
    }

    /// A spoken form for assistive technologies, such as "1 minute 5 seconds".
    public static func spoken(_ milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds) / 1_000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let secondsText = seconds == 1 ? "1 second" : "\(seconds) seconds"
        guard minutes > 0 else { return secondsText }
        return (minutes == 1 ? "1 minute " : "\(minutes) minutes ") + secondsText
    }

    /// WebVTT's "hh:mm:ss.ttt".
    public static func webVTT(_ milliseconds: Int) -> String {
        let clamped = max(0, milliseconds)
        func pad(_ value: Int, _ width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(pad(clamped / 3_600_000, 2)):\(pad((clamped / 60_000) % 60, 2)):\(pad((clamped / 1_000) % 60, 2)).\(pad(clamped % 1_000, 3))"
    }
}
