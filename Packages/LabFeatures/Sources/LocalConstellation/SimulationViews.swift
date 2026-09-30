import PeerSession
import SwiftUI

extension ConstellationSimulation {
    /// The conductor's actions, bound to this simulation.
    public var conductorActions: ConductorActions {
        ConductorActions(
            openPairing: { Task { await self.openPairingOnly() } },
            answerPairing: { allow in Task { await self.answerPairing(allow: allow) } },
            allow: { id in Task { await self.allow(id) } },
            decline: { id in Task { await self.decline(id) } },
            setRunning: { running in Task { await self.conductorSetRunning(running) } },
            move: { command in Task { await self.conductorMove(command) } }
        )
    }

    /// A simulated device's actions.
    public func joinerActions(_ role: PeerRole) -> JoinerActions {
        JoinerActions(
            submitCode: { typed in Task { await self.submitCode(typed, on: role) } },
            cancelCode: { Task { await self.cancelCode(on: role) } },
            send: { command in Task { await self.send(command, from: role) } },
            point: { x, y in Task { await self.point(x: x, y: y) } }
        )
    }

    public func state(of role: PeerRole) -> ClientState<Constellation>? {
        role == .controller ? controller : display
    }

    func openPairingOnly() async {
        await openPairingWindow()
    }
}

/// A simulated device: its panel, and the controls that join it, break its link, and bring it
/// back.
public struct SimulatedDeviceSection: View {
    @Bindable var model: ConstellationSimulation
    let role: PeerRole

    public init(model: ConstellationSimulation, role: PeerRole) {
        self.model = model
        self.role = role
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(role == .controller ? "Controller: a simulated phone" : "Display: a simulated TV")
                .font(.title3.weight(.semibold))
            JoinerPanel(state: model.state(of: role), actions: model.joinerActions(role))
            SimulatedLinkControls(model: model, role: role)
        }
    }
}

/// Joining, and the faults a person can apply to one simulated device's link.
public struct SimulatedLinkControls: View {
    @Bindable var model: ConstellationSimulation
    let role: PeerRole

    public init(model: ConstellationSimulation, role: PeerRole) {
        self.model = model
        self.role = role
    }

    private var phase: ClientPhase? { model.state(of: role)?.phase }
    private var paired: Bool { model.state(of: role)?.host != nil }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !paired {
                Button("Ask to Join", systemImage: "person.badge.plus") { Task { await model.pair(role) } }
                    .accessibilityHint("Opens pairing on the conductor. It shows a code to type here.")
            } else {
                switch phase {
                case .disconnected, .idle:
                    Button("Reconnect", systemImage: "arrow.clockwise") { Task { await model.reconnect(role) } }
                        .accessibilityHint("Rejoins with the pinned identities, without a code.")
                default:
                    HStack {
                        Button(model.linksDown.contains(role) ? "Bring Back in Range" : "Walk Out of Range",
                               systemImage: model.linksDown.contains(role) ? "wifi" : "wifi.slash") {
                            model.setLinkDown(role, !model.linksDown.contains(role))
                        }
                        .accessibilityHint("Stops every frame in both directions without closing the link, so both sides notice only by silence.")
                        Button("Lose Next Frame", systemImage: "scissors") { model.dropNextFrame(from: role) }
                            .accessibilityHint("The next frame this device sends is lost, as on a lossy radio. The receiver sees a sequence gap.")
                        Button("Disconnect", systemImage: "bolt.horizontal") { Task { await model.disconnect(role) } }
                    }
                }
            }
        }
        .buttonStyle(.bordered)
    }
}

/// The simulation's conductor, with its wire log, events, and whole-simulation controls.
public struct SimulatedConductorSection: View {
    @Bindable var model: ConstellationSimulation

    public init(model: ConstellationSimulation) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Conductor: this device")
                .font(.title3.weight(.semibold))
            if let outcome = model.lastOutcome {
                Text(outcome)
                    .font(.callout)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityAddTraits(.updatesFrequently)
            }
            ConductorPanel(state: model.conductor, actions: model.conductorActions, trueOffsets: model.trueOffsets)
            VStack(alignment: .leading, spacing: 8) {
                Text("Test the session").font(.headline)
                Button("Unpaired Device Tries to Join", systemImage: "person.fill.questionmark") {
                    Task { await model.strangerTriesToJoin() }
                }
                .accessibilityHint("A device the conductor never paired asks to rejoin. It is refused before any session data.")
                Button("Restart the Conductor", systemImage: "restart") { Task { await model.restartConductor() } }
                    .accessibilityHint("A new epoch. Devices reconnect without a code; their older commands are refused.")
                Button("Start Over", systemImage: "arrow.counterclockwise") { Task { await model.reset() } }
                    .accessibilityHint("Forgets every pairing in the simulation. The show's stored state is kept.")
            }
            .buttonStyle(.bordered)
            VStack(alignment: .leading, spacing: 8) {
                Text("Wire").font(.headline)
                Text("Every frame is sealed and carried by the in-process loopback, byte for byte as a network would carry it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                WireLogList(lines: model.wire)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Events").font(.headline)
                SessionEventList(events: model.conductor?.events ?? [])
            }
            Text("The show's running flag is stored in \(model.storeDescription), through the operation service. Round trips here are microseconds and nothing leaves this device: a simulation, not a network measurement.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
