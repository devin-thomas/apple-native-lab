import LabCatalog
import SwiftUI
import TinyDoorway

/// Tiny Doorway on one page for iPhone and iPad.
struct TinyDoorwayPage: View {
    @Environment(LabLibrary.self) private var library
    @State private var session = DoorwaySession()

    var body: some View {
        List {
            Section { DoorwayHeader() }
            Section("App Clip") {
                DoorwayClipStatusRow(status: session.clipStatus)
            }
            Section("Open a link") {
                DoorwayLinkField(session: session, library: library)
            }
            Section("Fixtures") {
                DoorwayFixtureList(session: session, library: library)
            }
            if case .proposal = session.validation {
                Section("Review") {
                    DoorwayProposalReview(session: session, library: library)
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
                    if let record = session.outcome?.record {
                        NavigationLink {
                            ReceiptDetailView(record: record)
                                .navigationTitle("Receipt")
                                #if os(iOS)
                                .navigationBarTitleDisplayMode(.inline)
                                #endif
                        } label: {
                            Text("Open receipt")
                        }
                    }
                }
            }
            Section("Experiment data") {
                DoorwayResetControls(session: session, library: library)
                Text("Reset Visits removes only the visit marker. Lab › Reset Demo restores every demo sample to the seed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .overlay {
            if library.collections.isEmpty { LibraryPhaseView() }
        }
        .navigationTitle(TinyDoorwayExperiment.title)
        .onDisappear { session.cancelReset() }
    }
}

/// The catalog page's Open button for LAB-039.
struct TinyDoorwayLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == TinyDoorwayExperiment.id {
            #if os(macOS)
            Button {
                window?.destination = .tinyDoorway
            } label: {
                Label("Open \(TinyDoorwayExperiment.title)", systemImage: TinyDoorwayExperiment.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .disabled(window == nil)
            .help("Show Tiny Doorway in this window (⌘9)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            NavigationLink {
                TinyDoorwayPage()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Open \(TinyDoorwayExperiment.title)", systemImage: TinyDoorwayExperiment.symbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .accessibilityHint("Opens the experiment.")
            #endif
        }
    }
}
