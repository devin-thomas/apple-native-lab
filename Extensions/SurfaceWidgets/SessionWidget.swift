import SurfaceDeck
import SwiftUI
import WidgetKit

/// One timeline entry: the presentation of the snapshot as read at `confirmedAt`.
struct SessionEntry: TimelineEntry {
    let date: Date
    let presentation: SurfacePresentation
}

/// Reads the snapshot file, and only that file, whenever WidgetKit asks. The refresh policy is
/// `SessionTimeline`: the snapshot now, the same snapshot marked stale an hour later, and one
/// refresh requested then. The app asks for a reload only when the snapshot changes.
struct SessionTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SessionEntry {
        SessionEntry(date: .now, presentation: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SessionEntry) -> Void) {
        let now = Date.now
        completion(SessionEntry(date: now, presentation: SurfacePresentation(
            reading: SessionSnapshotFile.currentReading(), confirmedAt: now, now: now
        )))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SessionEntry>) -> Void) {
        let timeline = SessionTimeline(reading: SessionSnapshotFile.currentReading(), now: .now)
        completion(Timeline(
            entries: timeline.entries.map { SessionEntry(date: $0.date, presentation: $0.presentation) },
            policy: .after(timeline.refreshAfter)
        ))
    }
}

struct SessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SurfaceDeck.widgetKind, provider: SessionTimelineProvider()) { entry in
            SessionWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Demo Session")
        .description("Shows Native Lab's demo session and starts or pauses it. Details stay hidden unless you show them in the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct SessionWidgetEntryView: View {
    let entry: SessionEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        SessionWidgetView(presentation: entry.presentation, layout: layout) {
            // The toggle runs the same intent as the Control, carrying the revision this entry
            // shows, so a stale widget reconciles instead of overwriting a newer change.
            Toggle(
                isOn: entry.presentation.isOn,
                intent: SetDemoSessionIntent(showing: entry.presentation.state, surface: .widget)
            ) {
                Text("Running")
            }
            .font(.caption)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var layout: SessionWidgetLayout {
        switch family {
        case .systemMedium: .medium
        case .accessoryRectangular: .accessory
        default: .small
        }
    }
}
