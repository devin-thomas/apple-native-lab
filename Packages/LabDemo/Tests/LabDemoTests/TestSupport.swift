import Foundation
@testable import LabDemo
import LabDomain
import LabStore
import LabSupport
import Synchronization
import Testing

// MARK: - Repository fixtures

/// `Fixtures/showcase/` at the repository root, found from this source file.
enum Showcase {
    static let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent() // LabDemoTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LabDemo
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository root

    static let fixtures = repositoryRoot.appending(path: "Fixtures/showcase", directoryHint: .isDirectory)
    static let atlasBasics = fixtures.appending(path: "atlas-basics", directoryHint: .isDirectory)

    static func script() throws -> DemoScript {
        try DemoScript(folder: atlasBasics)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: atlasBasics.appending(path: name))
    }

    /// The showcase's IDs.
    static let shoreline = CollectionID(rawValue: UUID(uuidString: "806C6A4B-D828-4215-9AD3-3A4BCE562A2D")!)
    static let seaGlass = ItemID(rawValue: UUID(uuidString: "07E994E4-9EF4-46EC-B09A-B670F9EBB07B")!)
    static let periwinkle = ItemID(rawValue: UUID(uuidString: "14F1D683-BDFA-45A3-82A7-5B8513C8CDC2")!)
}

// MARK: - Values

extension EntityTitle: @retroactive ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        do { try self.init(value) } catch { fatalError("Invalid test title \(value): \(error)") }
    }
}

func name(_ value: String) -> DemoName {
    guard let name = DemoName(value) else { fatalError("Invalid test name \(value)") }
    return name
}

/// Deterministic identifiers: 00000000-0000-0000-0000-000000000001, …
func uuid(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
}

func revision(_ value: Int) -> Revision { Revision(rawValue: value)! }

let testProvenance = BuildProvenance(sourceRevision: "0000000", sdkName: "macosx27.0", xcodeVersion: "27.0", xcodeBuild: "27A266a")

/// 2026-09-29T12:00:00Z.
let fixedDate = Date(timeIntervalSince1970: 1_790_683_200)

// MARK: - Runners

extension DemoRunner {
    /// A runner with a manual clock, a fixed wall clock, and the given store.
    static func manual(
        store: DemoStoreFactory = .inMemory,
        step: Duration = .milliseconds(1),
        adapter: AdapterKind = .appUI,
        wallClock: Date = fixedDate
    ) -> DemoRunner {
        DemoRunner(
            adapter: adapter,
            store: store,
            clock: ManualIntervalClock(stepPerReading: step),
            wallClock: { wallClock }
        )
    }
}

/// Every run a test produced, so the invariants can be checked across all of them.
func checkStepInvariants(_ run: DemoRun, sourceLocation: SourceLocation = #_sourceLocation) {
    for step in run.steps {
        if step.result == .passed {
            #expect(step.disposition == .ran, "a passed step ran", sourceLocation: sourceLocation)
            #expect(step.timing != nil, "a passed step has a measured interval", sourceLocation: sourceLocation)
        }
        if step.disposition != .ran {
            #expect(step.result != .passed, "a step that never started is never passed", sourceLocation: sourceLocation)
            #expect(step.timing == nil, "a step that never started has no interval", sourceLocation: sourceLocation)
            #expect(step.receipt == nil && step.found == nil && step.approval == nil, sourceLocation: sourceLocation)
        }
    }
    #expect((run.result == .passed) == run.steps.allSatisfy { $0.result == .passed }, sourceLocation: sourceLocation)
}

// MARK: - Code-built scripts

/// A two-item seed for scripts built in tests.
func smallSeed(note: String = "First note.") throws -> DemoSeed {
    try DemoSeed(
        version: 1,
        collections: [CollectionDraft(id: CollectionID(rawValue: uuid(1)), title: "Test shelf")],
        items: [
            ItemDraft(id: ItemID(rawValue: uuid(11)), in: CollectionID(rawValue: uuid(1)), title: "Brass key", note: try ItemNote(note)),
            ItemDraft(id: ItemID(rawValue: uuid(12)), in: CollectionID(rawValue: uuid(1)), title: "Copper coin"),
        ]
    )
}

let brassKey = ItemID(rawValue: uuid(11))
let copperCoin = ItemID(rawValue: uuid(12))

func find(_ text: String?, expect: [ItemID], includeArchived: Bool = false) throws -> DemoAction {
    .find(ScriptedFind(filter: try ItemFilter(text: text, includeArchived: includeArchived), expected: expect))
}

/// Approve and reset, then `steps`.
func smallScript(
    _ steps: [DemoStep],
    tier: DataTier = .publicFixture,
    seed: DemoSeed? = nil,
    untested: [String] = ["Nothing beyond the domain service."]
) throws -> DemoScript {
    try DemoScript(
        id: name("small"),
        subject: "CORE-009",
        title: "Small test script",
        dataTier: tier,
        provenance: "Written for the LabDemo tests.",
        seed: seed ?? smallSeed(),
        steps: [
            DemoStep(name("approve-reset"), .approve(name("reset"))),
            DemoStep(name("reset"), .perform(request: RequestID(rawValue: uuid(100)), operation: .resetDemo)),
        ] + steps,
        untested: untested
    )
}

// MARK: - Files

/// A folder removed when the value is released. Paths are resolved, so `/var` and `/private/var`
/// never differ in a comparison.
final class TemporaryFolder: Sendable {
    let url: URL

    init() throws {
        let raw = FileManager.default.temporaryDirectory.appending(path: "LabDemoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        url = raw.resolvingSymlinksInPath()
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func write(_ text: String, to relative: String) throws -> URL {
        try write(Data(text.utf8), to: relative)
    }

    @discardableResult
    func write(_ data: Data, to relative: String) throws -> URL {
        let file = url.appending(path: relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
        return file
    }

    func folder(_ relative: String) throws -> URL {
        let folder = url.appending(path: relative, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Every file below `folder`, relative to it, including hidden ones.
    func files(below folder: URL) -> Set<String> {
        var result = Set<String>()
        let walker = FileManager.default.enumerator(atPath: folder.path(percentEncoded: false))
        while let relative = walker?.nextObject() as? String {
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: folder.appending(path: relative).path(percentEncoded: false), isDirectory: &isFolder),
               !isFolder.boolValue {
                result.insert(relative)
            }
        }
        return result
    }

    /// A copy of the showcase folder, for tests that change one file.
    func showcaseCopy() throws -> URL {
        let copy = url.appending(path: "atlas-basics", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: Showcase.atlasBasics, to: copy)
        return copy
    }
}

/// The showcase script as a mutable JSON object, rewritten into a copied folder.
func rewriteScript(in folder: URL, _ change: (inout [String: Any]) -> Void) throws {
    let file = folder.appending(path: DemoScript.fileName)
    var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    change(&object)
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: file)
}

/// A JSON object without the named fields; `steps[].x` removes `x` from every step.
func removing(_ fields: [String], from object: [String: Any]) -> [String: Any] {
    var result = object
    for field in fields {
        if field.hasPrefix("steps[].") {
            let key = String(field.dropFirst("steps[].".count))
            if let steps = result["steps"] as? [[String: Any]] {
                result["steps"] = steps.map { step in
                    var copy = step
                    copy[key] = nil
                    return copy
                }
            }
        } else {
            result[field] = nil
        }
    }
    return result
}

func jsonObject(_ text: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

/// Cancels the task that calls it. From a runner's observer, that is the runner's own task.
func cancelCurrentTask() {
    withUnsafeCurrentTask { $0?.cancel() }
}

/// A store factory that always fails to open.
let unopenableStore = DemoStoreFactory(description: "unopenable") {
    throw StoreError.cannotOpen(code: 14)
}

/// A factory returning a store that already holds a person's collection.
func storeWithUserData() async throws -> DemoStoreFactory {
    let store = InMemoryOperationStore()
    let service = OperationService(store: store)
    _ = try await service.perform(OperationRequest(
        id: RequestID(),
        operation: .createCollection(draft: CollectionDraft(title: "A person's own collection")),
        actor: ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
    ))
    return DemoStoreFactory(description: "pre-filled") { OpenedDemoStore(store: store) }
}

/// Holds values written from a `@Sendable` observer.
final class Collected<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])

    func append(_ value: Value) { storage.withLock { $0.append(value) } }

    var values: [Value] { storage.withLock { $0 } }
}
