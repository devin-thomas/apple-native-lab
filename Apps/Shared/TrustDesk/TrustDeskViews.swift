import LabCatalog
import SwiftUI
import TrustDesk

/// The desk, shared by the Mac columns and the iPhone page. Local authorization and the passkey
/// simulation are separate sections, so the difference is on the screen.
struct TrustDeskForm: View {
    @Bindable var session: TrustDeskSession
    var onReceipt: (ReceiptRecord) -> Void = { _ in }
    @Environment(LabLibrary.self) private var library
    @State private var displayName = TrustDeskFixture.defaultDisplayName

    var body: some View {
        List {
            identitySection
            authorizationSection
            recordSection
            passkeySection
        }
        .navigationTitle(TrustDeskExperiment.title)
        .task { await session.refresh(in: library) }
        .onAppear { displayName = session.identity.displayName }
    }

    private var identitySection: some View {
        Section {
            LabeledContent("Identity") {
                Text(session.identity.id.account)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            TextField("Display name", text: $displayName)
                .accessibilityHint("Changing this name does not change the identity.")
            Button("Rename") {
                Task {
                    if let record = await session.rename(to: displayName, in: library) {
                        displayName = session.identity.displayName
                        onReceipt(record)
                    }
                }
            }
            .disabled(session.isRunning || library.phase != .ready)
        } header: {
            Text("Identity")
        } footer: {
            Text("The identity is the identifier above. The display name is only a label.")
        }
    }

    private var authorizationSection: some View {
        Section {
            Button("Authorize with this device") {
                Task { await session.authorizeWithDevice() }
            }
            .disabled(session.isRunning)
            Button("Confirm locally") { session.confirmLocally() }
                .disabled(session.isRunning)
                .accessibilityHint(TrustDeskFixture.localConfirmationLabel)
            if let grant = session.liveGrant {
                LabeledContent("Grant") {
                    Text(grant.method == .deviceOwner ? "This device" : "Local confirmation")
                }
                Button("Revoke authorization") { session.revokeGrant() }
            } else {
                Text("No live local authorization.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Local authorization")
        } footer: {
            Text("This unlocks the sealed record in this app. It is not an account sign-in. A grant lasts 60 seconds.")
        }
    }

    private var recordSection: some View {
        Section {
            Button("Open the sealed record") {
                Task {
                    if let record = await session.openSealedRecord(in: library) { onReceipt(record) }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.liveGrant == nil || session.isRunning || library.phase != .ready)
            Button("Reset Desk") {
                Task {
                    if let record = await session.reset(in: library) {
                        displayName = session.identity.displayName
                        onReceipt(record)
                    } else {
                        displayName = session.identity.displayName
                    }
                }
            }
            .disabled(session.isRunning)
            if let message = session.message {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let receipt = session.receipt {
                Text(receipt.receipt.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Receipt: \(receipt.receipt.summary)")
            }
        } header: {
            Text("Sealed record")
        } footer: {
            Text("Opening stores the fixture secret in a keychain record scoped to this identity. The note and the receipt do not contain it.")
        }
    }

    private var passkeySection: some View {
        Section {
            Text(session.passkeyLabel)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Relying party") {
                Text(TrustDeskFixture.relyingPartyID)
            }
            if let reference = session.passkeyReference {
                LabeledContent("Credential") {
                    Text(reference.account)
                        .font(.body.monospaced())
                        .lineLimit(2)
                }
                Text("Not an exportable app secret.")
                    .foregroundStyle(.secondary)
            }
            Button("Register simulated passkey") { session.registerPasskey() }
                .disabled(session.isRunning)
            Button("Authenticate with simulated passkey") { session.authenticatePasskey() }
                .disabled(session.passkeyReference == nil || session.isRunning)
            if let summary = session.assertionSummary {
                Text(summary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Passkey protocol simulation")
        } footer: {
            Text("A simulated authentication does not unlock the sealed record. Local authorization does. This is not a system passkey.")
        }
    }
}

/// The experiment on iPhone and iPad, pushed from its catalog page.
struct TrustDeskScreen: View {
    @State private var session = TrustDeskSession()

    var body: some View {
        TrustDeskForm(session: session)
    }
}

/// The catalog page's way in. Shown only on LAB-041.
struct TrustDeskLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == TrustDeskExperiment.id {
            #if os(macOS)
            Button {
                window?.destination = .trustDesk
            } label: {
                Label("Open \(TrustDeskExperiment.title)", systemImage: TrustDeskExperiment.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .disabled(window == nil)
            .help("Show the experiment in this window (⌘9)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            NavigationLink {
                TrustDeskScreen()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Open \(TrustDeskExperiment.title)", systemImage: TrustDeskExperiment.symbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .accessibilityHint("Opens the experiment.")
            #endif
        }
    }
}
