import Foundation
import LabDomain

/// The narrow surface a controller on another device uses to watch and steer this device's
/// screening: read a snapshot, send a command, get a receipt.
///
/// It carries commands and snapshots only. Signals (interruptions, route changes, the player's
/// own controls) stay with the host that owns the player, and the receiving side, never the
/// sender, decides which actor a command runs as. LAB-019 Local Constellation supplies the paired
/// transport later; until then `InProcessScreeningLink` stands in for it inside one app, and the
/// experiment labels it as a simulation.
public protocol ScreeningLink: Sendable {
    func snapshot() async throws(ScreeningError) -> PlaybackState

    /// Sends one command. `seen` is the revision the controller last showed, so a stale command
    /// conflicts instead of overwriting a newer change. Reuse `requestID` on a retry.
    func send(_ command: PlaybackCommand, requestID: RequestID, seen: Revision?) async throws(ScreeningError) -> PlaybackReceipt
}

/// What a host needs to admit commands from a link: its own session's read and submit.
public protocol ScreeningConductor: Sendable {
    func read(as actor: ActorScope) async throws(ScreeningError) -> PlaybackState
    func submit(_ request: PlaybackRequest) async throws(ScreeningError) -> PlaybackReceipt
}

/// A link within one process: the receiving end of a paired transport, without the transport.
///
/// Every command it forwards runs as `companionScope`, an `authorizedPeer` that may read and
/// commit but, by the adapter's fixed ceiling, never commit a destructive change.
public struct InProcessScreeningLink: ScreeningLink {
    public static let companionScope = ActorScope(adapter: .authorizedPeer, grants: [.read, .commit])

    private let conductor: any ScreeningConductor
    private let scope: ActorScope

    public init(conductor: any ScreeningConductor, scope: ActorScope = InProcessScreeningLink.companionScope) {
        self.conductor = conductor
        self.scope = scope
    }

    public func snapshot() async throws(ScreeningError) -> PlaybackState {
        try await conductor.read(as: scope)
    }

    public func send(_ command: PlaybackCommand, requestID: RequestID, seen: Revision?) async throws(ScreeningError) -> PlaybackReceipt {
        try await conductor.submit(PlaybackRequest(id: requestID, command: command, actor: scope, source: .companion, expected: seen))
    }
}
