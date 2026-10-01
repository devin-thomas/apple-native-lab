import CommercialFrontier
import LabCatalog
import SwiftUI

struct FrontierLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @State private var presented = false
    #endif
    var body: some View {
        if experiment.id == "LAB-048" {
            #if os(macOS)
            Button("Open Commercial Frontier Desk") { presented = true }
                .buttonStyle(.borderedProminent)
                .sheet(isPresented: $presented) {
                    NavigationStack {
                        FrontierView()
                            .toolbar {
                                Button("Done") { presented = false }.keyboardShortcut(.cancelAction)
                            }
                    }
                    .frame(minWidth: 520, minHeight: 580)
                }
            #else
            NavigationLink("Open Commercial Frontier Desk") { FrontierView() }
                .buttonStyle(.borderedProminent)
            #endif
        }
    }
}

struct FrontierView: View {
    @Environment(LabLibrary.self) private var library
    @State private var session = FrontierSession()
    var body: some View {
        Form {
            Text("Simulation — no system connection, audio transmission or device restrictions.")
            ForEach(FrontierCapabilityCase.allCases) { capability in
                Section(capability.title) {
                    Text(capability.gate)
                    let snapshot = session.snapshots[capability] ?? FrontierSnapshot()
                    if session.snapshots[capability] != nil {
                        Text(status(capability, snapshot))
                    } else {
                        Text("Saved status unavailable")
                    }
                    if capability == .carPlay && snapshot.active {
                        ForEach(FrontierFixture.audioRows, id: \.self) { Text($0) }
                    }
                    if capability == .screenTime { Text(FrontierFixture.escape) }
                    ForEach(actions(capability), id: \.self) { action in
                        Button(action.title) {
                            Task { await session.perform(action, capability: capability, library: library) }
                        }
                        .disabled(session.busy || session.snapshots[capability] == nil || (try? snapshot.applying(action, to: capability)) == nil)
                    }
                }
            }
            if session.snapshots.isEmpty {
                Button("Reload saved status") { Task { await session.refresh(library: library) } }
                    .disabled(session.busy)
            }
            if let message = session.message { Text(message).accessibilityAddTraits(.updatesFrequently) }
        }
        .formStyle(.grouped)
        .navigationTitle("Commercial Frontier Desk")
        .task { await session.refresh(library: library) }
    }

    private func actions(_ capability: FrontierCapabilityCase) -> [FrontierAction] {
        switch capability {
        case .pushToTalk: [.join, .leave, .reset]
        case .carPlay: [.connect, .disconnect, .reset]
        case .screenTime: [.authorizeSelf, .restrictSample, .revoke, .reset]
        }
    }
    private func status(_ capability: FrontierCapabilityCase, _ snapshot: FrontierSnapshot) -> String {
        switch capability {
        case .pushToTalk: snapshot.active ? "Joined sample channel" : "Not joined"
        case .carPlay: snapshot.active ? "Audio preview connected" : "Preview disconnected"
        case .screenTime: snapshot.restricted ? "Sample restricted (simulated)" : snapshot.active ? "Self-authorized (simulated), unrestricted" : "Unauthorized, unrestricted"
        }
    }
}
