import CommerceWithoutTricks
import SwiftUI

/// Commerce Without Tricks in the Mac window. The content column is the desk; the detail column
/// explains the charge boundary and the local simulator.
struct CommerceListColumn: View {
    @Bindable var window: MainWindowState
    var session: CommerceSession

    var body: some View {
        CommerceForm(session: session, searchText: window.searchText) { record in
            window.inspect(record)
        }
    }
}

struct CommerceDetailColumn: View {
    var session: CommerceSession

    var body: some View {
        List {
            Section {
                Text("Products and terms are original test fixtures. Buy, restore, refund, pending approval, and offline states run in the local transaction-state simulator. Restoration reads this screen’s session history and does not need an Apple Account or a private developer account.")
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Local transaction-state simulator")
            }
            Section {
                Text("An unverified transaction never produces a VerifiedEntitlement and never writes the store. A verified grant commits as createItem or updateItem through the operation service, with a receipt in the inspector.")
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Verification before entitlement")
            }
            if session.isOffline {
                Section {
                    Text("The simulator is offline. Previously verified entitlements stay readable.")
                } header: {
                    Text("Offline")
                }
            }
        }
        .navigationTitle("How it works")
    }
}
