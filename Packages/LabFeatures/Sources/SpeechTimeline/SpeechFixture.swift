import Foundation

/// The experiment's original fixtures, in `Fixtures/speech/`. Both are text written for this
/// project; the hosts bundle them as resources.
///
/// No audio is committed. The sample clip is spoken from the script by this device's own speech
/// synthesizer (`SampleClipRenderer`) into the experiment's folder, because the system voices'
/// license does not cover redistributing their output.
public enum SpeechFixture: String, CaseIterable, Hashable, Sendable {
    /// Four short sentences, one per line, in English (United States).
    case sampleScript = "speech-sample-script"
    /// WebVTT captions for the script, timed by hand: the fallback's import.
    case sampleCaptions = "speech-sample-captions"

    /// The fixtures' language, BCP 47.
    public static let language = "en-US"

    public var fileExtension: String {
        switch self {
        case .sampleScript: "txt"
        case .sampleCaptions: "vtt"
        }
    }

    public var fileName: String { "\(rawValue).\(fileExtension)" }

    public func url(in bundle: Bundle) -> URL? {
        bundle.url(forResource: rawValue, withExtension: fileExtension)
    }

    /// The script's sentences, one per line, from a bundle or a file.
    public static func script(at url: URL) throws(SpeechFixtureError) -> [String] {
        guard let data = try? Data(contentsOf: url), data.count <= 4_096,
              let text = String(data: data, encoding: .utf8) else { throw .unreadable }
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw .unreadable }
        return lines
    }

    /// The caption fixture as a timeline of caption segments.
    public static func captions(at url: URL) throws(SpeechFixtureError) -> TranscriptTimeline {
        guard let data = try? Data(contentsOf: url) else { throw .unreadable }
        do {
            return try CaptionDocument.timeline(from: CaptionDocument.parse(data))
        } catch let error as CaptionError {
            throw .captions(error)
        } catch {
            throw .unreadable
        }
    }
}

public enum SpeechFixtureError: Error, Hashable, Sendable {
    case unreadable
    case captions(CaptionError)

    public var message: String {
        switch self {
        case .unreadable: "The sample is missing from this build."
        case .captions(let error): error.message
        }
    }
}
