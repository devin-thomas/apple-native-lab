import CommerceWithoutTricks
import LabCatalog
import SwiftUI

/// The commerce desk, shared by the Mac columns and the iPhone page. Purchase scripts and product
/// terms stay visible so the charge boundary is never hidden.
struct CommerceForm: View {
    @Bindable var session: CommerceSession
    var searchText = ""
    var onReceipt: (ReceiptRecord) -> Void = { _ in }
    @Environment(LabLibrary.self) private var library

    var body: some View {
        List {
            boundarySection
            productsSection
            actionsSection
            statusSection
        }
        .navigationTitle(CommerceExperiment.title)
    }

    private var boundarySection: some View {
        Section {
            Text(session.chargeBoundary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Charge boundary")
        } footer: {
            Text("History lasts for this screen’s session. Reopening starts a new simulation; saved lab receipts remain.")
        }
    }

    private var filteredProducts: [CommerceProduct] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return session.products }
        return session.products.filter {
            $0.displayName.localizedStandardContains(query) || $0.id.rawValue.localizedStandardContains(query)
        }
    }

    private var productsSection: some View {
        Section {
            if filteredProducts.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
            ForEach(filteredProducts) { product in
                Button {
                    session.selectedProductID = product.id
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(product.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if session.selectedProductID == product.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        Text(product.displayPrice)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(product.terms)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("State: \(session.state(for: product.id).title)")
                            .font(.caption.weight(.semibold))
                        if let entitlement = session.entitlement(for: product.id) {
                            Text(entitlement.noteSummary)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityLabel("\(product.displayName), \(session.state(for: product.id).title)")
                .accessibilityHint(product.terms)
                .disabled(session.isRunning)
            }
        } header: {
            Text("Test products")
        }
    }

    private var actionsSection: some View {
        Section {
            Text(CommerceFixture.product(id: session.selectedProductID)?.displayName ?? "Choose a product")
                .font(.headline)
            Picker("Simulate purchase as", selection: $session.purchaseScript) {
                Text("Verified").tag(SimulatedPurchaseScript.verified)
                Text("Unverified").tag(SimulatedPurchaseScript.unverified)
                Text("Pending approval").tag(SimulatedPurchaseScript.pendingApproval)
                Text("Cancelled").tag(SimulatedPurchaseScript.cancelled)
                Text("Failed").tag(SimulatedPurchaseScript.failed)
            }
            .disabled(session.isRunning)
            .accessibilityHint("Chooses how the local simulator resolves the purchase. None creates a real charge.")

            Button("Simulate purchase (no charge)") {
                Task {
                    if let record = await session.purchase(in: library) { onReceipt(record) }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isRunning || library.phase != .ready || session.isOffline)

            Button("Simulate approval") {
                Task {
                    if let record = await session.approvePending(in: library) { onReceipt(record) }
                }
            }
            .disabled(session.isRunning || library.phase != .ready || session.isOffline)

            Button("Restore simulated purchases") {
                Task {
                    if let record = await session.restore(in: library) { onReceipt(record) }
                }
            }
            .disabled(session.isRunning || library.phase != .ready || session.isOffline)
            .accessibilityHint("Restores from this screen's session history. No Apple Account is required.")

            Button("Simulate refund") {
                Task {
                    if let record = await session.refund(in: library) { onReceipt(record) }
                }
            }
            .disabled(session.isRunning || library.phase != .ready)

            Button("Simulate revocation") {
                Task {
                    if let record = await session.revoke(in: library) { onReceipt(record) }
                }
            }
            .disabled(session.isRunning || library.phase != .ready)

            Button(session.isOffline ? "Go online" : "Go offline") {
                session.setOffline(!session.isOffline)
            }
            .disabled(session.isRunning)

            Button("Reset Commerce") {
                Task {
                    if let record = await session.reset(in: library) {
                        onReceipt(record)
                    }
                }
            }
            .disabled(session.isRunning || library.phase != .ready)
        } header: {
            Text("Actions")
        } footer: {
            Text("Every entitlement write goes through the lab's authorization and receipt path. Unverified transactions grant nothing.")
        }
    }

    private var statusSection: some View {
        Section {
            if let message = session.message {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let receipt = session.receipt {
                Text("Last committed receipt: \(receipt.receipt.summary)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Last committed receipt: \(receipt.receipt.summary)")
            }
        } header: {
            Text("Status")
        }
    }
}

#if os(iOS)
struct CommerceScreen: View {
    @State private var session = CommerceSession()

    var body: some View {
        CommerceForm(session: session)
    }
}
#endif

struct CommerceLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == CommerceExperiment.id {
            #if os(macOS)
            Button {
                window?.destination = .commerceWithoutTricks
            } label: {
                Label("Open \(CommerceExperiment.title)", systemImage: CommerceExperiment.symbol)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(window == nil)
            .help("Show Commerce Without Tricks in this window (⌘9)")
            .accessibilityHint("Shows buy, restore, refund, and offline states with no real charge.")
            #else
            NavigationLink {
                CommerceScreen()
            } label: {
                Label("Open \(CommerceExperiment.title)", systemImage: CommerceExperiment.symbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Exercise buy, restore, refund, pending, and offline states with no real charge.")
            #endif
        }
    }
}
