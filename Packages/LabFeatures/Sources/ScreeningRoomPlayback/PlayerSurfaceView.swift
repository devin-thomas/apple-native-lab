#if os(iOS) || os(macOS) || os(tvOS)
import AVKit
import ScreeningRoom
import SwiftUI

/// The platform's own player view on the screening's one `AVPlayer`: `AVPlayerViewController` on
/// iPhone, iPad, and Apple TV, `AVPlayerView` on the Mac. Its controls, caption menu, full-screen
/// and Picture in Picture buttons are the system's.
///
/// `role` is the surface this view is (`inline` or `theater`). When the system moves the clip to
/// full screen or Picture in Picture and back, the view reports it to the model as a signal, so
/// the session always knows where the clip is.
public struct PlayerSurfaceView {
    let model: ScreeningRoomModel
    let role: PlaybackSurface

    public init(model: ScreeningRoomModel, role: PlaybackSurface) {
        self.model = model
        self.role = role
    }

    @MainActor
    public final class Coordinator: NSObject {
        let model: ScreeningRoomModel
        let role: PlaybackSurface

        nonisolated init(model: ScreeningRoomModel, role: PlaybackSurface) {
            self.model = model
            self.role = role
        }

        func report(_ surface: PlaybackSurface) {
            model.surfaceDidChange(to: surface)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(model: model, role: role)
    }
}

#if os(iOS) || os(tvOS)
extension PlayerSurfaceView: UIViewControllerRepresentable {
    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = model.player.player
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = model.readiness.status(of: PlaybackReadiness.pictureInPictureTitle) == .systemManaged
        #if os(iOS)
        // The lab publishes Now Playing itself, so remote commands become commands with receipts.
        controller.updatesNowPlayingInfoCenter = false
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        #endif
        return controller
    }

    public func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== model.player.player { controller.player = model.player.player }
    }

    public static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        // Picture in Picture keeps its own reference to the player; the view lets go of it.
        if !(coordinator.model.state.surface == .pictureInPicture) { controller.player = nil }
    }
}

extension PlayerSurfaceView.Coordinator: @preconcurrency AVPlayerViewControllerDelegate {
    public func playerViewControllerWillStartPictureInPicture(_ controller: AVPlayerViewController) {
        report(.pictureInPicture)
    }

    public func playerViewControllerDidStopPictureInPicture(_ controller: AVPlayerViewController) {
        report(role)
    }

    public func playerViewController(
        _ controller: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }

    #if os(iOS)
    public func playerViewController(
        _ controller: AVPlayerViewController,
        willBeginFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
    ) {
        report(.fullScreen)
    }

    public func playerViewController(
        _ controller: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
    ) {
        let role = role
        coordinator.animate(alongsideTransition: nil) { [weak self] context in
            guard !context.isCancelled else { return }
            MainActor.assumeIsolated { self?.report(role) }
        }
    }
    #endif
}
#endif

#if os(macOS)
extension PlayerSurfaceView: NSViewRepresentable {
    public func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = model.player.player
        view.delegate = context.coordinator
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = model.readiness.status(of: PlaybackReadiness.pictureInPictureTitle) == .systemManaged
        // The lab publishes Now Playing itself, so the media keys become commands with receipts.
        view.updatesNowPlayingInfoCenter = false
        view.pictureInPictureDelegate = context.coordinator
        return view
    }

    public func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== model.player.player { view.player = model.player.player }
    }
}

extension PlayerSurfaceView.Coordinator: @preconcurrency AVPlayerViewDelegate, @preconcurrency AVPlayerViewPictureInPictureDelegate {
    public func playerViewWillEnterFullScreen(_ playerView: AVPlayerView) {
        report(.fullScreen)
    }

    public func playerViewDidExitFullScreen(_ playerView: AVPlayerView) {
        report(role)
    }

    public func playerViewWillStartPicture(inPicture playerView: AVPlayerView) {
        report(.pictureInPicture)
    }

    public func playerViewDidStopPicture(inPicture playerView: AVPlayerView) {
        report(role)
    }

    public func playerView(
        _ playerView: AVPlayerView,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}
#endif

#if os(iOS) || os(macOS)
/// The system's AirPlay route picker. Choosing a route is the person's decision in the system's
/// own sheet; the lab only learns that external playback started or ended.
public struct RoutePickerButton {
    public init() {}
}

#if os(iOS)
extension RoutePickerButton: UIViewRepresentable {
    public func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        return picker
    }

    public func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
#else
extension RoutePickerButton: NSViewRepresentable {
    public func makeNSView(context: Context) -> AVRoutePickerView {
        AVRoutePickerView()
    }

    public func updateNSView(_ view: AVRoutePickerView, context: Context) {}
}
#endif
#endif
#endif
