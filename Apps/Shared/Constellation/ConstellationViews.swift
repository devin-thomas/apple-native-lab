import LabCatalog
import LabDomain
import LocalConstellation
import PeerSession
import SwiftUI

/// Opens Local Constellation from its catalog page (LAB-019).
struct ConstellationLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == LocalConstellation.experimentID {
            #if os(macOS)
            Button {
                window?.destination = .localConstellation
            } label: {
                Label("Open \(LocalConstellation.title)", systemImage: LocalConstellation.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .disabled(window == nil)
            .help("Show the experiment in this window (⌘9)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            NavigationLink {
                ConstellationPage()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Open \(LocalConstellation.title)", systemImage: LocalConstellation.symbol)
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

/// Keeps the show in line with the store whenever a receipt arrives from any entry point.
struct ConstellationStoreWatcher: ViewModifier {
    @Environment(LabLibrary.self) private var library
    let model: ConstellationModel

    func body(content: Content) -> some View {
        content.onChange(of: library.receipts.first?.id) {
            Task { await model.storeChanged() }
        }
    }
}

/// The live path's section: in a Companions build, Host or Join on the local network; in a
/// CoreLocal build, why it is not here.
struct ConstellationLiveSection: View {
    @Environment(LabLibrary.self) private var library
    let model: ConstellationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live on the local network").font(.title3.weight(.semibold))
            #if LAB_PROFILE_COMPANIONS
            LiveControls(live: model.live, library: library)
            #else
            Text("This build has no local-network adapter: it is the CoreLocal build, which carries no network entitlement and links no network framework. The Companions builds (LabMac-Companions, LabPhone-Companions, and the Apple TV host) host and join live shows. The simulation above sends the same sealed messages.")
                .font(.callout)
                .foregroundStyle(.secondary)
            #endif
        }
    }
}

#if LAB_PROFILE_COMPANIONS
/// Host a show here, or join one; each first stages the local network permission.
struct LiveControls: View {
    let live: LiveConstellation
    let library: LabLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explicit only: nothing is advertised or browsed until you choose. Traffic stays on the local network (no cellular, no internet server), and every frame after pairing is sealed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let staging = live.staging {
                Text(staging).font(.callout)
            }
            if let conductor = live.conductor {
                LiveConductorView(conductor: conductor) { Task { await live.stopHosting() } }
            } else if let joiner = live.joiner {
                LiveJoinerView(joiner: joiner) { Task { await live.stopJoining() } }
            } else {
                HStack {
                    Button("Host a Live Show", systemImage: "antenna.radiowaves.left.and.right") {
                        Task { await live.host(library: library) }
                    }
                    Button("Join as Controller", systemImage: "iphone.radiowaves.left.and.right") {
                        Task { await live.join(as: .controller) }
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct LiveConductorView: View {
    let conductor: LiveConductor
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(conductor.deviceName): \(conductor.networkStatus.title)", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
            if conductor.networkStatus == .denied {
                Text("Local network access is off for Native Lab. Turn it on in Settings › Privacy & Security › Local Network, or use the simulation.")
                    .font(.callout)
            }
            if let outcome = conductor.lastOutcome { Text(outcome).font(.callout) }
            ConductorPanel(state: conductor.state, actions: ConductorActions(
                openPairing: { Task { await conductor.openPairing() } },
                answerPairing: { allow in Task { await conductor.answerPairing(allow: allow) } },
                allow: { id in Task { await conductor.allow(id) } },
                decline: { id in Task { await conductor.decline(id) } },
                setRunning: { running in Task { await conductor.setRunning(running) } },
                move: { command in Task { await conductor.move(command) } }
            ))
            WireLogList(lines: conductor.wire)
            Button("Stop Hosting", systemImage: "stop.fill", role: .destructive, action: stop)
                .buttonStyle(.bordered)
        }
    }
}

struct LiveJoinerView: View {
    let joiner: LiveJoiner
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Looking for conductors: \(joiner.networkStatus.title)", systemImage: "magnifyingglass")
                .font(.headline)
            if joiner.networkStatus == .denied {
                Text("Local network access is off for Native Lab. Turn it on in Settings › Privacy & Security › Local Network, or use the simulation.")
                    .font(.callout)
            }
            if joiner.state?.host == nil || joiner.state?.phase != .live {
                ForEach(joiner.conductors) { endpoint in
                    Button("Join \(endpoint.name)", systemImage: "arrow.right.circle") { Task { await joiner.join(endpoint) } }
                        .buttonStyle(.bordered)
                }
                if joiner.conductors.isEmpty {
                    Text("No conductor found yet. On a Mac, choose Host a Live Show.").foregroundStyle(.secondary)
                }
            }
            if let outcome = joiner.lastOutcome { Text(outcome).font(.callout) }
            JoinerPanel(state: joiner.state, actions: JoinerActions(
                submitCode: { typed in Task { await joiner.submitCode(typed) } },
                cancelCode: { Task { await joiner.cancelCode() } },
                send: { command in Task { await joiner.send(command) } },
                point: { x, y in Task { await joiner.point(x: x, y: y) } }
            ))
            HStack {
                if case .disconnected = joiner.state?.phase, joiner.joinedEndpoint != nil {
                    Button("Rejoin", systemImage: "arrow.clockwise") { Task { await joiner.rejoin() } }
                }
                Button("Stop", systemImage: "stop.fill", role: .destructive, action: stop)
            }
            .buttonStyle(.bordered)
        }
    }
}
#endif

#if os(iOS)
/// The experiment on iPhone and iPad: the conductor, the controller, and the display, one at a
/// time, then the live path.
struct ConstellationPage: View {
    enum Pane: String, CaseIterable, Identifiable {
        case conductor = "Conductor"
        case controller = "Controller"
        case display = "Display"
        var id: String { rawValue }
    }

    @Environment(LabLibrary.self) private var library
    @State private var model = ConstellationModel.shared
    @State private var simulation: ConstellationSimulation?
    @State private var pane = Pane.conductor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("A conductor, a controller, and a display, simulated on this device with the same sealed messages a local network would carry. Pair each device with the code the conductor shows, then try the faults.")
                    .font(.callout)
                if let simulation {
                    Picker("Device", selection: $pane) {
                        ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch pane {
                    case .conductor: SimulatedConductorSection(model: simulation)
                    case .controller: SimulatedDeviceSection(model: simulation, role: .controller)
                    case .display: SimulatedDeviceSection(model: simulation, role: .display)
                    }
                } else if let problem = model.problem {
                    ContentUnavailableView("Show Unavailable", systemImage: "exclamationmark.triangle", description: Text(problem))
                } else {
                    ProgressView("Starting the simulation")
                }
                Divider()
                ConstellationLiveSection(model: model)
            }
            .padding()
        }
        .navigationTitle(LocalConstellation.title)
        .modifier(ConstellationStoreWatcher(model: model))
        .task { simulation = await model.simulation(for: library) }
    }
}
#endif
