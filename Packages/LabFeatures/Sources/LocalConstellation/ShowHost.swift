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
    /// Why the conductor would not let the request be allowed or declined, when it would not.
    public var refusal: HeldCommandRefusal? = nil
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
    ///
    /// The conductor takes the request before anything is committed and checks that the device
    /// that asked is still paired, so an Allow for a forgotten or unknown device, a second Allow,
    /// or an Allow pressed on a request the screen still showed is refused with its reason, and
    /// nothing is committed (`settle`).
    public func allow(_ id: MessageID) async -> ShowOutcome {
        let backend = self.backend
        let settled = await conductor.settle(id) { held in
            await Self.commit(held, backend: backend)
        }
        switch settled {
        case .failure(let refusal):
            return ShowOutcome(result: nil, receipt: nil, message: refusal.explanation, refusal: refusal)
        case .success(let settled):
            if settled.extra.resynchronize { await syncFromStore() }
            return ShowOutcome(result: settled.result, receipt: settled.extra.receipt, message: settled.extra.message ?? settled.result.summary)
        }
    }

    /// What an allowed request's commit did, for `allow` to report.
    private struct Committed: Sendable {
        var receipt: ActionReceipt?
        var message: String?
        var resynchronize = false
    }

    /// Commits an allowed request through the backend and returns the decision for the
    /// conductor's state. Runs only after the conductor took the request and found its peer paired.
    private static func commit(_ held: PendingCommand<ShowCommand>, backend: any ShowSessionBackend) async -> HeldDecision<ShowSnapshot, Committed> {
        let running = held.command == .start
        let approval = PeerApproval(peer: held.from, commandID: held.commandID)
        let session: LabSession?
        do {
            session = try await backend.showSession()
        } catch {
            return HeldDecision(extra: Committed(message: error.message)) { _ in .refuse(summary: error.message) }
        }
        let operation = DomainOperation.setSession(id: LocalConstellation.showSessionID, expected: session?.revision, running: running)
        let receipt: ActionReceipt
        do {
            receipt = try await backend.commit(operation, requestID: approval.requestID, authority: .allowedPeer(approval))
        } catch .refused(.ruleViolation(.noChanges)) {
            let stored = try? await backend.showSession()
            return HeldDecision(extra: Committed()) { state in
                .apply(
                    state.with(running: running, sessionRevision: stored?.revision.rawValue, note: state.note),
                    summary: running ? "The show is already running." : "The show is already paused."
                )
            }
        } catch {
            return HeldDecision(extra: Committed(message: error.message, resynchronize: true)) { _ in .refuse(summary: error.message) }
        }
        if receipt.conflict != nil {
            return HeldDecision(extra: Committed(receipt: receipt, resynchronize: true)) { _ in
                .refuse(summary: "The show changed at the conductor first. Nothing changed.")
            }
        }
        let revision = receipt.changes.first?.newRevision.rawValue
        let verb = running ? "Started" : "Paused"
        let note = "\(verb) at \(held.from.name)'s request, allowed at the conductor."
        return HeldDecision(extra: Committed(receipt: receipt, message: note)) { state in
            .apply(state.with(running: running, sessionRevision: revision, note: note), summary: "\(verb) the show. \(receipt.summary)")
        }
    }

    /// Declines a held request. Nothing is committed.
    public func decline(_ id: MessageID) async -> ShowOutcome {
        let result = await conductor.resolve(id) { _ in .refuse(summary: "The person at the conductor declined. Nothing changed.") }
        guard let result else {
            return ShowOutcome(result: nil, receipt: nil, message: HeldCommandRefusal.notWaiting.explanation, refusal: .notWaiting)
        }
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
