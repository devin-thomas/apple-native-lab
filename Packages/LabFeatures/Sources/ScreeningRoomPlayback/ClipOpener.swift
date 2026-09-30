#if os(iOS) || os(macOS) || os(tvOS)
import AVFoundation
import Foundation
import ScreeningRoom

/// A clip AVFoundation opened and can play, with its caption options matched to the lab's tracks.
public struct OpenedClip: @unchecked Sendable {
    public let clip: MediaAsset
    public let asset: AVURLAsset
    public let duration: Double
    /// The legible group, when the file has one.
    public let captionGroup: AVMediaSelectionGroup?
    /// The player option for each of the clip's tracks that the file really carries.
    public let captionOptions: [SubtitleTrack.ID: AVMediaSelectionOption]

    /// The lab caption an option stands for, or `nil` for an option the clip does not list.
    public func choice(for option: AVMediaSelectionOption?) -> CaptionChoice? {
        guard let option else { return .off }
        return captionOptions.first { $0.value == option }.map { .track($0.key) }
    }
}

/// Opens a bundled clip and decides, before any player sees it, whether it can play.
///
/// A file whose tracks no decoder claims is still "ready to play" to an `AVPlayerItem`, which then
/// shows nothing. So the opener asks the asset first: is it protected, is it playable, and if not,
/// which track formats are the reason. The answer is a real `PlaybackFailure` the page shows.
@MainActor
public enum ClipOpener {
    public static func open(_ clip: MediaAsset, from url: URL? = nil) async -> Result<OpenedClip, PlaybackFailure> {
        guard let url = url ?? BundledClips.url(for: clip) else { return .failure(.missingResource(name: clip.fileName)) }
        let asset = AVURLAsset(url: url)
        do {
            let (playable, protected, duration) = try await asset.load(.isPlayable, .hasProtectedContent, .duration)
            if protected { return .failure(.protectedContent) }
            guard playable else { return .failure(.unsupportedCodec(codes: try await unplayableCodes(in: asset))) }
            let seconds = duration.seconds
            guard seconds.isFinite, seconds > 0 else { return .failure(.unreadable(code: 0)) }
            let group = try await asset.loadMediaSelectionGroup(for: .legible)
            return .success(OpenedClip(
                clip: clip,
                asset: asset,
                duration: seconds,
                captionGroup: group,
                captionOptions: group.map { CaptionMatcher.match($0.options, to: clip) } ?? [:]
            ))
        } catch {
            let error = error as NSError
            return .failure(PlaybackFailure.classify(domain: error.domain, code: error.code, whileOpening: true))
        }
    }

    /// The four-character sample-entry codes of every track the device cannot play.
    static func unplayableCodes(in asset: AVURLAsset) async throws -> [String] {
        var codes: [String] = []
        for track in try await asset.load(.tracks) {
            let (playable, descriptions) = try await track.load(.isPlayable, .formatDescriptions)
            guard !playable else { continue }
            codes += descriptions.map { FourCharacterCode(CMFormatDescriptionGetMediaSubType($0)).text }
        }
        return codes
    }
}

/// A four-character code as text, such as `avc1`.
struct FourCharacterCode {
    let value: FourCharCode

    init(_ value: FourCharCode) { self.value = value }

    var text: String {
        let bytes = [24, 16, 8, 0].map { UInt8((value >> $0) & 0xFF) }
        let printable = bytes.allSatisfy { (0x20...0x7E).contains($0) }
        return printable ? String(decoding: bytes, as: UTF8.self) : String(format: "0x%08X", value)
    }
}

/// Matches a player's caption options to the clip's declared tracks by language and SDH, the two
/// facts that do not change with the system language. Options that show only forced subtitles
/// are left out: they are what plays when captions are "off", not a choice.
public enum CaptionMatcher {
    /// What the matcher reads from one option.
    public struct Facts: Hashable, Sendable {
        public let languageTag: String?
        public let isSDH: Bool
        public let isForcedOnly: Bool

        public init(languageTag: String?, isSDH: Bool, isForcedOnly: Bool) {
            self.languageTag = languageTag
            self.isSDH = isSDH
            self.isForcedOnly = isForcedOnly
        }
    }

    /// The track these facts describe, or `nil` when the clip lists no such track.
    public static func trackID(for facts: Facts, in clip: MediaAsset) -> SubtitleTrack.ID? {
        guard !facts.isForcedOnly, let tag = facts.languageTag?.lowercased() else { return nil }
        let language = tag.split(separator: "-").first.map(String.init) ?? tag
        return clip.captions.first { track in
            track.languageTag.lowercased() == language && track.isForDeafAndHardOfHearing == facts.isSDH
        }?.id
    }

    static func facts(_ option: AVMediaSelectionOption) -> Facts {
        Facts(
            languageTag: option.extendedLanguageTag ?? option.locale?.identifier,
            isSDH: option.hasMediaCharacteristic(.transcribesSpokenDialogForAccessibility)
                && option.hasMediaCharacteristic(.describesMusicAndSoundForAccessibility),
            isForcedOnly: option.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
        )
    }

    static func match(_ options: [AVMediaSelectionOption], to clip: MediaAsset) -> [SubtitleTrack.ID: AVMediaSelectionOption] {
        var matched: [SubtitleTrack.ID: AVMediaSelectionOption] = [:]
        for option in options {
            if let id = trackID(for: facts(option), in: clip), matched[id] == nil { matched[id] = option }
        }
        return matched
    }
}
#endif
