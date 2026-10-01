import Foundation
import LabDomain

/// One device's durable sync ledger.
///
/// Edits are appended to a write-ahead log, then materialized through `OperationService`. Two
/// devices that edited apart keep both versions until a person chooses. A deletion is a tombstone
/// in the log: replaying the log, including after the lab store is gone, does not recreate the
/// record. Private records are partitioned by account. iCloud off leaves the log and manual
/// documents usable and does not touch the profile.
public actor SyncLedger {
    public let account: AccountID
    public let device: DeviceID
    public let deviceLabel: String
    public let scope: RecordScope
    public let share: ShareID?
    public let collectionID: CollectionID

    private let profile: any SyncProfile
    private let backend: any LedgerBackend
    private var log: WriteAheadLog
    private var labels: [DeviceID: String]
    private var decisions: [RecordID: LedgerDecision] = [:]
    private var historyLog: [LedgerDecision] = []

    public init(
        directory: URL,
        account: AccountID,
        device: DeviceID,
        deviceLabel: String,
        scope: RecordScope,
        share: ShareID?,
        profile: any SyncProfile,
        backend: any LedgerBackend
    ) throws {
        switch scope {
        case .private:
            guard share == nil else { throw LedgerError.invalidMutation("A private ledger names no shared database.") }
        case .shared:
            guard share != nil else { throw LedgerError.invalidMutation("A shared ledger names its shared database.") }
        }
        let meta = try LedgerMeta.loadOrCreate(
            directory: directory, account: account, device: device, deviceLabel: deviceLabel, scope: scope, share: share
        )
        self.account = account
        self.device = device
        self.deviceLabel = deviceLabel
        self.scope = scope
        self.share = share
        self.collectionID = meta.collection
        self.profile = profile
        self.backend = backend
        log = try WriteAheadLog(directory: directory)
        labels = [device: deviceLabel]
    }

    public func label(_ device: DeviceID, as name: String) {
        labels[device] = name
    }

    public func decision(for record: RecordID) -> LedgerDecision? { decisions[record] }

    public func history() -> [LedgerDecision] { historyLog }

    /// Materializes anything the log already held, such as an edit written before a crash.
    @discardableResult
    public func open() async throws -> [LedgerDecision] {
        try await reconcileAll()
    }

    /// Records an envelope without materializing it, so a test can reopen the ledger the way a
    /// crash between the write-ahead append and the commit would.
    func plantUnappliedForTesting(_ envelope: MutationEnvelope) throws {
        try log.append(envelope)
    }

    @discardableResult
    public func edit(
        record: RecordID,
        title: String,
        note: String,
        mutation: MutationID = MutationID()
    ) async throws -> LedgerDecision {
        try checkCancelled()
        _ = try await reconcileAll()
        let heads = frontier(log.envelopes(for: record))
        if heads.count > 1 { throw LedgerError.unresolvedConflict(record) }
        let envelope = try MutationEnvelope(
            id: mutation,
            record: record,
            account: account,
            device: device,
            scope: scope,
            share: share,
            vector: nextVector(for: record),
            kind: .upsert(title: title, note: note)
        )
        if let current = heads.first, current.kind == envelope.kind {
            throw LedgerError.invalidMutation("That edit matches the current record, so nothing was written.")
        }
        return try await author(envelope)
    }

    @discardableResult
    public func delete(record: RecordID, mutation: MutationID = MutationID()) async throws -> LedgerDecision {
        try checkCancelled()
        _ = try await reconcileAll()
        let heads = frontier(log.envelopes(for: record))
        guard !heads.isEmpty else { throw LedgerError.invalidMutation("There is no record to delete.") }
        if heads.count == 1, heads[0].kind.isTombstone {
            throw LedgerError.invalidMutation("The record is already deleted.")
        }
        let envelope = try MutationEnvelope(
            id: mutation,
            record: record,
            account: account,
            device: device,
            scope: scope,
            share: share,
            vector: nextVector(for: record),
            kind: .tombstone
        )
        return try await author(envelope)
    }

    /// Keeps the chosen edit and records a new one that happened after every side of the conflict.
    @discardableResult
    public func resolve(
        record: RecordID,
        choosing chosen: MutationID,
        mutation: MutationID = MutationID()
    ) async throws -> LedgerDecision {
        try checkCancelled()
        _ = try await reconcileAll()
        let heads = frontier(log.envelopes(for: record))
        guard heads.count > 1 else { throw LedgerError.invalidMutation("This record has no conflict to resolve.") }
        guard let winner = heads.first(where: { $0.id == chosen }) else {
            throw LedgerError.invalidMutation("That edit is not one of the conflicting edits.")
        }
        let envelope = try MutationEnvelope(
            id: mutation,
            record: record,
            account: account,
            device: device,
            scope: scope,
            share: share,
            vector: nextVector(for: record),
            kind: winner.kind
        )
        return try await author(envelope)
    }

    /// Pulls the optional profile, merges, and pushes. iCloud off throws before the profile is read.
    @discardableResult
    public func sync() async throws -> [LedgerDecision] {
        try checkCancelled()
        guard profile.isEnabled else { throw LedgerError.icloudDisabled }
        let remote = try await profile.pull()
        try checkCancelled()
        for envelope in remote {
            try accept(envelope)
        }
        let decisions = try await reconcileAll()
        let known = Set(remote.map(\.id))
        let outgoing = log.envelopes.filter { !known.contains($0.id) && $0.scope == scope && $0.share == share }
        try checkCancelled()
        try await profile.push(outgoing)
        return decisions
    }

    public func exportDocument() throws -> LedgerDocument {
        try LedgerDocument(account: account, scope: scope, share: share, envelopes: log.envelopes)
    }

    /// Merges a manual-exchange document into the local log. It does not contact the profile, so
    /// it works while iCloud is off.
    @discardableResult
    public func importDocument(_ data: Data) async throws -> [LedgerDecision] {
        try checkCancelled()
        let document = try LedgerDocument.decode(data)
        guard document.scope == scope, document.share == share else {
            throw LedgerError.invalidDocument("This document is for a different database than the one open now.")
        }
        if scope == .private, document.account != account { throw LedgerError.wrongAccount }
        for envelope in document.envelopes {
            try accept(envelope)
        }
        return try await reconcileAll()
    }

    public func state(for record: RecordID) async -> RecordState {
        let heads = frontier(log.envelopes(for: record))
        if heads.count > 1 {
            let stored = try? await backend.item(record.itemID)
            return .conflict(ConflictRecord(
                record: record,
                edits: heads,
                storedTitle: stored?.title.value,
                storedNote: stored?.note.value,
                storedIsDeleted: stored?.isArchived ?? false,
                explanation: conflictExplanation(heads)
            ))
        }
        if heads.first?.kind.isTombstone == true { return .deleted }
        if let item = try? await backend.item(record.itemID), !item.isArchived {
            return .live(title: item.title.value, note: item.note.value)
        }
        return .absent
    }

    // MARK: Writing

    private func author(_ envelope: MutationEnvelope) async throws -> LedgerDecision {
        try log.append(envelope)
        do {
            try checkCancelled()
            return try await reconcile(envelope.record)
        } catch let error as LedgerError {
            if !log.isApplied(envelope.id), Self.rollsBack(error) {
                try? log.removeUnapplied(envelope.id)
            }
            throw error
        } catch {
            throw LedgerError.storage
        }
    }

    private func accept(_ envelope: MutationEnvelope) throws {
        guard envelope.scope == scope, envelope.share == share else {
            throw LedgerError.invalidMutation("An edit does not belong in this database.")
        }
        if scope == .private, envelope.account != account { return }
        if log.contains(envelope.id) { return }
        try log.append(envelope)
    }

    private func checkCancelled() throws {
        if Task.isCancelled { throw LedgerError.cancelled }
    }

    private static func rollsBack(_ error: LedgerError) -> Bool {
        switch error {
        case .unauthorized, .cancelled, .invalidMutation, .invalidDocument, .domain, .wrongAccount, .unresolvedConflict:
            true
        case .storage, .icloudDisabled, .notAShareMember, .foreignLedger:
            false
        }
    }

    // MARK: Reconciliation

    private func reconcileAll() async throws -> [LedgerDecision] {
        var made: [LedgerDecision] = []
        var failure: LedgerError?
        for record in log.records {
            do {
                made.append(try await reconcile(record))
            } catch let error as LedgerError {
                if failure == nil { failure = error }
            } catch {
                if failure == nil { failure = LedgerError.storage }
            }
        }
        if let failure { throw failure }
        return made
    }

    private func reconcile(_ record: RecordID) async throws -> LedgerDecision {
        let group = log.envelopes(for: record)
        let heads = frontier(group)
        for old in group where !heads.contains(where: { $0.id == old.id }) {
            try log.markApplied(old.id)
        }
        if heads.count > 1 {
            let decision = LedgerDecision(
                id: MutationID(rawValue: RequestIdentity.uuid(named: heads.map(\.id.rawValue.uuidString).sorted().joined(separator: "|"))),
                record: record,
                explanation: conflictExplanation(heads),
                receiptSummary: nil
            )
            remember(decision)
            return decision
        }
        guard let winner = heads.first else {
            throw LedgerError.invalidMutation("The record has no edits.")
        }
        let summary = try await materialize(winner)
        try log.markApplied(winner.id)
        let decision = LedgerDecision(
            id: winner.id,
            record: record,
            explanation: explanation(winner: winner, group: group),
            receiptSummary: summary
        )
        remember(decision)
        return decision
    }

    private func materialize(_ winner: MutationEnvelope) async throws -> String? {
        if log.isApplied(winner.id) { return nil }
        switch winner.kind {
        case .tombstone:
            return try await materializeTombstone(winner)
        case .upsert(let title, let note):
            return try await materializeUpsert(winner, title: title, note: note)
        }
    }

    private func materializeTombstone(_ winner: MutationEnvelope) async throws -> String? {
        guard let item = try await backend.item(winner.record.itemID), !item.isArchived else { return nil }
        let receipt = try await backend.perform(
            .archiveItem(id: item.id, expected: item.revision),
            id: winner.id.requestID
        )
        guard case .committed = receipt.status else {
            throw LedgerError.domain("The deletion did not commit.")
        }
        return receipt.summary
    }

    private func materializeUpsert(_ winner: MutationEnvelope, title: String, note: String) async throws -> String? {
        try await ensureCollection()
        let titleValue: EntityTitle
        let noteValue: ItemNote
        do {
            titleValue = try EntityTitle(title)
            noteValue = try ItemNote(note)
        } catch {
            throw LedgerError.invalidMutation(LedgerError.describe(error))
        }
        guard var item = try await backend.item(winner.record.itemID) else {
            let draft = ItemDraft(id: winner.record.itemID, in: collectionID, title: titleValue, note: noteValue)
            let receipt = try await backend.perform(.createItem(draft: draft), id: winner.id.requestID)
            guard case .committed = receipt.status else { throw LedgerError.domain("The edit did not commit.") }
            return receipt.summary
        }
        if item.isArchived {
            let receipt = try await backend.perform(
                .restoreItem(id: item.id, expected: item.revision),
                id: RequestIdentity.step(winner.id, "restore")
            )
            guard case .committed = receipt.status else { throw LedgerError.domain("The record could not be restored.") }
            guard let restored = try await backend.item(item.id) else {
                throw LedgerError.domain("The record could not be restored.")
            }
            item = restored
        }
        let titleChange = item.title == titleValue ? nil : titleValue
        let noteChange = item.note == noteValue ? nil : noteValue
        guard titleChange != nil || noteChange != nil else { return nil }
        let changes: ItemChanges
        do { changes = try ItemChanges(title: titleChange, note: noteChange) } catch {
            throw LedgerError.invalidMutation(LedgerError.describe(error))
        }
        let receipt = try await backend.perform(
            .updateItem(id: item.id, expected: item.revision, changes: changes),
            id: winner.id.requestID
        )
        guard case .committed = receipt.status else { throw LedgerError.domain("The edit did not commit.") }
        return receipt.summary
    }

    private func ensureCollection() async throws {
        if try await backend.collection(collectionID) != nil { return }
        let title: EntityTitle
        do { title = try EntityTitle(scope == .private ? "Private ledger" : "Shared ledger") } catch {
            throw LedgerError.invalidMutation(LedgerError.describe(error))
        }
        let draft = CollectionDraft(id: collectionID, title: title)
        let receipt = try await backend.perform(
            .createCollection(draft: draft),
            id: RequestID(rawValue: collectionID.rawValue)
        )
        guard case .committed = receipt.status else { throw LedgerError.domain("The ledger collection did not commit.") }
    }

    private func nextVector(for record: RecordID) -> VersionVector {
        let heads = frontier(log.envelopes(for: record))
        let base = heads.reduce(VersionVector.empty) { $0.merging($1.vector) }
        return base.incrementing(device)
    }

    private func frontier(_ group: [MutationEnvelope]) -> [MutationEnvelope] {
        let undominated = group.filter { candidate in
            !group.contains { other in
                other.id != candidate.id && other.vector.happenedAfter(candidate.vector)
            }
        }
        var kept: [MutationEnvelope] = []
        let ordered = undominated.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        for candidate in ordered {
            if kept.contains(where: { $0.record == candidate.record && $0.vector == candidate.vector && $0.kind == candidate.kind }) {
                continue
            }
            kept.append(candidate)
        }
        return kept
    }

    private func remember(_ decision: LedgerDecision) {
        let previous = decisions[decision.record]
        decisions[decision.record] = decision
        if previous?.explanation != decision.explanation {
            historyLog.append(decision)
        }
    }

    // MARK: Explanations

    private func name(of device: DeviceID) -> String { labels[device] ?? "Another device" }

    private func phrase(_ envelope: MutationEnvelope) -> String {
        let who = name(of: envelope.device)
        switch envelope.kind {
        case .tombstone:
            return "\(who) deleted the record"
        case .upsert(let title, let note):
            return "\(who) wrote “\(title)” — \(note)"
        }
    }

    private func conflictExplanation(_ heads: [MutationEnvelope]) -> String {
        let details = heads.map { phrase($0) }.joined(separator: ". ")
        return "These edits were made apart, and neither device had seen the other. \(details). Both stay here until you choose. Nothing was overwritten."
    }

    private func explanation(winner: MutationEnvelope, group: [MutationEnvelope]) -> String {
        let others = group.filter { $0.id != winner.id }
        let concurrent = others.filter { left in
            others.contains { right in left.id != right.id && left.vector.concurrent(with: right.vector) }
        }
        if !concurrent.isEmpty, case .upsert = winner.kind {
            let source = others.first { $0.kind == winner.kind }
            let chosen = source.map { name(of: $0.device) } ?? name(of: winner.device)
            let rivals = others.filter { $0.kind != winner.kind || $0.id != source?.id }.map { phrase($0) }.joined(separator: ". ")
            return "You chose the edit from \(chosen). \(phrase(winner)). It was concurrent with \(rivals). The choice is a new edit that happened after both, so later syncs follow it."
        }
        if winner.kind.isTombstone, !concurrent.isEmpty {
            let details = concurrent.map { phrase($0) }.joined(separator: ". ")
            return "You deleted the record after edits that were made apart. \(details). The deletion happened after both, so neither edit remains."
        }
        if winner.kind.isTombstone {
            return "The record stays deleted. The deletion happened after the last edit, so a reinstall that replays the ledger does not bring it back."
        }
        return "\(name(of: winner.device)) is the final state because that edit happened after every other edit of this record. \(phrase(winner)). The version vector includes the earlier edits, so nothing was overwritten."
    }
}

private struct LedgerMeta: Codable, Equatable {
    var schemaVersion: Int
    var account: AccountID
    var device: DeviceID
    var deviceLabel: String
    var scope: RecordScope
    var share: ShareID?
    var collection: CollectionID

    static func loadOrCreate(
        directory: URL,
        account: AccountID,
        device: DeviceID,
        deviceLabel: String,
        scope: RecordScope,
        share: ShareID?
    ) throws -> LedgerMeta {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw LedgerError.storage
        }
        let url = directory.appending(path: "meta.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let data: Data
            do { data = try Data(contentsOf: url) } catch { throw LedgerError.storage }
            let meta: LedgerMeta
            do { meta = try JSONDecoder().decode(LedgerMeta.self, from: data) } catch { throw LedgerError.foreignLedger }
            guard meta.schemaVersion == 1,
                  meta.account == account,
                  meta.device == device,
                  meta.scope == scope,
                  meta.share == share
            else { throw LedgerError.foreignLedger }
            return meta
        }
        let meta = LedgerMeta(
            schemaVersion: 1,
            account: account,
            device: device,
            deviceLabel: deviceLabel,
            scope: scope,
            share: share,
            collection: CollectionID()
        )
        do {
            try LedgerJSON.data(meta).write(to: url, options: .atomic)
        } catch {
            throw LedgerError.storage
        }
        return meta
    }
}
