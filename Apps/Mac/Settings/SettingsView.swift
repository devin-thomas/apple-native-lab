import SwiftUI

/// Settings holds only what acts on this Mac's data: which namespaces exist and how much each
/// holds, and Reset Demo with its own confirmation.
struct SettingsView: View {
    @Environment(LabLibrary.self) private var library
    @State private var isConfirmingReset = false
    @State private var lastReset: ReceiptRecord?

    var body: some View {
        Form {
            Section {
                NamespaceSummary()
            } header: {
                Text("Data namespaces")
            } footer: {
                Text("Both live in one file in this app's container: \(LabStoreLocation.displayPath). Nothing leaves this Mac.")
            }
            Section {
                LabeledContent("Seed") {
                    Text(seedDescription)
                        .monospacedDigit()
                }
                HStack {
                    ResetDemoButton(isConfirming: $isConfirmingReset)
                    if library.isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Working")
                    }
                }
                if let lastReset {
                    let presentation = ReceiptPresentation(lastReset)
                    VStack(alignment: .leading, spacing: 4) {
                        ReceiptStatusLabel(presentation: presentation)
                        Text(presentation.summary)
                        Text("Operation \(presentation.operationID)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
                LibraryFailureBanner()
            } header: {
                Text("Demo")
            } footer: {
                Text("Reset Demo restores every sample to the seed and removes demo entries the seed no longer lists. It asks first, and it never changes your data.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .resetDemoConfirmation(isPresented: $isConfirmingReset) { lastReset = $0 }
        .task { await library.start() }
    }

    private var seedDescription: String {
        guard let seed = library.seed else { return "Not loaded" }
        return "Version \(seed.seed.version) · \(seed.seed.collections.count) collections · \(seed.seed.items.count) items"
    }
}
