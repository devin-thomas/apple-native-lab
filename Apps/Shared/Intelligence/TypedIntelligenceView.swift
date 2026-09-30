import LabDomain
import LabSupport
import SwiftUI
import TypedIntelligence

/// One note in Typed Local Intelligence: the note, the three ways to draft, the proposal under
/// review with its issues, evidence, and diff, and Apply.
///
/// Every draft is labeled with its source, and the two non-model paths say so. When the model is
/// unavailable, the probe's own words name the gate that closed it, and the sample parser and the
/// manual editor stay fully usable.
struct TypedIntelligenceView: View {
    let fixture: IntelligenceFixture
    /// Called with each new receipt. The Mac opens its receipt inspector on it.
    var onReceipt: (ReceiptRecord) -> Void = { _ in }
    @State private var workbench: IntelligenceWorkbench
    @State private var isConfirmingReset = false
    @Environment(LabLibrary.self) private var library

    /// - Parameter registry: Where the model probe reads this device. Tests pass a fake device.
    init(
        fixture: IntelligenceFixture,
        registry: CapabilityRegistry = .live(),
        onReceipt: @escaping (ReceiptRecord) -> Void = { _ in }
    ) {
        self.fixture = fixture
        self.onReceipt = onReceipt
        _workbench = State(initialValue: IntelligenceWorkbench(fixture: fixture, registry: registry))
    }

    var body: some View {
        Form {
            NoteSection(workbench: workbench)
            DraftSection(workbench: workbench)
            if let message = workbench.message {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Problem: \(message)")
                }
            }
            if workbench.source != nil, workbench.phase == .reviewing || workbench.phase == .applying {
                ProposalSections(workbench: workbench) { record in
                    onReceipt(record)
                    LabAnnouncement(receipt: ReceiptPresentation(record)).post()
                }
            }
            if let record = workbench.applied {
                Section("Receipt") {
                    IntelligenceReceiptLink(record: record, onReceipt: onReceipt)
                }
            }
            Section {
                ResetDemoButton(isConfirming: $isConfirmingReset)
            } footer: {
                Text("Applied changes edit demo samples only. Reset Demo restores every sample; your own data is not changed.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(fixture.title)
        .resetDemoConfirmation(isPresented: $isConfirmingReset) { record in
            onReceipt(record)
            Task { await workbench.readAgain() }
        }
        .task { await workbench.start(with: library) }
        .onDisappear { workbench.cancelDraft() }
    }
}

// MARK: - Note

private struct NoteSection: View {
    let workbench: IntelligenceWorkbench

    var body: some View {
        Section {
            if let note = workbench.note {
                Text(note.text)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Note: \(note.text)")
            } else if workbench.phase == .loading {
                ProgressView("Loading the note…")
            }
        } header: {
            Text("Note")
        } footer: {
            Text("Original sample text. The note is data: instructions inside it cannot choose an action, add a tool, or grant a permission.")
        }
    }
}

// MARK: - Draft

private struct DraftSection: View {
    let workbench: IntelligenceWorkbench

    var body: some View {
        Section {
            ModelRouteRow(workbench: workbench)
            if let source = workbench.drafting {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text(source == .onDeviceModel
                         ? "Drafting on this device. Stops after \(workbench.timeLimitSeconds) seconds."
                         : "Parsing…")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Cancel", role: .cancel) { workbench.cancelDraft() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityHint("Stops drafting. Nothing is proposed.")
                }
                .accessibilityElement(children: .contain)
            }
            SourceButton(
                title: "Draft with the On-Device Model", detail: "Apple Intelligence, on this device only.",
                symbol: "sparkles", isEnabled: workbench.modelIsOffered && workbench.canDraft
            ) { workbench.draft(with: .onDeviceModel) }
            SourceButton(
                title: "Draft with the Sample Parser", detail: "Not a model: fixed rules read the note.",
                symbol: "text.magnifyingglass", isEnabled: workbench.canDraft
            ) { workbench.draft(with: .sampleParser) }
            SourceButton(
                title: "Write It Myself", detail: "Not a model: the manual editor.",
                symbol: "square.and.pencil", isEnabled: workbench.canDraft
            ) { workbench.draft(with: .manualEditor) }
        } header: {
            Text("Draft a proposal")
        } footer: {
            Text("A draft is a proposal. Nothing changes until you review it and press Apply.")
        }
    }
}

/// Whether the model route is open, and if not, which gate the probe found closed.
private struct ModelRouteRow: View {
    let workbench: IntelligenceWorkbench

    var body: some View {
        if let readiness = workbench.readiness {
            VStack(alignment: .leading, spacing: 6) {
                StatusLabel(status: readiness.status)
                if let explanation = readiness.explanation {
                    ForEach(readiness.failedGates) { gate in
                        Text("\(gate.kind.title): \(gate.detail)")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Use the sample parser or the manual editor. Neither is a model, and neither needs one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHint(explanation)
                } else if let variant = OnDeviceModelExtractor.variantName {
                    Text("System model: \(variant). No network, no cloud route.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No network, no cloud route.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            ProgressView("Checking the on-device model…")
        }
    }
}

private struct SourceButton: View {
    let title: String
    let detail: String
    let symbol: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            }
        }
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}

// MARK: - Proposal

private struct ProposalSections: View {
    @Bindable var workbench: IntelligenceWorkbench
    let onApplied: (ReceiptRecord) -> Void

    var body: some View {
        if let source = workbench.source {
            Section {
                HStack {
                    StatusBadge(status: source.status)
                    if workbench.review?.proposal.editedByPerson == true {
                        StatusBadge(status: StatusDescriptor(kind: "Edits", title: "Edited by you", symbol: "pencil", tone: .neutral))
                    }
                }
                Picker("Sample", selection: $workbench.targetID) {
                    Text("Choose a sample").tag(ItemID?.none)
                    ForEach(workbench.candidates) { candidate in
                        Text(candidate.title).tag(Optional(candidate.id))
                    }
                }
                .onChange(of: workbench.targetID) { old, _ in workbench.targetChanged(from: old) }
                TextField("Title", text: $workbench.title)
                    .onChange(of: workbench.title) { workbench.fieldsChanged() }
                TextField("Add to the note", text: $workbench.addedNote, axis: .vertical)
                    .lineLimit(2...6)
                    .onChange(of: workbench.addedNote) { workbench.fieldsChanged() }
            } header: {
                Text("Proposal")
            } footer: {
                Text("Title up to \(ProposalLimits.title) characters. Added text up to \(ProposalLimits.addedNote) characters, on a new line after the sample's note.")
            }
            IssuesSection(workbench: workbench)
            EvidenceSection(workbench: workbench)
            DiffSection(review: workbench.review)
            Section {
                Button {
                    Task {
                        await workbench.apply()
                        if let record = workbench.applied { onApplied(record) }
                    }
                } label: {
                    Label("Apply Change", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!workbench.canApply)
                .accessibilityHint("Commits this change to the sample as you. Only this button changes anything.")
                Button("Discard Proposal", role: .destructive) { workbench.discard() }
                    .disabled(workbench.phase == .applying)
                    .accessibilityHint("Drops the proposal. Nothing was stored.")
            } footer: {
                if let summary = workbench.review?.serviceSummary, workbench.canApply {
                    Text("The lab checked this change: \(summary)")
                }
            }
        }
    }
}

private struct IssuesSection: View {
    let workbench: IntelligenceWorkbench

    var body: some View {
        let issues = workbench.review?.issues ?? []
        Section {
            if workbench.isRevising {
                Label("Checking your edits…", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            } else if issues.isEmpty {
                Label("No problems found. Still check it against the note.", systemImage: "checkmark.seal")
            }
            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                Label {
                    Text(issue.message)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: issue.isBlocking ? "xmark.octagon" : "exclamationmark.triangle")
                        .foregroundStyle(issue.isBlocking ? .red : .orange)
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("\(issue.isBlocking ? "Must fix" : "Check"): \(issue.message)")
            }
            if case .stale? = workbench.review?.serviceCheck {
                Button("Read the Sample Again", systemImage: "arrow.clockwise") {
                    Task { await workbench.readAgain() }
                }
            }
        } header: {
            Text("Check before applying")
        }
    }
}

private struct EvidenceSection: View {
    let workbench: IntelligenceWorkbench

    var body: some View {
        let evidence = workbench.review?.proposal.evidence ?? []
        if !evidence.isEmpty || workbench.droppedQuotes > 0 {
            Section {
                ForEach(evidence, id: \.self) { span in
                    Text("“\(span.quote)”")
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Quote from the note: \(span.quote)")
                }
                if workbench.droppedQuotes > 0 {
                    Text(workbench.droppedQuotes == 1
                         ? "1 quote the draft gave was not in the note and was dropped."
                         : "\(workbench.droppedQuotes) quotes the draft gave were not in the note and were dropped.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Evidence from the note")
            } footer: {
                Text("Found in the note word for word. A real quote can still be read wrongly.")
            }
        }
    }
}

private struct DiffSection: View {
    let review: ReviewableProposal?

    var body: some View {
        if let diff = review?.proposal.diff {
            Section("Change") {
                DiffRow(label: "Title", before: diff.titleBefore, after: diff.titleAfter, changed: diff.changesTitle)
                DiffRow(label: "Note", before: diff.noteBefore, after: diff.noteAfter, changed: diff.changesNote)
            }
        }
    }
}

private struct DiffRow: View {
    let label: String
    let before: String
    let after: String
    let changed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(changed ? "\(label): changes" : "\(label): unchanged")
                .font(.subheadline.weight(.semibold))
            if changed {
                Text("Before: \(before.isEmpty ? "empty" : before)")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("After: \(after)")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(before.isEmpty ? "empty" : before)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }
}

/// A receipt row that opens the full receipt: pushed on iPhone, in the inspector on the Mac.
private struct IntelligenceReceiptLink: View {
    let record: ReceiptRecord
    let onReceipt: (ReceiptRecord) -> Void

    var body: some View {
        #if os(iOS)
        NavigationLink {
            ReceiptDetailView(record: record)
        } label: {
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

// MARK: - Presentation

extension ProposalSource {
    var status: StatusDescriptor {
        switch self {
        case .onDeviceModel: StatusDescriptor(kind: "Source", title: title, symbol: "sparkles", tone: .active)
        case .sampleParser: StatusDescriptor(kind: "Source", title: title, symbol: "text.magnifyingglass", tone: .neutral)
        case .manualEditor: StatusDescriptor(kind: "Source", title: title, symbol: "square.and.pencil", tone: .neutral)
        }
    }
}

extension ModelReadiness {
    var status: StatusDescriptor {
        switch route {
        case .model:
            StatusDescriptor(kind: "On-device model", title: "Available", symbol: "checkmark.circle", tone: .success)
        case .fallback:
            StatusDescriptor(kind: "On-device model", title: readiness == .unknown ? "Unknown" : "Unavailable",
                             symbol: readiness == .unknown ? "questionmark.circle" : "xmark.circle", tone: .attention)
        }
    }
}
