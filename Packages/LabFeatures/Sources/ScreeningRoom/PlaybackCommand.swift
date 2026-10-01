import Foundation
import LabDomain

/// A decision someone makes about playback: the lab's buttons, the platform's remote commands, or
/// a controller on another device. Every command is authorized, recorded under its request ID,
/// and answered with a receipt.
public enum PlaybackCommand: Hashable, Sendable, Codable {
    /// Opens a clip from the start, captions off.
    case open(MediaAssetID)
    case play
    case pause
    /// Moves to a time in seconds. A time past either end is clamped to the clip.
    case seek(to: Double)
    /// Moves by a number of seconds, backwards when negative.
    case skip(by: Double)
    case selectCaption(CaptionChoice)
    /// Moves the clip to a surface the lab's own controls may ask for (`PlaybackSurface.isRequestable`).
    case present(PlaybackSurface)
    /// Returns to the start with captions off and discards the saved resume point: the
    /// experiment's own Reset Demo. Destructive, so only the app's own controls and intents may
    /// ask (ADR-011); a controller on another device cannot.
    case forgetResumePoint

    public var kind: Kind {
        switch self {
        case .open: .open
        case .play: .play
        case .pause: .pause
        case .seek: .seek
        case .skip: .skip
        case .selectCaption: .selectCaption
        case .present: .present
        case .forgetResumePoint: .forgetResumePoint
        }
    }

    /// A command without its payload, for permissions and display.
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        case open, play, pause, seek, skip
        case selectCaption = "select-caption"
        case present
        case forgetResumePoint = "forget-resume-point"

        public var isDestructive: Bool { self == .forgetResumePoint }

        /// The permission a command needs, in the domain's own terms: a destructive command needs
        /// `commitDestructive`, which no model tool, share extension, or peer can hold.
        public var permission: Permission { isDestructive ? .commitDestructive : .commit }
    }
}

/// Something the system or the player reports. A signal is not a decision and needs no grant,
/// but only the host that owns the player can deliver one: the cross-device link carries
/// commands and snapshots, never signals.
public enum PlaybackSignal: Hashable, Sendable {
    /// The clip opened, with its real length.
    case opened(duration: Double)
    case failed(PlaybackFailure)
    /// A position sample from the player. Replaces the last one; never raises the revision.
    case position(Double)
    /// The player started or stopped on its own controls, or reached the end.
    case playing(Bool)
    /// A caption was chosen in the platform player's own menu.
    case caption(CaptionChoice)
    /// The platform moved the clip, such as its full-screen or Picture in Picture button, or an
    /// AirPlay route that started or ended.
    case surface(PlaybackSurface)
    /// The system took the audio away, such as for a call or an alarm.
    case interruptionBegan
    /// The system gave the audio back. `shouldResume` is its recommendation.
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(RouteChange)
}

/// Where a command came from, for the receipt line. Display only: the adapter kind and grants
/// in the request's `ActorScope` decide what it may do.
public enum CommandSource: String, Hashable, Sendable, Codable, CaseIterable {
    /// The lab's own buttons, menus, or keyboard shortcuts.
    case controls
    /// The platform's Now Playing remote commands: Control Center, the Lock Screen, headphones,
    /// a keyboard's media keys, or the Siri Remote.
    case remoteCommand = "remote-command"
    /// A controller on another device, or the in-process stand-in for one.
    case companion
    /// Opening the experiment again at the saved resume point.
    case resume

    public var title: String {
        switch self {
        case .controls: "Screening Room controls"
        case .remoteCommand: "Now Playing remote"
        case .companion: "Companion remote"
        case .resume: "Resume point"
        }
    }
}

/// One command as it reaches the session.
///
/// Like `OperationRequest`, it is not `Codable`: the actor is assigned by whoever receives the
/// command, never read from a payload.
public struct PlaybackRequest: Hashable, Sendable {
    public let id: RequestID
    public let command: PlaybackCommand
    public let actor: ActorScope
    public let source: CommandSource
    /// The revision the sender last saw, or `nil` to act on whatever is current, as the local
    /// controls do. A remote controller sends what it saw, so a stale command conflicts.
    public let expected: Revision?

    public init(
        id: RequestID = RequestID(),
        command: PlaybackCommand,
        actor: ActorScope,
        source: CommandSource,
        expected: Revision? = nil
    ) {
        self.id = id
        self.command = command
        self.actor = actor
        self.source = source
        self.expected = expected
    }
}
