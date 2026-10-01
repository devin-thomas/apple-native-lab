import LabCatalog
import LabDomain
import SwiftUI
import WalletMoment

/// Wallet Moment on one page: unsigned pass preview, sample event card, update inspection, and
/// the signing boundary. iPhone and iPad push it from the experiment's catalog page.
struct WalletMomentPage: View {
    @Environment(LabLibrary.self) private var library
    @State private var session: WalletMomentSession

    init(session: WalletMomentSession = WalletMomentSession()) {
        _session = State(initialValue: session)
    }

    var body: some View {
        List {
            Section {
                PassPreviewCard(preview: session.preview)
            } header: {
                Text("Local pass preview")
            } footer: {
                Text("Fallback: local pass preview and sample event card. No Wallet install is claimed here.")
            }
            WalletMomentControls(session: session, library: library)
            if session.message != nil || session.lastReceipt != nil {
                Section("Result") {
                    if let message = session.message {
                        Text(message)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let record = session.lastReceipt {
                        NavigationLink {
                            ReceiptDetailView(record: record)
                                .navigationTitle("Receipt")
                                #if os(iOS)
                                .navigationBarTitleDisplayMode(.inline)
                                #endif
                        } label: {
                            ReceiptRow(record: record)
                        }
                    }
                }
            }
        }
        .navigationTitle(WalletMomentExperiment.title)
    }
}

/// The experiment's entry on its catalog page. Shown only on LAB-038's page.
struct WalletMomentLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == WalletMomentExperiment.id {
            #if os(macOS)
            Button {
                window?.destination = .walletMoment
            } label: {
                Label("Open \(WalletMomentExperiment.title)", systemImage: WalletMomentExperiment.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .disabled(window == nil)
            .help("Show the experiment in this window (⌘9)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            NavigationLink {
                WalletMomentPage()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Open \(WalletMomentExperiment.title)", systemImage: WalletMomentExperiment.symbol)
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
