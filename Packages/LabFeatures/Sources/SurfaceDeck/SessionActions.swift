import Foundation
import LabDomain

/// Where a session request arrived. The host maps it to an adapter kind (ADR-011).
public enum SessionEntryPoint: String, Hashable, Sendable, CaseIterable {
    /// The deck in the app, where a person presses a control.
    case appUI = "app-ui"
    /// An App Intent the system ran: the Control, the widget's toggle, or Shortcuts.
    case appIntent = "app-intent"

    public var adapter: AdapterKind {
        switch self {
        case .appUI: .appUI
        case .appIntent: .appIntent
        }
    }
}

/// What the deck and its intents need from the host: the session read and the commit, both
/// through the host's own `OperationService`, under the adapter the entry point names.
///
/// The host implements this with the same data service its views use, so the Control, the
/// widget's toggle, Shortcuts, and the deck take one path to the store. Nothing here holds the
/// store, and nothing here runs in the widget extension.
public protocol SessionBackend: Sendable {
    func session(via entryPoint: SessionEntryPoint) async throws(SurfaceDeckError) -> LabSession?

    /// Commits one request and returns its receipt. `surface` labels where it was asked for.
    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        via entryPoint: SessionEntryPoint,
        surface: SessionSurface
    ) async throws(SurfaceDeckError) -> ActionReceipt

    /// Called after every request, including one that changed nothing, so the host can rewrite
    /// the snapshot and bring stale surfaces back to the current state.
    func didSettle(_ outcome: SessionOutcome, surface: SessionSurface) async
}

/// Why a session request did not complete. Each case changed nothing.
public enum SurfaceDeckError: Error, Hashable, Sendable {
    /// The app's store cannot be used right now.
    case unavailable(reason: String)
    /// The operation service refused the request.
    case refused(OperationError)
    /// The request was cancelled before anything was committed.
    case cancelled

    public var message: String {
        switch self {
        case .unavailable(let reason):
            reason
        case .refused(.unauthorized):
            "This entry point is not allowed to change the demo session. Nothing was changed."
        case .refused(.storeFailure):
            "Native Lab could not read or save its data. Nothing was changed. Try again."
        case .refused:
            "The demo session could not be changed. Nothing was changed."
        case .cancelled:
            "Cancelled. Nothing was changed."
        }
    }
}

extension SurfaceDeckError: LocalizedError, CustomLocalizedStringResourceConvertible {
    public var errorDescription: String? { message }

    public var localizedStringResource: LocalizedStringResource { "\(message)" }
}

/// The result of one request to start or pause the session.
public enum SessionOutcome: Hashable, Sendable {
    /// The session changed. The receipt offers the opposite change as its undo.
    case changed(ActionReceipt, SessionState)
    /// The surface was out of date. The service recorded a conflict receipt and changed nothing.
    case conflict(ActionReceipt, SessionState)
    /// The surface was out of date in a way the service refuses before a receipt: it saw no
    /// session when one now exists. Nothing changed.
    case stale(SessionState)
    /// The session was already in the requested state.
    case unchanged(SessionState)
    /// The surface had no usable snapshot, so the request only showed the current state.
    case reconciled(SessionState)

    public var state: SessionState {
        switch self {
        case .changed(_, let state), .conflict(_, let state), .stale(let state), .unchanged(let state), .reconciled(let state):
            state
        }
    }

    public var receipt: ActionReceipt? {
        switch self {
        case .changed(let receipt, _), .conflict(let receipt, _): receipt
        case .stale, .unchanged, .reconciled: nil
        }
    }

    public var didChange: Bool {
        if case .changed = self { true } else { false }
    }

    /// The sentence the system or the deck shows.
    public var message: String {
        let now = state.title.lowercased()
        return switch self {
        case .changed(let receipt, _):
            receipt.undo == nil ? receipt.summary : "\(receipt.summary) Its receipt in Native Lab offers an undo."
        case .conflict, .stale:
            "The demo session changed since this was shown. It is \(now). Nothing was changed."
        case .unchanged:
            "The demo session is already \(now)."
        case .reconciled:
            "The demo session is \(now)."
        }
    }
}

/// Starting and pausing the session, shared by the deck and the App Intents.
///
/// Every change is one `setSession` request through the backend, so it is authorized, recorded
/// with a receipt, and reversible. A surface passes the revision it showed; if the session moved
/// since, the service answers with a conflict and the surface reconciles to what is current.
public struct SessionActions: Sendable {
    public let backend: any SessionBackend
    public let entryPoint: SessionEntryPoint

    public init(backend: any SessionBackend, entryPoint: SessionEntryPoint) {
        self.backend = backend
        self.entryPoint = entryPoint
    }

    public func current() async throws(SurfaceDeckError) -> SessionState {
        SessionState(try await backend.session(via: entryPoint))
    }

    /// Asks for the session to be running or paused, as a surface that saw `seen`.
    public func setRunning(
        _ running: Bool,
        seen: SeenRevision,
        surface: SessionSurface,
        requestID: RequestID = RequestID()
    ) async throws(SurfaceDeckError) -> SessionOutcome {
        let outcome = try await decide(running, seen: seen, surface: surface, requestID: requestID)
        await backend.didSettle(outcome, surface: surface)
        return outcome
    }

    private func decide(
        _ running: Bool,
        seen: SeenRevision,
        surface: SessionSurface,
        requestID: RequestID
    ) async throws(SurfaceDeckError) -> SessionOutcome {
        let expected: Revision?
        switch seen {
        case .unknown:
            return .reconciled(try await current())
        case .unspecified:
            let session = try await backend.session(via: entryPoint)
            guard (session?.isRunning ?? false) != running else { return .unchanged(SessionState(session)) }
            expected = session?.revision
        case .neverStarted:
            expected = nil
        case .revision(let revision):
            expected = revision
        }
        let operation = DomainOperation.setSession(id: SurfaceDeck.sessionID, expected: expected, running: running)
        // The last point at which cancelling leaves nothing behind; after it the commit runs whole.
        guard !Task.isCancelled else { throw .cancelled }
        let receipt: ActionReceipt
        do {
            receipt = try await backend.commit(operation, requestID: requestID, via: entryPoint, surface: surface)
        } catch .refused(.ruleViolation(.noChanges)) {
            return .unchanged(try await current())
        } catch .refused(.ruleViolation(.alreadyExists)), .refused(.notFound) {
            return .stale(try await current())
        }
        let state = try await current()
        return receipt.conflict == nil ? .changed(receipt, state) : .conflict(receipt, state)
    }
}

/// The handle App Intents receive through `AppDependencyManager`. The host registers one at
/// launch; until then intents use `unavailable`, which refuses with a readable reason.
public final class SurfaceDeckLink: Sendable {
    public let backend: any SessionBackend
    private let openDeck: @MainActor @Sendable () -> Void

    public init(backend: any SessionBackend, openDeck: @escaping @MainActor @Sendable () -> Void) {
        self.backend = backend
        self.openDeck = openDeck
    }

    public func actions(_ entryPoint: SessionEntryPoint) -> SessionActions {
        SessionActions(backend: backend, entryPoint: entryPoint)
    }

    @MainActor
    public func open() {
        openDeck()
    }

    public static let unavailable = SurfaceDeckLink(
        backend: UnavailableSessionBackend(
            reason: "Native Lab has not opened its store yet. Open Native Lab and try again."
        ),
        openDeck: {}
    )
}

/// A backend that refuses everything with one reason: the unavailable path.
public struct UnavailableSessionBackend: SessionBackend {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public func session(via entryPoint: SessionEntryPoint) async throws(SurfaceDeckError) -> LabSession? {
        throw .unavailable(reason: reason)
    }

    public func commit(
        _ operation: DomainOperation, requestID: RequestID, via entryPoint: SessionEntryPoint, surface: SessionSurface
    ) async throws(SurfaceDeckError) -> ActionReceipt {
        throw .unavailable(reason: reason)
    }

    public func didSettle(_ outcome: SessionOutcome, surface: SessionSurface) async {}
}
