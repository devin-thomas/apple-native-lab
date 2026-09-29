import ActionAtlas
import LabDomain
import SwiftUI

/// The form for one action. Each form calls `ActionAtlasActions` as the app UI, the same actions
/// its Shortcuts counterpart calls as an App Intent.
struct AtlasActionForm: View {
    let action: AtlasAction
    /// Called with each new receipt. The Mac opens its receipt inspector on it.
    var onReceipt: (ReceiptRecord) -> Void = { _ in }

    var body: some View {
        Group {
            switch action {
            case .createCollection: CreateCollectionForm(onReceipt: onReceipt)
            case .createItem: CreateItemForm(onReceipt: onReceipt)
            case .findItems: FindItemsForm()
            case .getItem: GetItemForm()
            case .updateItem: UpdateItemForm(onReceipt: onReceipt)
            case .archiveItem: ArchiveItemForm(onReceipt: onReceipt)
            case .restoreItem: RestoreItemForm(onReceipt: onReceipt)
            case .exportItem: ExportItemForm()
            }
        }
        .formStyle(.grouped)
        .navigationTitle(action.title)
    }
}

// MARK: - Create

private struct CreateCollectionForm: View {
    let onReceipt: (ReceiptRecord) -> Void
    @Environment(LabLibrary.self) private var library
    @State private var run = AtlasRun()
    @State private var title = ""
    @State private var created: LabCollection?

    var body: some View {
        Form {
            AtlasSummarySection(action: .createCollection)
            Section("New collection") {
                TextField("Title", text: $title)
            }
            AtlasRunButton(run: run, title: "Create Collection", isEnabled: !title.isBlank) {
                let succeeded = await run.perform(in: library) { request in
                    let outcome = try await library.atlasActions.createCollection(title: title, request: request)
                    created = outcome.entity
                    return outcome.receipt
                }
                // A second press should be a new decision, not an accidental duplicate.
                if succeeded { title = "" }
                reveal(run, onReceipt)
            }
            if let created, run.message == nil {
                Section("Result") {
                    AtlasCollectionSummary(collection: created)
                }
            }
            AtlasOutcomeSections(run: run, onReceipt: onReceipt)
        }
        .onChange(of: title) { run.inputsChanged() }
    }
}

private struct CreateItemForm: View {
    let onReceipt: (ReceiptRecord) -> Void
    @Environment(LabLibrary.self) private var library
    @State private var run = AtlasRun()
    @State private var choices = AtlasChoices()
    @State private var collectionID: CollectionID?
    @State private var title = ""
    @State private var note = ""
    @State private var created: LabItem?

    var body: some View {
        Form {
            AtlasSummarySection(action: .createItem)
            Section("Collection") {
                if choices.ownCollections.isEmpty {
                    Text("You have no collection of your own yet. Create one with Create Lab Collection first; demo collections hold only the samples.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Picker("Collection", selection: $collectionID) {
                        Text("Choose a collection").tag(CollectionID?.none)
                        ForEach(choices.ownCollections) { collection in
                            Text(collection.title.value).tag(Optional(collection.id))
                        }
                    }
                }
            }
            Section("New item") {
                TextField("Title", text: $title)
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(2...6)
            }
            AtlasRunButton(run: run, title: "Create Item", isEnabled: collectionID != nil && !title.isBlank) {
                let succeeded = await run.perform(in: library) { request in
                    let outcome = try await library.atlasActions.createItem(
                        title: title, note: note, in: collectionID, request: request
                    )
                    created = outcome.entity
                    return outcome.receipt
                }
                if succeeded { title = ""; note = "" }
                reveal(run, onReceipt)
            }
            if let created, run.message == nil {
                Section("Result") {
                    AtlasItemSummary(item: created, collectionTitle: choices.collections.first { $0.id == created.collectionID }?.title.value)
                }
            }
            AtlasOutcomeSections(run: run, onReceipt: onReceipt, loadMessage: choices.loadMessage)
        }
        .task {
            await choices.load(library.atlasActions)
            if collectionID == nil, choices.ownCollections.count == 1 { collectionID = choices.ownCollections[0].id }
        }
        .onChange(of: [title, note, collectionID?.description ?? ""]) { run.inputsChanged() }
    }
}

// MARK: - Find

private struct FindItemsForm: View {
    @Environment(LabLibrary.self) private var library
    @State private var run = AtlasRun()
    @State private var choices = AtlasChoices()
    @State private var text = ""
    @State private var collectionID: CollectionID?
    @State private var includeArchived = false
    @State private var limit = 50
    @State private var results: [AtlasItemChoice]?

    var body: some View {
        Form {
            AtlasSummarySection(action: .findItems)
            Section("Search") {
                TextField("Text", text: $text, prompt: Text("Any text"))
                Picker("Collection", selection: $collectionID) {
                    Text("Any collection").tag(CollectionID?.none)
                    ForEach(choices.collections) { collection in
                        Text(collection.namespace == .demo ? "\(collection.title.value) (demo)" : collection.title.value)
                            .tag(Optional(collection.id))
                    }
                }
                Toggle("Include archived items", isOn: $includeArchived)
                Picker("Limit", selection: $limit) {
                    ForEach([5, 20, 50, 200], id: \.self) { Text("\($0)").tag($0) }
                }
            }
            AtlasRunButton(run: run, title: "Find Items", isEnabled: true) {
                await run.perform(in: library) { _ in
                    let actions = library.atlasActions
                    let items = try await actions.findItems(
                        text: text, in: collectionID, includeArchived: includeArchived, limit: limit
                    )
                    let titles = try await actions.collectionTitles(for: items)
                    results = items.map { AtlasItemChoice(item: $0, collectionTitle: titles[$0.collectionID] ?? "") }
                    return nil
                }
            }
            if let results, run.message == nil {
                Section(results.count == 1 ? "1 item" : "\(results.count) items") {
                    if results.isEmpty {
                        Text("No lab items matched.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results) { choice in
                        AtlasItemRow(choice: choice)
                    }
                }
            }
            AtlasOutcomeSections(run: run, onReceipt: { _ in }, loadMessage: choices.loadMessage)
        }
        .task { await choices.load(library.atlasActions) }
    }
}

private struct GetItemForm: View {
    @Environment(LabLibrary.self) private var library
    @State private var run = AtlasRun()
    @State private var choices = AtlasChoices()
    @State private var itemID: ItemID?
    @State private var current: AtlasItemChoice?

    var body: some View {
        Form {
            AtlasSummarySection(action: .getItem)
            Section("Item") {
                AtlasItemPicker(choices: choices.items, selection: $itemID)
            }
            AtlasRunButton(run: run, title: "Get Item", isEnabled: itemID != nil) {
                guard let itemID else { return }
                await run.perform(in: library) { _ in
                    let actions = library.atlasActions
                    let item = try await actions.item(itemID)
                    let titles = try await actions.collectionTitles(for: [item])
                    current = AtlasItemChoice(item: item, collectionTitle: titles[item.collectionID] ?? "")
                    return nil
                }
            }
            if let current, run.message == nil {
                Section("Current state") {
                    AtlasItemSummary(item: current.item, collectionTitle: current.collectionTitle)
                }
            }
            AtlasOutcomeSections(run: run, onReceipt: { _ in }, loadMessage: choices.loadMessage)
        }
        .task { await choices.load(library.atlasActions) }
    }
}

// MARK: - Change

private struct UpdateItemForm: View {
    let onReceipt: (ReceiptRecord) -> Void
    @Environment(LabLibrary.self) private var library
    @State private var run = AtlasRun()
    @State private var choices = AtlasChoices()
    @State private var itemID: ItemID?
    @State private var newTitle = ""
    @State private var newNote = ""
    @State private var updated: LabItem?

    var body: some View {
        let picked = choices.item(itemID)
        Form {
            AtlasSummarySection(action: .updateItem)
            Section {
                AtlasItemPicker(choices: choices.items.filter { !$0.item.isArchived }, selection: $itemID)
                if let picked {
                    LabeledContent("Revision you see", value: "\(picked.item.revision.rawValue)")
                }
            } header: {
                Text("Item")
            } footer: {
                Text("If the item changes before you update it, nothing is overwritten and the receipt records the conflict.")
            }
            Section("Changes") {
                TextField("New title", text: $newTitle, prompt: Text(picked?.item.title.value ?? "Unchanged"))
                TextField("New note", text: $newNote, prompt: Text("Unchanged"), axis: .vertical)
                    .lineLimit(2...6)
            }
            AtlasRunButton(run: run, title: "Update Item", isEnabled: picked != nil && !(newTitle.isBlank && newNote.isEmpty)) {
                guard let picked else { return }
                let succeeded = await run.perform(in: library) { request in
                    let outcome = try await library.atlasActions.updateItem(
                        picked.item.id, expected: picked.item.revision,
                        title: newTitle.isBlank ? nil : newTitle, note: newNote.isEmpty ? nil : newNote,
                        request: request
                    )
                    updated = outcome.entity
                    return outcome.receipt
                }
                if succeeded { newTitle = ""; newNote = "" }
                reveal(run, onReceipt)
                await choices.load(library.atlasActions)
            }
            if let updated, run.message == nil {
                Section("Result") {
                    AtlasItemSummary(item: updated, collectionTitle: choices.item(updated.id)?.collectionTitle)
                }
            }
            AtlasOutcomeSections(run: run, onReceipt: onReceipt, loadMessage: choices.loadMessage)
        }
        .task { await choices.load(library.atlasActions) }
        .onChange(of: [newTitle, newNote, itemID?.description ?? ""]) { run.inputsChanged() }
    }
}

private struct ArchiveItemForm: View {
    let onReceipt: (ReceiptRecord) -> Void
    @Environment(LabLibrary.self) private var library
    @State private var run = AtlasRun()
    @State private var choices = AtlasChoices()
    @State private var itemID: ItemID?
    @State private var archived: LabItem?

    var body: some View {
        let picked = choices.item(itemID)
        Form {
            AtlasSummarySection(action: .archiveItem)
            Section {
                AtlasItemPicker(choices: choices.items.filter { !$0.item.isArchived }, selection: $itemID)
            } header: {
                Text("Item")
            } footer: {
                Text("Pressing Archive Item is your approval here. In Shortcuts the system asks you to confirm first.")
            }
            AtlasRunButton(run: run, title: "Archive Item", role: .destructive, isEnabled: picked != nil) {
                guard let picked else { return }
                await run.perform(in: library) { request in
                    let outcome = try await library.atlasActions.archiveItem(
                        picked.item.id, expected: picked.item.revision, request: request, confirm: { _ in }
                    )
                    archived = outcome.entity
                    return outcome.receipt
                }
                if run.message == nil { itemID = nil }
                reveal(run, onReceipt)
                await choices.load(library.atlasActions)
            }
            if let archived, run.message == nil {
                Section("Result") {
                    AtlasItemSummary(item: archived, collectionTitle: choices.item(archived.id)?.collectionTitle)
                }
            }
            AtlasOutcomeSections(run: run, onReceipt: onReceipt, loadMessage: choices.loadMessage)
        }
        .task { await choices.load(library.atlasActions) }
        .onChange(of: itemID) { run.inputsChanged() }
    }
}

private struct RestoreItemForm: View {
    let onReceipt: (ReceiptRecord) -> Void
    @Environment(LabLibrary.self) private var library
    @State private var run = AtlasRun()
    @State private var choices = AtlasChoices()
    @State private var itemID: ItemID?
    @State private var restored: LabItem?

    var body: some View {
        let archivedChoices = choices.items.filter { $0.item.isArchived }
        let picked = choices.item(itemID)
        Form {
            AtlasSummarySection(action: .restoreItem)
            Section("Archived item") {
                if archivedChoices.isEmpty {
                    Text("No item is archived.")
                        .foregroundStyle(.secondary)
                } else {
                    AtlasItemPicker(choices: archivedChoices, selection: $itemID)
                }
            }
            AtlasRunButton(run: run, title: "Restore Item", isEnabled: picked?.item.isArchived == true) {
                guard let picked else { return }
                await run.perform(in: library) { request in
                    let outcome = try await library.atlasActions.restoreItem(
                        picked.item.id, expected: picked.item.revision, request: request
                    )
                    restored = outcome.entity
                    return outcome.receipt
                }
                if run.message == nil { itemID = nil }
                reveal(run, onReceipt)
                await choices.load(library.atlasActions)
            }
            if let restored, run.message == nil {
                Section("Result") {
                    AtlasItemSummary(item: restored, collectionTitle: choices.item(restored.id)?.collectionTitle)
                }
            }
            AtlasOutcomeSections(run: run, onReceipt: onReceipt, loadMessage: choices.loadMessage)
        }
        .task { await choices.load(library.atlasActions) }
        .onChange(of: itemID) { run.inputsChanged() }
    }
}

// MARK: - Share

private struct ExportItemForm: View {
    @Environment(LabLibrary.self) private var library
    @State private var run = AtlasRun()
    @State private var choices = AtlasChoices()
    @State private var itemID: ItemID?
    @State private var format = AtlasExportFormat.json
    @State private var export: AtlasExport?

    var body: some View {
        Form {
            AtlasSummarySection(action: .exportItem)
            Section("Item") {
                AtlasItemPicker(choices: choices.items, selection: $itemID)
                Picker("Format", selection: $format) {
                    ForEach(AtlasExportFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            AtlasRunButton(run: run, title: "Export Item", isEnabled: itemID != nil) {
                guard let itemID else { return }
                await run.perform(in: library) { _ in
                    export = try await library.atlasActions.exportItem(itemID, as: format)
                    return nil
                }
            }
            if let export, run.message == nil {
                Section {
                    Text(export.text)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    ShareLink(item: export.text, subject: Text(export.filename), preview: SharePreview(export.filename)) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Preview · \(export.filename)")
                } footer: {
                    Text("Only this item's own fields and its collection's name. Nothing leaves this device unless you share it.")
                }
            }
            AtlasOutcomeSections(run: run, onReceipt: { _ in }, loadMessage: choices.loadMessage)
        }
        .task { await choices.load(library.atlasActions) }
        .onChange(of: itemID) { export = nil }
        .onChange(of: format) { export = nil }
    }
}

// MARK: - Parts

/// Opens a new receipt where the host shows receipts, once a change committed or conflicted.
@MainActor
private func reveal(_ run: AtlasRun, _ onReceipt: (ReceiptRecord) -> Void) {
    if let record = run.record { onReceipt(record) }
}

private struct AtlasSummarySection: View {
    let action: AtlasAction

    var body: some View {
        Section {
            Label(action.summary, systemImage: action.symbol)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The form's one action, disabled while it runs or while its input is incomplete.
private struct AtlasRunButton: View {
    let run: AtlasRun
    let title: String
    var role: ButtonRole?
    let isEnabled: Bool
    let action: () async -> Void

    var body: some View {
        Section {
            HStack {
                Button(title, role: role) {
                    Task { await action() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isEnabled || run.isRunning)
                if run.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Working")
                }
            }
        }
    }
}

/// The failure message, if any, then the receipt the run left.
private struct AtlasOutcomeSections: View {
    let run: AtlasRun
    let onReceipt: (ReceiptRecord) -> Void
    var loadMessage: String?

    var body: some View {
        if let message = run.message ?? loadMessage {
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Problem: \(message)")
            }
        }
        if let record = run.record {
            Section("Receipt") {
                AtlasReceiptLink(record: record, onReceipt: onReceipt)
            }
        }
    }
}

/// A receipt row that opens the full receipt: pushed on iPhone, in the inspector on the Mac.
private struct AtlasReceiptLink: View {
    let record: ReceiptRecord
    let onReceipt: (ReceiptRecord) -> Void

    var body: some View {
        #if os(iOS)
        NavigationLink(value: record.id) {
            ReceiptRow(record: record)
        }
        #else
        Button {
            onReceipt(record)
        } label: {
            ReceiptRow(record: record)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the receipt in the inspector.")
        #endif
    }
}

private struct AtlasItemPicker: View {
    let choices: [AtlasItemChoice]
    @Binding var selection: ItemID?

    var body: some View {
        Picker("Item", selection: $selection) {
            Text("Choose an item").tag(ItemID?.none)
            ForEach(choices) { choice in
                Text(choice.label).tag(Optional(choice.id))
            }
        }
    }
}

private struct AtlasItemRow: View {
    let choice: AtlasItemChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(choice.item.title.value)
                .font(.headline)
            Text(choice.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !choice.item.note.value.isEmpty {
                Text(choice.item.note.value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// An item's state as typed output: every field an intent returns.
private struct AtlasItemSummary: View {
    let item: LabItem
    let collectionTitle: String?

    var body: some View {
        LabeledContent("Title", value: item.title.value)
        if !item.note.value.isEmpty {
            LabeledContent("Note", value: item.note.value)
        }
        LabeledContent("Collection", value: collectionTitle ?? "Unknown")
        LabeledContent("Status", value: item.isArchived ? "Archived" : "Active")
        LabeledContent("Revision", value: "\(item.revision.rawValue)")
        LabeledContent("Namespace", value: item.namespace == .demo ? "Demo sample" : "Yours")
        LabeledContent("Identifier") {
            Text(item.id.description)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

private struct AtlasCollectionSummary: View {
    let collection: LabCollection

    var body: some View {
        LabeledContent("Title", value: collection.title.value)
        LabeledContent("Namespace", value: collection.namespace == .demo ? "Demo" : "Yours")
        LabeledContent("Revision", value: "\(collection.revision.rawValue)")
        LabeledContent("Identifier") {
            Text(collection.id.description)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
