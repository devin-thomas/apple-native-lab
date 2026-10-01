import DurableSyncLedger
import Foundation
import LabDomain
import Observation

/// Labels and IDs for LAB-017. Kept off the main-actor session so the sidebar and menus can
/// read them without hopping.
enum DurableSyncExperiment {
    static let title = "Durable Sync Ledger"
    static let symbol = "arrow.triangle.2.circlepath"
    static let experimentID = "LAB-017"
    /// What the replay is. Shown on the screen so a folder profile is not read as iCloud.
    static let replayCaption = "Fixture replay of two devices on Account A. They share a folder on this device. This is not iCloud."
}

/// LAB-017 in one window: two labeled devices, one private ledger each, and a folder that stands
/// in for a private database.
///
/// This is a fixture replay. The profile is files under Application Support, beside the lab store,
/// and it is not iCloud. Each device materializes edits through `OperationService` with a grant
/// for a deletion. Reset Demo removes only this experiment's folder.
@MainActor
@Observable
final class DurableSyncSession {
    struct Pane: Identifiable, Hashable {
        let id: DeviceID
        let label: String
        var state: RecordState
        var explanation: String
        var receipt: String?
    }

    private struct DeviceSpec: Sendable {
        let id: DeviceID
        let label: String
    }

    private static let specs = [
        DeviceSpec(id: SyncFixtures.device1, label: SyncFixtures.device1Label),
        DeviceSpec(id: SyncFixtures.device2, label: SyncFixtures.device2Label),
    ]

    private(set) var panes: [Pane] = []
    var selected: DeviceID = SyncFixtures.device1
    /// When false, reconnect refuses before it reads the profile. Export and import still work.
    var cloudEnabled = true
    private(set) var message: String?
    private(set) var isWorking = false

    @ObservationIgnored private var ledgers: [DeviceID: SyncLedger] = [:]
    @ObservationIgnored private var opened = false
    @ObservationIgnored private let locateRoot: @Sendable () throws -> URL

    init(locateRoot: @escaping @Sendable () throws -> URL = DurableSyncSession.defaultRoot) {
        self.locateRoot = locateRoot
    }

    /// `Application Support › Native Lab › Durable Sync Ledger`, beside the store.
    nonisolated static func defaultRoot() throws -> URL {
        try LabStoreLocation.defaultURL().deletingLastPathComponent()
            .appending(path: "Durable Sync Ledger", directoryHint: .isDirectory)
    }

    var selectedPane: Pane? { panes.first { $0.id == selected } }

    func label(for device: DeviceID) -> String {
        Self.specs.first { $0.id == device }?.label ?? "Another device"
    }

    func openIfNeeded() async {
        guard !opened else { return }
        opened = true
        await reopen()
    }

    func setCloudEnabled(_ enabled: Bool) async {
        guard enabled != cloudEnabled else { return }
        cloudEnabled = enabled
        guard opened else { return }
        await reopen()
    }

    func save(title: String, note: String) async {
        await step { ledger in
            try await ledger.edit(record: SyncFixtures.record, title: title, note: note)
        }
    }

    func deleteSelected() async {
        await step { ledger in
            try await ledger.delete(record: SyncFixtures.record)
        }
    }

    func choose(_ mutation: MutationID) async {
        await step { ledger in
            try await ledger.resolve(record: SyncFixtures.record, choosing: mutation)
        }
    }

    /// Pulls and pushes. With the profile off, the ledger refuses before it reads anything.
    func reconnect() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if !cloudEnabled {
                guard let ledger = ledgers[selected] else { return }
                _ = try await ledger.sync()
            } else {
                // Two passes: the second device's push is visible to the first only after it syncs again.
                for _ in 0 ..< 2 {
                    for spec in Self.specs {
                        guard let ledger = ledgers[spec.id] else { continue }
                        _ = try await ledger.sync()
                    }
                }
            }
            message = nil
            await refresh()
        } catch {
            message = Self.explain(error)
            await refresh()
        }
    }

    func exportSelected() async -> Data? {
        guard let ledger = ledgers[selected] else { return nil }
        do {
            let document = try await ledger.exportDocument()
            return try document.encoded()
        } catch {
            message = Self.explain(error)
            return nil
        }
    }

    func noteExportFailed() {
        message = "The file couldn't be saved. The ledger was not changed."
    }

    func noteImportFailed() {
        message = "The file couldn't be read. The ledger was not changed."
    }

    func importSelected(_ data: Data) async {
        guard let ledger = ledgers[selected], !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await ledger.importDocument(data)
            message = nil
            await refresh()
        } catch {
            message = Self.explain(error)
        }
    }

    /// Removes the experiment folder and opens empty ledgers. The lab collection is not in that folder.
    func reset() async {
        opened = true
        isWorking = true
        defer { isWorking = false }
        ledgers = [:]
        panes = []
        do {
            let root = try locateRoot()
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
            try await buildLedgers()
            message = "The ledger demo was reset. The lab collection was not changed."
            await refresh()
        } catch {
            message = Self.explain(error)
        }
    }

    // MARK: Opening

    private func reopen() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await buildLedgers()
            message = nil
            await refresh()
        } catch {
            ledgers = [:]
            panes = []
            message = Self.explain(error)
            opened = false
        }
    }

    private func buildLedgers() async throws {
        let root = try locateRoot()
        let profileRoot = root.appending(path: "profile", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: profileRoot, withIntermediateDirectories: true)
        var built: [DeviceID: SyncLedger] = [:]
        for spec in Self.specs {
            let profile = try makeProfile(profileRoot: profileRoot)
            let directory = root
                .appending(path: SyncFixtures.accountA.rawValue.uuidString, directoryHint: .isDirectory)
                .appending(path: spec.id.rawValue.uuidString, directoryHint: .isDirectory)
                .appending(path: RecordScope.private.rawValue, directoryHint: .isDirectory)
            let ledger = try SyncLedger(
                directory: directory,
                account: SyncFixtures.accountA,
                device: spec.id,
                deviceLabel: spec.label,
                scope: .private,
                share: nil,
                profile: profile,
                backend: Self.backend()
            )
            await ledger.label(SyncFixtures.device1, as: SyncFixtures.device1Label)
            await ledger.label(SyncFixtures.device2, as: SyncFixtures.device2Label)
            _ = try await ledger.open()
            built[spec.id] = ledger
        }
        ledgers = built
    }

    private func makeProfile(profileRoot: URL) throws -> any SyncProfile {
        if cloudEnabled {
            return try FileSyncProfile(
                root: profileRoot, account: SyncFixtures.accountA, scope: .private, share: nil
            )
        }
        return DisabledSyncProfile()
    }

    private static func backend() -> ServiceBackend {
        let grants = GrantLedger()
        let service = OperationService(
            store: InMemoryOperationStore(),
            policy: GrantAuthorizationPolicy(ledger: grants)
        )
        let actor = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
        return ServiceBackend(service: service, actor: actor, grants: grants, grantMode: .issueForUserAction)
    }

    private func step(_ body: (SyncLedger) async throws -> Void) async {
        guard let ledger = ledgers[selected], !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await body(ledger)
            message = nil
            await refresh()
        } catch {
            message = Self.explain(error)
            await refresh()
        }
    }

    private func refresh() async {
        var next: [Pane] = []
        for spec in Self.specs {
            guard let ledger = ledgers[spec.id] else { continue }
            let state = await ledger.state(for: SyncFixtures.record)
            let decision = await ledger.decision(for: SyncFixtures.record)
            next.append(Pane(
                id: spec.id,
                label: spec.label,
                state: state,
                explanation: decision?.explanation ?? Self.absentExplanation,
                receipt: decision?.receiptSummary
            ))
        }
        panes = next
    }

    private static let absentExplanation = "This device has no edit for the field note yet."

    private static func explain(_ error: any Error) -> String {
        if let ledger = error as? LedgerError { return ledger.explanation }
        return "The ledger could not finish that step."
    }
}
