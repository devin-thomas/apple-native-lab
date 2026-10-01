import Foundation
import HomeSceneSandbox
import LabDomain
import Observation
import SwiftUI

/// LAB-037's names in the catalog and the sidebar.
enum HomeSceneExperiment {
    static let id = "LAB-037"
    static let title = "Home Scene Sandbox"
    static let symbol = "house.fill"
}

/// One screen's home-scene sandbox. Preview and commit go through `LabLibrary.submit`.
@MainActor
@Observable
final class HomeSceneSession {
    private let sandbox: HomeSceneSandbox
    private(set) var home: HomeSnapshot?
    private(set) var proposal: SceneProposal?
    private(set) var report: SceneCommitReport?
    private(set) var message: String?
    private(set) var receipt: ReceiptRecord?
    private(set) var isRunning = false
    private(set) var livingOn = true
    private(set) var livingBrightness = 70
    private(set) var hallwayOn = false
    private(set) var hallwayBrightness = 20
    private(set) var includeHallway = true

    @ObservationIgnored private var commitRequest: RequestID?
    @ObservationIgnored private var resetRequest: RequestID?

    init(source: any HomeAccessSource = FictionalHomeSource()) {
        sandbox = HomeSceneSandbox(source: source)
    }

    var route: HomeRoute { sandbox.route }
    var simulationLabel: String { sandbox.simulationLabel }
    var platformGate: String { sandbox.platformGate }

    func refresh() async {
        do {
            home = try await sandbox.refreshHome()
            rebuildProposal()
            message = nil
        } catch let error as HomeSceneError {
            if case .permissionRevoked = error {
                home = try? await sandbox.refreshHome()
            }
            message = error.message
            LabAnnouncement(failure: error.message).post()
        } catch {
            message = "The home could not be loaded."
        }
    }

    func requestLiveAccess() async {
        guard begin() else { return }
        defer { isRunning = false }
        do {
            let permission = try await sandbox.requestLiveAccess()
            message = permission.allowsLiveMode ? permission.explanation : platformGate
            home = try await sandbox.refreshHome()
            rebuildProposal()
            LabAnnouncement(text: message ?? "").post()
        } catch let error as HomeSceneError {
            message = error.message
            LabAnnouncement(failure: error.message).post()
        } catch {
            message = "Home access could not be requested."
        }
    }

    func useSimulatedHome() async {
        sandbox.useSimulatedHome()
        await refresh()
        message = FictionalHome.simulationLabel
    }

    func setLiving(on: Bool) {
        livingOn = on
        rebuildProposal()
    }

    func setLivingBrightness(_ value: Double) {
        livingBrightness = Int(value.rounded())
        rebuildProposal()
    }

    func setHallway(on: Bool) {
        hallwayOn = on
        rebuildProposal()
    }

    func setHallwayBrightness(_ value: Double) {
        hallwayBrightness = Int(value.rounded())
        rebuildProposal()
    }

    func setIncludeHallway(_ value: Bool) {
        includeHallway = value
        rebuildProposal()
    }

    func commit(in library: LabLibrary) async -> ReceiptRecord? {
        guard begin() else { return nil }
        defer { isRunning = false }
        rebuildProposal()
        let requestID = commitRequest ?? RequestID()
        commitRequest = requestID
        do {
            let outcome = try await sandbox.commit(
                through: LibraryHomeSceneBackend(library: library),
                requestID: requestID
            )
            commitRequest = nil
            report = outcome.report
            home = try? await sandbox.refreshHome()
            rebuildProposal()
            let sentence = outcome.report.explanation
            message = sentence
            let record = library.receipt(id: outcome.receipt.operationID)
                ?? ReceiptRecord(receipt: outcome.receipt, recordedAt: .now, names: [
                    .item(FictionalHome.item): outcome.receipt.summary,
                    .collection(FictionalHome.collection): FictionalHome.collectionTitle,
                ])
            receipt = record
            if outcome.report.sceneSucceeded {
                LabAnnouncement(text: sentence).post()
            } else {
                LabAnnouncement(failure: sentence).post()
            }
            return record
        } catch let error as HomeSceneError {
            message = error.message
            LabAnnouncement(failure: error.message).post()
            return nil
        } catch {
            message = "The scene could not be committed."
            return nil
        }
    }

    func reset(in library: LabLibrary) async -> ReceiptRecord? {
        guard begin() else { return nil }
        defer { isRunning = false }
        let requestID = resetRequest ?? RequestID()
        resetRequest = requestID
        do {
            let action = try await sandbox.resetDemo(
                through: LibraryHomeSceneBackend(library: library),
                requestID: requestID
            )
            resetRequest = nil
            report = nil
            livingOn = true
            livingBrightness = 70
            hallwayOn = false
            hallwayBrightness = 20
            includeHallway = true
            await refresh()
            message = "Reset the fictional home and its run note."
            guard let action else { return nil }
            let record = library.receipt(id: action.operationID)
                ?? ReceiptRecord(receipt: action, recordedAt: .now, names: [:])
            receipt = record
            return record
        } catch let error as HomeSceneError {
            message = error.message
            return nil
        } catch {
            message = "Reset failed."
            return nil
        }
    }

    private func rebuildProposal() {
        sandbox.clearSelection()
        do {
            try sandbox.select(
                LightChange(isOn: livingOn, brightness: livingBrightness),
                for: FictionalHome.livingLamp
            )
            if includeHallway {
                try sandbox.select(
                    LightChange(isOn: hallwayOn, brightness: hallwayBrightness),
                    for: FictionalHome.hallwayLamp
                )
            }
            proposal = try sandbox.preview()
        } catch let error as HomeSceneError {
            proposal = nil
            message = error.message
        } catch {
            proposal = nil
        }
    }

    private func begin() -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        return true
    }
}

struct LibraryHomeSceneBackend: HomeSceneBackend {
    let library: LabLibrary

    func item(_ id: ItemID) async throws(HomeSceneError) -> LabItem? {
        let service = try await opened()
        do { return try await service.item(id, as: LabDataService.appUI) } catch .notFound {
            return nil
        } catch {
            throw .operation(error)
        }
    }

    func collection(_ id: CollectionID) async throws(HomeSceneError) -> LabCollection? {
        let service = try await opened()
        do { return try await service.collection(id, as: LabDataService.appUI) } catch .notFound {
            return nil
        } catch {
            throw .operation(error)
        }
    }

    func perform(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(HomeSceneError) -> ActionReceipt {
        do {
            return try await library.submit(
                operation,
                requestID: requestID,
                authority: .userAction,
                names: names
            ).receipt
        } catch let failure as LabLibrary.SubmitFailure {
            switch failure {
            case .unavailable(let reason): throw .labUnavailable(reason)
            case .refused(let error): throw .operation(error)
            }
        } catch {
            throw .labUnavailable("The lab could not commit the change.")
        }
    }

    private func opened() async throws(HomeSceneError) -> LabDataService {
        do { return try await library.openedService() } catch let failure as LabLibrary.SubmitFailure {
            switch failure {
            case .unavailable(let reason): throw .labUnavailable(reason)
            case .refused(let error): throw .operation(error)
            }
        } catch {
            throw .labUnavailable("The lab store is still opening. Try again.")
        }
    }
}
