import LocalConstellation
import PeerSession
import SwiftUI

/// The content column for Local Constellation (LAB-019): this Mac as the conductor of the
/// single-device simulation, with its requests, peers, wire log, and events.
struct ConstellationListColumn: View {
    @Environment(LabLibrary.self) private var library
    @State private var model = ConstellationModel.shared
    @State private var simulation: ConstellationSimulation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let simulation {
                    SimulatedConductorSection(model: simulation)
                } else if let problem = model.problem {
                    ContentUnavailableView("Show Unavailable", systemImage: "exclamationmark.triangle", description: Text(problem))
                } else {
                    ProgressView("Starting the simulation")
                }
            }
            .padding()
        }
        .navigationTitle(LocalConstellation.title)
        .navigationSplitViewColumnWidth(min: 340, ideal: 420)
        .modifier(ConstellationStoreWatcher(model: model))
        .task { simulation = await model.simulation(for: library) }
    }
}

/// The detail column: the simulated controller and display beside each other, then the live path.
struct ConstellationDetailColumn: View {
    @Environment(LabLibrary.self) private var library
    @State private var model = ConstellationModel.shared
    @State private var simulation: ConstellationSimulation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Pair each simulated device with the code the conductor shows. Then walk one out of range, lose a frame, disconnect, or restart the conductor, and watch both sides.")
                    .font(.callout)
                if let simulation {
                    HStack(alignment: .top, spacing: 24) {
                        SimulatedDeviceSection(model: simulation, role: .controller)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        SimulatedDeviceSection(model: simulation, role: .display)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                Divider()
                ConstellationLiveSection(model: model)
            }
            .padding(24)
            .frame(maxWidth: 1_000, alignment: .leading)
        }
        .task { simulation = await model.simulation(for: library) }
    }
}
