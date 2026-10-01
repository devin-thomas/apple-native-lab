import ScreeningRoom
import ScreeningRoomPlayback
import SwiftUI

/// The content column for Native Screening Room (LAB-031): the clips, what this Mac offers, the
/// companion stand-in, and the receipts.
struct ScreeningRoomListColumn: View {
    @State private var isConfirmingReset = false
    private let model = ScreeningRoomHost.model

    var body: some View {
        List {
            Section("Clips") {
                ScreeningClipList(model: model)
            }
            Section("On this Mac") {
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
                SectionNote("Returns the Test Card to the start with captions off and removes the saved resume point. Nothing else changes.")
            }
        }
        .navigationTitle(ScreeningRoom.title)
        .navigationSplitViewColumnWidth(min: 300, ideal: 360)
        .screeningResetConfirmation(isPresented: $isConfirmingReset, model: model)
        .task { await model.start() }
    }
}

/// The detail column: the player with the system's controls, and the lab's own controls below it.
struct ScreeningRoomDetailColumn: View {
    private let model = ScreeningRoomHost.model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreeningPlayerArea(model: model)
                ScreeningStatus(model: model)
                HStack(spacing: 24) {
                    ScreeningTransport(model: model)
                    ScreeningCaptionPicker(model: model)
                        .frame(maxWidth: 240)
                    ScreeningSurfaceControls(model: model)
                }
                SectionNote("The player's own controls, caption menu, full-screen and Picture in Picture buttons, and the media keys all reach the same screening. Moving between surfaces keeps the position and the captions.")
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .screeningTheater(model)
        .task { await model.start() }
        .onDisappear { model.persist() }
    }
}
