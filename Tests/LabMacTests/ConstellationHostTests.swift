import Foundation
import LabDomain
import LocalConstellation
import PeerSession
import Testing
@testable import NativeLab

/// LAB-019 in the sandboxed Mac host: the single-device simulation over the host's own
/// `LabLibrary`. A simulated controller's start request, allowed at the conductor, commits through
/// `LabDataService` as the authorized peer and lists its receipt beside every other receipt; Reset
/// Demo pauses the show and the display follows. Each test uses a fresh store, never the app's own.
@MainActor
@Suite(.serialized) struct ConstellationHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ConstellationHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func started() async throws -> (LabLibrary, ConstellationSimulation) {
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let simulation = ConstellationSimulation(
            backend: LibraryShowBackend(library: library), storeDescription: "a test store", sheet: try CueSheet.bundled()
        )
        await simulation.start()
        return (library, simulation)
    }

    private func pair(_ role: PeerRole, in simulation: ConstellationSimulation) async throws {
        let pairing = Task { await simulation.pair(role) }
        let request = try await waitFor { simulation.conductor?.pairingRequest }
        _ = try await waitFor { simulation.state(of: role)?.codePrompt }
        #expect(await simulation.submitCode(request.code.description, on: role))
        await simulation.answerPairing(allow: true)
        await pairing.value
        _ = try await waitFor { simulation.state(of: role)?.phase == .live ? true : nil }
    }

    private func waitFor<Value>(_ timeout: Duration = .seconds(5), _ read: @MainActor () -> Value?) async throws -> Value {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let value = read() { return value }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out")
        throw CancellationError()
    }

    @Test func anAllowedPeerRequestCommitsAsTheAuthorizedPeerWithAReceiptInTheHostsList() async throws {
        let (library, simulation) = try await started()
        try await pair(.controller, in: simulation)
        try await pair(.display, in: simulation)
        let receiptsBefore = library.receipts.count

        await simulation.send(.start)
        let pending = try await waitFor { simulation.conductor?.pending.first }
        #expect(pending.command == .start)
        #expect(library.receipts.count == receiptsBefore, "nothing is committed while the request waits")
        await simulation.allow(pending.commandID)
        _ = try await waitFor { simulation.display?.snapshot?.isRunning == true ? true : nil }

        let record = try #require(library.receipts.first)
        #expect(record.receipt.admitted.adapter == .authorizedPeer)
        #expect(record.receipt.admitted.operation == .setSession(id: LocalConstellation.showSessionID, expected: nil, running: true))
        #expect(ReceiptPresentation(record).adapter == "Authorized peer")
        let service = try await library.openedService()
        #expect(try await service.session(LocalConstellation.showSessionID, as: LabDataService.appUI)?.isRunning == true)
        await simulation.stop()
    }

    @Test func resetDemoPausesTheShowAndTheDisplayFollows() async throws {
        let (library, simulation) = try await started()
        try await pair(.display, in: simulation)
        await simulation.conductorSetRunning(true)
        _ = try await waitFor { simulation.display?.snapshot?.isRunning == true ? true : nil }
        #expect(library.receipts.first?.receipt.admitted.adapter == .appUI)

        _ = try #require(await library.resetDemo())
        await ConstellationModel.shared.storeChanged()
        await simulation.syncFromStore()
        _ = try await waitFor { simulation.display?.snapshot?.isRunning == false ? true : nil }
        await simulation.stop()
    }

    @Test func theSidebarDestinationRoundTrips() {
        #expect(SidebarDestination(storageKey: SidebarDestination.localConstellation.storageKey) == .localConstellation)
        #expect(SidebarDestination.localConstellation.title == "Local Constellation")
    }

    /// The release manifest checks what CoreLocal links; this checks what it declares.
    @Test func theCoreLocalMacDeclaresNoLocalNetworkUse() throws {
        let info = try #require(Bundle.main.infoDictionary)
        #expect(info["LabBuildProfile"] as? String == "CoreLocal")
        #expect(info["NSBonjourServices"] == nil)
        #expect(info["NSLocalNetworkUsageDescription"] == nil)
    }
}
