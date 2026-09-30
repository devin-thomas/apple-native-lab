import LabCatalog
import LocalConstellation
import PeerSession
import SwiftUI

/// Opens Local Constellation from its record (LAB-019). The only experiment with a module on
/// Apple TV so far.
///
/// It presents the screen over the catalog rather than pushing it, so the catalog's value-based
/// navigation is untouched, and Menu closes it.
struct ConstellationTVLaunch: View {
    let experiment: RegisteredExperiment
    @State private var isPresented = false

    var body: some View {
        if experiment.id == LocalConstellation.experimentID {
            Button {
                isPresented = true
            } label: {
                Label("Open \(LocalConstellation.title)", systemImage: LocalConstellation.symbol)
                    .font(.headline)
            }
            .accessibilityIdentifier("detail.open-constellation")
            .fullScreenCover(isPresented: $isPresented) {
                ConstellationScreen()
            }
        }
    }
}

/// The display, live or simulated, and the simulation's conductor and controller below it.
struct ConstellationScreen: View {
    @State private var model = TVConstellationModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                liveSection
                simulationSection
            }
            .padding(80)
        }
        .task { await model.startSimulation() }
    }

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Live on the local network").font(.title2.bold())
            Text("This Apple TV joins a conductor as its display. Nothing is browsed until you choose Join, and traffic stays on the local network.")
                .foregroundStyle(.secondary)
            if let staging = model.staging { Text(staging) }
            if let joiner = model.joiner {
                if joiner.networkStatus == .denied {
                    Text("Local network access is off for Native Lab. Turn it on in Settings, or use the simulation below.")
                }
                if joiner.state?.phase != .live {
                    ForEach(joiner.conductors) { endpoint in
                        Button("Join \(endpoint.name)") { Task { await joiner.join(endpoint) } }
                    }
                    if joiner.conductors.isEmpty {
                        Text("No conductor found yet. On a Mac or iPhone, choose Host a Live Show.").foregroundStyle(.secondary)
                    }
                }
                if let outcome = joiner.lastOutcome { Text(outcome) }
                JoinerPanel(state: joiner.state, actions: JoinerActions(
                    submitCode: { typed in Task { await joiner.submitCode(typed) } },
                    cancelCode: { Task { await joiner.cancelCode() } },
                    send: { _ in },
                    point: { _, _ in }
                ))
                HStack {
                    if case .disconnected = joiner.state?.phase, joiner.joinedEndpoint != nil {
                        Button("Rejoin") { Task { await joiner.rejoin() } }
                    }
                    Button("Stop") { Task { await model.stopJoining() } }
                }
            } else {
                Button("Join a Live Show as the Display") { Task { await model.joinAsDisplay() } }
            }
        }
    }

    @ViewBuilder private var simulationSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Simulation on this Apple TV").font(.title2.bold())
            Text("A conductor, a controller, and this display, with the same sealed messages a network would carry. Nothing leaves this Apple TV.")
                .foregroundStyle(.secondary)
            if let simulation = model.simulation {
                SimulatedDeviceSection(model: simulation, role: .display)
                SimulatedDeviceSection(model: simulation, role: .controller)
                SimulatedConductorSection(model: simulation)
            } else if let problem = model.problem {
                Text(problem)
            } else {
                ProgressView()
            }
        }
    }
}
