import ShareIngress
import SwiftUI

/// The share sheet's content: progress while staging, then what happened to each item, in the
/// order they were shared. Messages name positions, never content.
struct ShareSheetView: View {
    let session: ShareSession

    var body: some View {
        NavigationStack {
            List {
                switch session.phase {
                case .staging(let count):
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                                .accessibilityHidden(true)
                            Text(count == 1 ? "Saving 1 item for review…" : "Saving \(count) items for review…")
                        }
                        .accessibilityElement(children: .combine)
                    }
                case .cancelling:
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                                .accessibilityHidden(true)
                            Text("Cancelling. Nothing from this share will be kept.")
                        }
                        .accessibilityElement(children: .combine)
                    }
                case .unavailable:
                    Section {
                        Text("Native Lab's inbox isn't available to this build: its shared App Group folder is missing. Nothing was saved. Copy the item and use Paste on Native Lab's Import tab instead.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .finished(let report):
                    Section {
                        Text(report.summary)
                            .font(.headline)
                    }
                    Section("Items") {
                        ForEach(report.outcomes) { outcome in
                            Label(outcome.message, systemImage: symbol(for: outcome.result))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Section {
                        Text("Open Native Lab's Import tab to review and add them to one of your collections. Nothing is added until you choose Add there.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle("Native Lab Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !session.isFinished {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { session.cancel() }
                            .disabled(session.phase == .cancelling)
                            .accessibilityHint("Stops saving and keeps nothing from this share")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { session.done() }
                        .disabled(!session.isFinished)
                }
            }
        }
    }

    private func symbol(for result: AttachmentResult) -> String {
        switch result {
        case .staged: "tray.and.arrow.down"
        case .duplicate: "equal.circle"
        case .refused: "xmark.octagon"
        case .cancelled: "stop.circle"
        }
    }
}
