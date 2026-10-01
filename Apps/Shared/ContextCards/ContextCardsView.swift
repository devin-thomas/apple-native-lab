import ActionAtlas
import ContextCards
import LabCatalog
import LabDomain
import Observation
import SwiftUI

/// The Context Cards screen in this app (LAB-002): one sample, the decision to set it aside, and
/// the other sample that replaces it.
///
/// Setting aside archives the sample through the same operation the Shortcut uses. Replacing the
/// sample publishes a new generation, and a decision captured against the previous one is refused
/// before anything is archived. Reset Demo restores a demo sample.
@MainActor
@Observable
final class ContextCardsSession {
    private(set) var item: LabItem?
    private(set) var board = ContextBoard()
    private(set) var message: String?
    /// Whether `message` is a refusal. A committed set-aside is not.
    private(set) var messageIsFailure = false
    private(set) var busy = false
    private var showingReplacement = false

    var card: DecisionCard? {
        guard let context = board.context, let item else { return nil }
        return DecisionCard.showing(title: context.title, note: item.note.value, siriEnabled: false)
    }

    /// The activity type from the host's Info.plist, or `nil` when this process has none.
    static var activityType: String? {
        Bundle.main.object(forInfoDictionaryKey: ContextCards.activityTypeInfoKey) as? String
    }

    func showPrimary() async {
        showingReplacement = false
        await show(ContextCards.primarySampleID)
    }

    func showOther() async {
        showingReplacement.toggle()
        let id = showingReplacement ? ContextCards.replacementSampleID : ContextCards.primarySampleID
        await show(id)
    }

    func prepareDecision() {
        message = nil
        messageIsFailure = false
        board.prepareDecision()
    }

    func cancelDecision() {
        board.cancelDecision()
        message = nil
        messageIsFailure = false
    }

    /// Confirms the waiting decision. A sample that has left the screen is not archived.
    func confirm(in library: LabLibrary, onReceipt: (ReceiptRecord) -> Void) async {
        guard let proposal = board.proposal, !busy else { return }
        busy = true
        defer { busy = false }
        let actions = ContextCardsHost.link.actions(.appUI)
        do {
            let outcome = try await actions.setAside(proposal, request: AtlasRequest(), confirm: { _ in })
            message = ContextCards.completedDialog(summary: outcome.receipt.summary)
            messageIsFailure = false
            board.cancelDecision()
            if let record = library.receipt(id: outcome.receipt.operationID) {
                onReceipt(record)
                LabAnnouncement(receipt: ReceiptPresentation(record)).post()
            }
            await show(proposal.itemID, keepMessage: true)
        } catch let error as ContextCardsError {
            message = error.message
            messageIsFailure = true
            LabAnnouncement(failure: error.message).post()
        } catch {
            let text = ContextCardsError.cancelled.message
            message = text
            messageIsFailure = true
            LabAnnouncement(failure: text).post()
        }
    }

    private func show(_ id: ItemID, keepMessage: Bool = false) async {
        if !keepMessage {
            message = nil
            messageIsFailure = false
        }
        do {
            try await publish(id)
        } catch {
            message = error.message
            messageIsFailure = true
        }
    }

    /// Reads the sample and publishes it. A thrown error leaves the previous sample on screen.
    private func publish(_ id: ItemID) async throws(ContextCardsError) {
        let actions = ContextCardsHost.link.actions(.appUI)
        let item = try await actions.read(id)
        try board.show(item)
        self.item = item
        ContextCardsHost.link.publish(board.context)
    }
}

/// The card, the decision, and the other sample. The Mac also shows the schema note in its detail
/// column; the iPhone includes it here.
struct ContextCardsPage: View {
    @Bindable var session: ContextCardsSession
    var showsSchemaNote: Bool
    var onReceipt: (ReceiptRecord) -> Void = { _ in }
    @State private var isConfirmingReset = false
    @Environment(LabLibrary.self) private var library

    var body: some View {
        Form {
            sampleSection
            decisionSection
            if showsSchemaNote {
                schemaSection
            }
            Section {
                ResetDemoButton(isConfirming: $isConfirmingReset)
            } footer: {
                Text("Setting a demo sample aside is a real change with a receipt. Reset Demo restores every sample. Your own data is not changed.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(ContextCards.title)
        .resetDemoConfirmation(isPresented: $isConfirmingReset) { record in
            onReceipt(record)
            Task { await session.showPrimary() }
        }
        .task { await session.showPrimary() }
        .onDisappear { ContextCardsHost.link.publish(nil) }
    }

    @ViewBuilder private var sampleSection: some View {
        Section {
            if let card = session.card, let item = session.item, let context = session.board.context {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.title)
                        .font(.title2)
                    if !card.note.isEmpty {
                        Text(card.note)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(item.isArchived ? "Set aside." : "On screen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(card.contextResolution)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .visibleSample(itemID: item.id.rawValue, title: context.title, activityType: ContextCardsSession.activityType)
                .accessibilityElement(children: .combine)
            } else if session.message == nil {
                ProgressView("Opening the lab…")
            }
            Button(session.board.context?.itemID == ContextCards.primarySampleID ? "Show the other sample" : "Show the first sample") {
                Task { await session.showOther() }
            }
            .disabled(session.busy)
        } header: {
            Text("Visible sample")
        }
    }

    @ViewBuilder private var decisionSection: some View {
        Section {
            if let message = session.message {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(session.messageIsFailure ? "Problem: \(message)" : message)
            }
            if let proposal = session.board.proposal, let card = session.card {
                Text(session.board.decisionIsStale
                    ? "This decision is for “\(proposal.title)”, which is no longer on screen."
                    : card.prompt)
                    .fixedSize(horizontal: false, vertical: true)
                Button(card.acceptLabel) {
                    Task { await session.confirm(in: library, onReceipt: onReceipt) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(session.busy)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint(session.board.decisionIsStale
                    ? "Refuses the decision. \(proposal.title) is not changed."
                    : "Sets \(proposal.title) aside. The receipt offers an undo.")
                Button(card.cancelLabel) { session.cancelDecision() }
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
            } else if session.item?.isArchived == true {
                Text("This sample is set aside. Reset Demo restores it.")
                    .foregroundStyle(.secondary)
            } else if session.card != nil {
                Button("Set Aside…") { session.prepareDecision() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(session.busy)
                    .accessibilityHint("Prepares the decision. Nothing is changed until you confirm.")
            }
        } header: {
            Text("Decision")
        } footer: {
            Text("Shortcuts can run Ask About Visible Sample and Set Aside Visible Sample. Both work with Siri off. Ask names the sample you choose, because context resolution is unavailable.")
        }
    }

    private var schemaSection: some View {
        Section {
            Text("A lab sample is not adopted as a note, a book, or any other Apple schema. Claiming one fails, and the sample on screen stays as it was.")
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Schema")
        }
    }
}

/// The experiment's entry on its catalog page.
struct ContextCardsLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == ContextCards.experimentID {
            #if os(macOS)
            Button {
                window?.destination = .contextCards
            } label: {
                Label("Open \(ContextCards.title)", systemImage: ContextCards.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .disabled(window == nil)
            .help("Show the experiment in this window (⌥⌘2)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            ContextCardsPhoneLink()
            #endif
        }
    }
}

#if os(iOS)
/// Keeps one session for the pushed screen, so a refresh of the catalog page does not replace it.
private struct ContextCardsPhoneLink: View {
    @State private var session = ContextCardsSession()

    var body: some View {
        NavigationLink {
            ContextCardsPage(session: session, showsSchemaNote: true)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            Label("Open \(ContextCards.title)", systemImage: ContextCards.symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .accessibilityHint("Opens the experiment.")
    }
}
#endif
