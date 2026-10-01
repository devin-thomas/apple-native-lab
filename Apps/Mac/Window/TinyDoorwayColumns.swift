import LabDomain
import SwiftUI
import TinyDoorway

/// Mac content column: fixtures and the paste field.
struct TinyDoorwayListColumn: View {
    @Bindable var window: MainWindowState
    @Bindable var session: DoorwaySession
    @Environment(LabLibrary.self) private var library

    var body: some View {
        List {
            Section {
                DoorwayHeader()
            }
            Section("Fixtures") {
                DoorwayFixtureList(session: session, library: library)
            }
            Section("Paste a link") {
                DoorwayLinkField(session: session, library: library)
            }
        }
        .overlay {
            if library.collections.isEmpty { LibraryPhaseView() }
        }
        .navigationTitle(TinyDoorwayExperiment.title)
        .navigationSplitViewColumnWidth(min: 280, ideal: 340)
    }
}

/// Mac detail column: App Clip status, review/confirm, information page, result, reset.
struct TinyDoorwayDetailColumn: View {
    @Bindable var window: MainWindowState
    @Bindable var session: DoorwaySession
    @Environment(LabLibrary.self) private var library

    var body: some View {
        Form {
            Section("App Clip") {
                DoorwayClipStatusRow(status: session.clipStatus)
            }
            if case .proposal = session.validation {
                Section("Review") {
                    DoorwayProposalReview(session: session, library: library) { record in
                        window.inspect(record)
                    }
                }
            }
            if session.showsInformation {
                Section("Information") {
                    DoorwayInformationPage()
                }
            }
            if session.outcome != nil || session.message != nil {
                Section("Result") {
                    DoorwayResultSection(outcome: session.outcome, message: session.message)
                }
            }
            Section("Experiment data") {
                DoorwayResetControls(session: session, library: library)
                Text("Reset Visits removes only the visit marker from demo samples.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Fallback") {
                Text(DoorwayFallback.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(TinyDoorwayExperiment.title)
    }
}
