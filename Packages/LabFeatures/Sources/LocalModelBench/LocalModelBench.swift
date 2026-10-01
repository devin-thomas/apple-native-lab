import Foundation
import LabDomain

/// LAB-015 Local Model Bench: compare a fixed corpus on correctness, latency, memory, and
/// thermal class. This module does not load a model. The runnable path is the fixture executor,
/// and every result it produces says it is not inference.
///
/// Recording a result and resetting the experiment's own items go through `OperationService`
/// (ADR-011, ADR-013). A model tool can read; it cannot record or archive.
public enum LocalModelBench {
    public static let experimentID = "LAB-015"

    /// The sentence the fixture path shows. It matches the experiment's fallback.
    public static let notInferenceLabel = "Deterministic fixture executor benchmarks the pipeline, marked as not inference."

    /// App UI records and resets. A grant is still required for the archive (ADR-013); the host
    /// issues it only when a person presses Reset Bench Results.
    public static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    /// The model-tool ceiling. Recording uses `commit`, which this scope cannot hold.
    public static let modelTool = ActorScope(adapter: .modelTool, grants: [.read, .propose])

    /// The user collection that holds only this experiment's recorded reports.
    public static let resultsCollectionID = CollectionID(rawValue: UUID(uuidString: "015A0000-0000-4000-8000-000000000015")!)

    /// One request ID for creating that collection, so a retry does not create a second one.
    public static let resultsCollectionRequestID = RequestID(rawValue: UUID(uuidString: "015A0000-0000-4000-8000-000000000016")!)
}

/// Why a bench step was refused. A refusal loads nothing and, unless a record had already
/// committed, writes nothing.
public enum BenchError: Error, Hashable, Sendable {
    case invalidCase
    case emptyCorpus
    /// The license is not the fixture license this build accepts.
    case licenseRefused
    /// The descriptor named no memory budget, so it cannot be checked.
    case missingMemoryBudget
    case exceedsMemory(required: UInt64, available: UInt64)
    /// No model runtime is linked. The fixture executor is the usable path.
    case liveModelUnavailable
    /// Cold and warm results are different runs. They are not one score.
    case mixedThermal
    /// A failed task is not a performance result.
    case failedTask
    /// Download and warm-up are not measured runs.
    case notMeasured
    case emptyScore
    case cancelled
    case unauthorized
    case unavailable
    case reportTooLarge
    case refused(OperationError)

    /// A sentence for a person. It names the rule, not a score.
    public var explanation: String {
        switch self {
        case .invalidCase:
            "That case is not in the fixed corpus, so nothing ran."
        case .emptyCorpus:
            "The corpus is empty, so nothing ran."
        case .licenseRefused:
            "This model's license is not accepted, so it was not loaded."
        case .missingMemoryBudget:
            "This model names no memory budget, so it was not loaded."
        case .exceedsMemory(let required, let available):
            "This model asks for \(required) bytes and \(available) are available, so it was not loaded."
        case .liveModelUnavailable:
            "No model runtime is linked in this build. The fixture executor can still run, and it is not inference."
        case .mixedThermal:
            "Cold and warm results stay separate. They are not one score."
        case .failedTask:
            "A task failed, so there is no performance score."
        case .notMeasured:
            "Only a measured run has a score. Download and warm-up stay separate."
        case .emptyScore:
            "There is no measured run to score."
        case .cancelled:
            "The run was cancelled. Nothing was recorded."
        case .unauthorized:
            "That action is not allowed from here. Nothing was recorded."
        case .unavailable:
            "The lab is unavailable. Nothing was recorded."
        case .reportTooLarge:
            "The report is too large to store. Nothing was recorded."
        case .refused:
            "The lab refused the change. Nothing new was recorded."
        }
    }
}

/// The live model route. This build does not call Core ML or Foundation Models.
/// The installed load entry allocates a model, and the SDK reports no byte budget before that.
public enum LiveModelBench {
    /// Refuses before any loader. There is no model to allocate.
    public static func run() throws(BenchError) {
        throw .liveModelUnavailable
    }
}
