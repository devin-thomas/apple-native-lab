import Foundation
import LabDomain

/// LAB-004 Surface Deck: one reversible demo session that the app, a widget, and a Control show.
///
/// The session changes only through `OperationService` (`DomainOperation.setSession`), with a
/// receipt and an undo. The app writes an immutable, redacted-by-default `SessionSnapshot` after
/// each change; the widget and the Control read only that snapshot. They never open the store and
/// never run a model.
public enum SurfaceDeck {
    public static let experimentID = "LAB-004"
    public static let title = "Surface Deck"
    public static let symbol = "rectangle.3.group"

    /// The one session the deck, its widget, and its Control show. Fixed, so every surface and
    /// every launch name the same session.
    public static let sessionID = SessionID(rawValue: UUID(uuidString: "9B54BD13-C217-4447-BF24-6664727C367A")!)

    /// WidgetKit kinds. The host reloads these only when the snapshot changes.
    public static let widgetKind = "SurfaceDeckSessionWidget"
    public static let toggleControlKind = "SurfaceDeckSessionToggle"
    public static let openControlKind = "SurfaceDeckOpen"

    /// A name for the session in receipts and on surfaces.
    public static let sessionName = "Demo session"
}

/// The state every surface shows: running or paused, and the revision it was read at.
public struct SessionState: Hashable, Sendable, Codable {
    public let isRunning: Bool
    /// The session's revision, or `nil` when it was never started (it then reads as paused).
    public let revision: Int?

    public init(isRunning: Bool, revision: Int?) {
        self.isRunning = isRunning
        self.revision = revision
    }

    /// The state of a stored session, or of one never started when `session` is `nil`.
    public init(_ session: LabSession?) {
        isRunning = session?.isRunning ?? false
        revision = session?.revision.rawValue
    }

    public static let neverStarted = SessionState(isRunning: false, revision: nil)

    public var title: String { isRunning ? "Running" : "Paused" }

    /// What a surface that showed this state saw, for a toggle it offers.
    public var seen: SeenRevision {
        revision.flatMap(Revision.init(rawValue:)).map(SeenRevision.revision) ?? .neverStarted
    }
}

/// Where a change was asked for. Display only: it labels the receipt line and the snapshot's
/// detail. It never chooses an adapter or a permission; the adapter is fixed by wiring (ADR-011).
public enum SessionSurface: String, Hashable, Sendable, Codable, CaseIterable {
    case app
    case widget
    case control
    case shortcuts

    public var title: String {
        switch self {
        case .app: "Native Lab"
        case .widget: "the widget"
        case .control: "Control Center"
        case .shortcuts: "Shortcuts"
        }
    }
}

/// What revision a surface saw when it offered a toggle.
///
/// A toggle carries it so a stale surface reconciles instead of overwriting a newer change: the
/// service answers a stale revision with a conflict receipt and changes nothing.
public enum SeenRevision: Hashable, Sendable {
    /// No surface state was involved, as when Shortcuts sets a value: apply it to what is current.
    case unspecified
    /// The surface had no usable snapshot. Only show the current state; change nothing.
    case unknown
    /// The surface showed a session that was never started.
    case neverStarted
    case revision(Revision)

    /// The intent parameter's encoding: `nil` unspecified, a negative number unknown, `0` never
    /// started, and a positive number a revision.
    public init(parameter: Int?) {
        switch parameter {
        case nil: self = .unspecified
        case let value? where value < 0: self = .unknown
        case 0?: self = .neverStarted
        case let value?: self = Revision(rawValue: value).map(SeenRevision.revision) ?? .unknown
        }
    }

    public var parameter: Int? {
        switch self {
        case .unspecified: nil
        case .unknown: -1
        case .neverStarted: 0
        case .revision(let revision): revision.rawValue
        }
    }
}
