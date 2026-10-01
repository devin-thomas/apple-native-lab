import ModelRouting
import SwiftUI

/// Shared list body used by the Mac detail and the iPhone page.
struct ModelRoutingPageContent: View {
    @Bindable var session: ModelRoutingSession

    var body: some View {
        List {
            if let observation = session.observation {
                Section("Policy") {
                    Picker("Routing policy", selection: Binding(
                        get: { session.policy },
                        set: { new in Task { await session.setPolicy(new) } }
                    )) {
                        ForEach(RoutingPolicy.allCases, id: \.self) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(observation.decision.reason)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("On-device availability") {
                    LabeledContent("Route") {
                        Text(observation.onDevice.isAvailable ? "Available" : "Unavailable")
                    }
                    Text(observation.onDevice.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Private Cloud Compute eligibility") {
                    ForEach(observation.pcc.gates) { gate in
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(gate.kind.title) {
                                Text(gate.state.rawValue)
                            }
                            Text(gate.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Section("Chosen route") {
                    LabeledContent("Would run") {
                        Text(observation.decision.route.title)
                    }
                    LabeledContent("Leaves device") {
                        Text(observation.decision.route.leavesDevice ? "Yes, after consent" : "No")
                    }
                }
                if let preview = observation.preview {
                    Section("Proposed outgoing fields") {
                        ForEach(preview.fields) { field in
                            VStack(alignment: .leading, spacing: 2) {
                                LabeledContent(field.name) {
                                    Text("\(field.characterCount) characters")
                                }
                                Text(field.value)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            Section("Fallback") {
                Button("Generate local excerpt") {
                    Task { await session.runLocal() }
                }
                .disabled(session.isBusy || session.prompt.isEmpty)
                .accessibilityHint("Produces a deterministic excerpt on this device.")
                if let summary = session.localSummary {
                    Text(summary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if session.localSummary != nil {
                    Button("Review demo annotation") {
                        Task { await session.prepareAnnotation() }
                    }
                    .disabled(session.isBusy || session.prompt.isEmpty)
                }
                if session.pendingAnnotation != nil {
                    Text("Append the displayed local summary to \(session.annotationTarget ?? "the demo sample")’s note.")
                    Button("Save approved annotation") {
                        Task { await session.approveAnnotation() }
                    }
                    .disabled(session.isBusy || session.pendingAnnotation?.isReady != true)
                }
                TextField("Manual answer", text: $session.manualAnswer, axis: .vertical)
                    .lineLimit(2...6)
                Button("Record manual answer") {
                    Task { await session.runManual() }
                }
                .disabled(session.isBusy || session.manualAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("Cloud attempt") {
                Button("Grant consent for previewed fields") {
                    Task { await session.grantConsent() }
                }
                .disabled(session.policy != .cloudAllowed || session.isBusy)
                Button("Attempt Private Cloud Compute") {
                    Task { await session.attemptCloud() }
                }
                .disabled(session.isBusy || session.prompt.isEmpty)
                Text("This build has no live cloud adapter. The preview shows the lab’s proposed fields.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = session.message {
                Section("Status") {
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !session.usage.isEmpty {
                Section("Usage receipts (no raw prompt)") {
                    ForEach(session.usage) { receipt in
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(receipt.route.title) {
                                Text(receipt.outcome.rawValue)
                            }
                            Text(receipt.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !receipt.outgoingFieldNames.isEmpty {
                                Text(
                                    "Fields: "
                                        + zip(receipt.outgoingFieldNames, receipt.outgoingFieldLengths)
                                        .map { "\($0.0) (\($0.1))" }
                                        .joined(separator: ", ")
                                )
                                .font(.caption2.monospaced())
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if let record = session.lastStoreReceipt {
                Section("Lab receipt") {
                    NavigationLink {
                        ReceiptDetailView(record: record)
                            .navigationTitle("Receipt")
                    } label: {
                        ReceiptRow(record: record)
                    }
                }
            }
            Section {
                Button("Reset Demo", role: .destructive) {
                    Task { await session.resetDemo() }
                }
                .disabled(session.isBusy || session.prompt.isEmpty)
                Text("Clears only this experiment's usage and consent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(ModelRoutingExperiment.title)
    }
}
