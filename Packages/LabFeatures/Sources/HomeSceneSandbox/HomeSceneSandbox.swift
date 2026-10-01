import Foundation
import LabDomain
import Synchronization

/// Preview a home-scene diff, execute only selected harmless light actions, and explain partial
/// failure. Locks, doors, alarms, and heating stay excluded by default. Live mode stops when
/// home permission is revoked. Commits record a run through `HomeSceneBackend` (OperationService).
public final class HomeSceneSandbox: @unchecked Sendable {
    private let source: any HomeAccessSource
    private let routeLock = Mutex<HomeRoute>(.simulated)
    private let selection = Mutex<[AccessoryID: LightChange]>([:])
    private let lastHome = Mutex<HomeSnapshot?>(nil)

    public init(source: any HomeAccessSource = FictionalHomeSource()) {
        self.source = source
    }

    public var route: HomeRoute { routeLock.withLock { $0 } }

    public var simulationLabel: String { FictionalHome.simulationLabel }

    public var platformGate: String { HomeKitPlatformFacts.coreLocalGateExplanation }

    public func permission() async -> HomePermission {
        await source.permission
    }

    /// Loads the home for the current route. Revoked live permission falls back to simulated.
    public func refreshHome() async throws(HomeSceneError) -> HomeSnapshot {
        try cancelled()
        let current = route
        if current == .live {
            let permission = await source.permission
            if !permission.allowsLiveMode {
                routeLock.withLock { $0 = .simulated }
                if let home = try await source.homes(on: .simulated).first {
                    lastHome.withLock { $0 = home }
                }
                throw .permissionRevoked(permission)
            }
        }
        let homes = try await source.homes(on: current)
        guard let home = homes.first else {
            throw .notFound("No home is available on this route.")
        }
        lastHome.withLock { $0 = home }
        return home
    }

    /// Asks for live home access. On denial or restriction, live mode is not entered.
    @discardableResult
    public func requestLiveAccess() async throws(HomeSceneError) -> HomePermission {
        try cancelled()
        let permission = await source.requestAccess()
        if permission.allowsLiveMode {
            routeLock.withLock { $0 = .live }
        } else {
            routeLock.withLock { $0 = .simulated }
        }
        return permission
    }

    /// Leaves live mode for the fictional home. Safe when already simulated.
    public func useSimulatedHome() {
        routeLock.withLock { $0 = .simulated }
    }

    /// Records a desired light change. Sensitive kinds are refused.
    public func select(_ change: LightChange, for id: AccessoryID) throws(HomeSceneError) {
        try cancelled()
        guard let home = lastHome.withLock({ $0 }) else {
            throw .notFound("Load a home before selecting changes.")
        }
        guard let accessory = home.accessory(id) else {
            throw .notFound("That accessory is not in the selected home.")
        }
        if accessory.isExcludedByDefault {
            throw .sensitiveKindExcluded(accessory.kind)
        }
        guard accessory.kind == .light else {
            throw .sensitiveKindExcluded(accessory.kind)
        }
        if let brightness = change.brightness, !(0...100).contains(brightness) {
            throw .invalidInput("Brightness must be between 0 and 100.")
        }
        if change.isEmpty {
            selection.withLock { $0[id] = nil }
            return
        }
        selection.withLock { $0[id] = change }
    }

    public func clearSelection() {
        selection.withLock { $0 = [:] }
    }

    /// Builds a preview of selected light diffs and every default exclusion.
    public func preview() throws(HomeSceneError) -> SceneProposal {
        try cancelled()
        guard let home = lastHome.withLock({ $0 }) else {
            throw .notFound("Load a home before previewing.")
        }
        let chosen = selection.withLock { $0 }
        var selected: [ProposedAccessoryAction] = []
        for accessory in home.lights where !accessory.isExcludedByDefault {
            guard let change = chosen[accessory.id] else { continue }
            let before = LightChange(isOn: accessory.isOn, brightness: accessory.brightness)
            selected.append(ProposedAccessoryAction(accessory: accessory, change: change, before: before))
        }
        let excluded = home.excludedByDefault.map {
            ExcludedAccessory(
                accessory: $0,
                reason: "\($0.kind.title) accessories are excluded by default."
            )
        }
        return SceneProposal(home: home, route: route, selected: selected, excluded: excluded)
    }

    /// Applies selected actions, records per-accessory outcomes, and writes a run receipt.
    /// A disconnected lamp fails its outcome and keeps `sceneSucceeded` false.
    public func commit(
        through backend: any HomeSceneBackend,
        requestID: RequestID
    ) async throws(HomeSceneError) -> (report: SceneCommitReport, receipt: ActionReceipt) {
        try cancelled()
        if route == .live {
            let permission = await source.permission
            if !permission.allowsLiveMode {
                routeLock.withLock { $0 = .simulated }
                throw .permissionRevoked(permission)
            }
        }
        let proposal = try preview()
        guard !proposal.selected.isEmpty else { throw .emptySelection }

        var outcomes: [AccessoryOutcome] = []
        for action in proposal.selected {
            if Task.isCancelled { throw .cancelled }
            let outcome = try await source.apply(action.change, to: action.accessory, in: proposal.home)
            outcomes.append(outcome)
        }
        let report = SceneCommitReport(proposal: proposal, outcomes: outcomes)
        let receipt = try await record(report, through: backend, requestID: requestID)
        // Refresh home state after writes.
        _ = try? await refreshHome()
        selection.withLock { $0 = [:] }
        return (report, receipt)
    }

    /// Removes only this experiment's fixture item note back to the sealed state when present.
    @discardableResult
    public func resetDemo(through backend: any HomeSceneBackend, requestID: RequestID) async throws(HomeSceneError) -> ActionReceipt? {
        try cancelled()
        clearSelection()
        useSimulatedHome()
        guard let item = try await backend.item(FictionalHome.item) else { return nil }
        let sealed = try note(FictionalHome.sealedNote)
        guard item.note != sealed else { return nil }
        let changes = try itemChanges(title: nil, note: sealed)
        return try await backend.perform(
            .updateItem(id: item.id, expected: item.revision, changes: changes),
            requestID: requestID,
            names: names(title: item.title.value)
        )
    }

    // MARK: Receipt recording

    private func record(
        _ report: SceneCommitReport,
        through backend: any HomeSceneBackend,
        requestID: RequestID
    ) async throws(HomeSceneError) -> ActionReceipt {
        let runTitle = try title("Scene run · \(report.proposal.home.name)")
        let body = try note(runNote(report))
        if try await backend.collection(FictionalHome.collection) == nil {
            let collectionTitle = try title(FictionalHome.collectionTitle)
            _ = try await backend.perform(
                .createCollection(draft: CollectionDraft(id: FictionalHome.collection, title: collectionTitle)),
                requestID: FictionalHome.createCollectionRequest,
                names: [.collection(FictionalHome.collection): collectionTitle.value]
            )
        }
        if let item = try await backend.item(FictionalHome.item) {
            let changes = try itemChanges(title: runTitle, note: body)
            return try await backend.perform(
                .updateItem(id: item.id, expected: item.revision, changes: changes),
                requestID: requestID,
                names: names(title: runTitle.value)
            )
        }
        return try await backend.perform(
            .createItem(draft: ItemDraft(
                id: FictionalHome.item,
                in: FictionalHome.collection,
                title: runTitle,
                note: body
            )),
            requestID: requestID,
            names: names(title: runTitle.value)
        )
    }

    private func runNote(_ report: SceneCommitReport) -> String {
        var lines: [String] = [
            report.sceneSucceeded ? "Scene succeeded." : "Scene did not succeed.",
            report.explanation,
            "Route: \(report.proposal.route.rawValue).",
            "Home: \(report.proposal.home.name)\(report.proposal.home.isSimulated ? " (fictional)" : "").",
        ]
        for outcome in report.outcomes {
            lines.append(outcome.line)
        }
        for excluded in report.proposal.excluded {
            lines.append("Excluded: \(excluded.accessory.name) — \(excluded.reason)")
        }
        return lines.joined(separator: "\n")
    }

    private func names(title: String) -> [EntityReference: String] {
        [
            .item(FictionalHome.item): title,
            .collection(FictionalHome.collection): FictionalHome.collectionTitle,
        ]
    }

    private func note(_ raw: String) throws(HomeSceneError) -> ItemNote {
        do { return try ItemNote(raw) } catch { throw .operation(.invalidPayload(error)) }
    }

    private func title(_ raw: String) throws(HomeSceneError) -> EntityTitle {
        do { return try EntityTitle(raw) } catch { throw .operation(.invalidPayload(error)) }
    }

    private func itemChanges(title: EntityTitle?, note: ItemNote?) throws(HomeSceneError) -> ItemChanges {
        do { return try ItemChanges(title: title, note: note) } catch { throw .operation(.invalidPayload(error)) }
    }

    private func cancelled() throws(HomeSceneError) {
        if Task.isCancelled { throw .cancelled }
    }
}
