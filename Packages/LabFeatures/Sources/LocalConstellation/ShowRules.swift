import Foundation
import PeerSession

/// The show's rules for a command that passed every session check (role, epoch, age, sequence,
/// and base revision). Moving between cues applies at once. Starting or pausing from a peer is
/// held for the person at the conductor; `ShowHost.allow` then commits it through the operation
/// service.
public struct ShowRules: Sendable {
    public let sheet: CueSheet

    public init(sheet: CueSheet) {
        self.sheet = sheet
    }

    public func decide(_ command: ShowCommand, on state: ShowSnapshot, from origin: CommandOrigin) -> CommandDecision<ShowSnapshot> {
        let who = origin.role == .conductor ? "The conductor" : origin.peer.name
        switch command {
        case .next:
            guard state.cue + 1 < sheet.cues.count else { return .unchanged(summary: "Already at the last cue.") }
            return move(to: state.cue + 1, on: state, by: who)
        case .previous:
            guard state.cue > 0 else { return .unchanged(summary: "Already at the first cue.") }
            return move(to: state.cue - 1, on: state, by: who)
        case .goTo(let index):
            guard sheet.cues.indices.contains(index) else { return .refuse(summary: "There is no cue \(index + 1).") }
            guard index != state.cue else { return .unchanged(summary: "Already at cue \(index + 1).") }
            return move(to: index, on: state, by: who)
        case .start, .pause:
            let running = command == .start
            guard state.isRunning != running else {
                return .unchanged(summary: running ? "The show is already running." : "The show is already paused.")
            }
            guard origin.role != .conductor else {
                // The conductor's own person starts and pauses through `ShowHost.setRunning`, which
                // commits first; a command here would skip the receipt.
                return .refuse(summary: "Use Start or Pause at the conductor.")
            }
            return .hold(summary: running ? "Start the show?" : "Pause the show?")
        }
    }

    private func move(to index: Int, on state: ShowSnapshot, by who: String) -> CommandDecision<ShowSnapshot> {
        let title = sheet.cues[index].title
        return .apply(
            state.with(cue: index, from: sheet, note: "\(who) moved to cue \(index + 1), \(title)."),
            summary: "Moved to cue \(index + 1), \(title)."
        )
    }
}
