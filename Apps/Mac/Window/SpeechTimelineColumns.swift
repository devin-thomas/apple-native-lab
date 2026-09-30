import SwiftUI

/// The content column for Speech Timeline (LAB-013): the language, the on-device routes, Record,
/// and the fallback. The session lives in `SpeechTimelineModel.shared`, so moving to another
/// destination and back keeps it.
struct SpeechTimelineListColumn: View {
    @State private var model = SpeechTimelineModel.shared

    var body: some View {
        // Controls, not a selection list, so a grouped form like the detail column.
        Form {
            SpeechSourcesSections(model: model)
        }
        .formStyle(.grouped)
        .navigationTitle("Speech Timeline")
        .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        .task { await model.refreshSupport() }
    }
}

/// The detail column: the scrubber, the segments, annotation, and saving. A save's receipt opens
/// in the inspector.
struct SpeechTimelineDetailColumn: View {
    @Bindable var window: MainWindowState
    @State private var model = SpeechTimelineModel.shared

    var body: some View {
        Form {
            SpeechTimelineSections(model: model) { record in
                window.inspect(record)
            }
        }
        .formStyle(.grouped)
    }
}
