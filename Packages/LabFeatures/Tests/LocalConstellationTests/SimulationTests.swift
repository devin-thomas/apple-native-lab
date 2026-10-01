import Foundation
import LabDomain
@testable import LocalConstellation
import PeerSession
import Testing

/// LAB-019: the single-device simulation, the declared fallback, runs the whole interaction with
/// the real session layer on real time.
@MainActor
@Suite(.serialized) struct SimulationTests {
    func pair(_ role: PeerRole, in simulation: ConstellationSimulation) async throws {
        let pairing = Task { await simulation.pair(role) }
        let request = try await eventually { await MainActor.run { simulation.conductor?.pairingRequest } }
        let state: @MainActor () -> ClientState<Constellation>? = { role == .controller ? simulation.controller : simulation.display }
        _ = try await eventually { await MainActor.run { state()?.codePrompt } }
        #expect(await simulation.submitCode(request.code.description, on: role))
        await simulation.answerPairing(allow: true)
        await pairing.value
        try await until { await MainActor.run { state()?.phase == .live } }
    }

    @Test func theFallbackCompletesTheInteractionAndADisconnectedClientBecomesStale() async throws {
        let simulation = ConstellationSimulation(backend: ServiceShowBackend.inMemory(), storeDescription: "In-memory store", sheet: try CueSheet.bundled())
        await simulation.start()
        try await pair(.controller, in: simulation)
        try await pair(.display, in: simulation)

        await simulation.send(.next)
        try await until { await MainActor.run { simulation.display?.snapshot?.cueTitle == "Lanterns" } }
        await simulation.point(x: 0.25, y: 0.75)
        try await until { await MainActor.run { simulation.display?.samples.values.first?.sample == Pointer(x: 0.25, y: 0.75) } }

        await simulation.send(.start)
        let pending = try await eventually { await MainActor.run { simulation.conductor?.pending.first } }
        await simulation.allow(pending.commandID)
        try await until { await MainActor.run { simulation.display?.snapshot?.isRunning == true } }
        #expect(simulation.wire.contains { $0.kind == "snapshot" && $0.outgoing })

        // The clock estimates find the simulated devices' offsets.
        try await until(.seconds(3)) { await MainActor.run { simulation.conductor?.peers.allSatisfy { $0.clock != nil } == true } }
        for peer in simulation.conductor?.peers ?? [] {
            let truth = try #require(simulation.trueOffsets[peer.role])
            let estimate = try #require(peer.clock)
            #expect(abs((estimate.offset - truth).wholeNanoseconds) <= (estimate.uncertainty + .milliseconds(5)).wholeNanoseconds)
        }

        // The display walks out of range: both sides show it stale, without anyone closing a link.
        simulation.setLinkDown(.display, true)
        try await until(.seconds(5)) {
            await MainActor.run {
                let peer = simulation.conductor?.peers.first { $0.role == .display }
                if case .stale = peer?.presence { return simulation.display?.phase == .stale }
                return false
            }
        }
        simulation.setLinkDown(.display, false)
        try await until(.seconds(3)) { await MainActor.run { simulation.conductor?.peers.first { $0.role == .display }?.presence == .live } }

        await simulation.strangerTriesToJoin()
        #expect(simulation.lastOutcome?.contains("received no session data") == true)
        await simulation.stop()
    }
}
