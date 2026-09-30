import LabDomain
import ShareIngress
import SwiftUI
import UniformTypeIdentifiers

extension LabAnnouncement {
    /// An intake's one-sentence result: counts only, never content.
    init(intake report: IntakeReport) {
        text = report.summary
        priority = report.refusal != nil || report.refusedCount > 0 || report.wasCancelled ? .high : .normal
    }
}

/// The types the paste action and the share extension accept: movies, images, web links, text.
enum ShareInboxTypes {
    static let pasteable: [UTType] = [.movie, .image, .url, .plainText]
    static let choosable: [UTType] = [.item]
}

// MARK: - Adding to the inbox

/// Paste and Choose Files, the fallbacks that need no extension, with the limits shown first.
struct InboxIntakeControls: View {
    @Bindable var model: ShareInboxModel
    @Binding var isChoosingFiles: Bool

    var body: some View {
        Group {
            PasteButton(supportedContentTypes: ShareInboxTypes.pasteable) { providers in
                model.paste(providers)
            }
            .disabled(!model.canImport)
            .accessibilityHint("Adds what you copied to the inbox for review")
            Button("Choose Files…", systemImage: "folder") { isChoosingFiles = true }
                .disabled(!model.canImport || !model.canChooseFiles)
                .accessibilityHint(model.canChooseFiles
                    ? "Adds files you choose to the inbox for review"
                    : "Unavailable in this build. Paste a copied file or drag it here instead.")
        }
    }
}

/// The effective limits, shown before an import starts.
struct InboxLimitsText: View {
    let limits: ImportLimits

    var body: some View {
        Text("Up to \(limits.maximumFiles) items at a time: text up to \(Self.bytes(limits.maximumTextBytes)), files up to \(Self.bytes(limits.maximumTotalBytes)) together. Everything waits here until you add it to a collection.")
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .binary)
    }
}

/// The running intake with its Cancel button, or the last intake's result.
struct InboxIntakeStatus: View {
    let model: ShareInboxModel

    var body: some View {
        if let active = model.activeIntake {
            HStack(spacing: 12) {
                ProgressView()
                    .accessibilityHidden(true)
                Text("Importing \(active.count == 1 ? "1 item" : "\(active.count) items") from \(active.surface.title)…")
                Spacer(minLength: 8)
                Button("Cancel", role: .cancel) { model.cancelIntake() }
                    .accessibilityHint("Stops the import and keeps nothing from it")
            }
            .accessibilityElement(children: .contain)
        } else if let report = model.lastReport {
            VStack(alignment: .leading, spacing: 4) {
                Text(report.summary)
                    .font(.body.weight(.semibold))
                ForEach(report.outcomes.filter(\.isRefused)) { outcome in
                    Text(outcome.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

extension AttachmentOutcome {
    var isRefused: Bool {
        if case .refused = result { true } else { false }
    }
}

// MARK: - Rows

extension InboxEntry {
    var symbolName: String {
        switch content {
        case .text: "text.alignleft"
        case .link: "link"
        case .files(let files):
            if files.contains(where: { Self.type(of: $0)?.conforms(to: .movie) == true }) {
                "film"
            } else if files.allSatisfy({ Self.type(of: $0)?.conforms(to: .image) == true }) {
                "photo"
            } else {
                "doc"
            }
        }
    }

    private static func type(of file: InboxFile) -> UTType? {
        UTType(filenameExtension: (file.name as NSString).pathExtension)
    }

    var kindTitle: String {
        switch content {
        case .text: "Text"
        case .link: "Web link"
        case .files(let files): files.count == 1 ? "File" : "\(files.count) files"
        }
    }

    /// Where it came from: surface, position, and time, in reading order.
    var originParts: [String] {
        guard let origin else { return ["Origin unknown"] }
        let parts: [String?] = [
            origin.surface.title,
            origin.count > 1 ? "\(origin.position) of \(origin.count)" : nil,
            origin.receivedAt.formatted(date: .abbreviated, time: .shortened),
        ]
        return parts.compactMap(\.self)
    }

    var isAdoptable: Bool { adoptability == .ready }

    /// The row as VoiceOver reads it: commas, never the visual middle dots.
    var spokenDescription: String {
        ([headline.isEmpty ? kindTitle : headline, kindTitle] + originParts + (isAdoptable ? [] : ["Can't be added in this version"]))
            .joined(separator: ", ")
    }
}

struct InboxEntryRow: View {
    let entry: InboxEntry

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.headline.isEmpty ? entry.kindTitle : entry.headline)
                    .lineLimit(2)
                Text(([entry.kindTitle] + entry.originParts).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !entry.isAdoptable {
                    Text("Can't be added in this version")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: entry.symbolName)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.spokenDescription)
    }
}

struct QuarantineRow: View {
    let entry: QuarantineEntry
    let model: ShareInboxModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Set aside", systemImage: "exclamationmark.triangle")
                .font(.body.weight(.semibold))
            Text(entry.message)
                .fixedSize(horizontal: false, vertical: true)
            if let origin = entry.origin {
                Text("\(origin.surface.title), \(origin.receivedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button("Remove", systemImage: "trash", role: .destructive) {
                Task { await model.remove(entry) }
            }
            .accessibilityLabel("Remove set-aside import")
        }
        .padding(.vertical, 2)
    }
}

/// Whether this build's share sheet reaches the inbox, stated plainly.
struct ShareSheetStatusText: View {
    let status: ShareInboxModel.ShareSheetStatus

    var body: some View {
        switch status {
        case .available:
            Text("Share sheet: on. Choose Native Lab in another app's share sheet; what you share waits here.")
        case .notInThisBuild:
            Text("Share sheet: not in this build. Sharing from other apps needs the SystemSurfaces build (LabPhone-Surfaces) and a team that can use App Groups. Paste and Choose Files work in every build.")
        case .unavailable:
            Text("Share sheet: unavailable. This build has the share extension, but its shared App Group folder isn't available to this signature. Paste and Choose Files still work.")
        }
    }
}

// MARK: - Detail

/// One waiting import: its content, where it came from, and the explicit Add and Remove actions.
struct InboxEntryDetail: View {
    let entry: InboxEntry
    let model: ShareInboxModel
    /// Opens an adoption's receipt. The Mac shows it in the inspector; iPhone pushes it.
    var onReceipt: (ReceiptRecord) -> Void = { _ in }
    @Environment(LabLibrary.self) private var library
    @State private var isNaming = false
    @State private var newTitle = ""
    @State private var isConfirmingRemoval = false

    var body: some View {
        Form {
            Section("Content") {
                InboxContentView(content: entry.content)
            }
            Section("Origin") {
                if let origin = entry.origin {
                    LabeledContent("Came through", value: origin.surface.title)
                    LabeledContent("Received", value: origin.receivedAt.formatted(date: .abbreviated, time: .standard))
                    if origin.count > 1 {
                        LabeledContent("Position", value: "\(origin.position) of \(origin.count) shared together")
                    }
                    if let type = origin.contentType {
                        LabeledContent("Declared type", value: type)
                    }
                } else {
                    Text("Origin unknown. The import itself was checked and is intact.")
                }
                LabeledContent("Adds as", value: entry.source.adapter.title)
            }
            if let added = model.added[entry.id] {
                resultSection(added)
            } else {
                destinationSection
            }
            if let failure = model.failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.circle")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(entry.kindTitle)
        .task { await model.loadCollections(from: library) }
        .alert("New Collection", isPresented: $isNaming) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) { newTitle = "" }
            Button("Create") {
                let title = newTitle
                newTitle = ""
                Task { await model.createCollection(titled: title, in: library) }
            }
        } message: {
            Text("A collection of your own. Demo collections hold only the samples.")
        }
        .confirmationDialog("Remove this import?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await model.discard(entry) } }
        } message: {
            Text("It leaves the inbox without being added. Nothing in your collections changes.")
        }
    }

    @ViewBuilder private var destinationSection: some View {
        Section {
            switch entry.adoptability {
            case .ready:
                if model.collections.isEmpty {
                    Text("You have no collection of your own yet. Create one to add this import to.")
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Picker("Collection", selection: Bindable(model).destinationID) {
                        Text("Choose a collection").tag(CollectionID?.none)
                        ForEach(model.collections) { collection in
                            Text(collection.title.value).tag(Optional(collection.id))
                        }
                    }
                }
                Button("New Collection…", systemImage: "folder.badge.plus") { isNaming = true }
                Button {
                    guard let destination = model.destinationID else { return }
                    Task {
                        if let added = await model.add(entry, to: destination, in: library) { onReceipt(added.record) }
                    }
                } label: {
                    Label(model.isAdding ? "Adding…" : "Add to Collection", systemImage: "tray.and.arrow.down")
                }
                .disabled(model.destinationID == nil || model.isAdding)
                .accessibilityHint("Adds this import as one new item. Its receipt opens afterwards.")
            case .unavailable(let reason):
                Text(reason.userMessage)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Remove from Inbox", systemImage: "trash", role: .destructive) { isConfirmingRemoval = true }
        } header: {
            Text("Add")
        } footer: {
            Text("Adding creates one item in the collection you choose, with this content as its note. Nothing in the content can choose the collection or the change.")
        }
    }

    private func resultSection(_ added: AddedImport) -> some View {
        Section("Added") {
            Text(added.isDuplicate
                 ? "Already in “\(added.collectionTitle)”. Nothing new was stored; this is the original receipt."
                 : "Added to “\(added.collectionTitle)”.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Show Receipt", systemImage: "doc.text.magnifyingglass") { onReceipt(added.record) }
        }
    }
}

/// An import's content as data: text is shown as text, a link as its address, never opened.
struct InboxContentView: View {
    let content: InboxContent
    static let previewLimit = 2_000

    var body: some View {
        switch content {
        case .text(let text):
            Text(text.count > Self.previewLimit ? String(text.prefix(Self.previewLimit)) + "…" : text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if text.count > Self.previewLimit {
                Text("\(text.count) characters; the first \(Self.previewLimit) are shown.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .link(let url, let title):
            if let title, !title.isEmpty {
                LabeledContent("Page title", value: title)
            }
            LabeledContent("Address") {
                Text(url.absoluteString)
                    .textSelection(.enabled)
                    .lineLimit(4)
            }
        case .files(let files):
            ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                LabeledContent(file.name, value: InboxLimitsText.bytes(file.byteCount))
            }
        }
    }
}
