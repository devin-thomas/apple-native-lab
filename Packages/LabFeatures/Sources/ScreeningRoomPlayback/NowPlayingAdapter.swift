#if os(iOS) || os(macOS)
import Foundation
import MediaPlayer
import ScreeningRoom

/// Publishes the screening to the system's Now Playing surfaces and turns their remote commands
/// into playback commands: Control Center, the Lock Screen, headphone buttons, and a keyboard's
/// media keys.
///
/// The player views are told not to publish Now Playing themselves (`updatesNowPlayingInfoCenter`
/// is off), so every remote command reaches the session as a command with a receipt, like a
/// button in the page. Apple TV is different: `updatesNowPlayingInfoCenter` is unavailable on
/// tvOS, and its native player answers the Siri Remote itself; the session sees those changes as
/// signals.
@MainActor
final class NowPlayingAdapter {
    private let center = MPRemoteCommandCenter.shared()
    private var targets: [(MPRemoteCommand, Any)] = []

    /// Registers the commands. `perform` receives each as a playback command.
    init(perform: @escaping @MainActor (PlaybackCommand) -> Void) {
        func handle(_ command: MPRemoteCommand, _ make: @escaping @Sendable (MPRemoteCommandEvent) -> PlaybackCommand?) {
            command.isEnabled = true
            let target = command.addTarget { event in
                guard let playback = make(event) else { return .commandFailed }
                // The system calls handlers on its own schedule; the command runs on the main actor.
                Task { @MainActor in perform(playback) }
                return .success
            }
            targets.append((command, target))
        }
        handle(center.playCommand) { _ in .play }
        handle(center.pauseCommand) { _ in .pause }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: ScreeningRoom.skipInterval)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: ScreeningRoom.skipInterval)]
        handle(center.skipForwardCommand) { _ in .skip(by: ScreeningRoom.skipInterval) }
        handle(center.skipBackwardCommand) { _ in .skip(by: -ScreeningRoom.skipInterval) }
        handle(center.changePlaybackPositionCommand) { event in
            (event as? MPChangePlaybackPositionCommandEvent).map { .seek(to: $0.positionTime) }
        }
    }

    /// The toggle has no fixed direction, so it needs the current state.
    func registerToggle(isPlaying: @escaping @MainActor () -> Bool, perform: @escaping @MainActor (PlaybackCommand) -> Void) {
        let command = center.togglePlayPauseCommand
        command.isEnabled = true
        let target = command.addTarget { _ in
            Task { @MainActor in perform(isPlaying() ? .pause : .play) }
            return .success
        }
        targets.append((command, target))
    }

    /// Shows the state on the system's Now Playing surfaces. The title is the clip's; nothing a
    /// person wrote is published.
    func update(_ state: PlaybackState, title: String) {
        let info = MPNowPlayingInfoCenter.default()
        guard state.clip != nil, state.failure == nil else {
            info.nowPlayingInfo = nil
            #if os(macOS)
            info.playbackState = .stopped
            #endif
            return
        }
        var values: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.position,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let duration = state.duration { values[MPMediaItemPropertyPlaybackDuration] = duration }
        info.nowPlayingInfo = values
        #if os(macOS)
        info.playbackState = state.isPlaying ? .playing : .paused
        #endif
    }

    func invalidate() {
        for (command, target) in targets { command.removeTarget(target) }
        targets = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
#endif
