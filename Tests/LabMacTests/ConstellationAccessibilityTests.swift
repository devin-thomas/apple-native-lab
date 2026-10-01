import AppKit
import Foundation
import LocalConstellation
import PeerSession
import SwiftUI
import Testing
@testable import NativeLab

/// LAB-019: the single-device simulation's real views in the running Mac app, operated through the
/// accessibility press action as VoiceOver or Voice Control would. The code is typed through the
/// model: the hosted harness has no way to type into a text field. This is not a VoiceOver pass.
@MainActor
@Suite(.serialized) struct ConstellationAccessibilityTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "ConstellationAccessibilityTests-\(UUID().uuidString)")

    @Test func theFallbackPairsCommandsAndGoesStaleThroughItsControls() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let simulation = ConstellationSimulation(
            backend: LibraryShowBackend(library: library), storeDescription: "a test store", sheet: try CueSheet.bundled()
        )
        await simulation.start()
        let hosted = AccessHostedView(VStack(alignment: .leading) {
            SimulatedConductorSection(model: simulation)
            SimulatedDeviceSection(model: simulation, role: .controller)
        }.environment(library))
        defer { hosted.close() }

        // The controller's Ask to Join opens pairing; the conductor shows the code and Allow.
        #expect(try await hosted.press("Ask to Join"))
        let asked = try await hosted.elements(until: { $0.contains { $0.role == "AXButton" && $0.label == "Allow" } })
        let request = try #require(simulation.conductor?.pairingRequest, "\(asked.dump)")
        #expect(asked.contains { $0.spoken.contains("Code \(request.code.digits.map(String.init).joined(separator: " "))") }, "\(asked.dump)")
        #expect(await simulation.submitCode(request.code.description, on: .controller))
        #expect(try await hosted.press("Allow"))
        _ = try await hosted.elements(until: { _ in simulation.controller?.phase == .live })
        #expect(simulation.controller?.phase == .live)

        // The controller's Next moves the show, and its board reads the new cue.
        #expect(try await hosted.press("Next"))
        let moved = try await hosted.elements(until: { $0.contains { $0.spoken.hasPrefix("Cue 2 of 6, Lanterns.") } })
        #expect(moved.filter { $0.spoken.hasPrefix("Cue 2 of 6, Lanterns.") }.count >= 2, "the conductor's and the controller's boards")

        // Out of range: the controller's board and the conductor's roster say stale, in words.
        #expect(try await hosted.press("Walk Out of Range"))
        try await Task.sleep(for: .seconds(2.5))
        let stale = try await hosted.elements(until: { elements in
            elements.contains { $0.spoken.contains("Nothing heard from the conductor") }
                && elements.contains { $0.spoken.contains("Stale") && $0.spoken.contains("Controller (simulated phone)") }
        })
        #expect(stale.contains { $0.spoken.contains("Nothing heard from the conductor") }, "\(stale.dump)")
        #expect(stale.contains { $0.spoken.contains("Stale") && $0.spoken.contains("Controller (simulated phone)") }, "\(stale.dump)")
        #expect(stale.contains { $0.role == "AXButton" && $0.label == "Bring Back in Range" })
        await simulation.stop()
    }
}
