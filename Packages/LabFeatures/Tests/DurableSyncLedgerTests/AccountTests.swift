import Foundation
import LabDomain
import Testing
@testable import DurableSyncLedger

@Suite struct AccountAndProfileTests {
    @Test func accountANeverAppearsInAccountB() async throws {
        let harness = try SyncHarness()
        let record = SyncFixtures.record
        let (accountA, _, _) = try await harness.ledger(account: SyncFixtures.accountA)
        let (accountB, _, _) = try await harness.ledger(account: SyncFixtures.accountB, device: SyncFixtures.device2, label: SyncFixtures.device2Label)
        try await accountA.edit(record: record, title: "Field note", note: "Account A only")
        try await accountA.sync()
        try await accountB.sync()
        #expect(await accountB.state(for: record) == .absent)
        #expect(await accountA.state(for: record) == .live(title: "Field note", note: "Account A only"))

        let document = try await accountA.exportDocument().encoded()
        await #expect(throws: LedgerError.wrongAccount) {
            try await accountB.importDocument(document)
        }
        #expect(await accountB.state(for: record) == .absent)
    }

    @Test func openingAnotherAccountsFolderIsRefused() async throws {
        let harness = try SyncHarness()
        let (accountA, _, _) = try await harness.ledger(account: SyncFixtures.accountA)
        try await accountA.edit(record: SyncFixtures.record, title: "Field note", note: "Private")
        let directory = harness.root
            .appending(path: SyncFixtures.accountA.rawValue.uuidString, directoryHint: .isDirectory)
            .appending(path: SyncFixtures.device1.rawValue.uuidString, directoryHint: .isDirectory)
            .appending(path: RecordScope.private.rawValue, directoryHint: .isDirectory)
        let store = InMemoryOperationStore()
        let grants = GrantLedger()
        let service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: grants))
        let backend = ServiceBackend(
            service: service,
            actor: ActorScope(adapter: .appUI, grants: Set(Permission.allCases)),
            grants: grants,
            grantMode: .issueForUserAction
        )
        let profile = try FileSyncProfile(root: harness.profileRoot, account: SyncFixtures.accountB, scope: .private, share: nil)
        #expect(throws: LedgerError.foreignLedger) {
            try SyncLedger(
                directory: directory,
                account: SyncFixtures.accountB,
                device: SyncFixtures.device1,
                deviceLabel: "Device 1",
                scope: .private,
                share: nil,
                profile: profile,
                backend: backend
            )
        }
    }

    @Test func aSharedRecordReachesMembersAndNotAStranger() async throws {
        let harness = try SyncHarness()
        try FileSyncProfile.admit(SyncFixtures.accountA, to: SyncFixtures.share, in: harness.profileRoot)
        try FileSyncProfile.admit(SyncFixtures.accountB, to: SyncFixtures.share, in: harness.profileRoot)
        let record = SyncFixtures.record
        let (memberA, _, _) = try await harness.ledger(
            account: SyncFixtures.accountA, scope: .shared, share: SyncFixtures.share
        )
        let (memberB, _, _) = try await harness.ledger(
            account: SyncFixtures.accountB, device: SyncFixtures.device2, label: SyncFixtures.device2Label,
            scope: .shared, share: SyncFixtures.share
        )
        let (stranger, _, _) = try await harness.ledger(
            account: SyncFixtures.accountC, device: SyncFixtures.device2, label: "Device 2",
            scope: .shared, share: SyncFixtures.share
        )
        try await memberA.edit(record: record, title: "Field note", note: "Shared count")
        try await memberA.sync()
        try await memberB.sync()
        #expect(await memberB.state(for: record) == .live(title: "Field note", note: "Shared count"))
        await #expect(throws: LedgerError.notAShareMember) {
            try await stranger.sync()
        }
        #expect(await stranger.state(for: record) == .absent)

        let (privateB, _, _) = try await harness.ledger(account: SyncFixtures.accountB, device: SyncFixtures.device1)
        try await privateB.sync()
        #expect(await privateB.state(for: record) == .absent)
    }

    @Test func disabledICloudDoesNotTouchTheProfile() async throws {
        let harness = try SyncHarness()
        let spy = SpyProfile(enabled: false)
        let (ledger, _, _) = try await harness.ledger(profile: spy)
        let record = SyncFixtures.record
        try await ledger.edit(record: record, title: "Field note", note: "Local only")
        await #expect(throws: LedgerError.icloudDisabled) {
            try await ledger.sync()
        }
        #expect(spy.counts() == (0, 0))
        #expect(await ledger.state(for: record) == .live(title: "Field note", note: "Local only"))

        let exported = try await ledger.exportDocument().encoded()
        let (other, _, _) = try await harness.ledger(
            device: SyncFixtures.device2, label: SyncFixtures.device2Label, profile: DisabledSyncProfile()
        )
        try await other.importDocument(exported)
        #expect(await other.state(for: record) == .live(title: "Field note", note: "Local only"))
    }
}
