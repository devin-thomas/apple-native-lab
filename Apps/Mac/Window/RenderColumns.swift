import RenderThatSurvives
import SwiftUI

/// The content column for Render That Survives (LAB-032): the recipe and Render (⌘Return), the
/// jobs with Pause, Resume, and Cancel (Escape while running), and this session's receipts, which
/// open in the inspector. The Mac worker runs while Native Lab is open; quitting stops a render at
/// once, and the next launch shows it stopped and resumable.
struct RenderListColumn: View {
    @Bindable var window: MainWindowState
    @State private var model = RenderStudioModel.shared

    var body: some View {
        List {
            RenderControlsSection(model: model)
            RenderJobsSection(model: model)
            RenderReceiptsSection(model: model) { window.inspect($0) }
        }
        .navigationTitle(RenderThatSurvives.title)
        .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        .task { await model.refresh() }
    }
}

/// The detail column: the published movie, its digest, and a player.
struct RenderDetailColumn: View {
    @State private var model = RenderStudioModel.shared

    var body: some View {
        Form {
            RenderOutputSection(model: model, showsPlayer: true)
        }
        .formStyle(.grouped)
    }
}
