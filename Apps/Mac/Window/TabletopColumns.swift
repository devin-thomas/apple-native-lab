import LabDomain
import SwiftUI
import TabletopReality

/// The content column for Tabletop Reality (LAB-023): the object list, the scene's accessible
/// form, filtered by the window's search. It is the window's results stop: Command-9, Tab to this
/// list, and the arrow keys select an object; Option with an arrow then moves it, Option-[ and
/// Option-] turn it, and Command-Delete removes it. Each row's VoiceOver actions do the same.
struct TabletopListColumn: View {
    @Bindable var window: MainWindowState
    @Bindable var session: TabletopSession
    @Environment(LabLibrary.self) private var library

    var body: some View {
        let shown = session.entries.filter { Self.matches($0, window.searchText) }
        List(selection: $session.selectedAnchorID) {
            Section {
                ForEach(shown) { entry in
                    if case .anchor(let id) = entry.subject {
                        SceneEntryRow(entry: entry)
                            .accessibilityElement(children: .combine)
                            .modifier(EntryActions(entry: entry, session: session))
                            .tag(id)
                    } else {
                        SceneEntryRow(entry: entry)
                            .accessibilityElement(children: .combine)
                            .selectionDisabled()
                    }
                }
                if session.anchors.isEmpty, session.phase == .ready {
                    SectionNote("The table is empty. Place an object, or set out the starter scene.")
                }
            } header: {
                Text("Objects on the table")
            }
            Section("Result") {
                TabletopResult(session: session) { window.inspect($0) }
            }
        }
        .contextMenu(forSelectionType: AnchorID.self) { selection in
            if let id = selection.first {
                Button("Turn Left", systemImage: "rotate.left") { Task { await session.turn(clockwise: false, id, in: library) } }
                Button("Turn Right", systemImage: "rotate.right") { Task { await session.turn(clockwise: true, id, in: library) } }
                Button("Remove", systemImage: "trash", role: .destructive) { Task { await session.remove(id, in: library) } }
            }
        }
        .accessibilityLabel("Objects on the table, \(session.anchors.count == 1 ? "1 object" : "\(session.anchors.count) objects")")
        .navigationTitle(TabletopExperiment.title)
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        .task { await session.start(in: library) }
        // Reset Demo, an undo from the inspector, or another window can change the table.
        .onChange(of: library.latestReceipt?.id) { Task { await session.refresh(in: library) } }
        .onChange(of: session.lastRecord) { _, record in if let record { window.inspect(record) } }
    }

    static func matches(_ entry: SceneEntry, _ text: String) -> Bool {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return [entry.label, entry.value, entry.detail].contains { $0.localizedStandardContains(needle) }
    }
}

/// The detail column: the orbitable virtual table, then tracking, the route, placing, the
/// selected object's controls, and the table's actions. The Mac has no AR camera, so the virtual
/// table is its whole route, and the route section says why.
struct TabletopDetailColumn: View {
    let session: TabletopSession

    var body: some View {
        Form {
            Section {
                VirtualTabletopScene(session: session)
                    .frame(minHeight: 340)
            } footer: {
                Text("Drag to orbit and scroll to zoom. Click the table to place the chosen object; click an object to select it.")
            }
            Section("Tracking") {
                TrackingStatusSection(session: session)
            }
            Section("Route") {
                RouteSection(session: session)
            }
            Section("Place") {
                PlacementControls(session: session)
            }
            Section("Selected object") {
                SelectionControls(session: session)
            }
            Section("Table") {
                TableActions(session: session)
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            session.stopReplay()
            session.cancelList()
        }
    }
}
