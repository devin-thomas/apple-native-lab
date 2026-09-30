import Foundation
import SurfaceDeck
#if LAB_PROFILE_SYSTEM_SURFACES && canImport(WidgetKit) && os(iOS)
import WidgetKit
#endif

/// What happened to the snapshot the last time the deck published it.
enum SnapshotPublication: Hashable, Sendable {
    /// This build has no App Group, so there is no widget or Control to write for. CoreLocal.
    case noSurfaces
    /// The snapshot file was written, and WidgetKit was asked to reload when it changed.
    case written(at: Date, reloaded: Bool)
    /// The file already held this state. Nothing was written or reloaded.
    case unchanged
    /// The file could not be written. The surfaces keep showing the previous snapshot.
    case failed
}

/// Writes the session snapshot for the widget and the Control, and asks WidgetKit to reload them
/// only when what they show would change.
///
/// Only a SystemSurfaces build has an App Group and links WidgetKit. A CoreLocal build has neither:
/// `file` is `nil`, publishing reports `noSurfaces`, and the deck's in-app previews are the
/// fallback.
struct SnapshotPublisher: Sendable {
    let file: SessionSnapshotFile?
    let reloadSurfaces: @MainActor @Sendable () -> Void

    /// The snapshot file in this build's App Group, and WidgetKit reloads when the build has them.
    static func live() -> SnapshotPublisher {
        SnapshotPublisher(file: SessionSnapshotFile.shared(), reloadSurfaces: reloadWidgetKit)
    }

    /// Publishes `snapshot`. With `force`, reloads the surfaces even when the file already holds
    /// the same state: a surface that acted on a stale state must redraw from the current one.
    @MainActor
    func publish(_ snapshot: SessionSnapshot, force: Bool = false) -> SnapshotPublication {
        guard let file else { return .noSurfaces }
        let existing: SessionSnapshot? = if case .snapshot(let stored) = file.read() { stored } else { nil }
        let changed = snapshot.differs(from: existing)
        guard changed || force else { return .unchanged }
        if changed {
            do { try file.write(snapshot) } catch { return .failed }
        }
        reloadSurfaces()
        return .written(at: changed ? snapshot.writtenAt : existing?.writtenAt ?? snapshot.writtenAt, reloaded: true)
    }

    /// Asks WidgetKit to reload the widget and the toggle Control. Reloads are requested only for
    /// a change or a stale surface's request, never on a timer.
    @MainActor
    static func reloadWidgetKit() {
        #if LAB_PROFILE_SYSTEM_SURFACES && canImport(WidgetKit) && os(iOS)
        WidgetCenter.shared.reloadTimelines(ofKind: SurfaceDeck.widgetKind)
        ControlCenter.shared.reloadControls(ofKind: SurfaceDeck.toggleControlKind)
        #endif
    }

    /// Whether this build carries the widget and the Control.
    var hasSurfaces: Bool { file != nil }
}
