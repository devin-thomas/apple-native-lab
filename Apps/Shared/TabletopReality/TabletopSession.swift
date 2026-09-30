import Foundation
import LabDomain
import LabSupport
import Observation
import TabletopReality

/// One person's tabletop, on one screen or window: the objects on the table, the selection, the
/// tracking state, and every change to them.
///
/// Every way of changing the table (a tap in the 3D view, a button, a keyboard shortcut, a
/// VoiceOver action on the object list, the live AR adapter) calls one of the methods here. Each
/// one plans its operation with `TabletopPlanner` from the snapshot the person saw, checks the
/// tracking gate, and commits through `LabLibrary.submit` as the app UI: the one operation service,
/// its grant for a removal (ADR-013), and a receipt in the library's list. A retry after a failure
/// reuses the failed request's ID, so one decision commits at most once.
@MainActor
@Observable
final class TabletopSession {
    enum Phase: Hashable {
        case loading
        case ready
        /// The kit or the store cannot be used. The reason is a sentence for a person.
        case unavailable(String)
    }

    /// Where the tracking status comes from.
    enum TrackingSource: Hashable {
        /// The virtual table: nothing is tracked.
        case virtualScene
        /// A recorded sequence, labeled as a replay wherever it shows.
        case replay
        /// The live AR camera (iPhone and iPad only).
        case live
    }

    private(set) var phase: Phase = .loading
    private(set) var kit: TabletopKit?
    /// The lab-owned anchors as last read through the operation service, ordered by title.
    private(set) var anchors: [LabAnchor] = []
    var selectedAnchorID: AnchorID?
    /// The fixture a tap on the table or Place on Table puts down.
    var fixtureToPlace: FixtureKey?
    var nudgeStep: NudgeStep = .normal
    /// Whether a tap on the table moves the selected object there instead of placing a new one.
    var tapMovesSelection = false
    private(set) var tracking: TrackingStatus = .virtualScene
    private(set) var trackingSource: TrackingSource = .virtualScene
    private(set) var advice: RelocalizationWatch.Advice = .none
    /// Which route this device and build allow, once probed.
    private(set) var route: TabletopRoute?
    /// The last result, as a sentence. The same words are announced.
    private(set) var message: String?
    /// The last receipt a change here produced.
    private(set) var lastRecord: ReceiptRecord?
    private(set) var isWorking = false
    /// True while Clear Table or Set Out Starter Scene is committing its list.
    private(set) var isRunningList = false

    @ObservationIgnored private var requests: [DomainOperation: RequestID] = [:]
    @ObservationIgnored private var listRun: Task<Void, Never>?
    @ObservationIgnored private var replayRun: Task<Void, Never>?
    @ObservationIgnored private var watch = RelocalizationWatch()
    @ObservationIgnored private let registry: CapabilityRegistry
    @ObservationIgnored private let loadKit: @Sendable () throws(KitError) -> TabletopKit

    init(
        registry: CapabilityRegistry = .live(),
        loadKit: @escaping @Sendable () throws(KitError) -> TabletopKit = { () throws(KitError) in try TabletopKit.bundled() }
    ) {
        self.registry = registry
        self.loadKit = loadKit
    }

    // MARK: Reading

    var planner: TabletopPlanner? {
        kit.map { TabletopPlanner(kit: $0, anchors: anchors, tracking: tracking) }
    }

    var entries: [SceneEntry] {
        kit.map { SceneDescription.entries(kit: $0, anchors: anchors) } ?? []
    }

    var selectedAnchor: LabAnchor? {
        selectedAnchorID.flatMap { id in anchors.first { $0.id == id } }
    }

    func entry(for id: AnchorID) -> SceneEntry? {
        entries.first { $0.subject == .anchor(id) }
    }

    func canAct(in library: LabLibrary) -> Bool {
        phase == .ready && library.phase == .ready && !isWorking && !isRunningList && !library.isWorking
    }

    /// Whether an interaction may run now, and if not, the sentence that says why.
    func availability(of interaction: TabletopInteraction, in library: LabLibrary) -> (allowed: Bool, reason: String?) {
        guard canAct(in: library) else { return (false, nil) }
        guard InteractionGate.allows(interaction, under: tracking) else {
            return (false, "\(tracking.title): placing, moving, and turning wait until tracking is normal.")
        }
        return (true, nil)
    }

    /// Loads the kit, reads the table, and probes the route. Safe to call again; it rereads.
    func start(in library: LabLibrary) async {
        if kit == nil {
            do {
                let loaded = try loadKit()
                kit = loaded
                fixtureToPlace = fixtureToPlace ?? loaded.fixtures.first?.key
            } catch {
                phase = .unavailable(error.message)
                return
            }
        }
        await refresh(in: library)
        if route == nil {
            route = TabletopRoute(report: await registry.report(for: .worldTracking))
        }
    }

    /// Reads the anchors again through the service. The selection is kept only while its object
    /// is still on the table.
    func refresh(in library: LabLibrary) async {
        guard kit != nil else { return }
        do {
            let service = try await library.openedService()
            anchors = try await service.anchors(as: LabDataService.appUI)
            phase = .ready
        } catch let failure as LabLibrary.SubmitFailure {
            phase = .unavailable(Self.describe(failure))
        } catch {
            phase = .unavailable(LibraryMessages.describe(error))
        }
        if let id = selectedAnchorID, !anchors.contains(where: { $0.id == id }) { selectedAnchorID = nil }
    }

    // MARK: Changing the table

    /// Places the chosen fixture with its base at `(x, z)` millimeters: a tap on the table.
    @discardableResult
    func place(atX x: Int, z: Int, in library: LabLibrary) async -> ReceiptRecord? {
        guard let key = fixtureToPlace else { return nil }
        return await change(in: library, selectingPlaced: true) { planner throws(TabletopError) in try planner.place(key, x: x, z: z) }
    }

    /// Places the chosen fixture at the free spot nearest the center: no pointing needed.
    @discardableResult
    func placeAtFreeSpot(in library: LabLibrary) async -> ReceiptRecord? {
        guard let key = fixtureToPlace else { return nil }
        return await change(in: library, selectingPlaced: true) { planner throws(TabletopError) in try planner.placeAtFreeSpot(key) }
    }

    @discardableResult
    func nudge(_ direction: TableDirection, _ id: AnchorID? = nil, in library: LabLibrary) async -> ReceiptRecord? {
        guard let id = id ?? selectedAnchorID else { return nil }
        let step = nudgeStep
        return await change(in: library) { planner throws(TabletopError) in try planner.nudge(id, direction, by: step) }
    }

    @discardableResult
    func move(_ id: AnchorID, toX x: Int, z: Int, in library: LabLibrary) async -> ReceiptRecord? {
        await change(in: library) { planner throws(TabletopError) in try planner.move(id, toX: x, z: z) }
    }

    /// Turns counterclockwise, seen from above, by one step; `clockwise` turns the other way.
    @discardableResult
    func turn(clockwise: Bool, _ id: AnchorID? = nil, in library: LabLibrary) async -> ReceiptRecord? {
        guard let id = id ?? selectedAnchorID else { return nil }
        let degrees = clockwise ? -TabletopPlanner.turnStep : TabletopPlanner.turnStep
        return await change(in: library) { planner throws(TabletopError) in try planner.turn(id, by: degrees) }
    }

    /// Removes one object. Its receipt offers an undo that places it again.
    @discardableResult
    func remove(_ id: AnchorID? = nil, in library: LabLibrary) async -> ReceiptRecord? {
        guard let id = id ?? selectedAnchorID else { return nil }
        return await change(in: library) { planner throws(TabletopError) in try planner.remove(id) }
    }

    /// Removes every object on the table, one receipt each, stopping if cancelled.
    func clearTable(in library: LabLibrary) {
        runList(in: library, verb: "Removed") { planner throws(TabletopError) in try planner.clear() }
    }

    /// Places the kit's starter scene, one receipt per object.
    func setOutStarter(in library: LabLibrary) {
        runList(in: library, verb: "Placed") { planner throws(TabletopError) in try planner.setOutStarter() }
    }

    /// Stops Clear Table or Set Out Starter Scene between two commits.
    func cancelList() {
        listRun?.cancel()
    }

    // MARK: Tracking

    /// A tracking update from the live AR adapter.
    func liveTrackingChanged(_ status: TrackingStatus) {
        trackingSource = .live
        apply(status)
    }

    /// The AR camera closed: back to the virtual table.
    func liveEnded() {
        watch.reset()
        advice = .none
        trackingSource = .virtualScene
        tracking = .virtualScene
    }

    /// Keep Looking after a stalled relocalization.
    func keepLooking() {
        watch.keepLooking(at: .now)
        advice = watch.observe(tracking, at: .now)
    }

    /// Plays the recorded tracking sequence into the same gate, labeled as a replay. The virtual
    /// table returns when it ends or is stopped.
    func startReplay() {
        guard trackingSource == .virtualScene else { return }
        let replay = TrackingReplay.standard
        watch = RelocalizationWatch(patience: TrackingReplay.replayPatience)
        trackingSource = .replay
        message = "Replay started: \(replay.title). This is a recorded sequence, not a camera."
        replayRun = Task { [weak self] in
            for step in replay.steps {
                guard let self, !Task.isCancelled else { break }
                self.apply(step.status)
                // Sample twice per step, so the watch can reach its stalled advice mid-step.
                let half = step.duration / 2
                try? await Task.sleep(for: half)
                guard !Task.isCancelled else { break }
                self.apply(step.status)
                try? await Task.sleep(for: step.duration - half)
            }
            self?.endReplay()
        }
    }

    func stopReplay() {
        replayRun?.cancel()
        endReplay()
    }

    private func endReplay() {
        guard trackingSource == .replay else { return }
        replayRun = nil
        watch = RelocalizationWatch()
        advice = .none
        trackingSource = .virtualScene
        tracking = .virtualScene
        message = "Replay ended. The virtual table is back."
    }

    private func apply(_ status: TrackingStatus) {
        let before = tracking
        tracking = status
        advice = watch.observe(status, at: .now)
        if before.allowsPrecision != status.allowsPrecision {
            LabAnnouncement(text: status.allowsPrecision
                ? "\(status.title). Placing, moving, and turning are available."
                : "\(status.title). Placing, moving, and turning are paused.").post()
        }
    }

    // MARK: Committing

    private func change(
        in library: LabLibrary,
        selectingPlaced: Bool = false,
        _ plan: (TabletopPlanner) throws(TabletopError) -> DomainOperation
    ) async -> ReceiptRecord? {
        guard canAct(in: library), let planner else { return nil }
        let operation: DomainOperation
        do {
            operation = try plan(planner)
        } catch {
            report(error.message, failed: true)
            return nil
        }
        isWorking = true
        defer { isWorking = false }
        let requestID = requests[operation] ?? RequestID()
        requests[operation] = requestID
        do {
            let record = try await library.submit(operation, requestID: requestID, authority: .userAction, names: names(for: operation))
            requests[operation] = nil
            await refresh(in: library)
            if selectingPlaced, case .placeAnchor(let draft) = operation, record.receipt.conflict == nil {
                selectedAnchorID = draft.id
            }
            lastRecord = record
            message = record.receipt.summary
            LabAnnouncement(receipt: ReceiptPresentation(record)).post()
            return record
        } catch {
            await refresh(in: library)
            report(Self.describe(error), failed: true)
            return nil
        }
    }

    private func runList(
        in library: LabLibrary,
        verb: String,
        _ plan: @escaping (TabletopPlanner) throws(TabletopError) -> [DomainOperation]
    ) {
        guard canAct(in: library), let planner else { return }
        let operations: [DomainOperation]
        do {
            operations = try plan(planner)
        } catch {
            report(error.message, failed: true)
            return
        }
        guard !operations.isEmpty else {
            report("The table is already clear.", failed: false)
            return
        }
        let names = operations.reduce(into: [EntityReference: String]()) { $0.merge(self.names(for: $1)) { current, _ in current } }
        isRunningList = true
        listRun = Task {
            defer { isRunningList = false }
            do {
                let receipts = try await SequentialRun.perform(operations) { operation throws(TabletopError) in
                    do {
                        return try await library.submit(operation, requestID: RequestID(), authority: .userAction, names: names).receipt
                    } catch let failure as LabLibrary.SubmitFailure {
                        throw Self.tabletopError(failure)
                    } catch {
                        throw .unavailable(LibraryMessages.describe(error))
                    }
                }
                await refresh(in: library)
                lastRecord = library.receipts.first { $0.receipt == receipts.last }
                let count = receipts.count == 1 ? "1 object" : "\(receipts.count) objects"
                report("\(verb) \(count). Each has its own receipt.", failed: false)
            } catch {
                await refresh(in: library)
                report(Self.describe(error), failed: true)
            }
        }
    }

    /// Titles for the receipt inspector, so a removed object is still named.
    private func names(for operation: DomainOperation) -> [EntityReference: String] {
        var names = Dictionary(anchors.map { ($0.reference, $0.title.value) }, uniquingKeysWith: { first, _ in first })
        if case .placeAnchor(let draft) = operation { names[.anchor(draft.id)] = draft.title.value }
        return names
    }

    private func report(_ sentence: String, failed: Bool) {
        message = sentence
        (failed ? LabAnnouncement(failure: sentence) : LabAnnouncement(text: sentence)).post()
    }

    static func tabletopError(_ failure: LabLibrary.SubmitFailure) -> TabletopError {
        switch failure {
        case .unavailable(let reason): .unavailable(reason)
        case .refused(let refusal): .refused(refusal)
        }
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case let failure as LabLibrary.SubmitFailure: tabletopError(failure).message
        case let error as TabletopError: error.message
        default: LibraryMessages.describe(error)
        }
    }
}
