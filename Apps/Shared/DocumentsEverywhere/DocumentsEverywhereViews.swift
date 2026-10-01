import DocumentsEverywhere
import LabDomain
import SwiftUI

/// Where Documents Everywhere is described in the catalog.
enum DocumentsEverywhereModule {
    static let experimentID = "LAB-009"
    static let summary = "In this build: the document browser lists original sample .anlab files and shows the same preview Quick Look uses, without activating the File Provider. Adopting a sample into the lab goes through Portable Objects' importer and the operation service. The sample provider stays disabled until it is qualified."
}

// MARK: - Browser

struct DocumentsEverywhereRow: View {
    let entry: DocumentsEverywhereSession.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.sample.displayName)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.sample.displayName), \(detail)")
    }

    private var detail: String {
        [
            entry.item.filename,
            "Revision \(entry.item.revision.content)",
            entry.item.byteCount.map { "\($0) bytes" },
        ]
        .compactMap(\.self).joined(separator: " · ")
    }
}

struct DocumentsEverywherePreviewPane: View {
    let preview: DocumentPreview?
    let providerMessage: String
    let outcome: DocumentsEverywhereSession.Outcome?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let preview {
                    Text(preview.title)
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)
                    Text(preview.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(preview.plainText)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ContentUnavailableView(
                        "Select a Sample",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Previews use the same builder as Quick Look and need no File Provider.")
                    )
                }

                Label(providerMessage, systemImage: "externaldrive.badge.xmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let outcome {
                    outcomeBanner(outcome)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func outcomeBanner(_ outcome: DocumentsEverywhereSession.Outcome) -> some View {
        switch outcome {
        case .previewed:
            EmptyView()
        case .adopted(let result):
            Label(
                result.change == .created
                    ? "Added to the lab with a receipt."
                    : "Updated the lab copy with a receipt.",
                systemImage: "checkmark.circle"
            )
            .foregroundStyle(.green)
        case .refused(let message):
            Label(message, systemImage: "xmark.octagon")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        case .cancelled:
            Label("Cancelled. Nothing was changed.", systemImage: "nosign")
                .foregroundStyle(.secondary)
        }
    }
}

struct DocumentsEverywhereControls: View {
    @Bindable var session: DocumentsEverywhereSession
    @Environment(LabLibrary.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.destinations.isEmpty {
                Text("You have no collection of your own yet. Create one with Create Lab Collection in Action Atlas; demo collections hold only the samples.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Collection", selection: $session.destinationID) {
                    Text("Choose…").tag(Optional<CollectionID>.none)
                    ForEach(session.destinations) { collection in
                        Text(collection.title.value).tag(Optional(collection.id))
                    }
                }
                Button {
                    Task { await session.adoptSelected() }
                } label: {
                    Label("Add Sample to Lab", systemImage: "plus.circle")
                }
                .disabled(session.selectedID == nil || session.destinationID == nil || !library.canAct)
                .accessibilityHint("Stages the sample and commits it through the operation service.")
            }

            Button {
                _ = session.requestProviderActivation()
            } label: {
                Label("Activate Sample Provider…", systemImage: "externaldrive.badge.plus")
            }
            .disabled(true)
            .help(session.providerStatusMessage)
            .accessibilityHint(session.providerStatusMessage)
        }
    }
}

#if os(iOS)
struct DocumentsEverywhereScreen: View {
    @State private var session = DocumentsEverywhereSession()
    @Environment(LabLibrary.self) private var library

    var body: some View {
        Group {
            switch session.phase {
            case .notStarted:
                ProgressView("Opening samples…")
                    .task { await session.open(library: library) }
            case .unavailable(let message):
                ContentUnavailableView(
                    "Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .ready:
                List {
                    Section("Samples") {
                        ForEach(session.entries) { entry in
                            Button {
                                session.select(entry.id)
                            } label: {
                                DocumentsEverywhereRow(entry: entry)
                            }
                        }
                    }
                    Section("Preview") {
                        DocumentsEverywherePreviewPane(
                            preview: session.preview,
                            providerMessage: session.providerStatusMessage,
                            outcome: session.outcome
                        )
                        .listRowInsets(EdgeInsets())
                    }
                    Section("Actions") {
                        DocumentsEverywhereControls(session: session)
                    }
                }
                .task { await session.refresh(library) }
            }
        }
        .navigationTitle("Documents Everywhere")
    }
}
#endif

struct OpenDocumentsEverywhereAction: Equatable {
    let window: ObjectIdentifier
    let perform: @MainActor () -> Void

    @MainActor func callAsFunction() { perform() }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.window == rhs.window }
}

extension EnvironmentValues {
    @Entry var openDocumentsEverywhere: OpenDocumentsEverywhereAction? = nil
}
