import InkHasStructure
import SwiftUI

/// Mac list column: task summary and working-document status.
struct InkHasStructureListColumn: View {
    @Bindable var window: MainWindowState
    @Bindable var session: InkSession

    var body: some View {
        List {
            Section("Task") {
                Text("Annotate the harbor chart and keep the ink as editable data. Save commits through the same receipt path as every other lab change.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Working document") {
                if let document = session.document {
                    LabeledContent("Media", value: document.mediaTitle)
                    LabeledContent("Size", value: "\(Int(document.size.width))×\(Int(document.size.height))")
                    LabeledContent("Strokes", value: "\(document.layer.strokes.count)")
                    LabeledContent("Notes", value: "\(document.notes.count)")
                    LabeledContent("Document ID", value: String(document.documentID.uuidString.prefix(8)) + "…")
                } else {
                    Text("No annotation open.")
                        .foregroundStyle(.secondary)
                    Button("Open Harbor Chart") { Task { await session.openSample() } }
                }
            }
            Section("Fallback") {
                Text(session.capability.fallbackSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(InkHasStructureExperiment.title)
        .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        .task {
            if session.document == nil { await session.openSample() }
        }
    }
}

/// Mac detail column: the canvas and controls. Saves open the receipt inspector.
struct InkHasStructureDetailColumn: View {
    @Bindable var window: MainWindowState
    @Bindable var session: InkSession
    @Environment(LabLibrary.self) private var library

    var body: some View {
        ScrollView {
            InkWorkbench(session: session, onSave: save, usesPencilKitInput: false)
                .padding(20)
        }
        .navigationTitle(session.document?.mediaTitle ?? InkHasStructureExperiment.title)
    }

    private func save() {
        Task {
            if let record = await session.save(in: library) {
                window.inspect(record)
            }
        }
    }
}
