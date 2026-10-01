import Foundation
import LabDomain
import PeerSession

/// What a show change at the conductor did.
public struct ShowOutcome: Hashable, Sendable {
    /// The answer the peer received, when a peer asked.
    public let result: CommandResult?
    /// The operation service's receipt, when something was committed or a conflict recorded.
    public let receipt: ActionReceipt?
    public let message: String
}

/// The conductor's side of the show: a `Conductor` with the show's rules, and the path by which a
/// held request reaches the host's operation service.
public actor ShowHost {
    public nonisolated let conductor: Conductor<Constellation>
    public nonisolated let sheet: CueSheet
    private let backend: any ShowSessionBackend

    /// Opens the show at the first cue, running only if the stored session runs.
    public init(
        configuration: Conductor<Constellation>.Configuration,
        sheet: CueSheet,
        backend: any ShowSessionBackend
    ) async {
        self.sheet = sheet
        self.backend = backend
        let session = try? await backend.showSession()
        let rules = ShowRules(sheet: sheet)
        conductor = Conductor(
            configuration: configuration,
            initialState: sheet.openingSnapshot(session: session),
            decide: { rules.decide($0, on: $1, from: $2) }
        )
    }

    /// Allows a held start or pause: commits it as the authorized peer with a grant for this
    /// change alone, then answers the peer with the receipt's result.
    public func allow(_ id: MessageID) async -> ShowOutcome {
        guard let held = await conductor.state.pending.first(where: { $0.commandID == id }) else {
            return ShowOutcome(result: nil, receipt: nil, message: "That request is no longer waiting.")
        }
        let running = held.command == .start
        let approval = PeerApproval(peer: held.from, commandID: id)
        let session: LabSession?
        do {
            session = try await backend.showSession()
        } catch {
            let result = await conductor.resolve(id) { _ in .refuse(summary: error.message) }
            return ShowOutcome(result: result, receipt: nil, message: error.message)
        }
        let operation = DomainOperation.setSession(id: LocalConstellation.showSessionID, expected: session?.revision, running: running)
        let receipt: ActionReceipt
        do {
            receipt = try await backend.commit(operation, requestID: approval.requestID, authority: .allowedPeer(approval))
        } catch .refused(.ruleViolation(.noChanges)) {
            let stored = try? await backend.showSession()
            let result = await conductor.resolve(id) { state in
                .apply(
                    state.with(running: running, sessionRevision: stored?.revision.rawValue, note: state.note),
                    summary: running ? "The show is already running." : "The show is already paused."
                )
            }
            return ShowOutcome(result: result, receipt: nil, message: result?.summary ?? "")
        } catch {
            let result = await conductor.resolve(id) { _ in .refuse(summary: error.message) }
            await syncFromStore()
            return ShowOutcome(result: result, receipt: nil, message: error.message)
        }
        if receipt.conflict != nil {
            let result = await conductor.resolve(id) { _ in
                .refuse(summary: "The show changed at the conductor first. Nothing changed.")
            }
            await syncFromStore()
            return ShowOutcome(result: result, receipt: receipt, message: result?.summary ?? "")
        }
        let revision = receipt.changes.first?.newRevision.rawValue
        let verb = running ? "Started" : "Paused"
        let note = "\(verb) at \(held.from.name)'s request, allowed at the conductor."
        let result = await conductor.resolve(id) { state in
            .apply(state.with(running: running, sessionRevision: revision, note: note), summary: "\(verb) the show. \(receipt.summary)")
        }
        return ShowOutcome(result: result, receipt: receipt, message: note)
    }

    /// Declines a held request. Nothing is committed.
    public func decline(_ id: MessageID) async -> ShowOutcome {
        let result = await conductor.resolve(id) { _ in .refuse(summary: "The person at the conductor declined. Nothing changed.") }
        return ShowOutcome(result: result, receipt: nil, message: "Declined.")
    }

    /// Starts or pauses the show for the person at the conductor, through the app-UI adapter.
    public func setRunning(_ running: Bool, requestID: RequestID = RequestID()) async -> ShowOutcome {
        let session: LabSession?
        do { session = try await backend.showSession() } catch {
            return ShowOutcome(result: nil, receipt: nil, message: error.message)
        }
        guard (session?.isRunning ?? false) != running else {
            await syncFromStore()
            return ShowOutcome(result: nil, receipt: nil, message: running ? "The show is already running." : "The show is already paused.")
        }
        let operation = DomainOperation.setSession(id: LocalConstellation.showSessionID, expected: session?.revision, running: running)
        let receipt: ActionReceipt
        do {
            receipt = try await backend.commit(operation, requestID: requestID, authority: .conductorPerson)
        } catch {
            await syncFromStore()
            return ShowOutcome(result: nil, receipt: nil, message: error.message)
        }
        await syncFromStore(note: running ? "The conductor started the show." : "The conductor paused the show.")
        return ShowOutcome(result: nil, receipt: receipt, message: receipt.summary)
    }

    /// Moves between cues for the person at the conductor, through the same rules as a peer.
    public func move(_ command: ShowCommand) async -> CommandResult {
        await conductor.perform(command)
    }

    /// Brings the show's running flag in line with the store, after another entry point changed
    /// it (Reset Demo, a receipt's undo, or the conductor's own Start and Pause).
    public func syncFromStore(note: String? = nil) async {
        let session: LabSession?
        do { session = try await backend.showSession() } catch { return }
        let running = session?.isRunning ?? false
        let revision = session?.revision.rawValue
        await conductor.update { state in
            guard state.isRunning != running || state.sessionRevision != revision else { return nil }
            return state.with(running: running, sessionRevision: revision, note: note ?? "The show's stored state changed.")
        }
    }
}
