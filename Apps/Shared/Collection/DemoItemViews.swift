import LabDomain
import SwiftUI

/// One demo sample in a list: title, note, revision, and an explicit "Archived" label.
struct DemoItemRow: View {
    let item: LabItem
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title.value)
                .font(.headline)
                .strikethrough(item.isArchived)
            if !item.note.value.isEmpty {
                Text(item.note.value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            // Side by side normally; stacked at accessibility sizes, so neither wraps mid-word.
            let metadata = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(spacing: 8))
            metadata {
                if item.isArchived {
                    Label("Archived", systemImage: "archivebox")
                        .labelStyle(.titleAndIcon)
                }
                Text("Revision \(item.revision.rawValue)")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        [item.title.value, item.isArchived ? "Archived" : nil, item.note.value.isEmpty ? nil : item.note.value,
         "Revision \(item.revision.rawValue)"]
            .compactMap(\.self).joined(separator: ", ")
    }
}

/// Archives or restores one sample through the operation service. The label says which.
struct ArchiveToggleButton: View {
    let item: LabItem
    @Environment(LabLibrary.self) private var library

    var body: some View {
        Button {
            Task {
                let result = await library.setArchived(item, !item.isArchived)
                LabAnnouncement.outcome(of: result, in: library)?.post()
            }
        } label: {
            if item.isArchived {
                Label("Restore Sample", systemImage: "arrow.uturn.backward")
            } else {
                Label("Archive Sample", systemImage: "archivebox")
            }
        }
        .disabled(!library.canAct)
        .accessibilityInputLabels(item.isArchived ? ["Restore Sample", "Restore"] : ["Archive Sample", "Archive"])
        .accessibilityHint(item.isArchived
            ? "Returns the sample to the collection. The receipt offers an undo."
            : "Hides the sample from normal view without deleting it. The receipt offers an undo.")
    }
}

/// Everything about one sample, with its archive action.
struct DemoItemDetailView: View {
    let itemID: ItemID
    @Environment(LabLibrary.self) private var library

    var body: some View {
        if let item = library.item(id: itemID) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title.value)
                            .font(.title2.weight(.semibold))
                        if !item.note.value.isEmpty {
                            Text(item.note.value)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 4)
                    #if os(macOS)
                    ArchiveToggleButton(item: item)
                    #endif
                }
                Section("Record") {
                    LabeledContent("Collection", value: library.collection(containing: item)?.title.value ?? "Unknown")
                    LabeledContent("Namespace", value: "Demo sample")
                    LabeledContent("Status", value: item.isArchived ? "Archived" : "Active")
                    LabeledContent("Revision", value: "\(item.revision.rawValue)")
                    LabeledContent("Identifier") {
                        Text(item.id.description)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                Section {
                    Text("Samples belong to the demo. Archiving one is a real change with a receipt; Reset Demo restores every sample to its original content.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(item.title.value)
            #if os(iOS)
            // Pinned, so a long note at a large text size never hides the action.
            .safeAreaInset(edge: .bottom) {
                PinnedActionBar {
                    ArchiveToggleButton(item: item)
                        .frame(maxWidth: .infinity)
                }
            }
            #endif
        } else {
            ContentUnavailableView(
                "Sample Not Found", systemImage: "questionmark.folder",
                description: Text("Reset Demo may have removed it.")
            )
        }
    }
}

/// The demo and user namespaces and how much each holds. The user namespace is only ever counted.
struct NamespaceSummary: View {
    @Environment(LabLibrary.self) private var library

    var body: some View {
        if let census = library.census {
            NamespaceRow(
                title: "Demo samples", symbol: "sparkles.rectangle.stack", count: census.demo,
                detail: "Created by Reset Demo from the bundled seed. Reset Demo restores or removes only these."
            )
            NamespaceRow(
                title: "Your data", symbol: "person.crop.rectangle.stack", count: census.user,
                detail: "Anything you create or import. Reset Demo never changes it. Creating and importing arrive with later experiments."
            )
        } else {
            Label("Counting…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        }
    }
}

private struct NamespaceRow: View {
    let title: String
    let symbol: String
    let count: NamespaceCount
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Text(tally)
                .monospacedDigit()
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var tally: String {
        var parts = [
            count.collections == 1 ? "1 collection" : "\(count.collections) collections",
            count.items == 1 ? "1 item" : "\(count.items) items",
        ]
        if count.archived > 0 { parts.append("\(count.archived) archived") }
        return parts.joined(separator: " · ")
    }
}
