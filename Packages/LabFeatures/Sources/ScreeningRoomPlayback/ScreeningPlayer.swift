#if os(iOS) || os(macOS) || os(tvOS)
import AVFoundation
import Foundation
import ScreeningRoom

/// The one `AVPlayer` a screening uses, whatever surface shows it.
///
/// Every surface (the page, the theater, full screen, Picture in Picture, AirPlay) attaches to
/// this same player, so moving between them never reloads the item: the position and the caption
/// selection stay in the player itself. The player does what the model tells it and reports what
/// happened as `PlaybackSignal`s, including changes the platform's own controls made.
@MainActor
public final class ScreeningPlayer {
    public let player = AVPlayer()
    public private(set) var opened: OpenedClip?

    /// Receives every signal, on the main actor.
    var onSignal: (PlaybackSignal) -> Void = { _ in }

    private var timeObserver: Any?
    private var notificationTokens: [NSObjectProtocol] = []
    /// The current item's observers, replaced with the item.
    private var itemTokens: [NSObjectProtocol] = []
    private var externalObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    /// The surface to return to when an external route ends.
    private var surfaceBeforeExternal: PlaybackSurface = .inline
    var currentSurface: PlaybackSurface = .inline

    public init() {
        player.allowsExternalPlayback = true
        observePlayer()
    }

    // MARK: Loading

    /// Puts an opened clip in the player, paused at `position` with `caption` selected.
    func load(_ clip: OpenedClip, at position: Double, caption: CaptionChoice) {
        player.pause()
        let item = AVPlayerItem(asset: clip.asset)
        opened = clip
        observe(item)
        select(caption, in: item)
        player.replaceCurrentItem(with: item)
        seek(to: position)
    }

    /// Empties the player, for a clip that failed to open.
    func unload() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        opened = nil
        statusObservation = nil
    }

    // MARK: Commands

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func select(_ caption: CaptionChoice) {
        guard let item = player.currentItem else { return }
        select(caption, in: item)
    }

    private func select(_ caption: CaptionChoice, in item: AVPlayerItem) {
        guard let group = opened?.captionGroup else { return }
        let option = caption.trackID.flatMap { opened?.captionOptions[$0] }
        item.select(option, in: group)
    }

    /// What the player itself is showing now, for tests and diagnostics.
    public var selectedCaption: CaptionChoice? {
        guard let item = player.currentItem, let group = opened?.captionGroup else { return nil }
        return opened?.choice(for: item.currentMediaSelection.selectedMediaOption(in: group))
    }

    public var currentSeconds: Double { player.currentTime().seconds }

    // MARK: Observation

    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.onSignal(.position(time.seconds)) }
        }
        let center = NotificationCenter.default
        let reasonKey = AVPlayer.rateDidChangeReasonKey
        notificationTokens.append(center.addObserver(forName: AVPlayer.rateDidChangeNotification, object: player, queue: .main) { [weak self] note in
            let reason = note.userInfo?[reasonKey] as? AVPlayer.RateDidChangeReason
            MainActor.assumeIsolated { self?.rateChanged(reason: reason) }
        })
        externalObservation = player.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] player, _ in
            let active = player.isExternalPlaybackActive
            Task { @MainActor in self?.externalPlaybackChanged(active) }
        }
    }

    private func observe(_ item: AVPlayerItem) {
        let center = NotificationCenter.default
        itemTokens.forEach(center.removeObserver)
        itemTokens = []
        itemTokens.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onSignal(.playing(false)) }
        })
        itemTokens.append(center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            MainActor.assumeIsolated { self?.failed(error) }
        })
        itemTokens.append(center.addObserver(forName: AVPlayerItem.mediaSelectionDidChangeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.selectionChanged() }
        })
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let error = item.error as NSError?
            Task { @MainActor in self?.failed(error) }
        }
    }

    /// A rate change the audio session caused is an interruption, not a person's pause: the
    /// session keeps its plan to resume. Any other change is what the controls did.
    func rateChanged(reason: AVPlayer.RateDidChangeReason?) {
        if reason == .audioSessionInterrupted {
            onSignal(.interruptionBegan)
        } else {
            onSignal(.playing(player.rate != 0))
        }
    }

    private func selectionChanged() {
        guard let item = player.currentItem, let clip = opened, let group = clip.captionGroup,
              let choice = clip.choice(for: item.currentMediaSelection.selectedMediaOption(in: group)) else { return }
        onSignal(.caption(choice))
    }

    private func externalPlaybackChanged(_ active: Bool) {
        if active {
            if currentSurface != .external { surfaceBeforeExternal = currentSurface }
            onSignal(.surface(.external))
        } else if currentSurface == .external {
            onSignal(.surface(surfaceBeforeExternal))
        }
    }

    private func failed(_ error: NSError?) {
        let failure = PlaybackFailure.classify(domain: error?.domain ?? "unknown", code: error?.code ?? 0, whileOpening: false)
        onSignal(.failed(failure))
    }

    /// Stops observing, for a host that is closing the experiment for good.
    func invalidate() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        (notificationTokens + itemTokens).forEach(NotificationCenter.default.removeObserver)
        notificationTokens = []
        itemTokens = []
        externalObservation = nil
        statusObservation = nil
        player.pause()
    }
}
#endif
