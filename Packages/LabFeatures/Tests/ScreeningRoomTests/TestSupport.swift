import Foundation
import LabDomain
@testable import ScreeningRoom

/// The app's own controls: every permission the app UI can hold.
let appControls = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

extension ScreeningSession {
    /// A session with the test card open, as the player reported it.
    static func withTestCard(requestableSurfaces: Set<PlaybackSurface> = [.inline, .theater]) throws -> ScreeningSession {
        var session = ScreeningSession(requestableSurfaces: requestableSurfaces)
        _ = try session.submit(.local(.open(ScreeningClips.testCard.id)))
        session.observe(.opened(duration: 10))
        return session
    }

    /// Submits a command from the app's own controls.
    @discardableResult
    mutating func run(_ command: PlaybackCommand) throws(ScreeningError) -> PlaybackReceipt {
        try submit(.local(command))
    }
}

extension PlaybackRequest {
    static func local(_ command: PlaybackCommand, id: RequestID = RequestID()) -> PlaybackRequest {
        PlaybackRequest(id: id, command: command, actor: appControls, source: .controls)
    }
}

extension Revision {
    static func r(_ value: Int) -> Revision { Revision(rawValue: value)! }
}

/// A conductor over one session, as a host provides it to a link.
actor SessionConductor: ScreeningConductor {
    var session: ScreeningSession

    init(_ session: ScreeningSession) {
        self.session = session
    }

    func read(as actor: ActorScope) throws(ScreeningError) -> PlaybackState {
        try session.snapshot(for: actor)
    }

    func submit(_ request: PlaybackRequest) throws(ScreeningError) -> PlaybackReceipt {
        try session.submit(request)
    }

    func observe(_ signal: PlaybackSignal) {
        session.observe(signal)
    }
}
