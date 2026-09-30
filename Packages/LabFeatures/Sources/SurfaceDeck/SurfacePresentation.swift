import Foundation

/// What a widget, a Control, or an in-app preview shows for one snapshot reading.
///
/// Surfaces never guess. A missing or unreadable snapshot shows a placeholder that states no
/// session state and offers no toggle that changes anything. A snapshot older than `staleAfter`
/// since a surface last confirmed it says it may be out of date. Details stay hidden unless the
/// snapshot carries them, and a surface also marks them privacy-sensitive, so the system can hide
/// them on a locked device.
public struct SurfacePresentation: Hashable, Sendable {
    public enum Availability: String, Hashable, Sendable {
        /// Read from a snapshot the surface confirmed recently.
        case current
        /// Read from a snapshot, but the surface has not confirmed it within `staleAfter`,
        /// for example because the system declined a reload.
        case stale
        /// No usable snapshot. The surface shows a placeholder.
        case unavailable
    }

    /// How long a surface trusts a snapshot after reading it. The widget's timeline asks for one
    /// refresh at this point and shows the stale entry only if that refresh does not come.
    public static let staleAfter: TimeInterval = 60 * 60

    public let availability: Availability
    /// The state shown, or `nil` for the placeholder.
    public let state: SessionState?
    /// When the snapshot was written, for "as of" text.
    public let writtenAt: Date?
    /// Where and when the last change was made, only when the person chose to show details.
    public let detail: SnapshotDetail?

    public init(reading: SnapshotReading, confirmedAt: Date, now: Date) {
        switch reading {
        case .snapshot(let snapshot):
            availability = now.timeIntervalSince(confirmedAt) >= Self.staleAfter ? .stale : .current
            state = snapshot.state
            writtenAt = snapshot.writtenAt
            detail = snapshot.detail
        case .missing, .unreadable:
            availability = .unavailable
            state = nil
            writtenAt = nil
            detail = nil
        }
    }

    /// The placeholder, as a surface shows it before any snapshot exists.
    public static let placeholder = SurfacePresentation(reading: .missing, confirmedAt: .distantPast, now: .distantPast)

    /// Whether a toggle shows on. The placeholder shows off.
    public var isOn: Bool { state?.isRunning ?? false }

    /// What a toggle built from this presentation tells the intent it saw.
    public var seen: SeenRevision { state?.seen ?? .unknown }

    public var isRedacted: Bool { detail == nil }

    /// "Running", "Paused", or "Not available".
    public var stateTitle: String { state?.title ?? "Not available" }

    public var symbolName: String {
        switch state?.isRunning {
        case true?: "play.circle.fill"
        case false?: "pause.circle"
        case nil: "questionmark.circle"
        }
    }

    /// One short line under the state: what to do for the placeholder, or a stale warning.
    public var statusText: String {
        switch availability {
        case .current: isRedacted ? "Details hidden" : "Details shown"
        case .stale: "May be out of date"
        case .unavailable: "Open Native Lab"
        }
    }

    /// The private detail as a sentence, or `nil` when it is hidden.
    public var detailText: String? {
        detail.map { "Changed from \($0.changedFrom.title)" }
    }

    /// One sentence for VoiceOver, without the private detail when it is hidden.
    public var accessibilityLabel: String {
        switch availability {
        case .current: "\(SurfaceDeck.sessionName), \(stateTitle)."
        case .stale: "\(SurfaceDeck.sessionName), \(stateTitle), may be out of date."
        case .unavailable: "\(SurfaceDeck.sessionName) not available. Open Native Lab to show it."
        }
    }
}

/// The widget's refresh policy as plain values, so it can be tested without WidgetKit.
///
/// A timeline holds the snapshot as read now and the same snapshot marked stale at `staleAfter`,
/// and asks for one refresh at that moment. If the system grants the refresh, the stale entry never
/// shows; if it declines, the widget says it may be out of date instead of looking current. The app
/// asks for a reload only when the snapshot changes, so there is no timer and no polling.
public struct SessionTimeline: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public let date: Date
        public let presentation: SurfacePresentation
    }

    public let entries: [Entry]
    /// When the widget asks WidgetKit for its next timeline.
    public let refreshAfter: Date

    public init(reading: SnapshotReading, now: Date) {
        let staleAt = now.addingTimeInterval(SurfacePresentation.staleAfter)
        entries = [
            Entry(date: now, presentation: SurfacePresentation(reading: reading, confirmedAt: now, now: now)),
            Entry(date: staleAt, presentation: SurfacePresentation(reading: reading, confirmedAt: now, now: staleAt)),
        ]
        refreshAfter = staleAt
    }
}
