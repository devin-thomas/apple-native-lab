import FindTheThing
import SwiftUI

/// The shelf labels. Selecting one shows it beside the answer.
struct FindTheThingListColumn: View {
    @Bindable var session: FindTheThingSession

    var body: some View {
        List(selection: $session.selectedID) {
            ForEach(MessyCollection.corpus) { record in
                FindTheThingRecordRow(record: record, indexed: session.indexedIDs.contains(record.id))
                    .tag(record.id)
            }
        }
        .navigationTitle(FindTheThing.title)
        .task { await session.prepare() }
    }
}

/// The search, the cited records, and the index actions.
struct FindTheThingDetailColumn: View {
    @Bindable var session: FindTheThingSession

    var body: some View {
        FindTheThingPage(session: session, showsRecords: false)
    }
}
