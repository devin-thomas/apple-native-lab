import SurfaceDeck
import SwiftUI

/// The content column for the Surface Deck (LAB-004): the demo session, its toggle (⌘Return),
/// its receipts, which open in the inspector, and the privacy choice for widgets. The Mac has no
/// widget or Control extension; the detail column's previews are its fallback.
struct SurfaceDeckListColumn: View {
    @Bindable var window: MainWindowState
    @State private var model = SurfaceDeckModel.shared

    var body: some View {
        List {
            Section {
                SessionStateCard(model: model)
                SessionToggleButton(model: model)
                // A row, not a footer: a Mac list footer is one truncated line.
                SectionNote("Starting and pausing change only this demo state. Each change leaves a receipt with an undo, and Reset Demo pauses it. Shortcuts can run Set Demo Session and Open Surface Deck.")
            }
            SessionReceiptsSection(model: model) { window.inspect($0) }
            SurfacesSection(model: model)
        }
        .navigationTitle(SurfaceDeck.title)
        .navigationSplitViewColumnWidth(min: 300, ideal: 360)
        .task { await model.refresh() }
    }
}

/// The detail column: the widget and Control previews, drawn by the app and labeled as previews.
struct SurfaceDeckDetailColumn: View {
    @State private var model = SurfaceDeckModel.shared

    var body: some View {
        Form {
            Section {
                SurfacePreviewGallery(model: model)
            } header: {
                Text("Previews")
            } footer: {
                Text(SurfacePreviewGallery.caption(hasSurfaces: model.hasSurfaces))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
