import SwiftUI

/// The content column for Action Atlas: every action, grouped, filtered by the window's search.
struct ActionAtlasListColumn: View {
    @Bindable var window: MainWindowState

    var body: some View {
        let actions = AtlasAction.matching(window.searchText)
        List(selection: $window.atlasAction) {
            Section {
                AtlasBrowserHeader()
            }
            ForEach(AtlasAction.Group.allCases, id: \.self) { group in
                let members = actions.filter { $0.group == group }
                if !members.isEmpty {
                    Section(group.rawValue) {
                        ForEach(members) { action in
                            AtlasActionRow(action: action)
                                .tag(action)
                        }
                    }
                }
            }
        }
        .overlay {
            if actions.isEmpty {
                ContentUnavailableView.search(text: window.searchText)
            }
        }
        .navigationTitle("Action Atlas")
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
    }
}

/// The detail column for Action Atlas: the selected action's form. Each receipt opens in the
/// window's receipt inspector, the same inspector that shows receipts from App Intents.
struct ActionAtlasDetailColumn: View {
    @Bindable var window: MainWindowState

    var body: some View {
        if let action = window.atlasAction {
            AtlasActionForm(action: action) { record in
                window.inspect(record)
            }
            .id(action)
        } else {
            ContentUnavailableView(
                "Select an Action", systemImage: "bolt.horizontal",
                description: Text("Every action runs here without Siri or Shortcuts, through the same operation as its Shortcuts action.")
            )
        }
    }
}
