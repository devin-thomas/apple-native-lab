import SwiftUI

/// Home Scene Sandbox in the Mac window.
struct HomeSceneListColumn: View {
    @Bindable var window: MainWindowState
    var session: HomeSceneSession

    var body: some View {
        HomeSceneForm(session: session) { record in
            window.inspect(record)
        }
    }
}

struct HomeSceneDetailColumn: View {
    var session: HomeSceneSession

    var body: some View {
        List {
            Section {
                Text("Preview on/off and brightness for lights only. A disconnected lamp fails its own line and the scene as a whole does not succeed.")
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Partial failure")
            }
            Section {
                Text("Locks, doors, alarms, and heating are listed and excluded by default. Selecting them is refused before anything is submitted.")
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Excluded by default")
            }
            Section {
                Text(session.platformGate)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Live HomeKit")
            }
        }
        .navigationTitle("How this works")
    }
}
