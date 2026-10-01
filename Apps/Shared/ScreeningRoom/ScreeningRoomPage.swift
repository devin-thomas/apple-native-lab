import LabCatalog
import ScreeningRoom
import ScreeningRoomPlayback
import SwiftUI

/// Native Screening Room on iPhone and iPad (LAB-031): the player, its controls, the clips, what
/// this device offers, the companion stand-in, and the receipts, in one scrolling page.
struct ScreeningRoomPage: View {
    let model: ScreeningRoomModel
    @State private var isConfirmingReset = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                ScreeningPlayerArea(model: model)
                    .listRowInsets(EdgeInsets())
                ScreeningStatus(model: model)
                ScreeningTransport(model: model)
                    .frame(maxWidth: .infinity)
                ScreeningCaptionPicker(model: model)
                ScreeningSurfaceControls(model: model)
            }
            Section("Clips") {
                ScreeningClipList(model: model)
            }
            Section("On this device") {
                ScreeningReadinessList(readiness: model.readiness)
            }
            Section("Companion remote") {
                ScreeningCompanionPanel(model: model)
            }
            Section("Receipts") {
                ScreeningReceiptList(model: model)
            }
            Section {
                Button("Reset Screening…", role: .destructive) { isConfirmingReset = true }
                    .accessibilityIdentifier("screening.reset")
            } footer: {
                Text("Returns the Test Card to the start with captions off and removes the saved resume point. Nothing else changes.")
            }
        }
        .navigationTitle(ScreeningRoom.title)
        .screeningTheater(model)
        .screeningResetConfirmation(isPresented: $isConfirmingReset, model: model)
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.persist() } }
        .onDisappear { model.persist() }
    }
}

extension View {
    /// Asks before the experiment's Reset, which removes the saved resume point.
    func screeningResetConfirmation(isPresented: Binding<Bool>, model: ScreeningRoomModel) -> some View {
        confirmationDialog("Reset the screening?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Reset Screening", role: .destructive) {
                Task {
                    await model.reset()
                    if let notice = model.notice { LabAnnouncement(text: notice.message).post() }
                }
            }
        } message: {
            Text("The Test Card returns to the start with captions off, and the saved resume point is removed. Nothing outside Native Screening Room changes.")
        }
    }
}

/// The catalog page's way in: on the Mac it shows the experiment in this window (⌃⌘1); on iPhone
/// and iPad it opens the page.
struct ScreeningRoomLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == ScreeningRoom.experimentID {
            #if os(macOS)
            Button {
                window?.destination = .screeningRoom
            } label: {
                Label("Open \(ScreeningRoom.title)", systemImage: ScreeningRoom.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .disabled(window == nil)
            .help("Show the experiment in this window (⌃⌘1)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            NavigationLink {
                ScreeningRoomPage(model: ScreeningRoomHost.model)
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Open \(ScreeningRoom.title)", systemImage: ScreeningRoom.symbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .accessibilityHint("Opens the experiment.")
            .accessibilityIdentifier("screening.open")
            #endif
        }
    }
}
