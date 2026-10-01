import Foundation
import LabDomain
import LocalModelBench
import Observation

/// One run the bench keeps apart from the others. Download, warm-up, cold measured, and warm
/// measured are four results. The page never adds them together.
enum BenchSlot: String, CaseIterable, Identifiable, Hashable {
    case download
    case warmup
    case cold
    case warm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .download: "Download"
        case .warmup: "Warm-up"
        case .cold: "Measured, cold"
        case .warm: "Measured, warm"
        }
    }

    var phase: RunPhase {
        switch self {
        case .download: .download
        case .warmup: .warmup
        case .cold, .warm: .measured
        }
    }

    var thermal: ThermalClass {
        switch self {
        case .download, .cold: .cold
        case .warmup, .warm: .warm
        }
    }
}

/// LAB-015 in one window: the four runs, and the one report selected for recording.
@MainActor
@Observable
final class LocalModelBenchSession {
    private(set) var reports: [BenchSlot: BenchReport] = [:]
    var selection: BenchSlot?
    private(set) var message: String?
    private(set) var isRunning = false
    var isConfirmingReset = false
    private var task: Task<Void, Never>?

    /// Starts a run and keeps it so Cancel can stop it. Opening the experiment does not run anything.
    func start(_ slot: BenchSlot) {
        task?.cancel()
        task = Task { await run(slot) }
    }

    /// Runs one phase on the fixture executor. It does not record.
    func run(_ slot: BenchSlot) async {
        isRunning = true
        defer { isRunning = false }
        let executor = FixtureExecutor()
        do {
            let report = try await executor.run(
                phase: slot.phase,
                thermal: slot.thermal,
                availableBytes: ProcessInfo.processInfo.physicalMemory,
                machine: .current
            )
            if Task.isCancelled { return }
            reports[slot] = report
            selection = slot
            message = LocalModelBench.notInferenceLabel
        } catch let error as BenchError {
            if Task.isCancelled { return }
            reports[slot] = nil
            message = error.explanation
        } catch {
            message = BenchError.unavailable.explanation
        }
    }

    func cancel() {
        task?.cancel()
        message = BenchError.cancelled.explanation
    }

    /// Records the selected report. This is the explicit action; opening the experiment does not record.
    func record(using library: LabLibrary) async {
        guard let selection, let report = reports[selection] else {
            message = "Run a phase first. Nothing was recorded."
            return
        }
        do {
            let receipt = try await BenchRecorder(backend: LibraryBenchBackend(library: library)).record(report)
            message = "Recorded. \(receipt.summary)"
        } catch let error as BenchError {
            message = error.explanation
        } catch {
            message = BenchError.unavailable.explanation
        }
    }

    /// Archives this experiment's recorded reports and leaves every other item alone.
    func reset(using library: LabLibrary) async {
        do {
            let receipts = try await BenchRecorder(backend: LibraryBenchBackend(library: library)).reset()
            message = receipts.isEmpty
                ? "No bench reports to reset."
                : "Reset \(receipts.count == 1 ? "1 bench report" : "\(receipts.count) bench reports"). Other items were left alone."
        } catch let error as BenchError {
            message = error.explanation
        } catch {
            message = BenchError.unavailable.explanation
        }
    }
}

/// The host's bench adapter. Reads and commits go through `LabLibrary`, which is the app UI.
struct LibraryBenchBackend: LocalModelBenchBackend {
    let library: LabLibrary

    func collection(_ id: CollectionID) async throws(BenchError) -> LabCollection? {
        let service = try await opened()
        do {
            return try await service.collection(id, as: LabDataService.appUI)
        } catch .notFound {
            return nil
        } catch {
            throw .refused(error)
        }
    }

    func items(in collection: CollectionID) async throws(BenchError) -> [LabItem] {
        let service = try await opened()
        let filter: ItemFilter
        do {
            filter = try ItemFilter(collectionID: collection, includeArchived: true, limit: ItemFilter.allowedLimits.upperBound)
        } catch {
            throw .unavailable
        }
        do {
            return try await service.items(filter, as: LabDataService.appUI)
        } catch {
            throw .refused(error)
        }
    }

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(BenchError) -> ActionReceipt {
        do {
            return try await library.submit(operation, requestID: requestID, authority: .userAction, names: names).receipt
        } catch let error as LabLibrary.SubmitFailure {
            switch error {
            case .unavailable: throw .unavailable
            case .refused(let refusal):
                if case .unauthorized = refusal { throw .unauthorized }
                throw .refused(refusal)
            }
        } catch {
            throw .unavailable
        }
    }

    private func opened() async throws(BenchError) -> LabDataService {
        do { return try await library.openedService() } catch { throw .unavailable }
    }
}
