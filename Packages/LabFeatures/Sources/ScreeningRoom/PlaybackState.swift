import Foundation
import LabDomain

/// Where the clip is showing.
///
/// A person can ask for `inline` and `theater` from the lab's own buttons. The other three are
/// entered through the platform's own controls, the full-screen and Picture in Picture buttons
/// and the AirPlay route picker, and the session learns about them as signals. The lab never
/// starts Picture in Picture or AirPlay by itself.
public enum PlaybackSurface: String, Hashable, Sendable, Codable, CaseIterable {
    /// In the experiment's page.
    case inline
    /// The same player on its own: a full-screen cover on iPhone and iPad, a large sheet on the
    /// Mac, and the native full-screen player on Apple TV.
    case theater
    /// The platform player's own full-screen presentation.
    case fullScreen = "full-screen"
    case pictureInPicture = "picture-in-picture"
    /// Playing on another device through AirPlay or an external route.
    case external

    public var title: String {
        switch self {
        case .inline: "In the page"
        case .theater: "Theater"
        case .fullScreen: "Full screen"
        case .pictureInPicture: "Picture in Picture"
        case .external: "AirPlay"
        }
    }

    /// The surface as a place in a sentence, such as "Moved the clip to the theater."
    public var place: String {
        switch self {
        case .inline: "the page"
        case .theater: "the theater"
        case .fullScreen: "full screen"
        case .pictureInPicture: "Picture in Picture"
        case .external: "AirPlay"
        }
    }

    /// Whether the lab's own controls may ask for it. The rest belong to system controls.
    public var isRequestable: Bool {
        switch self {
        case .inline, .theater: true
        case .fullScreen, .pictureInPicture, .external: false
        }
    }
}

/// The last route change the session saw, for display and for the rule that a lost route pauses.
public enum RouteChange: String, Hashable, Sendable, Codable {
    /// The device that was playing went away, such as headphones unplugged. Playback pauses and
    /// does not resume by itself.
    case oldDeviceUnavailable = "old-device-unavailable"
    /// A new output appeared. Playback continues as it was.
    case newDeviceAvailable = "new-device-available"
    /// Any other reason, such as a category change. Playback continues as it was.
    case other

    public var title: String {
        switch self {
        case .oldDeviceUnavailable: "The audio output went away, so playback paused."
        case .newDeviceAvailable: "A new audio output is available."
        case .other: "The audio route changed."
        }
    }
}

/// What a watcher sees: the clip, where it is, whether it is playing, the captions, the surface,
/// and anything that interrupted it.
///
/// `revision` rises on every change a command or signal makes, except a position sample: those
/// arrive several times a second, replace each other, and carry no decision. A remote controller
/// that sends its last-seen revision gets a conflict instead of overwriting a newer change.
public struct PlaybackState: Hashable, Sendable, Codable {
    public var clip: MediaAssetID?
    /// Seconds from the start of the clip.
    public var position: Double
    /// Seconds, once the clip has opened.
    public var duration: Double?
    /// Whether the person wants the clip playing. An interruption or a lost route clears it.
    public var isPlaying: Bool
    public var caption: CaptionChoice
    public var surface: PlaybackSurface
    /// Set while the system has taken the audio away. `wasPlaying` says whether to resume if the
    /// system later recommends it.
    public var interruption: Interruption?
    public var lastRouteChange: RouteChange?
    public var failure: PlaybackFailure?
    public var revision: Revision

    public struct Interruption: Hashable, Sendable, Codable {
        public let wasPlaying: Bool

        public init(wasPlaying: Bool) { self.wasPlaying = wasPlaying }
    }

    public init(
        clip: MediaAssetID? = nil,
        position: Double = 0,
        duration: Double? = nil,
        isPlaying: Bool = false,
        caption: CaptionChoice = .off,
        surface: PlaybackSurface = .inline,
        interruption: Interruption? = nil,
        lastRouteChange: RouteChange? = nil,
        failure: PlaybackFailure? = nil,
        revision: Revision = .initial
    ) {
        self.clip = clip
        self.position = position
        self.duration = duration
        self.isPlaying = isPlaying
        self.caption = caption
        self.surface = surface
        self.interruption = interruption
        self.lastRouteChange = lastRouteChange
        self.failure = failure
        self.revision = revision
    }

    /// Nothing open, at the start, captions off, in the page.
    public static let empty = PlaybackState()

    /// The same state apart from its revision, for comparing what a change did.
    var content: PlaybackState {
        var copy = self
        copy.revision = .initial
        return copy
    }

    /// A one-line description, such as "Paused at 0:04 of 0:10 · English (SDH) · In the page".
    public var summary: String {
        let asset = clip.flatMap(ScreeningClips.clip)
        guard clip != nil else { return "No clip open" }
        if let failure { return "\(asset?.title ?? "Clip"): \(failure.title)" }
        let play = interruption != nil ? "Interrupted" : isPlaying ? "Playing" : "Paused"
        let time = duration.map { "\(Self.clock(position)) of \(Self.clock($0))" } ?? Self.clock(position)
        return "\(play) at \(time) · \(caption.title(in: asset)) · \(surface.title)"
    }

    /// Minutes and seconds, such as "0:04".
    public static func clock(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.isFinite ? seconds.rounded(.down) : 0))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }
}
