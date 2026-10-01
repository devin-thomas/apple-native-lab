import Foundation
import LabDomain
import Synchronization
import Testing
@testable import TypedIntelligence

/// Files in this repository, found from this source file's location.
enum Repository {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // TypedIntelligenceTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LabFeatures
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent()

    static func fixtureURL(_ fixture: IntelligenceFixture) -> URL {
        root.appending(path: "Fixtures/intelligence/\(fixture.fileName)")
    }

    static func note(_ fixture: IntelligenceFixture) throws -> SourceNote {
        try fixture.load(at: fixtureURL(fixture))
    }

    /// The app's demo seed, `Fixtures/demo/seed.json`, read into the domain type. The hosts load it
    /// through LabStore; the test reads the same file so the fixture notes meet the real samples.
    static func demoSeed() throws -> DemoSeed {
        struct Unreadable: Error {}
        let data = try Data(contentsOf: root.appending(path: "Fixtures/demo/seed.json"))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["seedVersion"] as? Int,
              let collections = object["collections"] as? [[String: String]],
              let items = object["items"] as? [[String: String]] else { throw Unreadable() }
        func uuid(_ text: String?) throws -> UUID {
            guard let text, let id = UUID(uuidString: text) else { throw Unreadable() }
            return id
        }
        func text(_ value: String?) throws -> String {
            guard let value else { throw Unreadable() }
            return value
        }
        return try DemoSeed(
            version: version,
            collections: try collections.map {
                CollectionDraft(id: CollectionID(rawValue: try uuid($0["id"])), title: try EntityTitle(try text($0["title"])))
            },
            items: try items.map {
                ItemDraft(
                    id: ItemID(rawValue: try uuid($0["id"])),
                    in: CollectionID(rawValue: try uuid($0["collection"])),
                    title: try EntityTitle(try text($0["title"])),
                    note: try ItemNote(try text($0["note"]))
                )
            }
        )
    }
}

/// A store that counts every write reaching it. "Never mutates" in these tests means this count
/// stays at zero and the entities compare equal, not only that no error was thrown.
final class CountingStore: OperationStore {
    let base = InMemoryOperationStore()
    private let applied = Mutex<[ActionReceipt]>([])

    var appliedReceipts: [ActionReceipt] { applied.withLock { $0 } }
    var appliedCount: Int { applied.withLock { $0.count } }
    func resetCount() { applied.withLock { $0.removeAll() } }

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

    func apply(_ commit: AuthorizedCommit) async throws -> CommitOutcome {
        let outcome = try await base.apply(commit)
        if outcome == .applied { applied.withLock { $0.append(commit.receipt) } }
        return outcome
    }
}

/// Records every access the service authorizes, with the adapter that asked.
final class AccessRecorder: AuthorizationPolicy {
    private let log = Mutex<[(Access, AdapterKind)]>([])
    private let inner: any AuthorizationPolicy

    init(inner: any AuthorizationPolicy) { self.inner = inner }

    var accesses: [(access: Access, adapter: AdapterKind)] { log.withLock { $0.map { ($0.0, $0.1) } } }

    func decide(_ access: Access, for actor: ActorScope) -> PolicyDecision {
        log.withLock { $0.append((access, actor.adapter)) }
        return inner.decide(access, for: actor)
    }

    func clear() { log.withLock { $0.removeAll() } }
}

/// The experiment over an in-memory store holding the real demo seed, with the host's rules:
/// `GrantAuthorizationPolicy`, reads and proposals as the proposer, commits as the app UI.
struct Lab {
    let store: CountingStore
    let recorder: AccessRecorder
    let service: OperationService
    let backend: ServiceIntelligenceBackend
    let flow: TypedIntelligenceFlow
    let events: CollectingDiagnosticSink

    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    static func seeded(timeLimit: Duration = .seconds(5)) async throws -> Lab {
        let store = CountingStore()
        let ledger = GrantLedger()
        let recorder = AccessRecorder(inner: GrantAuthorizationPolicy(ledger: ledger))
        let service = OperationService(store: store, policy: recorder)
        let reset = DomainOperation.resetDemo(seed: try Repository.demoSeed())
        let grant = try ledger.issue(for: reset, to: .appUI)
        _ = try await service.perform(OperationRequest(id: RequestID(), operation: reset, actor: appUI))
        ledger.revoke(grant.id)
        store.resetCount()
        recorder.clear()
        let events = CollectingDiagnosticSink()
        let backend = ServiceIntelligenceBackend(service: service)
        let flow = TypedIntelligenceFlow(backend: backend, diagnostics: DiagnosticsLog(sinks: [events]), timeLimit: timeLimit)
        return Lab(store: store, recorder: recorder, service: service, backend: backend, flow: flow, events: events)
    }

    /// Every stored item, ordered by ID.
    func items() async -> [LabItem] {
        await store.base.items(in: nil).sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
    }

    func candidates() async throws -> [SampleCandidate] { try await flow.candidates() }

    func candidate(_ title: String) async throws -> SampleCandidate {
        try #require(try await candidates().first { $0.title == title })
    }
}

/// An extractor that returns whatever the test says, as a hostile or broken model would.
struct ScriptedExtractor: NoteExtractor {
    let source: ProposalSource
    let body: @Sendable (ExtractionRequest) async throws(ExtractionFailure) -> ExtractionDraft

    init(source: ProposalSource = .onDeviceModel, _ body: @escaping @Sendable (ExtractionRequest) async throws(ExtractionFailure) -> ExtractionDraft) {
        self.source = source
        self.body = body
    }

    init(source: ProposalSource = .onDeviceModel, returning draft: ExtractionDraft) {
        self.init(source: source) { _ throws(ExtractionFailure) in draft }
    }

    func extract(_ request: ExtractionRequest) async throws(ExtractionFailure) -> ExtractionDraft {
        try await body(request)
    }
}

/// A flag set from another task.
final class Flag: Sendable {
    private let value = Mutex(false)
    func set() { value.withLock { $0 = true } }
    var isSet: Bool { value.withLock { $0 } }
}

/// Waits without honoring cancellation, as a stalled or hostile extractor might.
func uncancellableWait(_ seconds: Double) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { continuation.resume() }
    }
}

func candidate(_ title: String, note: String = "", archived: Bool = false, revision: Int = 1) throws -> SampleCandidate {
    SampleCandidate(LabItem(
        id: ItemID(),
        collectionID: CollectionID(),
        title: try EntityTitle(title),
        note: try ItemNote(note),
        isArchived: archived,
        revision: try #require(Revision(rawValue: revision)),
        namespace: .demo
    ))
}
