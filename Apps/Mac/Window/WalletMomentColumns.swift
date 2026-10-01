import SwiftUI
import WalletMoment

/// Mac list and detail columns for Wallet Moment.
struct WalletMomentListColumn: View {
    @Bindable var window: MainWindowState
    @Bindable var session: WalletMomentSession
    @Environment(LabLibrary.self) private var library

    var body: some View {
        List {
            Section("Preview clock") {
                Button("Before the event") { session.showBeforeEvent() }
                Button("During the event") { session.showDuringEvent() }
                Button("After expiry") { session.showAfterExpiry() }
            }
            Section("Actions") {
                Button("Apply seat update") {
                    Task { await session.applySeatUpdate(in: library) }
                }
                Button("Save event card") {
                    Task { await session.saveEventCard(in: library) }
                }
                .disabled(library.phase != .ready || session.isRunning || library.isWorking)
                Button("Request operator-signed test pass") {
                    Task { await session.requestSignedPass() }
                }
                Button("Reset sample card") {
                    Task { await session.resetEventCard(in: library) }
                }
                .disabled(session.isRunning || library.isWorking)
            }
        }
        .navigationTitle(WalletMomentExperiment.title)
    }
}

struct WalletMomentDetailColumn: View {
    @Bindable var window: MainWindowState
    @Bindable var session: WalletMomentSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PassPreviewCard(preview: session.preview)
                if let signingMessage = session.signingMessage {
                    Text(signingMessage)
                        .foregroundStyle(.secondary)
                }
                if let signedNote = session.signedNote {
                    Text(signedNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let message = session.message {
                    Text(message)
                }
                if let record = session.lastReceipt {
                    Button { window.inspect(record) } label: {
                        ReceiptRow(record: record)
                    }
                    .buttonStyle(.plain)
                }
                Text("Fallback: local pass preview and sample event card. Signing keys stay outside this client.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: 560, alignment: .leading)
        }
        .navigationTitle("Sample event card")
    }
}
