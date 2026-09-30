import Foundation
import LabDomain
import LabStaging

/// Reads the staging folders a host can see, for review.
///
/// Every listing validates each waiting import again from its bytes (CORE-006
/// `StagingArea.validatedRecord`). One that no longer validates is moved to quarantine by the
/// staging area, where it cannot block anything, and is listed there instead. A validated record
/// is kept in memory by ID, since its content determines its ID; adoption validates it again from
/// disk regardless.
///
/// The inbox reads and removes. It never adopts: the host adopts an entry with `ImportAdopter`
/// over its one `OperationService`, as the entry's source's adapter, with a grant the person's
/// Add action issues, then calls `didAdopt(_:)`.
public actor ShareInbox {
    public let areas: [IngressArea]
    private var validated: [InboxEntry.ID: StagingRecord] = [:]
    private let now: @Sendable () -> Date

    public init(areas: [IngressArea], now: @escaping @Sendable () -> Date = { Date() }) {
        self.areas = areas.sorted { $0.source < $1.source }
        self.now = now
    }

    public func area(for source: InboxSource) -> IngressArea? {
        areas.first { $0.source == source }
    }

    /// The staging folder an adoption of an entry from `source` reads, as `ImportAdopter` takes it.
    public func stagingInbox(for source: InboxSource) -> (any StagingInbox)? {
        area(for: source)?.staging
    }

    public func snapshot() async -> InboxSnapshot {
        var entries: [InboxEntry] = []
        var quarantined: [QuarantineEntry] = []
        var seen: Set<InboxEntry.ID> = []
        for area in areas {
            var live: Set<StagingID> = []
            for stagingID in await area.staging.waitingImports() {
                let id = InboxEntry.ID(source: area.source, staging: stagingID)
                let record: StagingRecord
                if let cached = validated[id] {
                    record = cached
                } else {
                    do {
                        record = try await area.staging.validatedRecord(stagingID)
                    } catch {
                        continue // set aside by the staging area; listed below with the quarantine
                    }
                    validated[id] = record
                }
                live.insert(stagingID)
                seen.insert(id)
                entries.append(Self.entry(id: id, record: record, origin: Self.origin(stagingID, in: area)))
            }
            for item in await area.staging.quarantinedImports() {
                if let stagingID = item.stagingID { live.insert(stagingID) }
                quarantined.append(QuarantineEntry(
                    id: QuarantineEntry.ID(source: area.source, quarantine: item.id),
                    origin: item.stagingID.flatMap { Self.origin($0, in: area) },
                    code: item.code
                ))
            }
            area.origins.sweep(keeping: live, now: now())
        }
        validated = validated.filter { seen.contains($0.key) }
        entries.sort(by: Self.arrivalOrder)
        return InboxSnapshot(entries: entries, quarantined: quarantined, sources: areas.map(\.source))
    }

    /// Removes a waiting import a person chose not to add, with its origin.
    public func discard(_ id: InboxEntry.ID) async throws(ImportRejection) {
        guard let area = area(for: id.source) else { throw .notFound }
        try await area.staging.discard(id.staging)
        area.origins.remove(id.staging)
        validated[id] = nil
    }

    /// Forgets an import the host adopted. `ImportAdopter` already cleared its staging folder.
    public func didAdopt(_ id: InboxEntry.ID) async {
        guard let area = area(for: id.source) else { return }
        try? await area.staging.markAdopted(id.staging)
        area.origins.remove(id.staging)
        validated[id] = nil
    }

    /// Removes a set-aside import, with its origin.
    public func removeQuarantined(_ entry: QuarantineEntry) async throws(ImportRejection) {
        guard let area = area(for: entry.source) else { throw .notFound }
        try await area.staging.removeQuarantined(entry.id.quarantine)
        if let stagingID = entry.origin?.stagingID { area.origins.remove(stagingID) }
    }

    // MARK: Building entries

    /// An origin is shown only when it matches the folder it sits in: a share-extension origin
    /// in the host's folder, or a paste origin in the App Group folder, reads as unknown.
    private static func origin(_ id: StagingID, in area: IngressArea) -> ImportOrigin? {
        guard let origin = area.origins.origin(for: id), area.source.accepts(origin.surface) else { return nil }
        return origin
    }

    static func entry(id: InboxEntry.ID, record: StagingRecord, origin: ImportOrigin?) -> InboxEntry {
        let content: InboxContent = switch record.payload {
        case .text(let text): .text(text)
        case .link(let url, let title): .link(url, title: title)
        case .files(let files): .files(files.map { InboxFile(name: $0.path.value, byteCount: $0.byteCount) })
        }
        // The collection does not change whether a record maps to an operation, only which one.
        let adoptability: Adoptability
        do {
            _ = try ImportAdopter.operation(for: record, into: CollectionID())
            adoptability = .ready
        } catch {
            adoptability = .unavailable(error)
        }
        return InboxEntry(
            id: id, origin: origin, stagedAt: record.stagedAt, content: content, byteCount: record.byteCount,
            adoptability: adoptability
        )
    }

    /// Oldest intake first, then position within it; imports without an origin by staging time.
    static func arrivalOrder(_ lhs: InboxEntry, _ rhs: InboxEntry) -> Bool {
        let left = (lhs.origin?.receivedAt ?? lhs.stagedAt, lhs.origin?.batch.description ?? "", lhs.origin?.position ?? 0)
        let right = (rhs.origin?.receivedAt ?? rhs.stagedAt, rhs.origin?.batch.description ?? "", rhs.origin?.position ?? 0)
        if left.0 != right.0 { return left.0 < right.0 }
        if left.1 != right.1 { return left.1 < right.1 }
        if left.2 != right.2 { return left.2 < right.2 }
        return lhs.id.description < rhs.id.description
    }
}
