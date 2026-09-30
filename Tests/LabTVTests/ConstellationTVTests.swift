import Foundation
import LocalConstellation
import PeerSession
import Testing
@testable import NativeLabTV

/// LAB-019 inside the built Apple TV app: the show's fixture is in the bundle, the app declares
/// its Bonjour service and local network purpose, and the simulation runs a whole show with the
/// display on this Apple TV, stored in memory. Nothing here browses or advertises.
@MainActor
@Suite(.serialized) struct ConstellationTVTests {
    @Test func theAppDeclaresItsLocalNetworkUseAndBundlesTheCueSheet() throws {
        let services = Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String]
        #expect(services == [LocalConstellation.serviceType])
        #expect((Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String)?.isEmpty == false)
        #expect(try CueSheet.bundled().cues.count == 6)
    }

    @Test func theSimulationShowsTheConductorsCueOnTheDisplay() async throws {
        let model = TVConstellationModel()
        await model.startSimulation()
        let simulation = try #require(model.simulation)
        let pairing = Task { await simulation.pair(.display) }
        let request = try await wait { simulation.conductor?.pairingRequest }
        _ = try await wait { simulation.display?.codePrompt }
        #expect(await simulation.submitCode(request.code.digits, on: .display))
        await simulation.answerPairing(allow: true)
        await pairing.value
        await simulation.conductorMove(.goTo(cue: 2))
        _ = try await wait { simulation.display?.snapshot?.cueTitle == "Tide line" ? true : nil }
        #expect(model.joiner == nil, "nothing was browsed")
        await simulation.stop()
    }

    private func wait<Value>(_ read: @MainActor () -> Value?) async throws -> Value {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if let value = read() { return value }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out")
        throw CancellationError()
    }
}
