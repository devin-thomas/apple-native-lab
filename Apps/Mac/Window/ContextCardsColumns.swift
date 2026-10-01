import ContextCards
import SwiftUI

/// The content column for Context Cards (LAB-002): the visible sample and the decision to set it aside.
struct ContextCardsListColumn: View {
    @Bindable var window: MainWindowState

    var body: some View {
        ContextCardsPage(session: window.contextCards, showsSchemaNote: false) { window.inspect($0) }
            .navigationSplitViewColumnWidth(min: 320, ideal: 420)
    }
}

/// The detail column: why a schema is not adopted, and where the same decision lives in Shortcuts.
struct ContextCardsDetailColumn: View {
    var body: some View {
        Form {
            Section {
                Text("A lab sample is not adopted as a note, a book, or any other Apple schema. Claiming one fails, and the sample on screen stays as it was.")
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Schema")
            }
            Section {
                Text("Ask About Visible Sample reads a sample you name. Set Aside Visible Sample asks you to confirm, then archives it. Neither needs Siri. Context resolution stays unavailable.")
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Shortcuts")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Schema")
    }
}
