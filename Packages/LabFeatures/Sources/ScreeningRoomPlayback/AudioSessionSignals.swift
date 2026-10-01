import Foundation
import ScreeningRoom
#if os(iOS) || os(tvOS)
import AVFoundation
#endif

/// Turns the audio session's interruption and route-change notifications into playback signals.
///
/// iOS and tvOS only: the Mac has no audio session, and its playback is not interrupted this way.
/// The mapping functions take the notifications' raw numbers, so the rules are tested on every
/// platform; the observer that reads the notifications compiles only where they exist.
public enum AudioSessionSignals {
    /// `AVAudioSession.InterruptionType`: 1 began, 0 ended.
    /// `AVAudioSession.InterruptionOptions.shouldResume` is bit 0 of the options.
    public static func interruption(type: UInt, options: UInt) -> PlaybackSignal? {
        switch type {
        case 1: .interruptionBegan
        case 0: .interruptionEnded(shouldResume: options & 1 == 1)
        default: nil
        }
    }

    /// `AVAudioSession.RouteChangeReason`: 1 new device available, 2 old device unavailable;
    /// every other reason (category change, override, wake from sleep, and so on) is `other`.
    public static func routeChange(reason: UInt) -> PlaybackSignal {
        switch reason {
        case 1: .routeChanged(.newDeviceAvailable)
        case 2: .routeChanged(.oldDeviceUnavailable)
        default: .routeChanged(.other)
        }
    }
}

#if os(iOS) || os(tvOS)
/// The app's audio session for a screening: the playback category with the movie mode, which
/// also lets Picture in Picture keep playing, and the observers that report interruptions and
/// route changes.
///
/// The interruption notification is the classic one. The 27 SDKs mark it deprecated in favor of
/// `didBecomeInactiveNotification` and `resumptionRecommendationNotification` (iOS and tvOS 27.0),
/// but the lab's floor is 26.0, where only the classic one exists, and a package has no SDK
/// compile flag to choose between them. The player's own rate-change reason
/// (`.audioSessionInterrupted`) reports the start of an interruption as well.
@MainActor
final class AudioSessionObserver {
    private var tokens: [NSObjectProtocol] = []
    private(set) var configurationError: String?

    init(onSignal: @escaping @MainActor (PlaybackSignal) -> Void) {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue ?? UInt.max
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            guard let signal = AudioSessionSignals.interruption(type: type, options: options) else { return }
            MainActor.assumeIsolated { onSignal(signal) }
        })
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue ?? 0
            MainActor.assumeIsolated { onSignal(AudioSessionSignals.routeChange(reason: reason)) }
        })
    }

    /// Sets the playback category and activates the session. Called when playback first starts,
    /// never at launch, so opening the lab does not take audio from another app.
    func activate() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            configurationError = nil
        } catch {
            configurationError = "The audio session could not be set up (\((error as NSError).code)). Playback may be silent or stop in the background."
        }
    }

    func invalidate() {
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens = []
    }
}
#endif
