import Foundation
import LabDomain
import LabJobs
@testable import RenderThatSurvives
import Synchronization
import Testing

let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

enum Recipes {
    static let bundled: [RenderRecipe] = try! RenderThatSurvives.bundledRecipes()
    static var short: RenderRecipe { bundled.first { $0.id == "short-bars" }! }
    static var long: RenderRecipe { bundled.first { $0.id == "long-bars" }! }
}

/// `Fixtures/LAB-032/` at the repository root, found from this source file.
enum HostileRecipes {
    static let folder: URL = URL(filePath: #filePath)
        .deletingLastPathComponent() // RenderThatSurvivesTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LabFeatures
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository root
        .appending(path: "Fixtures/LAB-032", directoryHint: .isDirectory)

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: folder.appending(path: name, directoryHint: .notDirectory))
    }
}

/// A capacity reading the test sets.
struct FixedCapacity: VolumeCapacityReading {
    let bytes: Int64?
    func availableBytes(at url: URL) throws -> Int64? { bytes }
}

/// A runway that grants a fixed mode and lets the test end its time early.
final class TestRunway: JobRunway {
    let mode: RunwayMode
    private let expirations = Mutex<[@Sendable () -> Void]>([])
    let finishes = Mutex<[Bool]>([])

    init(mode: RunwayMode) { self.mode = mode }

    func begin(_ request: RunwayRequest, onExpiration: @escaping @Sendable () -> Void) async -> any JobRunwayLease {
        expirations.withLock { $0.append(onExpiration) }
        return TestLease(mode: mode, runway: self)
    }

    /// Ends every lease's time, as the system would.
    func expire() {
        for handler in expirations.withLock({ $0 }) { handler() }
    }

    struct TestLease: JobRunwayLease {
        let mode: RunwayMode
        let runway: TestRunway
        func report(completed: Int64, total: Int64) {}
        func finish(success: Bool) { runway.finishes.withLock { $0.append(success) } }
    }
}

/// Stage hooks a test sets per run: each runs when the worker reaches that stage.
final class StageHooks: Sendable {
    private let hooks = Mutex<[RenderStage: @Sendable (JobID) async -> Void]>([:])
    let seen = Mutex<[RenderStage]>([])

    func on(_ stage: RenderStage, _ body: @escaping @Sendable (JobID) async -> Void) {
        hooks.withLock { $0[stage] = body }
    }

    func reached(_ id: JobID, _ stage: RenderStage) async {
        seen.withLock { $0.append(stage) }
        if let hook = hooks.withLock({ $0.removeValue(forKey: stage) }) { await hook(id) }
    }
}

/// A studio over an in-memory store and a temporary workspace.
final class Bench: Sendable {
    let store = InMemoryOperationStore()
    let service: OperationService
    let backend: RecordingBackend
    let workspace: RenderWorkspace
    let hooks = StageHooks()
    let runway: TestRunway
    let studio: RenderStudio

    init(gpu: GPUAccess = .unavailable, capacity: Int64? = 1 << 34, runway: RunwayMode = .whileAppRuns) {
        service = OperationService(store: store)
        backend = RecordingBackend(ServiceJobBackend(service: service, actor: appUI))
        workspace = RenderWorkspace(root: FileManager.default.temporaryDirectory
            .appending(path: "RenderThatSurvivesTests-\(UUID().uuidString)", directoryHint: .isDirectory))
        self.runway = TestRunway(mode: runway)
        let hooks = hooks
        studio = RenderStudio(
            backend: backend, workspace: workspace, destination: DestinationCheck(capacity: FixedCapacity(bytes: capacity)),
            gpu: gpu, runway: self.runway, onStage: { id, stage in await hooks.reached(id, stage) }
        )
    }

    deinit { try? FileManager.default.removeItem(at: workspace.root) }

    /// Starts a render and waits for its worker to end.
    func render(
        _ recipe: RenderRecipe = Recipes.short,
        options: RenderStudio.Options = RenderStudio.Options(preferGPU: false)
    ) async throws -> (LabJob, RenderOutcome) {
        let job = try await studio.start(recipe, options: options)
        let outcome = try #require(await studio.outcome(of: job.id))
        return (job, outcome)
    }

    func resume(_ id: JobID, options: RenderStudio.Options = RenderStudio.Options(preferGPU: false)) async throws -> RenderOutcome {
        _ = try await studio.resume(id, options: options)
        return try #require(await studio.outcome(of: id))
    }

    func job(_ id: JobID) async throws -> LabJob { try await backend.job(id) }

    var summaries: [String] { backend.summaries }

    func outputBytes(_ recipe: RenderRecipe = Recipes.short) throws -> Data {
        try Data(contentsOf: workspace.output(for: recipe))
    }

    func workFolderExists(_ id: JobID) -> Bool {
        FileManager.default.fileExists(atPath: workspace.workFolder(for: id).path(percentEncoded: false))
    }

    /// Every file under the workspace, as paths relative to its root, sorted.
    func files() -> [String] {
        let root = workspace.root.standardizedFileURL.path(percentEncoded: false)
        let enumerator = FileManager.default.enumerator(atPath: root)
        var files: [String] = []
        while let path = enumerator?.nextObject() as? String {
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: root + "/" + path, isDirectory: &isFolder)
            if !isFolder.boolValue { files.append(path) }
        }
        return files.sorted()
    }
}

/// A backend that keeps every receipt it returns, in order.
final class RecordingBackend: JobBackend {
    let inner: ServiceJobBackend
    let receipts = Mutex<[ActionReceipt]>([])

    init(_ inner: ServiceJobBackend) { self.inner = inner }

    func job(_ id: JobID) async throws(JobError) -> LabJob { try await inner.job(id) }
    func jobs(of kind: JobKind) async throws(JobError) -> [LabJob] { try await inner.jobs(of: kind) }

    func commit(_ operation: DomainOperation, requestID: RequestID) async throws(JobError) -> ActionReceipt {
        let receipt = try await inner.commit(operation, requestID: requestID)
        receipts.withLock { $0.append(receipt) }
        return receipt
    }

    var summaries: [String] { receipts.withLock { $0.map(\.summary) } }
}
