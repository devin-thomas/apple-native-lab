import Foundation
import LabDomain

/// Why a playback command was refused. Each case changed nothing and recorded nothing.
public enum ScreeningError: Error, Hashable, Sendable {
    case unauthorized(PlaybackDenial)
    /// The request ID was already used for a different command.
    case requestIDReused(RequestID)
    case noClip
    case unknownClip(MediaAssetID)
    /// The open clip failed; only opening a clip or forgetting the resume point is possible.
    case clipUnavailable(PlaybackFailure)
    /// A time that is not a finite number of seconds.
    case invalidTime
    case unknownCaption(SubtitleTrack.ID)
    /// The lab's controls cannot ask for this surface here; the platform's own controls can.
    case surfaceNotRequestable(PlaybackSurface)
    /// The other side of a link could not be reached. Nothing is known to have changed.
    case linkUnavailable(reason: String)

    public var message: String {
        switch self {
        case .unauthorized(let denial) where denial.required == .commitDestructive:
            "Only this device's own controls can reset the screening. Nothing was changed."
        case .unauthorized:
            "This controller is not allowed to do that. Nothing was changed."
        case .requestIDReused:
            "That request was already used for something else. Nothing was changed."
        case .noClip:
            "Open a clip first."
        case .unknownClip(let id):
            "\(id) is not one of this build's clips."
        case .clipUnavailable(let failure):
            "\(failure.message) \(failure.recovery)"
        case .invalidTime:
            "That is not a time in the clip. Nothing was changed."
        case .unknownCaption(let id):
            "This clip has no \(id) captions. Nothing was changed."
        case .surfaceNotRequestable(let surface):
            "\(surface.title) starts from the player's own controls, not from here."
        case .linkUnavailable(let reason):
            reason
        }
    }
}

extension ScreeningError: LocalizedError {
    public var errorDescription: String? { message }
}

/// Why an actor may not issue a command, in the domain's terms. LabDomain's own
/// `AuthorizationDenial` is built only by `OperationService`, so this carries the same facts.
public struct PlaybackDenial: Hashable, Sendable {
    public let adapter: AdapterKind
    public let required: Permission
    public let reason: AuthorizationDenial.Reason
}

/// The one place playback state changes: commands from people and controllers, and signals from
/// the system and the player.
///
/// It is a value owned by one host, on one actor (the app's main actor), and it is the
/// conductor for anything that controls this device's playback. Commands are authorized with the
/// domain's rules: the adapter's fixed ceiling, then the actor's grants, so an `authorizedPeer`
/// can play and pause but never reset, and a `modelTool` can only read. Each command is answered
/// once per request ID, a stale expected revision conflicts, and every applied change raises the
/// revision.
public struct ScreeningSession: Sendable {
    /// How many receipts the session keeps for retries and display, newest last.
    public static let receiptLimit = 64

    public private(set) var state: PlaybackState
    public private(set) var receipts: [PlaybackReceipt] = []
    /// The surfaces this host's own controls can present, of `inline` and `theater`.
    public let requestableSurfaces: Set<PlaybackSurface>

    public init(state: PlaybackState = .empty, requestableSurfaces: Set<PlaybackSurface> = [.inline, .theater]) {
        self.state = state
        self.requestableSurfaces = requestableSurfaces.filter(\.isRequestable)
    }

    public var clip: MediaAsset? { state.clip.flatMap(ScreeningClips.clip) }

    // MARK: Reading

    /// The current state, for an actor allowed to read.
    public func snapshot(for actor: ActorScope) throws(ScreeningError) -> PlaybackState {
        try Self.authorize(.read, for: actor)
        return state
    }

    // MARK: Commands

    /// Applies one command, or returns the receipt already given to its request ID.
    public mutating func submit(_ request: PlaybackRequest) throws(ScreeningError) -> PlaybackReceipt {
        try Self.authorize(request.command.kind.permission, for: request.actor)
        if let recorded = receipts.last(where: { $0.requestID == request.id }) {
            guard recorded.matches(request) else { throw .requestIDReused(request.id) }
            return recorded
        }
        let previous = state
        if let expected = request.expected, expected != state.revision {
            let summary = "Not applied: playback changed since this controller last looked (it saw revision \(expected), now \(state.revision))."
            return record(request, status: .conflict(expected: expected, current: state.revision),
                          previous: previous, summary: summary, undo: nil)
        }
        let (next, undo) = try planned(request.command)
        guard next.content != state.content else {
            return record(request, status: .unchanged, previous: previous,
                          summary: Self.unchangedSummary(request.command, state: state), undo: nil)
        }
        state = next
        state.revision = previous.revision.next()
        return record(request, status: .applied, previous: previous,
                      summary: Self.appliedSummary(request.command, from: previous, to: state), undo: undo)
    }

    /// The state a command leads to, and its exact reverse, or a refusal.
    private func planned(_ command: PlaybackCommand) throws(ScreeningError) -> (PlaybackState, PlaybackCommand?) {
        var next = state
        switch command {
        case .open(let id):
            guard let asset = ScreeningClips.clip(id) else { throw .unknownClip(id) }
            next = PlaybackState(clip: id, duration: asset.duration, surface: state.surface, revision: state.revision)
            return (next, nil)
        case .forgetResumePoint:
            guard state.clip != nil else { return (state, nil) }
            next = PlaybackState(clip: state.clip, duration: state.duration, failure: state.failure, revision: state.revision)
            return (next, nil)
        default:
            break
        }
        guard state.clip != nil else { throw .noClip }
        if let failure = state.failure { throw .clipUnavailable(failure) }
        switch command {
        case .open, .forgetResumePoint:
            return (state, nil)
        case .play:
            if let duration = state.duration, state.position >= duration - 0.05 { next.position = 0 }
            next.isPlaying = true
            next.interruption = nil
            return (next, .pause)
        case .pause:
            next.isPlaying = false
            // Pausing during an interruption is the person's decision not to resume afterwards.
            if next.interruption != nil { next.interruption = .init(wasPlaying: false) }
            return (next, .play)
        case .seek(let time):
            guard time.isFinite else { throw .invalidTime }
            next.position = clamped(time)
            return (next, .seek(to: state.position))
        case .skip(let delta):
            guard delta.isFinite else { throw .invalidTime }
            next.position = clamped(state.position + delta)
            return (next, .seek(to: state.position))
        case .selectCaption(let choice):
            if let id = choice.trackID, clip?.caption(id) == nil { throw .unknownCaption(id) }
            next.caption = choice
            return (next, .selectCaption(state.caption))
        case .present(let surface):
            guard requestableSurfaces.contains(surface) else { throw .surfaceNotRequestable(surface) }
            next.surface = surface
            return (next, requestableSurfaces.contains(state.surface) ? .present(state.surface) : nil)
        }
    }

    private mutating func record(
        _ request: PlaybackRequest,
        status: PlaybackReceipt.Status,
        previous: PlaybackState,
        summary: String,
        undo: PlaybackCommand?
    ) -> PlaybackReceipt {
        let receipt = PlaybackReceipt(
            requestID: request.id,
            adapter: request.actor.adapter,
            source: request.source,
            command: request.command,
            expected: request.expected,
            status: status,
            previous: previous.revision,
            revision: state.revision,
            summary: summary,
            undo: undo
        )
        receipts.append(receipt)
        if receipts.count > Self.receiptLimit { receipts.removeFirst(receipts.count - Self.receiptLimit) }
        return receipt
    }

    // MARK: Signals

    /// Applies what the system or the player reported, and says whether the state changed.
    ///
    /// Only the host that owns the player calls this. A position sample changes the position
    /// without raising the revision; every other change raises it.
    @discardableResult
    public mutating func observe(_ signal: PlaybackSignal) -> Bool {
        var next = state
        switch signal {
        case .opened(let duration):
            guard duration.isFinite, duration > 0 else { return false }
            next.duration = duration
            next.failure = nil
            next.position = min(next.position, duration)
        case .failed(let failure):
            next.failure = failure
            next.isPlaying = false
        case .position(let time):
            guard time.isFinite, state.clip != nil else { return false }
            let position = clamped(time)
            guard position != state.position else { return false }
            state.position = position
            return true
        case .playing(let playing):
            if next.interruption != nil {
                // A pause the system made for the interruption keeps the plan to resume. A start
                // means someone already resumed.
                guard playing else { return false }
                next.interruption = nil
            }
            next.isPlaying = playing
        case .caption(let choice):
            if let id = choice.trackID, clip?.caption(id) == nil { return false }
            next.caption = choice
        case .surface(let surface):
            next.surface = surface
        case .interruptionBegan:
            guard next.interruption == nil else { return false }
            next.interruption = .init(wasPlaying: state.isPlaying)
            next.isPlaying = false
        case .interruptionEnded(let shouldResume):
            guard let interruption = next.interruption else { return false }
            next.interruption = nil
            next.isPlaying = interruption.wasPlaying && shouldResume && state.failure == nil
        case .routeChanged(let change):
            next.lastRouteChange = change
            if change == .oldDeviceUnavailable {
                next.isPlaying = false
                if next.interruption != nil { next.interruption = .init(wasPlaying: false) }
            }
        }
        guard next.content != state.content else { return false }
        next.revision = state.revision.next()
        state = next
        return true
    }

    // MARK: Resume

    /// Where to come back to: the clip, the position, and the captions. `nil` when nothing
    /// playable is open.
    public var resumePoint: ResumePoint? {
        guard let clip = state.clip, state.failure == nil,
              ScreeningClips.clip(clip)?.expectation == .plays else { return nil }
        return ResumePoint(clip: clip, position: state.position, caption: state.caption)
    }

    /// Reopens a saved resume point, paused, in the page. A caption the clip no longer has is
    /// turned off. The host calls this once when the experiment opens; it is not a command.
    @discardableResult
    public mutating func resume(from point: ResumePoint) -> Bool {
        guard let asset = ScreeningClips.clip(point.clip), asset.expectation == .plays else { return false }
        var next = PlaybackState(clip: point.clip, duration: asset.duration, surface: .inline, revision: state.revision)
        next.position = min(max(0, point.position), asset.duration ?? point.position)
        if let id = point.caption.trackID, asset.caption(id) == nil { next.caption = .off } else { next.caption = point.caption }
        guard next.content != state.content else { return false }
        next.revision = state.revision.next()
        state = next
        return true
    }

    // MARK: Helpers

    private func clamped(_ time: Double) -> Double {
        let upper = state.duration ?? .greatestFiniteMagnitude
        return min(max(0, time), upper)
    }

    static func authorize(_ required: Permission, for actor: ActorScope) throws(ScreeningError) {
        let reason: AuthorizationDenial.Reason? =
            if !actor.adapter.ceiling.contains(required) { .outsideAdapterCeiling }
            else if !actor.grants.contains(required) { .notGranted }
            else { nil }
        if let reason {
            throw .unauthorized(PlaybackDenial(adapter: actor.adapter, required: required, reason: reason))
        }
    }

    private static func appliedSummary(_ command: PlaybackCommand, from old: PlaybackState, to new: PlaybackState) -> String {
        let clipTitle = new.clip.flatMap(ScreeningClips.clip)?.title ?? "the clip"
        let at = PlaybackState.clock(new.position)
        return switch command {
        case .open: "Opened \(clipTitle) at the start, captions off."
        case .play: "Played \(clipTitle) from \(at)."
        case .pause: "Paused \(clipTitle) at \(at)."
        case .seek, .skip: "Moved \(clipTitle) from \(PlaybackState.clock(old.position)) to \(at)."
        case .selectCaption(let choice): "\(choice.title(in: new.clip.flatMap(ScreeningClips.clip))) for \(clipTitle)."
        case .present(let surface): "Moved \(clipTitle) to \(surface.title), still at \(at)."
        case .forgetResumePoint: "Forgot the resume point: \(clipTitle) is back at the start, captions off, in the page."
        }
    }

    private static func unchangedSummary(_ command: PlaybackCommand, state: PlaybackState) -> String {
        switch command {
        case .open: "That clip is already open at the start."
        case .play: "Already playing."
        case .pause: "Already paused."
        case .seek, .skip: "Already at \(PlaybackState.clock(state.position))."
        case .selectCaption: "Those captions are already chosen."
        case .present(let surface): "Already showing \(surface.title.lowercased())."
        case .forgetResumePoint: "Nothing to reset."
        }
    }
}
