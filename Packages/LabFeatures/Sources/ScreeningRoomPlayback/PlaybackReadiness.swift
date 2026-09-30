import Foundation
import ScreeningRoom
#if os(iOS) || os(macOS) || os(tvOS)
import AVKit
#endif

/// What this device and build offer a screening, measured when the experiment opens and shown on
/// its page. Each line is a probe or a fixed platform fact, never inferred from a product name.
public struct PlaybackReadiness: Hashable, Sendable {
    public enum Status: String, Hashable, Sendable {
        /// The lab can use it here.
        case available
        /// The platform provides it through its own player or picker; the lab observes it.
        case systemManaged = "system-managed"
        case unavailable
        case notApplicable = "not-applicable"

        public var title: String {
            switch self {
            case .available: "Available"
            case .systemManaged: "From the system player"
            case .unavailable: "Unavailable"
            case .notApplicable: "Not on this platform"
            }
        }
    }

    public struct Line: Hashable, Sendable, Identifiable {
        public var id: String { title }
        public let title: String
        public let status: Status
        public let detail: String
    }

    public let platform: String
    public let lines: [Line]
    public let requestableSurfaces: Set<PlaybackSurface>

    public init(platform: String, lines: [Line], requestableSurfaces: Set<PlaybackSurface>) {
        self.platform = platform
        self.lines = lines
        self.requestableSurfaces = requestableSurfaces
    }

    public func status(of title: String) -> Status? {
        lines.first { $0.title == title }?.status
    }

    public static let playbackTitle = "Local playback"
    public static let pictureInPictureTitle = "Picture in Picture"
    public static let airPlayTitle = "AirPlay"
    public static let audioSessionTitle = "Interruptions and route changes"
    public static let nowPlayingTitle = "Now Playing and remote commands"

    #if os(iOS) || os(macOS) || os(tvOS)
    /// This device, read now.
    @MainActor public static var current: PlaybackReadiness {
        let pip = AVPictureInPictureController.isPictureInPictureSupported()
        #if os(iOS)
        let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        let backgroundAudio = backgroundModes.contains("audio")
        return PlaybackReadiness(
            platform: "iOS",
            lines: [
                Line(title: playbackTitle, status: .available, detail: "The bundled Test Card plays in the page with the system's controls."),
                pictureInPicture(supported: pip && backgroundAudio, reason: pip ? "This build does not declare background audio, which Picture in Picture needs." : "This device does not support Picture in Picture."),
                Line(title: airPlayTitle, status: .systemManaged, detail: "The AirPlay button opens the system's route picker. The lab never chooses a route."),
                Line(title: audioSessionTitle, status: .available, detail: "The playback audio session reports interruptions and lost outputs."),
                Line(title: nowPlayingTitle, status: .available, detail: "Control Center and the Lock Screen show the clip, and their buttons run as commands with receipts."),
            ],
            requestableSurfaces: [.inline, .theater]
        )
        #elseif os(macOS)
        return PlaybackReadiness(
            platform: "macOS",
            lines: [
                Line(title: playbackTitle, status: .available, detail: "The bundled Test Card plays in the window with the system's controls."),
                pictureInPicture(supported: pip, reason: "This Mac does not support Picture in Picture."),
                Line(title: airPlayTitle, status: .systemManaged, detail: "The AirPlay button opens the system's route picker. The lab never chooses a route."),
                Line(title: audioSessionTitle, status: .notApplicable, detail: "The Mac has no audio session to interrupt playback. A lost output is handled by the system."),
                Line(title: nowPlayingTitle, status: .available, detail: "The menu bar's Now Playing and the media keys run as commands with receipts."),
            ],
            requestableSurfaces: [.inline, .theater]
        )
        #else
        return PlaybackReadiness(
            platform: "tvOS",
            lines: [
                Line(title: playbackTitle, status: .available, detail: "The bundled Test Card plays in the system player, driven by the Siri Remote."),
                pictureInPicture(supported: pip, reason: "This Apple TV does not support Picture in Picture."),
                Line(title: airPlayTitle, status: .systemManaged, detail: "Audio routes are chosen in the system player's own controls."),
                Line(title: audioSessionTitle, status: .available, detail: "The playback audio session reports interruptions and lost outputs."),
                Line(title: nowPlayingTitle, status: .systemManaged, detail: "The system player publishes Now Playing and answers the remote itself; the lab sees its changes as signals."),
            ],
            requestableSurfaces: [.inline, .theater]
        )
        #endif
    }

    private static func pictureInPicture(supported: Bool, reason: String) -> Line {
        supported
            ? Line(title: pictureInPictureTitle, status: .systemManaged, detail: "Starts from the player's own Picture in Picture button. The lab never starts it by itself.")
            : Line(title: pictureInPictureTitle, status: .unavailable, detail: reason)
    }
    #endif
}
