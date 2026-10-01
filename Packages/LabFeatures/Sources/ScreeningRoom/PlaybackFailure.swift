import Foundation

/// Why a clip cannot play. Each case is shown to the person as it is; none is retried silently,
/// and none falls back to another source for the same content.
public enum PlaybackFailure: Error, Hashable, Sendable, Codable {
    /// The file is not in this build.
    case missingResource(name: String)
    /// The file cannot be opened as a movie at all, such as a truncated file. `code` is the
    /// AVFoundation error code.
    case unreadable(code: Int)
    /// The file opens, but no decoder on this device claims a track's format. `codes` are the
    /// four-character sample-entry codes of the tracks that cannot play.
    case unsupportedCodec(codes: [String])
    /// The file is protected by a content-protection scheme. The lab never decrypts, extracts, or
    /// converts protected media, and it offers no way around this.
    case protectedContent
    /// Playback stopped with an error after the clip opened.
    case playbackFailed(domain: String, code: Int)

    public var title: String {
        switch self {
        case .missingResource: "Clip missing"
        case .unreadable: "Clip can't be opened"
        case .unsupportedCodec: "Format not supported"
        case .protectedContent: "Protected content"
        case .playbackFailed: "Playback stopped"
        }
    }

    public var message: String {
        switch self {
        case .missingResource(let name):
            "\(name) is not in this build. Nothing was played."
        case .unreadable(let code):
            "The file is damaged or is not a movie this device can open (AVFoundation error \(code)). Nothing was played."
        case .unsupportedCodec(let codes):
            "No decoder on this device supports this clip's format (\(codes.joined(separator: ", "))). Nothing was played, and the clip was not converted."
        case .protectedContent:
            "This clip is protected. Native Screening Room plays only unprotected, original clips, and it never removes or works around protection."
        case .playbackFailed(let domain, let code):
            "Playback stopped with an error (\(domain) \(code)). The position was kept."
        }
    }

    /// What the person can still do. The test card is the declared fallback: a small clip every
    /// supported device decodes.
    public var recovery: String {
        switch self {
        case .missingResource, .unreadable, .unsupportedCodec, .protectedContent:
            "Open the Test Card to keep watching."
        case .playbackFailed:
            "Choose Play to try again from the same position, or open the Test Card."
        }
    }

    /// AVFoundation's error domain, named here so this target needs no AVFoundation import.
    public static let avFoundationErrorDomain = "AVFoundationErrorDomain"

    /// Maps an error an asset or player reported to the failure the person sees.
    ///
    /// The codes are AVFoundation's (`AVError.Code`): -11828 file format not recognized, -11829
    /// cannot open, -11831 content is protected, -11833 decoder not found, -11864 format
    /// unsupported. Anything else after the clip opened is a playback failure; anything else
    /// before it opened means it could not be read.
    public static func classify(domain: String, code: Int, whileOpening: Bool) -> PlaybackFailure {
        if domain == avFoundationErrorDomain {
            switch code {
            case -11831: return .protectedContent
            case -11833, -11864: return .unsupportedCodec(codes: [])
            case -11828, -11829: return .unreadable(code: code)
            default: break
            }
        }
        return whileOpening ? .unreadable(code: code) : .playbackFailed(domain: domain, code: code)
    }
}
