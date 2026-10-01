import AudioWorkshop
import SwiftUI

/// The content column for the Audio Workshop (LAB-029): the safety controls, the playback state,
/// the inspectable graph, and the render stats. Play, Panic Mute, and Bypass are also in the Lab
/// menu with shortcuts, so they are reachable from anywhere in the app.
struct AudioWorkshopListColumn: View {
    @Bindable var window: MainWindowState
    var session = AudioWorkshopSession.shared

    var body: some View {
        Form {
            Section {
                WorkshopSafetyControls(session: session)
                WorkshopStateLine(session: session)
                if let message = session.message {
                    Text(message).font(.footnote)
                }
            }
            WorkshopGraphSection(session: session)
            WorkshopStatsSection(session: session)
            Section {
                Button("Reset Workshop", systemImage: "arrow.counterclockwise") { session.resetDemo() }
                SectionNote("Stops playback and returns the graph, MIDI log, and render to their first-run state. Saved presets stay.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(AudioWorkshop.title)
        .navigationSplitViewColumnWidth(min: 320, ideal: 380)
    }
}

/// The detail column: the sound, MIDI, the offline fallback, presets, and the plugin form.
struct AudioWorkshopDetailColumn: View {
    @Bindable var window: MainWindowState
    var session = AudioWorkshopSession.shared

    var body: some View {
        Form {
            WorkshopSoundSection(session: session)
            WorkshopMidiSection(session: session)
            WorkshopOfflineSection(session: session)
            WorkshopPresetsSection(session: session) { window.inspect($0) }
            WorkshopPluginSection(session: session)
        }
        .formStyle(.grouped)
    }
}
