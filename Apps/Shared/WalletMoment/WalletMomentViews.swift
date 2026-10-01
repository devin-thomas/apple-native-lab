import SwiftUI
import WalletMoment

/// Shared Wallet Moment chrome: the unsigned pass preview and the sample event card.
struct PassPreviewCard: View {
    let preview: PassPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(preview.lifecycle.title, systemImage: lifecycleSymbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(preview.lifecycle == .expired ? .secondary : .primary)
            Text("Fixture replay · Unsigned")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(preview.headline)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(preview.detailLine)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Organization", value: preview.definition.organizationName)
            LabeledContent("Serial", value: preview.definition.serialNumber)
            LabeledContent("Barcode", value: preview.definition.barcode.altText)
            Text("Format: \(preview.definition.barcode.format.rawValue). Display only — not authorization.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(preview.signingNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(preview.lifecycle.sentence)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var lifecycleSymbol: String {
        switch preview.lifecycle {
        case .upcoming: "clock"
        case .active: "checkmark.seal"
        case .expired: "calendar.badge.exclamationmark"
        }
    }
}

struct WalletMomentControls: View {
    @Bindable var session: WalletMomentSession
    let library: LabLibrary

    var body: some View {
        Section("Clock") {
            Button("Before the event") { session.showBeforeEvent() }
            Button("During the event") { session.showDuringEvent() }
            Button("After expiry") { session.showAfterExpiry() }
        }
        Section("Updates") {
            Button("Apply seat update") {
                Task { await session.applySeatUpdate(in: library) }
            }
            .disabled(session.isRunning || library.isWorking)
            Button("Reset sample card") {
                Task { await session.resetEventCard(in: library) }
            }
            .disabled(session.isRunning || library.isWorking)
        }
        Section("Signing boundary") {
            Button("Request operator-signed test pass") {
                Task { await session.requestSignedPass() }
            }
            .disabled(session.isRunning)
            if let signingMessage = session.signingMessage {
                Text(signingMessage)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let signedNote = session.signedNote {
                Text(signedNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Operator signing is unavailable in this build. No signing credentials are loaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Section("Local event card") {
            Button("Save event card") {
                Task { await session.saveEventCard(in: library) }
            }
            .disabled(session.isRunning || library.isWorking || library.phase != .ready)
            Text("Saves through the operation service with a receipt. The barcode is stored as display metadata only.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
