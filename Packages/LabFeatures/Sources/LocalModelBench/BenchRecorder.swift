import Foundation
import LabDomain

/// What the bench needs from the host: reads and commits through the host's `OperationService`.
/// The module never holds the store.
public protocol LocalModelBenchBackend: Sendable {
    func collection(_ id: CollectionID) async throws(BenchError) -> LabCollection?
    func items(in collection: CollectionID) async throws(BenchError) -> [LabItem]
    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(BenchError) -> ActionReceipt
}

/// Records a report as one item, and archives only this experiment's items on reset.
///
/// Both go through the backend, so they are authorized and receipted like any other change.
/// Entering the experiment does not record anything; recording is its own call.
public struct BenchRecorder: Sendable {
    private let backend: any LocalModelBenchBackend

    public init(backend: any LocalModelBenchBackend) {
        self.backend = backend
    }

    /// Creates the results collection if this request has not already, then the report item.
    /// The same report uses the same request ID, so a retry returns the original item receipt.
    public func record(_ report: BenchReport) async throws(BenchError) -> ActionReceipt {
        let canonical: Data
        do { canonical = try report.canonical() } catch { throw .unavailable }
        let extras = try Self.extras(canonical)
        let itemID = ItemID(rawValue: Self.uuid(digestOf: canonical, salt: "lab-015-item"))
        let requestID = RequestID(rawValue: Self.uuid(digestOf: canonical, salt: "lab-015-request"))
        let title = try Self.title(report)
        let note = try Self.note(report)
        let collectionTitle: EntityTitle
        do { collectionTitle = try EntityTitle("Bench results") } catch { throw .unavailable }

        let collectionReceipt = try await backend.commit(
            .createCollection(draft: CollectionDraft(
                id: LocalModelBench.resultsCollectionID,
                title: collectionTitle
            )),
            requestID: LocalModelBench.resultsCollectionRequestID,
            names: [.collection(LocalModelBench.resultsCollectionID): collectionTitle.value]
        )
        _ = collectionReceipt

        let draft = ItemDraft(
            id: itemID,
            in: LocalModelBench.resultsCollectionID,
            title: title,
            note: note,
            extras: extras
        )
        return try await backend.commit(
            .createItem(draft: draft),
            requestID: requestID,
            names: [.item(itemID): title.value]
        )
    }

    /// Archives items in the results collection whose extras are a bench report. Demo items and
    /// anything else are not in that collection, so they stay. Each archive is its own receipt.
    public func reset() async throws(BenchError) -> [ActionReceipt] {
        guard let collection = try await backend.collection(LocalModelBench.resultsCollectionID) else {
            return []
        }
        guard !collection.isArchived else { throw .unavailable }
        let items = try await backend.items(in: collection.id)
        if items.count == ItemFilter.allowedLimits.upperBound { throw .reportTooLarge }
        var receipts: [ActionReceipt] = []
        for item in items.sorted(by: { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }) {
            guard Self.isBenchReport(item.extras), !item.isArchived else { continue }
            let digest = ContentDigest.sha256(Data("lab-015-reset:\(item.id.rawValue.uuidString):\(item.revision)".utf8))
            let receipt = try await backend.commit(
                .archiveItem(id: item.id, expected: item.revision),
                requestID: RequestID(rawValue: Self.uuid(digest: digest)),
                names: [.item(item.id): item.title.value]
            )
            receipts.append(receipt)
        }
        return receipts
    }

    static func isBenchReport(_ extras: ItemExtras) -> Bool {
        guard let data = extras.json.data(using: .utf8),
              let object = try? JSONDecoder().decode(Mark.self, from: data) else { return false }
        return object.experiment == LocalModelBench.experimentID && object.kind == "bench-report"
    }

    private struct Mark: Decodable {
        let experiment: String
        let kind: String
    }

    private static func extras(_ canonical: Data) throws(BenchError) -> ItemExtras {
        guard let canonicalText = String(data: canonical, encoding: .utf8) else { throw .unavailable }
        let payload: [String: String] = [
            "canonical": canonicalText,
            "experiment": LocalModelBench.experimentID,
            "kind": "bench-report",
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload), let text = String(data: data, encoding: .utf8) else {
            throw .unavailable
        }
        do {
            return try ItemExtras(json: text)
        } catch ExtrasRejection.tooLarge {
            throw .reportTooLarge
        } catch {
            throw .unavailable
        }
    }

    private static func title(_ report: BenchReport) throws(BenchError) -> EntityTitle {
        do {
            return try EntityTitle("Bench \(report.thermal.rawValue) \(report.phase.rawValue)")
        } catch {
            throw .invalidCase
        }
    }

    private static func note(_ report: BenchReport) throws(BenchError) -> ItemNote {
        do {
            return try ItemNote(report.summary)
        } catch {
            throw .reportTooLarge
        }
    }

    private static func uuid(digestOf data: Data, salt: String) -> UUID {
        let salted = Data(salt.utf8) + data
        return uuid(digest: ContentDigest.sha256(salted))
    }

    private static func uuid(digest: ContentDigest) -> UUID {
        let bytes = digest.bytes
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// A backend over an `OperationService`. Destructive commits issue a grant when `issueGrants`
/// is set, the way the host does for a control the person pressed.
public struct BenchServiceBackend: LocalModelBenchBackend {
    private let service: OperationService
    private let actor: ActorScope
    private let ledger: GrantLedger
    private let issueGrants: Bool

    public init(service: OperationService, actor: ActorScope, ledger: GrantLedger, issueGrants: Bool) {
        self.service = service
        self.actor = actor
        self.ledger = ledger
        self.issueGrants = issueGrants
    }

    public func collection(_ id: CollectionID) async throws(BenchError) -> LabCollection? {
        do {
            return try await service.findCollection(id, as: actor)
        } catch .notFound {
            return nil
        } catch {
            throw .refused(error)
        }
    }

    public func items(in collection: CollectionID) async throws(BenchError) -> [LabItem] {
        let filter: ItemFilter
        do {
            filter = try ItemFilter(collectionID: collection, includeArchived: true, limit: ItemFilter.allowedLimits.upperBound)
        } catch {
            throw .unavailable
        }
        do {
            return try await service.findItems(filter, as: actor)
        } catch {
            throw .refused(error)
        }
    }

    public func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(BenchError) -> ActionReceipt {
        _ = names
        var grant: GrantID?
        if issueGrants, operation.kind.isDestructive {
            do {
                grant = try ledger.issue(for: operation, to: actor.adapter, lifetime: .seconds(30)).id
            } catch {
                throw .unauthorized
            }
        }
        defer { if let grant { ledger.revoke(grant) } }
        do {
            return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
        } catch .unauthorized {
            throw .unauthorized
        } catch {
            throw .refused(error)
        }
    }
}
