#if os(iOS) || os(macOS) || os(tvOS)
import AVFoundation
import Foundation
import LabDomain
import Observation
import ScreeningRoom

/// One screening, shared by every surface that shows it: the session (the rules), the player
/// (AVFoundation), the audio session and Now Playing adapters, and the resume point.
///
/// Every command, whether from a button, a remote command, or the companion link, goes through
/// `admit(_:)`: the session authorizes it and answers with a receipt, and only an applied change
/// reaches the player. Every signal from the player or the system goes through `handle(_:)`.
/// The host keeps one model for the app, so leaving the page does not stop Picture in Picture.
@MainActor
@Observable
public final class ScreeningRoomModel {
    /// The app's own controls and intents: every permission the app UI can hold.
    public static let controls = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    public enum Phase: Hashable, Sendable {
        case idle
        case opening(MediaAssetID)
        case ready
        case failed(PlaybackFailure)
    }

    /// A sentence for the page: a refused command, or how the screening resumed.
    public struct Notice: Hashable, Sendable {
        public let message: String
        public let isProblem: Bool
    }

    public private(set) var session: ScreeningSession
    public private(set) var phase: Phase = .idle
    public private(set) var notice: Notice?
    public let readiness: PlaybackReadiness
    /// Whether the host's theater presentation holds the player now. The page shows a note
    /// instead of a second view on the same player while it does, including while Picture in
    /// Picture started from the theater is showing.
    public var theaterIsOpen = false
    @ObservationIgnored public let player = ScreeningPlayer()

    @ObservationIgnored private let store: any ResumePointStore
    @ObservationIgnored private let integratesWithSystem: Bool
    @ObservationIgnored private var started = false
    #if os(iOS) || os(tvOS)
    @ObservationIgnored private var audio: AudioSessionObserver?
    #endif
    #if os(iOS) || os(macOS)
    @ObservationIgnored private var nowPlaying: NowPlayingAdapter?
    #endif

    /// - Parameters:
    ///   - store: Where the resume point lives. Reset removes it and nothing else.
    ///   - integratesWithSystem: Whether to observe the audio session and publish Now Playing.
    ///     Tests pass `false`, so they neither take the system's audio nor register remote commands.
    public init(store: any ResumePointStore, integratesWithSystem: Bool = true, readiness: PlaybackReadiness = .current) {
        self.store = store
        self.integratesWithSystem = integratesWithSystem
        self.readiness = readiness
        session = ScreeningSession(requestableSurfaces: readiness.requestableSurfaces)
        player.onSignal = { [weak self] signal in self?.handle(signal) }
    }

    public var state: PlaybackState { session.state }
    public var clip: MediaAsset? { session.clip }
    /// Newest first.
    public var receipts: [PlaybackReceipt] { session.receipts.reversed() }

    /// A link a companion controller uses. Its commands run as an authorized peer.
    public var companionLink: InProcessScreeningLink {
        InProcessScreeningLink(conductor: ModelConductor(model: self))
    }

    // MARK: Starting

    /// Opens the saved resume point, or the test card from the start. Runs once; later calls do
    /// nothing, so every surface can call it when it appears.
    public func start() async {
        guard !started else { return }
        started = true
        if integratesWithSystem { connectSystem() }
        switch store.load() {
        case .found(let point):
            session.resume(from: point)
            let caption = session.state.caption == .off ? "captions off" : session.state.caption.title(in: session.clip)
            notice = Notice(message: "Resumed \(session.clip?.title ?? "the clip") at \(PlaybackState.clock(session.state.position)) with \(caption).", isProblem: false)
            await load(session.clip ?? ScreeningClips.testCard)
        case .discarded(let reason):
            await perform(.open(ScreeningClips.testCard.id))
            notice = Notice(message: "\(reason) It was ignored; the Test Card opened from the start.", isProblem: true)
        case .none:
            await perform(.open(ScreeningClips.testCard.id))
        }
    }

    private func connectSystem() {
        #if os(iOS) || os(tvOS)
        audio = AudioSessionObserver { [weak self] signal in self?.handle(signal) }
        #endif
        #if os(iOS) || os(macOS)
        let adapter = NowPlayingAdapter { [weak self] command in
            Task { await self?.perform(command, source: .remoteCommand) }
        }
        adapter.registerToggle(isPlaying: { [weak self] in self?.state.isPlaying ?? false }) { [weak self] command in
            Task { await self?.perform(command, source: .remoteCommand) }
        }
        nowPlaying = adapter
        #endif
    }

    // MARK: Commands

    /// Runs a command from this device's own controls or remote commands, and keeps any refusal
    /// as the page's notice. Returns the receipt, or `nil` when it was refused.
    @discardableResult
    public func perform(_ command: PlaybackCommand, source: CommandSource = .controls) async -> PlaybackReceipt? {
        do {
            let receipt = try await admit(PlaybackRequest(command: command, actor: Self.controls, source: source))
            if receipt.didChange, notice?.isProblem == true { notice = nil }
            return receipt
        } catch {
            notice = Notice(message: error.message, isProblem: true)
            return nil
        }
    }

    /// The one path for every command: authorize and record in the session, then make the player
    /// match an applied change.
    public func admit(_ request: PlaybackRequest) async throws(ScreeningError) -> PlaybackReceipt {
        let receipt = try session.submit(request)
        guard receipt.didChange else { return receipt }
        switch request.command {
        case .open:
            await load(session.clip ?? ScreeningClips.testCard)
        case .play:
            activateAudio()
            // Playing from the end starts over: the session moved the position, so the player follows.
            if abs(player.currentSeconds - state.position) > 0.5 { player.seek(to: state.position) }
            player.play()
        case .pause:
            player.pause()
        case .seek, .skip:
            player.seek(to: state.position)
        case .selectCaption:
            player.select(state.caption)
        case .present:
            player.currentSurface = state.surface
        case .forgetResumePoint:
            player.pause()
            player.seek(to: 0)
            player.select(.off)
            player.currentSurface = state.surface
            do {
                try store.remove()
            } catch {
                notice = Notice(message: "The saved resume point could not be removed. It will be replaced next time.", isProblem: true)
            }
        }
        if request.command != .forgetResumePoint { persist() }
        publishNowPlaying()
        return receipt
    }

    /// Opens another clip. A clip that cannot play shows its failure and keeps the others usable.
    public func open(_ clip: MediaAsset) async {
        await perform(.open(clip.id))
    }

    /// The experiment's Reset: back to the start, captions off, and the resume point removed.
    /// Nothing outside this experiment is touched.
    public func reset() async {
        guard state.clip != nil else { return }
        if await perform(.forgetResumePoint) != nil {
            notice = Notice(message: "Reset: the Test Card is back at the start with captions off, and the saved resume point was removed.", isProblem: false)
        }
    }

    // MARK: Signals

    /// Applies a signal from the player, the audio session, or a surface, then makes the player
    /// match the result: an interruption that ends with a recommendation to resume plays again,
    /// and a lost output stays paused.
    public func handle(_ signal: PlaybackSignal) {
        let before = session.state
        guard session.observe(signal) else { return }
        if case .position = signal { return }
        let after = session.state
        if before.isPlaying != after.isPlaying {
            if after.isPlaying {
                activateAudio()
                player.play()
            } else {
                player.pause()
            }
        }
        player.currentSurface = after.surface
        persist()
        publishNowPlaying()
    }

    /// A surface appeared or went away, as the platform's own controls reported it.
    public func surfaceDidChange(to surface: PlaybackSurface) {
        handle(.surface(surface))
    }

    /// Saves the resume point now, for a host whose scene is going to the background.
    public func persist() {
        guard let point = session.resumePoint else { return }
        try? store.save(point)
    }

    /// Clears the page's notice, as when a person dismisses it.
    public func dismissNotice() {
        notice = nil
    }

    // MARK: Internals

    private func load(_ clip: MediaAsset) async {
        phase = .opening(clip.id)
        let result = await ClipOpener.open(clip)
        // A later command opened something else while this one loaded: its answer wins.
        guard session.state.clip == clip.id else { return }
        switch result {
        case .success(let opened):
            player.load(opened, at: state.position, caption: state.caption)
            player.currentSurface = state.surface
            session.observe(.opened(duration: opened.duration))
            phase = .ready
        case .failure(let failure):
            player.unload()
            session.observe(.failed(failure))
            phase = .failed(failure)
        }
        publishNowPlaying()
    }

    private func activateAudio() {
        #if os(iOS) || os(tvOS)
        audio?.activate()
        #endif
    }

    private func publishNowPlaying() {
        #if os(iOS) || os(macOS)
        nowPlaying?.update(state, title: clip?.title ?? ScreeningRoom.title)
        #endif
    }

    /// For a host that is closing the experiment for good.
    public func invalidate() {
        player.invalidate()
        #if os(iOS) || os(tvOS)
        audio?.invalidate()
        #endif
        #if os(iOS) || os(macOS)
        nowPlaying?.invalidate()
        #endif
    }

    fileprivate func read(as actor: ActorScope) throws(ScreeningError) -> PlaybackState {
        try session.snapshot(for: actor)
    }
}

/// The model as the receiving end of a companion link.
struct ModelConductor: ScreeningConductor {
    let model: ScreeningRoomModel

    func read(as actor: ActorScope) async throws(ScreeningError) -> PlaybackState {
        try await model.read(as: actor)
    }

    func submit(_ request: PlaybackRequest) async throws(ScreeningError) -> PlaybackReceipt {
        try await model.admit(request)
    }
}
#endif
