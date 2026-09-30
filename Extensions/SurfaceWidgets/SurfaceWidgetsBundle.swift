import AppIntents
import SurfaceDeck
import SwiftUI
import WidgetKit

/// The SystemSurfaces widget extension (LAB-004 Surface Deck): one widget and two Controls, all
/// drawn from the snapshot the app writes into the App Group. The extension never opens the store,
/// never composes an operation service, and never runs a model. Embedded only by LabPhoneSurfaces.
@main
struct SurfaceWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SessionWidget()
        SessionToggleControl()
        OpenSurfaceDeckControl()
    }
}

/// Includes Surface Deck's intents in this extension's App Intents metadata, so the widget's
/// toggle and the Controls can name them. Their `perform()` runs in the app: the toggle is a
/// `LiveActivityIntent` and the launch action an `OpenIntent`.
struct SurfaceWidgetsIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [SurfaceDeckIntentsPackage.self] }
}

extension SessionSnapshotFile {
    /// The snapshot as this extension sees it now. No App Group, no file: the placeholder.
    static func currentReading() -> SnapshotReading {
        SessionSnapshotFile.shared()?.read() ?? .missing
    }
}
