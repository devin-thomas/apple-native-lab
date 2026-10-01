import Foundation
import LabDomain
import Synchronization
@testable import PointInspect

enum Repository {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static var swatch: Data {
        get throws {
            try Data(contentsOf: root.appending(path: "Fixtures/point-inspect/swatch-card.png"))
        }
    }
}

/// A store that counts writes. A proposal that records nothing leaves this at zero.
final class CountingStore: OperationStore, @unchecked Sendable {
    let base = InMemoryOperationStore()
    private let applied = Mutex<[ActionReceipt]>([])

    var appliedCount: Int { applied.withLock { $0.count } }

    func collections() async throws -> [LabCollection] { await base.collections() }
    func collection(_ id: CollectionID) async throws -> LabCollection? { await base.collection(id) }
    func item(_ id: ItemID) async throws -> LabItem? { await base.item(id) }
    func items(in collectionID: CollectionID?) async throws -> [LabItem] { await base.items(in: collectionID) }
    func receipt(for requestID: RequestID) async throws -> ActionReceipt? { await base.receipt(for: requestID) }
    func session(_ id: SessionID) async throws -> LabSession? { await base.session(id) }
    func sessions() async throws -> [LabSession] { await base.sessions() }
    func attention(_ id: AttentionID) async throws -> LabAttention? { await base.attention(id) }
    func attentions() async throws -> [LabAttention] { await base.attentions() }
    func job(_ id: JobID) async throws -> LabJob? { await base.job(id) }
    func jobs() async throws -> [LabJob] { await base.jobs() }
    func anchor(_ id: AnchorID) async throws -> LabAnchor? { await base.anchor(id) }
    func anchors() async throws -> [LabAnchor] { await base.anchors() }

    func apply(_ commit: AuthorizedCommit) async throws -> CommitOutcome {
        let outcome = try await base.apply(commit)
        if outcome == .applied {
            applied.withLock { $0.append(commit.receipt) }
        }
        return outcome
    }
}

struct Lab {
    let store: CountingStore
    let service: OperationService
    let backend: ServicePointInspectBackend
    let flow: PointInspectFlow

    static func open(timeLimit: Duration = .seconds(5)) -> Lab {
        let store = CountingStore()
        let service = OperationService(store: store)
        return Lab(
            store: store,
            service: service,
            backend: ServicePointInspectBackend(service: service),
            flow: PointInspectFlow(backend: ServicePointInspectBackend(service: service), timeLimit: timeLimit)
        )
    }

    func image(origin: ImageOrigin = .userSelected) throws -> SelectedImage {
        try SelectedImage(data: Repository.swatch, origin: origin)
    }

    func seed() async throws {
        let title = try EntityTitle(PointInspect.collectionTitle)
        _ = try await backend.createCollection(
            CollectionDraft(id: PointInspect.collectionID, title: title),
            requestID: RequestID()
        )
    }
}

func reading(lines: [RecognizedLine] = [], barcodes: [BarcodeReading] = []) -> OpticalReading {
    OpticalReading(lines: lines, barcodes: barcodes, engine: .scripted)
}
