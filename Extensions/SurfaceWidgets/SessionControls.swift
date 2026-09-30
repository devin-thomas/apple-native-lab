import SurfaceDeck
import SwiftUI
import WidgetKit

/// The Control's value: the snapshot as read when the system asks. A missing or unusable
/// snapshot gives the placeholder, whose toggle only shows the current state.
struct SessionControlProvider: ControlValueProvider {
    var previewValue: SurfacePresentation { .placeholder }

    func currentValue() async throws -> SurfacePresentation {
        let now = Date.now
        return SurfacePresentation(reading: SessionSnapshotFile.currentReading(), confirmedAt: now, now: now)
    }
}

/// Starts or pauses the demo session from Control Center, the Lock Screen, or the Action button.
struct SessionToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SurfaceDeck.toggleControlKind, provider: SessionControlProvider()) { presentation in
            ControlWidgetToggle(
                isOn: presentation.isOn,
                action: SetDemoSessionIntent(showing: presentation.state, surface: .control)
            ) {
                Label(SurfaceDeck.sessionName, systemImage: presentation.symbolName)
            } valueLabel: { isOn in
                Text(presentation.state == nil ? "Open Native Lab" : (isOn ? "Running" : "Paused"))
            }
        }
        .displayName("Demo Session")
        .description("Starts or pauses Native Lab's demo session. Each change leaves a receipt in the app.")
    }
}

/// The launch action: opens Native Lab at the Surface Deck.
struct OpenSurfaceDeckControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SurfaceDeck.openControlKind) {
            ControlWidgetButton(action: OpenSurfaceDeckIntent()) {
                Label("Surface Deck", systemImage: SurfaceDeck.symbol)
            }
        }
        .displayName("Open Surface Deck")
        .description("Opens Native Lab at the Surface Deck.")
    }
}
