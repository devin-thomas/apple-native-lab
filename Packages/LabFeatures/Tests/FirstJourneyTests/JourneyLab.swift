import AccessSuperpower
import ActionAtlas
import Foundation
import LabDomain
import LabStaging
import PortableObjects
import ShareIngress
import SurfaceDeck
import Synchronization
import TypedIntelligence
import UniformTypeIdentifiers

/// The fixed inputs of the first six-lab journey (CORE-012). The showcase script in
/// `Fixtures/showcase/first-journey/` uses the same values.
///
/// The shared object is the note `Fixtures/intelligence/intelligence-injected-note.txt`, shared or
/// pasted into the lab and added to one of the person's own collections. Its item ID is not chosen:
/// `ImportAdopter` derives it from the note's digest and the collection's ID.
enum Journey {
    static let fieldNotes = CollectionID(rawValue: UUID(uuidString: "06D9663A-9835-44CE-B9E9-C048717D597A")!)
    static let fieldNotesTitle = "Field notes"
    static let createFieldNotes = RequestID(rawValue: UUID(uuidString: "D5760E58-4EC8-4E59-A698-E5C7DEEB5D51")!)
    /// The item ID and request ID `ImportAdopter` derives for the shared note in Field notes.
    static let object = ItemID(rawValue: UUID(uuidString: "C784FB5A-4D9A-8895-9AE7-9418D700541D")!)
    static let addRequest = RequestID(rawValue: UUID(uuidString: "960A425D-9DD8-8548-B632-09DCEB54741D")!)

    static let renameRequest = RequestID(rawValue: UUID(uuidString: "A25537FF-F169-4DEA-A193-3E5E5ADBCD33")!)
    static let archiveRequest = RequestID(rawValue: UUID(uuidString: "79998709-4D82-411B-AE3E-4769B3CFA065")!)
    static let restoreRequest = RequestID(rawValue: UUID(uuidString: "7CAA28A8-03A7-44D1-98F5-53F798C9A06D")!)
    static let startRequest = RequestID(rawValue: UUID(uuidString: "47E2CDBA-EA7F-42BC-8A60-D126490D7A77")!)
    static let pauseRequest = RequestID(rawValue: UUID(uuidString: "6775BB1C-871C-4106-8116-F2471178BFA8")!)
    /// A second lab's own collection, for importing the exported object there.
    static let imports = CollectionID(rawValue: UUID(uuidString: "102DC40B-57B2-4BB6-9D2E-64F71E2421B5")!)
    static let importsTitle = "Imports"

    static let renamedTitle = "Kraft card wear note"
    /// The shared note's first line, which adoption makes the object's title.
    static let firstLine = "Kraft card: corners fray after a week in the drawer. Still takes pencil well."

    // Demo samples from Fixtures/demo/seed.json.
    static let kraft = ItemID(rawValue: UUID(uuidString: "6E2CED9D-B946-4188-8417-2E85C6A7268C")!)
    static let quartz = ItemID(rawValue: UUID(uuidString: "AF451890-CA80-4DE9-B18B-4007066C9177")!)
    static let minerals = CollectionID(rawValue: UUID(uuidString: "A222A032-267A-4208-B1F9-F55D739D3C24")!)
    static let papers = CollectionID(rawValue: UUID(uuidString: "E7EEE9BB-FA3B-41F1-805E-41BDB71B44A3")!)
    static let kraftSeedNote = "Brown and stiff. Takes pencil well."
    /// What the sample parser, or a person in the manual editor, adds to the kraft card: the
    /// shared note's first paragraph only.
    static let kraftNoteAfterReview = kraftSeedNote + "\n" + firstLine

    /// SHA-256 of the object's `.anlab` export at the end of the journey (revision 4). Every path
    /// that runs the journey, in any store and on any platform, must export exactly these bytes.
    static let exportSHA256 = "fa5f337a8ca37e5529ce343022afaf92db98a5a367b9212fe7090d37efd406ea"

    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
    static let appIntent = ActorScope(adapter: .appIntent, grants: Set(Permission.allCases))
}

/// Files in this repository, found from this source file.
enum JourneyFixtures {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // FirstJourneyTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LabFeatures
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent()

    static var sharedNoteURL: URL { root.appending(path: "Fixtures/intelligence/intelligence-injected-note.txt") }

    static func sharedNoteData() throws -> Data { try Data(contentsOf: sharedNoteURL) }

    static func sharedNote() throws -> String { String(decoding: try sharedNoteData(), as: UTF8.self) }

    /// `Fixtures/demo/seed.json`, read into the domain type as the hosts read it through LabStore.
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

/// One lab with the hosts' rules, over an in-memory store: one `OperationService` with
/// `GrantAuthorizationPolicy`, the host's staging folder and the share extension's folder, and
/// every M1 module's adapter over that service. A grant is issued only where the hosts issue one:
/// for a person's control press, an intent's confirmation of exactly that change, or an Add.
final class JourneyLab: @unchecked Sendable {
    let folder: URL
    let ledger = GrantLedger()
    let store = InMemoryOperationStore()
    let service: OperationService
    /// The host's own folder: paste, the file picker, and drop.
    let host: IngressArea
    /// The share extension's folder, as a SystemSurfaces host reads its App Group. A CoreLocal
    /// host has no share extension and no App Group, so it has none.
    let shared: IngressArea?
    let inbox: ShareInbox
    let seed: DemoSeed

    init(shareExtension: Bool = true) throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "FirstJourneyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
        host = try IngressArea(source: .host, root: folder.appending(path: "host"))
        shared = shareExtension ? try IngressArea(source: .shareExtension, root: folder.appending(path: "group")) : nil
        inbox = ShareInbox(areas: [host] + (shared.map { [$0] } ?? []))
        seed = try JourneyFixtures.demoSeed()
    }

    deinit { try? FileManager.default.removeItem(at: folder) }

    /// A lab after the host's first run: the demo seeded through Reset Demo.
    static func seeded(shareExtension: Bool = true) async throws -> JourneyLab {
        let lab = try JourneyLab(shareExtension: shareExtension)
        _ = try await lab.confirm(.resetDemo(seed: lab.seed))
        return lab
    }

    // MARK: The app UI

    /// A change a person made with a control in the app, committed as the app UI. A destructive
    /// one gets the grant the control press issues, for exactly this change.
    @discardableResult
    func confirm(_ operation: DomainOperation, request: RequestID = RequestID()) async throws -> ActionReceipt {
        var grant: CommitGrant?
        if GrantRequirement.sensitiveCommits.requiresGrant(operation.kind, from: .appUI) {
            grant = try ledger.issue(for: operation, to: .appUI, lifetime: .seconds(30))
        }
        defer { if let grant { ledger.revoke(grant.id) } }
        return try await service.perform(OperationRequest(id: request, operation: operation, actor: Journey.appUI))
    }

    /// New Collection… on the review screen: Field notes, with the journey's fixed ID.
    @discardableResult
    func createFieldNotes() async throws -> ActionReceipt {
        try await confirm(
            .createCollection(draft: CollectionDraft(id: Journey.fieldNotes, title: try EntityTitle(Journey.fieldNotesTitle))),
            request: Journey.createFieldNotes
        )
    }

    // MARK: Share Ingress (LAB-007)

    func paste(_ providers: [NSItemProvider]) async -> IntakeReport {
        await IngressStation(area: host).receive(ItemProviderAttachment.attachments(from: providers, acceptsFileReferences: true), via: .paste)
    }

    /// What the share extension does with a share: stage into its own folder, never the store.
    func share(_ providers: [NSItemProvider]) async throws -> IntakeReport {
        struct NoShareExtension: Error {}
        guard let shared else { throw NoShareExtension() }
        return await IngressStation(area: shared).receive(ItemProviderAttachment.attachments(from: providers), via: .shareExtension)
    }

    func waiting() async -> [InboxEntry] { await inbox.snapshot().entries }

    /// The host's Add: a grant for exactly this import's operation, for the adapter its folder
    /// names, revoked when the commit returns.
    func add(_ entry: InboxEntry, into collection: CollectionID) async throws(ImportRejection) -> ImportAdoption {
        guard let area = await inbox.area(for: entry.source) else { throw .notFound }
        let record = try await area.staging.validatedRecord(entry.id.staging)
        let operation = try ImportAdopter.operation(for: record, into: collection)
        let grant = try? ledger.issue(for: operation, to: entry.source.adapter, lifetime: .seconds(30))
        defer { if let grant { ledger.revoke(grant.id) } }
        let adoption = try await ImportAdopter(service: service, inbox: area.staging, ledger: ledger, adapter: entry.source.adapter)
            .adopt(entry.id.staging, into: collection)
        await inbox.didAdopt(entry.id)
        return adoption
    }

    // MARK: Action Atlas (LAB-001)

    var atlas: AtlasBackend { AtlasBackend(lab: self) }
    var atlasLink: ActionAtlasLink { ActionAtlasLink(backend: atlas) }
    func actions(_ entryPoint: AtlasEntryPoint) -> ActionAtlasActions { ActionAtlasActions(backend: atlas, entryPoint: entryPoint) }

    /// One item as the system resolves a stored reference for an App Intent.
    func entity(_ id: ItemID) async throws -> LabItemEntity? {
        let actions = actions(.appIntent)
        guard let item = try await actions.items(ids: [id]).first else { return nil }
        let titles = try await actions.collectionTitles(for: [item])
        return LabItemEntity(item, collectionTitle: titles[item.collectionID])
    }

    // MARK: Typed Local Intelligence (LAB-010)

    var intelligence: TypedIntelligenceFlow { TypedIntelligenceFlow(backend: ServiceIntelligenceBackend(service: service)) }

    // MARK: Surface Deck (LAB-004)

    var deck: DeckBackend { DeckBackend(service: service) }
    var deckLink: SurfaceDeckLink { SurfaceDeckLink(backend: deck, openDeck: {}) }

    // MARK: Access as a Superpower (LAB-035)

    /// Every collection with its items, as the host reads them for the chart, the person's own
    /// included, so the tally's own filter is what leaves them out.
    func tally() async throws -> ArchiveTally {
        var groups: [(collection: LabCollection, items: [LabItem])] = []
        let ids = await store.collections().map(\.id).sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        let order = seed.collections.map(\.id)
        for id in ids.sorted(by: { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }) {
            let collection = try await service.findCollection(id, as: Journey.appUI)
            let filter = try ItemFilter(collectionID: id, includeArchived: true, limit: ItemFilter.allowedLimits.upperBound)
            groups.append((collection, try await service.findItems(filter, as: Journey.appUI)))
        }
        return ArchiveTally(groups)
    }

    // MARK: Portable Objects (LAB-008)

    var portable: ServiceBackend { ServiceBackend(service: service, actor: Journey.appUI) }

    func importer() throws -> PortableObjectsImporter {
        try PortableObjectsImporter(backend: portable, stagingRoot: folder.appending(path: "portable-staging"))
    }

    func export(_ id: ItemID) async throws -> ExportPreview {
        let item = try await service.findItem(id, as: Journey.appUI)
        let collection = try await service.findCollection(item.collectionID, as: Journey.appUI)
        return try ExportPreview(item: item, collection: collection)
    }

    // MARK: Reading

    func item(_ id: ItemID, as actor: ActorScope = Journey.appUI) async throws -> LabItem {
        try await service.findItem(id, as: actor)
    }

    /// The whole persisted entity state, ordered by ID, for comparing two labs.
    func entities() async -> (collections: [LabCollection], items: [LabItem]) {
        (
            await store.collections().sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString },
            await store.items(in: nil).sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        )
    }
}

/// Action Atlas's backend with the host's rules (`LibraryAtlasBackend` and `LabDataService`): a
/// grant only for a control press in the app, or an intent holding a confirmation of exactly this
/// change.
struct AtlasBackend: ActionAtlasBackend {
    let lab: JourneyLab

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        authority: AtlasAuthority,
        names: [EntityReference: String]
    ) async throws(ActionAtlasError) -> ActionReceipt {
        let actor = Self.actor(authority.entryPoint)
        let permitted = switch authority {
        case .appControl: true
        case .intent(let confirmation): confirmation?.covers(operation) == true
        }
        var grant: GrantID?
        if GrantRequirement.sensitiveCommits.requiresGrant(operation.kind, from: actor.adapter), permitted {
            grant = try? lab.ledger.issue(for: operation, to: actor.adapter, lifetime: .seconds(30)).id
        }
        defer { if let grant { lab.ledger.revoke(grant) } }
        do {
            return try await lab.service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
        } catch {
            throw ActionAtlasError(error)
        }
    }

    func collection(_ id: CollectionID, via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> LabCollection {
        do { return try await lab.service.findCollection(id, as: Self.actor(entryPoint)) } catch { throw ActionAtlasError(error) }
    }

    func item(_ id: ItemID, via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> LabItem {
        do { return try await lab.service.findItem(id, as: Self.actor(entryPoint)) } catch { throw ActionAtlasError(error) }
    }

    func items(_ filter: ItemFilter, via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> [LabItem] {
        do { return try await lab.service.findItems(filter, as: Self.actor(entryPoint)) } catch { throw ActionAtlasError(error) }
    }

    func collections(via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> [LabCollection] {
        var found: [LabCollection] = []
        for id in await lab.store.collections().map(\.id) {
            found.append(try await collection(id, via: entryPoint))
        }
        return found
    }

    static func actor(_ entryPoint: AtlasEntryPoint) -> ActorScope {
        switch entryPoint {
        case .appUI: Journey.appUI
        case .appIntent: Journey.appIntent
        }
    }
}

/// Surface Deck's backend with the host's rules (`LibrarySessionBackend`): starting or pausing is
/// not destructive, so neither entry point needs a grant. It keeps the last snapshot the host
/// would write for the widget and the Control, redacted as by default.
final class DeckBackend: SessionBackend, @unchecked Sendable {
    let service: OperationService
    private let written = Mutex<SessionSnapshot?>(nil)

    init(service: OperationService) {
        self.service = service
    }

    var snapshot: SessionSnapshot? { written.withLock { $0 } }

    func session(via entryPoint: SessionEntryPoint) async throws(SurfaceDeckError) -> LabSession? {
        do { return try await service.findSession(SurfaceDeck.sessionID, as: Self.actor(entryPoint)) } catch { throw .refused(error) }
    }

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        via entryPoint: SessionEntryPoint,
        surface: SessionSurface
    ) async throws(SurfaceDeckError) -> ActionReceipt {
        do {
            return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: Self.actor(entryPoint)))
        } catch {
            throw .refused(error)
        }
    }

    func didSettle(_ outcome: SessionOutcome, surface: SessionSurface) async {
        let snapshot = SessionSnapshot(state: outcome.state, writtenAt: Date(timeIntervalSince1970: 1_800_000_000), detail: nil)
        written.withLock { $0 = snapshot }
    }

    static func actor(_ entryPoint: SessionEntryPoint) -> ActorScope {
        switch entryPoint {
        case .appUI: Journey.appUI
        case .appIntent: Journey.appIntent
        }
    }
}

/// A shared file still downloading, as a cloud-backed photo: it never calls back, and reports when
/// its progress is cancelled.
final class StalledDownload: @unchecked Sendable {
    private struct State {
        var started = false
        var cancelled = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())
    let provider: NSItemProvider

    init() {
        provider = NSItemProvider()
        provider.suggestedName = "Drawer photo"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { [self] _ in
            let progress = Progress(totalUnitCount: 100)
            progress.cancellationHandler = { [self] in state.withLock { $0.cancelled = true } }
            let waiters = state.withLock { state in
                state.started = true
                defer { state.waiters = [] }
                return state.waiters
            }
            waiters.forEach { $0.resume() }
            return progress
        }
    }

    var wasCancelled: Bool { state.withLock { $0.cancelled } }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            let started = state.withLock { state in
                if !state.started { state.waiters.append(continuation) }
                return state.started
            }
            if started { continuation.resume() }
        }
    }
}

/// An extractor that waits until cancelled, as a model that has not answered yet.
struct WaitingExtractor: NoteExtractor {
    let source = ProposalSource.sampleParser

    func extract(_ request: ExtractionRequest) async throws(ExtractionFailure) -> ExtractionDraft {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(10))
        }
        throw .cancelled
    }
}
