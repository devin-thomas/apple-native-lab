import LabDomain
import PickUpHere
import SwiftUI

/// Drafts this window can continue (LAB-016).
struct PickUpListColumn: View {
    @Bindable var window: MainWindowState
    @Environment(LabLibrary.self) private var library

    var body: some View {
        @Bindable var session = window.pickUp
        let rows = filtered(session.items)
        List(selection: $session.selectedItemID) {
            Section {
                Button("Add Sample Draft") { Task { await session.addSample(library) } }
                    .disabled(session.isWorking || !library.canAct)
                    .accessibilityHint("Adds an original three-section draft to one of your collections.")
            }
            Section("Drafts") {
                ForEach(rows) { item in
                    Text(item.title.value).tag(item.id)
                }
            }
        }
        .overlay {
            if rows.isEmpty, !window.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView.search(text: window.searchText)
            }
        }
        .navigationTitle("Pick Up Here")
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        .task { await session.load(library) }
        .onChange(of: library.latestReceipt?.id) { Task { await session.load(library) } }
        .onChange(of: session.selectedItemID) {
            session.selectedSection = 0
            session.isAdvertising = false
        }
    }

    private func filtered(_ items: [LabItem]) -> [LabItem] {
        let needle = window.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return items }
        return items.filter {
            $0.title.value.localizedStandardCompare(needle) == .orderedSame
                || $0.title.value.localizedCaseInsensitiveContains(needle)
        }
    }
}

/// The selected section, the advertisement, and an incoming link or document.
struct PickUpDetailColumn: View {
    @Bindable var window: MainWindowState
    @Environment(LabLibrary.self) private var library

    var body: some View {
        @Bindable var session = window.pickUp
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PickUpEditor(session: session)
                PickUpActions(session: session)
                PickUpIncoming(session: session)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Continue")
        .userActivity(HandoffActivity.activityType, isActive: session.isAdvertising) { activity in
            guard let offer = session.offer else { return }
            HandoffActivity.fill(activity, with: offer, handoffEligible: true)
        }
    }
}
