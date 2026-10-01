import Foundation

/// Why the conductor would not let a person decide a held command.
public enum HeldCommandRefusal: Error, Hashable, Sendable {
    /// Nothing with that ID is waiting: it was answered, it expired, or it was never held.
    case notWaiting
    /// The device that asked was forgotten, and its requests were withdrawn with it.
    case peerForgotten
    /// The device that asked is not paired with this conductor now: its pin is gone or changed.
    case peerNotPaired
    /// Someone at the conductor is deciding it already.
    case alreadyDeciding

    public var explanation: String {
        switch self {
        case .notWaiting: "That request is no longer waiting."
        case .peerForgotten: "The device that asked was forgotten, so its request was withdrawn. Nothing changed."
        case .peerNotPaired: "The device that asked is no longer paired with this conductor. Nothing changed."
        case .alreadyDeciding: "That request is already being answered."
        }
    }
}

/// What the host decided for a held command it took with `Conductor.settle`: the decision, made
/// against the conductor's state when it is applied, and anything the host wants back, such as
/// the receipt of what it committed.
public struct HeldDecision<Snapshot: WirePayload, Extra: Sendable>: Sendable {
    public let extra: Extra
    public let decide: @Sendable (Snapshot) -> CommandDecision<Snapshot>

    public init(extra: Extra, _ decide: @escaping @Sendable (Snapshot) -> CommandDecision<Snapshot>) {
        self.extra = extra
        self.decide = decide
    }
}

extension HeldDecision where Extra == Void {
    public init(_ decide: @escaping @Sendable (Snapshot) -> CommandDecision<Snapshot>) {
        self.init(extra: (), decide)
    }
}

/// A held command the conductor finished through `Conductor.settle`.
public struct SettledCommand<Extra: Sendable>: Sendable {
    /// The answer the peer received.
    public let result: CommandResult
    public let extra: Extra
}

/// The answers to commands from pairings a person forgot, kept so that nothing from a forgotten
/// pairing is admitted or allowed again, even after the device pairs anew. Bounded: the oldest
/// go first.
struct RetiredCommands: Sendable {
    static let capacity = 256

    private struct Entry: Sendable {
        let peer: PeerID
        let result: CommandResult
    }

    private var entries: [MessageID: Entry] = [:]
    private var order: [MessageID] = []

    mutating func retire(_ result: CommandResult, from peer: PeerID) {
        if entries[result.commandID] == nil { order.append(result.commandID) }
        entries[result.commandID] = Entry(peer: peer, result: result)
        if order.count > Self.capacity {
            entries[order.removeFirst()] = nil
        }
    }

    /// The recorded answer, if `peer` sent `id` under a pairing that was forgotten.
    func answer(for id: MessageID, from peer: PeerID) -> CommandResult? {
        guard let entry = entries[id], entry.peer == peer else { return nil }
        return entry.result
    }

    func contains(_ id: MessageID) -> Bool {
        entries[id] != nil
    }
}
