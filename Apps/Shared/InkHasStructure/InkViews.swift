import InkHasStructure
import LabDomain
import SwiftUI

/// Shared controls and status for Ink Has Structure on Mac and iPhone.
struct InkWorkbench: View {
    @Bindable var session: InkSession
    let onSave: () -> Void
    var usesPencilKitInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if session.document == nil {
                ContentUnavailableView {
                    Label("No annotation open", systemImage: InkHasStructureExperiment.symbol)
                } description: {
                    Text("Open the sample harbor chart to draw or type a note.")
                } actions: {
                    Button("Open Harbor Chart") { Task { await session.openSample() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                canvasSection
                tools
                typedNote
                actions
                status
            }
            capabilityNote
        }
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let document = session.document {
                Text("\(document.mediaTitle) · \(Int(document.size.width))×\(Int(document.size.height)) · document \(document.documentID.uuidString.prefix(8))…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            AnnotationCanvas(session: session, showsPencilKit: usesPencilKitInput)
                .frame(minHeight: 220)
        }
    }

    private var tools: some View {
        HStack {
            Picker("Tool", selection: $session.tool) {
                ForEach(InkTool.allCases, id: \.self) { tool in
                    Text(tool.title).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            Spacer(minLength: 0)
        }
        .accessibilityLabel("Drawing tool")
    }

    private var typedNote: some View {
        HStack {
            TextField("Typed note (semantic alternative)", text: $session.noteDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await session.addTypedNote() } }
            Button("Add Note") { Task { await session.addTypedNote() } }
                .disabled(session.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Undo", systemImage: "arrow.uturn.backward") { Task { await session.undo() } }
                    .disabled(!session.canUndo)
                Button("Erase Last Stroke", systemImage: "eraser") { Task { await session.eraseLastStroke() } }
                    .disabled(session.document?.layer.strokes.isEmpty != false)
                Button("Larger", systemImage: "plus.magnifyingglass") { Task { await session.resize(scale: 1.25) } }
                    .disabled(session.document == nil)
                Button("Smaller", systemImage: "minus.magnifyingglass") { Task { await session.resize(scale: 0.8) } }
                    .disabled(session.document == nil)
            }
            HStack {
                Button("Export Flattened Preview", systemImage: "doc.plaintext") { session.exportPreview() }
                    .disabled(session.document == nil)
                Button("Save Annotation", systemImage: "square.and.arrow.down") { onSave() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.canSave)
                Button("Reset Demo", systemImage: "arrow.counterclockwise") { Task { await session.resetDemo() } }
            }
        }
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder private var status: some View {
        if let message = session.message {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        if let preview = session.previewText {
            DisclosureGroup("Flattened preview (not editable ink)") {
                Text(preview)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if let record = session.lastReceipt {
            NavigationLink {
                ReceiptDetailView(record: record)
                    .navigationTitle("Receipt")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            } label: {
                ReceiptRow(record: record)
            }
        }
    }

    private var capabilityNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fallback: \(session.capability.fallbackSummary)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !session.capability.unsupportedPencilGestures.isEmpty {
                Text("Absent (not broken): \(session.capability.unsupportedPencilGestures.joined(separator: ", ")).")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if !session.capability.pencilKitCanvasAvailable {
                Text(InkError.drawingSurfaceUnavailable.message)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
