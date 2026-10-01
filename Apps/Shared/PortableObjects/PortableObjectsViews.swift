import LabDomain
import PortableObjects
import ShortcutWorkbench
import SwiftUI
import UniformTypeIdentifiers

/// Where Portable Objects is described in the catalog.
enum PortableObjectsModule {
    static let experimentID = "LAB-008"
    static let summary = "In this build: Portable Objects runs in the app. Drag an object to another window or app, export it as an .anlab document, JSON, or text, and import a document back through staging, review, and the operation service, with a receipt."
}

// MARK: - Objects

/// One object in a list: title, collection, revision, and whether it is a demo sample. Given an
/// object, the row is a drag source that carries the complete document.
struct PortableObjectRow: View {
    let entry: PortableObjectsSession.Entry
    let object: PortableObject?

    var body: some View {
        // One element for the whole row, drag source included, as on the export card.
        draggableContent
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var draggableContent: some View {
        let content = VStack(alignment: .leading, spacing: 2) {
            Text(entry.item.title.value)
                .font(.headline)
                .strikethrough(entry.item.isArchived)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        if let object {
            content.draggable(object) {
                Label(entry.item.title.value, systemImage: "shippingbox")
                    .padding(8)
            }
        } else {
            content
        }
    }

    private var detail: String {
        [
            entry.collectionTitle, "Revision \(entry.item.revision.rawValue)",
            entry.item.isArchived ? "Archived" : nil, entry.item.namespace == .demo ? "Demo sample" : nil,
        ]
        .compactMap(\.self).joined(separator: " · ")
    }

    private var accessibilityText: String {
        "\(entry.item.title.value), \(detail)"
    }
}

/// What a drop does here, and the two ways in that need no drag: a file and the sample. Each is
/// its own list row, because on iPhone every button in a row fires when the row is tapped.
struct PortableImportControls: View {
    @Bindable var session: PortableObjectsSession
    @Environment(LabLibrary.self) private var library
    @State private var isChoosingFile = false

    var body: some View {
        Label {
            Text("Drop a lab object or an .anlab file here to import it. Every import is checked and shown to you before anything is added.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "tray.and.arrow.down")
                .accessibilityHidden(true)
        }
        .font(.callout)
        Button {
            isChoosingFile = true
        } label: {
            Label("Import from File…", systemImage: "doc.badge.plus")
        }
        .disabled(session.isWorking || !library.canAct)
        .accessibilityHint("Choose an .anlab or JSON file. It is checked and shown to you before anything is added.")
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.labObject, .json]) { result in
            guard case .success(let url) = result else { return }
            Task { await session.open(fileAt: url, library: library) }
        }
        Button {
            Task { await session.openSample(library: library) }
        } label: {
            Label("Import Sample Object", systemImage: "shippingbox")
        }
        .disabled(session.isWorking || !library.canAct)
        .accessibilityHint("Reviews the bundled sample object, an original fixture.")
        if session.isWorking {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Checking the object")
        }
        if let message = session.message {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Problem: \(message)")
        }
    }
}

// MARK: - Export

/// Everything an export will produce, before anything is written: the fields, the
/// representations and what each keeps, the destination, and the document itself.
struct ExportPreviewView: View {
    let preview: ExportPreview
    @State private var format = RepresentationDescriptor.Kind.nativeDocument
    @State private var isExporting = false
    @State private var saved: String?
    @State private var exportFailure: String?

    var body: some View {
        Form {
            Section {
                ExportCard(object: preview.object)
            } footer: {
                Text("Drag the card to another window, to Finder or Files, or into another app. The receiving app takes the most complete representation it can read.")
            }
            Section("Fields") {
                ForEach(preview.fields) { field in
                    LabeledContent(field.label) {
                        Text(field.value)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            Section("Representations") {
                ForEach(preview.representations) { representation in
                    RepresentationRow(representation: representation)
                }
            }
            Section {
                Picker("Format", selection: $format) {
                    ForEach(exportable, id: \.kind) { representation in
                        Text(representation.title).tag(representation.kind)
                    }
                }
                LabeledContent("Destination", value: "A file you choose")
                LabeledContent("File name", value: preview.object.fileName(format))
                // One control per row: on iPhone, every button in a row fires when the row is tapped.
                Button {
                    saved = nil
                    exportFailure = nil
                    isExporting = true
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up.on.square")
                }
                .accessibilityHint("Saves the object as a file in a folder you choose.")
                ShareLink(item: preview.object, preview: SharePreview(preview.document.title)) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                if let saved {
                    Label("Saved “\(saved)”.", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
                if let exportFailure {
                    Label(exportFailure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Export")
            } footer: {
                Text("Exporting only writes the file you choose. Nothing is uploaded, and the lab is not changed, so there is no receipt.")
            }
            Section {
                // No accessibility label here: on the Mac, a label on selectable text made AppKit
                // resolve it in a loop when an assistive app read the text (LAB-008-A). The
                // section header names it, and the text is its value.
                Text(preview.text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if preview.omitsStoredMetadata {
                    Text("The lab keeps other metadata for this object that is not part of its document.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Document · \(preview.byteCount.formatted()) bytes")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(preview.document.title)
        .fileExporter(
            isPresented: $isExporting,
            item: preview.object,
            contentTypes: [contentType],
            defaultFilename: PortableObjectFileName.base(of: preview.object, format: format),
            onCompletion: { result in
                switch result {
                case .success(let url): saved = url.lastPathComponent
                case .failure: exportFailure = "The file couldn't be saved. Nothing was written."
                }
            },
            onCancellation: {}
        )
    }

    private var exportable: [RepresentationDescriptor] {
        preview.representations.filter { $0.contentType != nil }
    }

    private var contentType: UTType {
        preview.representations.first { $0.kind == format }?.contentType ?? .labObject
    }
}

enum PortableObjectFileName {
    /// The export dialog adds the type's extension to this.
    static func base(of object: PortableObject, format: RepresentationDescriptor.Kind) -> String {
        let name = object.fileName(format)
        guard let dot = name.lastIndex(of: ".") else { return name }
        return String(name[..<dot])
    }
}

/// The object as something to drag, with what it is.
private struct ExportCard: View {
    let object: PortableObject

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(object.document.title)
                    .font(.headline)
                Text(object.fileName(.nativeDocument))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .draggable(object) {
            Label(object.document.title, systemImage: "shippingbox")
                .padding(8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(object.document.title), lab object, \(object.fileName(.nativeDocument))")
        .accessibilityHint("Drag to another window or app, or use Export or Share below.")
    }
}

private struct RepresentationRow: View {
    let representation: RepresentationDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(representation.title)
                    .font(.body.weight(.semibold))
                Spacer()
                Text(fidelity)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var fidelity: String {
        switch representation.fidelity {
        case .complete: "Complete"
        case .lossy: "Summary only"
        case .notOffered: "Not offered"
        }
    }

    private var detail: String {
        if case .notOffered(let reason) = representation.fidelity { return reason }
        return representation.detail
    }
}

// MARK: - Import review

/// A staged object, checked and planned, waiting for the person's decision.
struct ImportReviewView: View {
    @Bindable var session: PortableObjectsSession
    let review: ImportReview
    /// Called with the import's receipt. The Mac opens its receipt inspector on it.
    var onReceipt: (ReceiptRecord) -> Void = { _ in }
    @Environment(LabLibrary.self) private var library

    var body: some View {
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline)
                            .font(.headline)
                        Text(explanation)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: symbol)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                ForEach(review.adjustments, id: \.self) { adjustment in
                    Label(adjustment, systemImage: "info.circle")
                        .font(.callout)
                }
            }
            decisionSection
            Section("Fields") {
                ForEach(review.document.previewFields) { field in
                    LabeledContent(field.label) {
                        Text(field.value)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            Section {
                Label("Checked as strict JSON within \(ByteCountFormatter.string(fromByteCount: Int64(ImportLimitText.maximumBytes), countStyle: .binary)), with every schema rule. Staged as \(review.byteCount.formatted()) bytes; nothing has been added.", systemImage: "checkmark.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Review Import")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { Task { await session.closeReview() } }
                    .accessibilityHint("Removes the checked copy. Nothing is imported.")
            }
        }
    }

    @ViewBuilder private var decisionSection: some View {
        switch review.plan {
        case .create:
            Section {
                if session.destinations.isEmpty {
                    Text("You have no collection of your own yet. Create one with Create Lab Collection in Action Atlas; demo collections hold only the samples.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Picker("Collection", selection: $session.destinationID) {
                        Text("Choose a collection").tag(CollectionID?.none)
                        ForEach(session.destinations) { collection in
                            Text(collection.title.value).tag(Optional(collection.id))
                        }
                    }
                }
                commitButton("Import", enabled: session.destinationID != nil)
            } header: {
                Text("Import into")
            }
        case .differs(let stored, let content, _):
            Section {
                LabeledContent("Lab's title", value: stored.title.value)
                LabeledContent("Document's title", value: content.title.value)
                LabeledContent("Lab's note", value: stored.note.value.isEmpty ? "Empty" : stored.note.value)
                LabeledContent("Document's note", value: content.note.value.isEmpty ? "Empty" : content.note.value)
                commitButton("Apply Document's Title and Note", enabled: true)
            } header: {
                Text("Compare")
            } footer: {
                Text("Applying updates the lab's copy at revision \(stored.revision.rawValue), and its receipt offers an undo. Extra fields stay as the lab has them.")
            }
        case .alreadyPresent, .refused:
            EmptyView()
        }
    }

    private func commitButton(_ title: String, enabled: Bool) -> some View {
        Button(title) {
            Task {
                if let record = await session.commit(library: library) {
                    LabAnnouncement(receipt: ReceiptPresentation(record)).post()
                    onReceipt(record)
                }
            }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!enabled || session.isWorking || !library.canAct)
    }

    private var headline: String {
        switch review.plan {
        case .create: "New to this lab"
        case .alreadyPresent: "Already in this lab"
        case .differs: "This lab's copy is different"
        case .refused: "Can't be imported"
        }
    }

    private var explanation: String {
        switch review.plan {
        case .create:
            "“\(review.document.title)” is not in this lab. Importing adds it to the collection you choose, under its stable identifier, with a receipt."
        case .alreadyPresent(let stored):
            "This lab holds “\(stored.title.value)” with the same identifier, title, and note. Importing it again would change nothing, so there is nothing to do."
        case .differs:
            "This lab holds this object under the same identifier with a different title or note. Nothing changes unless you apply the document's."
        case .refused(let reason, _):
            reason.userMessage
        }
    }

    private var symbol: String {
        switch review.plan {
        case .create: "plus.circle"
        case .alreadyPresent: "checkmark.circle"
        case .differs: "arrow.left.arrow.right.circle"
        case .refused: "exclamationmark.triangle"
        }
    }
}

enum ImportLimitText {
    static let maximumBytes = IncomingObject.maximumBytes
}

/// What the last import did, with its receipt.
struct PortableOutcomeView: View {
    let outcome: PortableObjectsSession.Outcome
    var onReceipt: (ReceiptRecord) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(outcome.sentence, systemImage: "checkmark.circle")
                .fixedSize(horizontal: false, vertical: true)
            #if os(iOS)
            NavigationLink {
                ReceiptDetailView(record: outcome.record)
                    .navigationTitle("Receipt")
            } label: {
                ReceiptRow(record: outcome.record)
            }
            #else
            Button {
                onReceipt(outcome.record)
            } label: {
                ReceiptRow(record: outcome.record)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the receipt in the inspector.")
            #endif
        }
    }
}

// MARK: - iPhone

/// Portable Objects on iPhone, pushed from its catalog page: import controls, the last import,
/// and every object, each opening its export preview. An import under review opens as a sheet.
struct PortableObjectsScreen: View {
    @State private var session = PortableObjectsSession()
    @Environment(LabLibrary.self) private var library

    var body: some View {
        List {
            Section {
                PortableImportControls(session: session)
            }
            if let outcome = session.outcome {
                Section("Last import") {
                    PortableOutcomeView(outcome: outcome)
                }
            }
            ForEach(session.groups) { group in
                Section {
                    ForEach(group.entries) { entry in
                        // A destination link, like the catalog link that opens this screen: in
                        // a stack that mixes them, a value link's first tap did nothing. The row
                        // is not a drag source here; the export card it opens is.
                        NavigationLink {
                            exportPreview(entry.id)
                        } label: {
                            PortableObjectRow(entry: entry, object: nil)
                        }
                    }
                } header: {
                    Text(group.collection.namespace == .demo ? "\(group.collection.title.value) · Demo" : group.collection.title.value)
                }
            }
        }
        .navigationTitle("Portable Objects")
        .dropDestination(for: IncomingObject.self) { items, _ in
            Task { await session.receive(items, library: library) }
        }
        .sheet(isPresented: Binding(
            get: { session.review != nil },
            set: { presented in if !presented { Task { await session.closeReview() } } }
        )) {
            if let review = session.review {
                NavigationStack {
                    ImportReviewView(session: session, review: review)
                }
                .environment(library)
            }
        }
        .task { await session.load(library) }
        .onChange(of: library.latestReceipt?.id) { Task { await session.load(library) } }
    }

    @ViewBuilder private func exportPreview(_ id: ItemID) -> some View {
        if let preview = session.exportPreview(for: id) {
            ExportPreviewView(preview: preview)
        } else {
            ContentUnavailableView("Object Not Found", systemImage: "questionmark.folder")
        }
    }
}


// MARK: - Catalog

/// Shows Portable Objects in one Mac window. Two actions are equal when they belong to the same
/// window, so providing one does not invalidate every reader on each update.
struct OpenPortableObjectsAction: Equatable {
    let window: ObjectIdentifier
    let perform: @MainActor () -> Void

    @MainActor func callAsFunction() { perform() }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.window == rhs.window }
}

extension EnvironmentValues {
    /// The main window provides it; elsewhere, and on iPhone, it is `nil`.
    @Entry var openPortableObjects: OpenPortableObjectsAction? = nil
}

/// The catalog page's way into an experiment that runs in this build. Nothing for the others.
struct ExperimentModuleAction: View {
    let experimentID: String
    @Environment(\.openPortableObjects) private var openPortableObjects

    var body: some View {
        if experimentID == PortableObjectsModule.experimentID {
            #if os(iOS)
            NavigationLink {
                PortableObjectsScreen()
            } label: {
                Label("Open Portable Objects", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Drag, export, and import lab objects.")
            #else
            if let openPortableObjects {
                Button {
                    openPortableObjects()
                } label: {
                    Label("Open Portable Objects", systemImage: "shippingbox")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Show Portable Objects in this window (⌘8)")
            }
            #endif
        } else if experimentID == "LAB-016" {
            PickUpCatalogAction()
        } else if experimentID == ShortcutWorkbench.experimentID {
            #if os(iOS)
            NavigationLink {
                ShortcutWorkbenchPage()
            } label: {
                Label("Open \(ShortcutWorkbench.title)", systemImage: ShortcutWorkbench.symbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Curated recipes and manual instructions; no secret storage in Shortcuts.")
            #else
            Button {
                ShortcutWorkbenchModel.shared.requestOpen()
            } label: {
                Label("Open \(ShortcutWorkbench.title)", systemImage: ShortcutWorkbench.symbol)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Show Shortcut Workbench in this window (⌥⌘8)")
            #endif
        }
    }
}
