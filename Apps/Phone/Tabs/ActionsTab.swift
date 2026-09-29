import LabDomain
import SwiftUI

/// Action Atlas on iPhone: every action, each opening its form. Receipts open from each form.
struct ActionsTab: View {
    @Environment(LabLibrary.self) private var library

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AtlasBrowserHeader()
                }
                ForEach(AtlasAction.Group.allCases, id: \.self) { group in
                    Section(group.rawValue) {
                        ForEach(AtlasAction.allCases.filter { $0.group == group }) { action in
                            NavigationLink(value: action) {
                                AtlasActionRow(action: action)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Action Atlas")
            .navigationDestination(for: AtlasAction.self) { action in
                AtlasActionForm(action: action)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(for: OperationID.self) { id in
                if let record = library.receipt(id: id) {
                    ReceiptDetailView(record: record)
                        .navigationTitle("Receipt")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }
}
