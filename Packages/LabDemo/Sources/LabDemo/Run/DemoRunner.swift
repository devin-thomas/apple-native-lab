import Foundation
import LabDomain
import LabStore
import LabSupport
import Synchronization

/// A store opened for exactly one run, and how to dispose of it afterwards.
public struct OpenedDemoStore: Sendable {
    public let store: any OperationStore
    let close: @Sendable () -> Void

    public init(store: any OperationStore, close: @escaping @Sendable () -> Void = {}) {
        self.store = store
        self.close = close
    }
}

/// Makes the fresh store each run starts from.
///
/// The runner refuses a store that already holds a collection or an item, so a script's approvals
/// can only ever act on the throwaway state it built itself, never on a person's data.
public struct DemoStoreFactory: Sendable {
    /// What the store is, recorded in the run's environment.
    public let description: String
    let open: @Sendable () async throws -> OpenedDemoStore

    public init(description: String, open: @escaping @Sendable () async throws -> OpenedDemoStore) {
        self.description = description
        self.open = open
    }

    /// LabDomain's in-memory reference store.
    public static let inMemory = DemoStoreFactory(description: "in-memory") {
        OpenedDemoStore(store: InMemoryOperationStore())
    }

    /// A new SQLite store in its own temporary folder, removed when the run ends.
    public static let temporarySQLite = DemoStoreFactory(
        description: "sqlite (schema \(SQLiteOperationStore.schemaVersion), temporary file)"
    ) {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "LabDemo-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            let store = try await SQLiteOperationStore(url: folder.appending(path: "demo.sqlite"))
            return OpenedDemoStore(store: store) { try? FileManager.default.removeItem(at: folder) }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}

/// Replays a `DemoScript` against a fresh store, through `OperationService`, and records what
/// every step did.
///
/// A run never throws: every refusal, failure, cancellation, or missing prerequisite becomes a
/// step record with its own result. The runner composes the domain the way a host does:
///
/// - The actor is the runner's adapter kind (the app UI by default) holding that adapter's
///   ceiling (ADR-011). A script cannot choose or widen it.
/// - The service uses `GrantAuthorizationPolicy` with `GrantRequirement.sensitiveCommits`
///   (ADR-013), and the only grants come from the script's `approve` steps, each issued by the
///   in-memory ledger for exactly one later step's operation.
/// - Receipt IDs are derived from the script's input hashes and a counter, so a replay of the
///   same inputs produces the same receipts.
/// - After the first step that does not pass, the remaining steps are `skipped` (not-run). If the
///   task is cancelled, the steps that had not started are `cancelled` (not-run). A step that was
///   running when the task was cancelled keeps its own result, because a commit is not
///   interrupted halfway.
public struct DemoRunner: Sendable {
    public let adapter: AdapterKind
    private let storeFactory: DemoStoreFactory
    private let clock: any IntervalClock
    private let grantClock: any GrantClock
    private let wallClock: @Sendable () -> Date
    private let diagnostics: DiagnosticsLog?

    /// - Parameters:
    ///   - adapter: The adapter the host composes the runner as. Its ceiling is the actor's scope.
    ///   - store: Where each run's fresh store comes from.
    ///   - clock: The monotonic clock for step intervals. Its timebase is recorded in the run.
    ///   - grantClock: The ledger's clock for grant expiry.
    ///   - wallClock: The wall clock for the run's start time only.
    public init(
        adapter: AdapterKind = .appUI,
        store: DemoStoreFactory = .temporarySQLite,
        clock: any IntervalClock = ContinuousIntervalClock(),
        grantClock: any GrantClock = SystemGrantClock(),
        wallClock: @escaping @Sendable () -> Date = { Date() },
        diagnostics: DiagnosticsLog? = nil
    ) {
        self.adapter = adapter
        storeFactory = store
        self.clock = clock
        self.grantClock = grantClock
        self.wallClock = wallClock
        self.diagnostics = diagnostics
    }

    /// Runs every step of `script` in order and returns the complete record.
    ///
    /// - Parameter observer: Called with each step's record as soon as it is final, on the
    ///   runner's task. A host can show progress; a test can cancel.
    public func run(_ script: DemoScript, observer: (@Sendable (DemoStepRecord) -> Void)? = nil) async -> DemoRun {
        let runID = DemoRunID()
        let startedAt = wallClock()
        let environment = DemoEnvironment(store: storeFactory.description, timebase: clock.timebase)

        func finish(_ steps: [DemoStepRecord], _ state: DemoState?) -> DemoRun {
            let run = DemoRun(
                id: runID, script: script, adapter: adapter, environment: environment,
                startedAt: startedAt, steps: steps, finalState: state
            )
            diagnostics?.record(
                "demo.run",
                outcome: run.result == .passed ? .succeeded : (run.steps.contains { $0.disposition == .cancelled } ? .cancelled : .failed),
                subject: DiagnosticSubject(script.subject),
                duration: run.totalDuration,
                counts: ["steps": run.steps.count, "passed": run.steps.filter { $0.result == .passed }.count]
            )
            return run
        }

        func notStarted(_ disposition: StepDisposition, _ reason: String) -> [DemoStepRecord] {
            script.steps.map { step in
                let record = DemoStepRecord(notStarted: step, disposition, reason: reason)
                observer?(record)
                return record
            }
        }

        if Task.isCancelled {
            return finish(notStarted(.cancelled, "The replay was cancelled before this step started."), nil)
        }
        let opened: OpenedDemoStore
        do {
            opened = try await storeFactory.open()
        } catch {
            return finish(notStarted(.blocked, "The fresh store could not be opened, so no step could start."), nil)
        }
        defer { opened.close() }
        let store = opened.store
        do {
            guard try await store.collections().isEmpty, try await store.items(in: nil).isEmpty else {
                return finish(
                    notStarted(.blocked, "The store was not empty, so the replay could not start from the seed alone."), nil
                )
            }
        } catch {
            return finish(notStarted(.blocked, "The fresh store could not be read, so no step could start."), nil)
        }

        let ledger = GrantLedger(clock: grantClock, diagnostics: diagnostics)
        let operationIDs = DerivedOperationIDs(script.inputDigest)
        let service = OperationService(
            store: store,
            policy: GrantAuthorizationPolicy(ledger: ledger, requirement: .sensitiveCommits, diagnostics: diagnostics),
            makeOperationID: { operationIDs.next() }
        )
        var context = StepContext(
            script: script,
            actor: ActorScope(adapter: adapter, grants: adapter.ceiling),
            service: service,
            ledger: ledger
        )

        let origin = clock.now()
        var records: [DemoStepRecord] = []
        var stop: (StepDisposition, String)?
        for step in script.steps {
            if stop == nil, Task.isCancelled {
                stop = (.cancelled, "The replay was cancelled before this step started.")
            }
            if case let (disposition, reason)? = stop {
                let record = DemoStepRecord(notStarted: step, disposition, reason: reason)
                records.append(record)
                observer?(record)
                continue
            }
            let start = clock.now()
            let execution = await context.execute(step)
            let end = clock.now()
            let record = DemoStepRecord(
                ran: step,
                passed: execution.passed,
                detail: execution.detail,
                timing: StepTiming(start: start - origin, duration: end - start),
                receipt: execution.receipt,
                found: execution.found,
                approval: execution.approval
            )
            records.append(record)
            observer?(record)
            if !execution.passed {
                stop = (.skipped, "Step \(step.id) did not pass, so this step would not start from the state the script expects.")
            }
        }

        let state: DemoState?
        do {
            state = DemoState(
                collections: try await store.collections(), items: try await store.items(in: nil), sessions: try await store.sessions()
            )
        } catch {
            state = nil
        }
        return finish(records, state)
    }
}

// MARK: - Steps

private struct StepExecution {
    var passed: Bool
    var detail: String
    var receipt: ActionReceipt?
    var found: [ItemID]?
    var approval: ApprovalRecord?
}

/// What one run knows while it executes steps: the service, the ledger, and earlier receipts.
private struct StepContext {
    let script: DemoScript
    let actor: ActorScope
    let service: OperationService
    let ledger: GrantLedger
    var receipts: [DemoStepID: ActionReceipt] = [:]

    init(script: DemoScript, actor: ActorScope, service: OperationService, ledger: GrantLedger) {
        self.script = script
        self.actor = actor
        self.service = service
        self.ledger = ledger
    }

    mutating func execute(_ step: DemoStep) async -> StepExecution {
        switch step.action {
        case .approve(let target):
            return approve(target)
        case .perform(let request, let scripted):
            return await perform(step.id, request: request, scripted)
        case .find(let find):
            return await self.find(find)
        }
    }

    /// Resolves what a `perform` step will submit. An undo is read from the recorded receipt.
    private func operation(for scripted: ScriptedOperation) -> Result<DomainOperation, StepFailure> {
        switch scripted {
        case .resetDemo:
            return .success(.resetDemo(seed: script.seed))
        case .domain(let operation):
            return .success(operation)
        case .undo(let earlier):
            guard let receipt = receipts[earlier] else {
                return .failure(StepFailure("Step \(earlier) recorded no receipt, so there is nothing to undo."))
            }
            guard let undo = receipt.undo else {
                return .failure(StepFailure("Step \(earlier)'s receipt offers no undo."))
            }
            return .success(undo)
        }
    }

    private func approve(_ target: DemoStepID) -> StepExecution {
        guard let step = script.steps.first(where: { $0.id == target }), case .perform(_, let scripted) = step.action else {
            return StepExecution(passed: false, detail: "Step \(target) is not a perform step.")
        }
        let operation: DomainOperation
        switch self.operation(for: scripted) {
        case .success(let resolved): operation = resolved
        case .failure(let failure): return StepExecution(passed: false, detail: failure.detail)
        }
        do {
            let grant = try ledger.issue(for: operation, to: actor.adapter)
            let approval = ApprovalRecord(approvedStep: target, grant: grant, operation: operation.kind)
            return StepExecution(
                passed: true,
                detail: "Approved \(operation.kind.rawValue) on \(approval.target) through \(actor.adapter.rawValue) for \(approval.lifetimeSeconds) s.",
                approval: approval
            )
        } catch {
            return StepExecution(passed: false, detail: "The grant ledger refused the approval: \(Self.describe(error)).")
        }
    }

    private mutating func perform(_ id: DemoStepID, request: RequestID, _ scripted: ScriptedOperation) async -> StepExecution {
        let operation: DomainOperation
        switch self.operation(for: scripted) {
        case .success(let resolved): operation = resolved
        case .failure(let failure): return StepExecution(passed: false, detail: failure.detail)
        }
        do {
            let receipt = try await service.perform(OperationRequest(id: request, operation: operation, actor: actor))
            receipts[id] = receipt
            switch receipt.status {
            case .committed:
                return StepExecution(passed: true, detail: "Committed: \(receipt.summary)", receipt: receipt)
            case .conflict:
                return StepExecution(passed: false, detail: "Conflict, nothing changed: \(receipt.summary)", receipt: receipt)
            }
        } catch {
            return StepExecution(passed: false, detail: "Refused: \(Self.describe(error)).")
        }
    }

    private func find(_ find: ScriptedFind) async -> StepExecution {
        do {
            let found = try await service.findItems(find.filter, as: actor).map(\.id)
            if found == find.expected {
                return StepExecution(passed: true, detail: "Found \(Self.count(found.count)) as expected.", found: found)
            }
            return StepExecution(
                passed: false,
                detail: "Found \(Self.list(found)), expected \(Self.list(find.expected)).",
                found: found
            )
        } catch {
            return StepExecution(passed: false, detail: "Refused: \(Self.describe(error)).")
        }
    }

    // MARK: Descriptions

    private static func count(_ value: Int) -> String { value == 1 ? "1 item" : "\(value) items" }

    private static func list(_ ids: [ItemID]) -> String {
        ids.isEmpty ? "no items" : "[" + ids.map(\.description).joined(separator: ", ") + "]"
    }

    static func describe(_ error: GrantError) -> String {
        switch error {
        case .noOperations: "no operation named"
        case .lifetimeOutOfRange: "lifetime out of range"
        case .exceedsAdapterCeiling(let kind): "\(kind.rawValue) is outside the adapter's ceiling"
        case .targetMismatch(let kind): "\(kind.rawValue) cannot act on that target"
        }
    }

    static func describe(_ error: OperationError) -> String {
        switch error {
        case .invalidPayload(let problem):
            "invalid payload (\(problem))"
        case .unauthorized(let denial):
            switch denial.reason {
            case .outsideAdapterCeiling:
                "\(denial.required.rawValue) is outside the \(denial.adapter.rawValue) adapter's ceiling"
            case .notGranted:
                "\(denial.required.rawValue) was not granted to the \(denial.adapter.rawValue) actor"
            case .deniedByPolicy:
                "no live approval covers this \(denial.required.rawValue) through \(denial.adapter.rawValue)"
            }
        case .notFound(let reference):
            "\(reference) was not found"
        case .requestIDReused(let request):
            "request ID \(request) already names a different request"
        case .ruleViolation(let violation):
            describe(violation)
        case .storeFailure(let failure):
            "store failure (\(failure))"
        }
    }

    private static func describe(_ violation: RuleViolation) -> String {
        switch violation {
        case .alreadyExists(let reference): "\(reference) already exists"
        case .alreadyArchived(let reference): "\(reference) is already archived"
        case .notArchived(let reference): "\(reference) is not archived"
        case .archived(let reference): "\(reference) is archived; restore it first"
        case .collectionArchived(let id): "collection \(id) is archived"
        case .demoCollection(let id): "collection \(id) is a demo collection, which holds only seed samples"
        case .noChanges(let reference): "the update would leave \(reference) unchanged"
        case .nothingToCancel: "there are no lab alerts to cancel"
        }
    }
}

private struct StepFailure: Error {
    let detail: String

    init(_ detail: String) { self.detail = detail }
}

/// Receipt IDs derived from a script's input digest and a counter.
private final class DerivedOperationIDs: Sendable {
    private let digest: ContentDigest
    private let counter = Mutex(0)

    init(_ digest: ContentDigest) { self.digest = digest }

    func next() -> OperationID {
        let value = counter.withLock { value in
            value += 1
            return value
        }
        return OperationID(rawValue: Canonical.derivedUUID("demo-operation", digest, value))
    }
}
