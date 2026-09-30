import Foundation

/// A clip's stable name. It is the bundled resource's base name, never a URL or a path, so a
/// command or a resume point can name a clip without carrying where it lives.
public struct MediaAssetID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public init(_ rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

/// One clip the experiment can open, and what it is expected to do.
public struct MediaAsset: Hashable, Sendable, Identifiable {
    /// What the clip is for. The two failing clips are part of the experiment: they prove that an
    /// unplayable file shows a real error instead of a black player.
    public enum Expectation: Hashable, Sendable {
        case plays
        case fails(PlaybackFailure)
    }

    public let id: MediaAssetID
    public let title: String
    public let resourceName: String
    public let fileExtension: String
    /// The length the fixture was written with, or `nil` when the file cannot say.
    public let duration: Double?
    /// The subtitle tracks the file carries, in the order a picker lists them.
    public let captions: [SubtitleTrack]
    public let expectation: Expectation

    public init(
        id: MediaAssetID,
        title: String,
        resourceName: String,
        fileExtension: String,
        duration: Double?,
        captions: [SubtitleTrack],
        expectation: Expectation
    ) {
        self.id = id
        self.title = title
        self.resourceName = resourceName
        self.fileExtension = fileExtension
        self.duration = duration
        self.captions = captions
        self.expectation = expectation
    }

    public var fileName: String { "\(resourceName).\(fileExtension)" }

    public func caption(_ id: SubtitleTrack.ID) -> SubtitleTrack? {
        captions.first { $0.id == id }
    }
}

/// One subtitle or caption track in a clip.
///
/// The ID is the lab's own, derived from the track's language and whether it is for the deaf and
/// hard of hearing. The playback adapter matches a player's options to it by those two facts,
/// never by a display name, which the system localizes.
public struct SubtitleTrack: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    /// A BCP 47 tag, such as `en`.
    public let languageTag: String
    public let title: String
    /// Captions that also describe sound, not only dialog (SDH).
    public let isForDeafAndHardOfHearing: Bool

    public init(id: String, languageTag: String, title: String, isForDeafAndHardOfHearing: Bool) {
        self.id = id
        self.languageTag = languageTag
        self.title = title
        self.isForDeafAndHardOfHearing = isForDeafAndHardOfHearing
    }
}

/// Which captions show: none, or one track.
public enum CaptionChoice: Hashable, Sendable, Codable {
    case off
    case track(SubtitleTrack.ID)

    public var trackID: SubtitleTrack.ID? {
        if case .track(let id) = self { id } else { nil }
    }

    /// A short label, such as "Captions off" or "English (SDH)".
    public func title(in clip: MediaAsset?) -> String {
        switch self {
        case .off: "Captions off"
        case .track(let id): clip?.caption(id)?.title ?? id
        }
    }
}
