import Foundation
import LabDomain

/// The original audio a timeline's times refer to, identified by content rather than by path.
///
/// An export names the audio this way so its times can be matched to the same bytes later, without
/// carrying the audio, a file path, or a name a person chose.
public struct AudioReference: Hashable, Sendable, Codable {
    public enum Origin: String, Hashable, Sendable, Codable {
        /// The experiment's sample script, spoken by this device's speech synthesizer.
        case synthesizedSample = "synthesized-sample"
        /// An audio file the person chose.
        case importedFile = "imported-file"
        /// Captured from the microphone after the person pressed Record.
        case recording
        /// No audio: a caption import or annotations without a clip.
        case none
    }

    public let origin: Origin
    /// SHA-256 of the audio file's bytes, lowercase hex, or `nil` when there is no file.
    public let sha256: String?
    public let durationMilliseconds: Int?
    /// The file's type, such as "caf" or "m4a". Never its name.
    public let fileType: String?

    public init(origin: Origin, sha256: String?, durationMilliseconds: Int?, fileType: String?) {
        self.origin = origin
        self.sha256 = sha256
        self.durationMilliseconds = durationMilliseconds
        self.fileType = fileType
    }

    public static let none = AudioReference(origin: .none, sha256: nil, durationMilliseconds: nil, fileType: nil)

    /// A reference for a file's bytes. Reads the file once to hash it.
    public static func file(at url: URL, origin: Origin, durationMilliseconds: Int?) throws -> AudioReference {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = ContentDigest.sha256(data).hex
        let type = url.pathExtension.lowercased()
        return AudioReference(
            origin: origin, sha256: digest, durationMilliseconds: durationMilliseconds,
            fileType: type.isEmpty ? nil : String(type.prefix(8))
        )
    }
}

/// The exported timeline: `native-lab-speech-timeline`, schema version 1.
///
/// It holds the audio reference, the locale the text is in, and every finalized segment with its
/// media range, current text, recognized text, source, and word times. Provisional text is never
/// part of it. Reading one back applies the same checks as every other input, and an unknown field
/// refuses the document.
public struct TimelineExport: Hashable, Sendable, Codable {
    public static let format = "native-lab-speech-timeline"
    public static let schemaVersion = 1

    public let format: String
    public let schemaVersion: Int
    public let audio: AudioReference
    /// BCP 47, such as "en-US". The language the transcript is in, not a guess about a speaker.
    public let language: String
    public let segments: [TranscriptSegment]

    public init(timeline: TranscriptTimeline, audio: AudioReference, language: String) {
        format = Self.format
        schemaVersion = Self.schemaVersion
        self.audio = audio
        self.language = language
        segments = timeline.segments
    }

    /// Canonical JSON: sorted keys, no extra whitespace, so the same timeline always gives the
    /// same bytes.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Reads an export back into a timeline, refusing anything this build did not write.
    public static func decode(_ data: Data) throws(ExportError) -> (export: TimelineExport, timeline: TranscriptTimeline) {
        guard data.count <= SpeechTimelineLimits.documentBytes else { throw .tooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw .malformed }
        guard object["format"] as? String == format else { throw .notATimeline }
        guard object["schemaVersion"] as? Int == schemaVersion else { throw .unsupportedVersion }
        let known: Set<String> = ["format", "schemaVersion", "audio", "language", "segments"]
        guard Set(object.keys).isSubset(of: known) else { throw .unknownFields }
        let export: TimelineExport
        do {
            export = try JSONDecoder().decode(TimelineExport.self, from: data)
        } catch {
            throw .malformed
        }
        do {
            return (export, try TranscriptTimeline(segments: export.segments))
        } catch {
            throw .invalidTimeline(error)
        }
    }
}

public enum ExportError: Error, Hashable, Sendable {
    case tooLarge
    case malformed
    case notATimeline
    case unsupportedVersion
    case unknownFields
    case invalidTimeline(TimelineError)

    public var message: String {
        switch self {
        case .tooLarge: "The file is larger than \(SpeechTimelineLimits.documentBytes / 1_024) KB."
        case .malformed: "The file is not a readable timeline."
        case .notATimeline: "The file is not a Native Lab speech timeline."
        case .unsupportedVersion: "The timeline was written by a newer version of the lab."
        case .unknownFields: "The timeline has fields this version does not know, so it was not read."
        case .invalidTimeline(let error): "The timeline was refused. \(error.message)"
        }
    }
}
