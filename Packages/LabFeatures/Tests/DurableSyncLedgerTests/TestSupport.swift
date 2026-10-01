import Foundation
import LabDomain
import Testing
@testable import DurableSyncLedger

final class SyncHarness {
    let root: URL
    let profileRoot: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "DurableSync-\(UUID().uuidString)", directoryHint: .isDirectory)
        profileRoot = root.appending(path: "profile", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: profileRoot, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func ledger(
        account: AccountID = SyncFixtures.accountA,
        device: DeviceID = SyncFixtures.device1,
        label: String = SyncFixtures.device1Label,
        scope: RecordScope = .private,
        share: ShareID? = nil,
        profile: (any SyncProfile)? = nil,
        grantMode: LedgerGrantMode = .issueForUserAction,
        actor: ActorScope = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
    ) async throws -> (SyncLedger, OperationService, GrantLedger) {
        let store = InMemoryOperationStore()
        let grants = GrantLedger()
        let service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: grants))
        let backend = ServiceBackend(service: service, actor: actor, grants: grants, grantMode: grantMode)
        let resolvedProfile: any SyncProfile
        if let profile {
            resolvedProfile = profile
        } else if scope == .private {
            resolvedProfile = try FileSyncProfile(root: profileRoot, account: account, scope: .private, share: nil)
        } else {
            resolvedProfile = try FileSyncProfile(root: profileRoot, account: account, scope: .shared, share: share)
        }
        let directory = root
            .appending(path: account.rawValue.uuidString, directoryHint: .isDirectory)
            .appending(path: device.rawValue.uuidString, directoryHint: .isDirectory)
            .appending(path: scope.rawValue, directoryHint: .isDirectory)
        let ledger = try SyncLedger(
            directory: directory,
            account: account,
            device: device,
            deviceLabel: label,
            scope: scope,
            share: share,
            profile: resolvedProfile,
            backend: backend
        )
        await ledger.label(SyncFixtures.device1, as: SyncFixtures.device1Label)
        await ledger.label(SyncFixtures.device2, as: SyncFixtures.device2Label)
        return (ledger, service, grants)
    }
}

/// A profile that records calls. It is a class so the ledger and the test share the counts.
final class SpyProfile: SyncProfile, @unchecked Sendable {
    let enabled: Bool
    private let lock = NSLock()
    private var pullCount = 0
    private var pushCount = 0

    init(enabled: Bool) { self.enabled = enabled }

    var isEnabled: Bool { enabled }

    func counts() -> (pulls: Int, pushes: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (pullCount, pushCount)
    }

    func pull() async throws(LedgerError) -> [MutationEnvelope] {
        recordPull()
        throw .icloudDisabled
    }

    func push(_ envelopes: [MutationEnvelope]) async throws(LedgerError) {
        recordPush()
        throw .icloudDisabled
    }

    private func recordPull() {
        lock.lock()
        pullCount += 1
        lock.unlock()
    }

    private func recordPush() {
        lock.lock()
        pushCount += 1
        lock.unlock()
    }
}
