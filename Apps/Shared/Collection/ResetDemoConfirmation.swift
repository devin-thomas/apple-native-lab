import SwiftUI

/// The one confirmation every Reset Demo entry point uses. It says what changes, what does not,
/// and that there is no undo, and it can always be cancelled.
///
/// An alert rather than a confirmation dialog: on iPhone a confirmation dialog opens as a popover
/// from its toolbar button and shows no Cancel button, while an alert always shows one.
struct ResetDemoConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    var onReset: (ReceiptRecord) -> Void
    @Environment(LabLibrary.self) private var library

    func body(content: Content) -> some View {
        content.alert("Reset the demo?", isPresented: $isPresented) {
            Button("Reset Demo", role: .destructive) {
                Task {
                    let record = await library.resetDemo()
                    if let record { onReset(record) }
                    LabAnnouncement.outcome(of: record, in: library)?.post()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.message(library))
        }
    }

    static func message(_ library: LabLibrary) -> String {
        let seed = library.seed.map { "\($0.seed.collections.count) collections and \($0.seed.items.count) items" }
            ?? "the original samples"
        let user = library.census.map { census in
            " Your data (\(census.user.collections) collections, \(census.user.items) items) is not changed."
        } ?? " Your data is not changed."
        return "Every demo sample returns to its original content (\(seed)), and demo entries the seed no longer lists are removed.\(user) There is no undo."
    }
}

extension View {
    func resetDemoConfirmation(isPresented: Binding<Bool>, onReset: @escaping (ReceiptRecord) -> Void = { _ in }) -> some View {
        modifier(ResetDemoConfirmation(isPresented: isPresented, onReset: onReset))
    }
}

/// The button that asks for that confirmation.
struct ResetDemoButton: View {
    @Binding var isConfirming: Bool
    @Environment(LabLibrary.self) private var library

    var body: some View {
        Button("Reset Demo…", systemImage: "arrow.counterclockwise") {
            isConfirming = true
        }
        .disabled(!library.canAct)
        .accessibilityHint("Asks before restoring every demo sample. Your own data is not changed.")
    }
}

/// What the library is doing when it has nothing to show yet, or why it cannot.
struct LibraryPhaseView: View {
    @Environment(LabLibrary.self) private var library

    var body: some View {
        switch library.phase {
        case .notStarted, .opening:
            ProgressView("Opening the lab store…")
        case .unavailable(let reason):
            ContentUnavailableView("Lab Collection Unavailable", systemImage: "externaldrive.badge.exclamationmark",
                                   description: Text(reason))
        case .ready:
            ContentUnavailableView("No Demo Samples", systemImage: "tray",
                                   description: Text("Reset Demo creates the original samples."))
        }
    }
}

/// The last failure, shown until the next action succeeds.
struct LibraryFailureBanner: View {
    @Environment(LabLibrary.self) private var library

    var body: some View {
        if let failure = library.failure {
            Label(failure, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: .rect(cornerRadius: 8))
                .accessibilityLabel("Problem: \(failure)")
        }
    }
}
