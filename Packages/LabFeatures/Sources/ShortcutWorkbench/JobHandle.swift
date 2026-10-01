import Foundation

/// Progress for a recipe run or export job. Terminal states are not restartable from a surface.
public enum JobState: String, Hashable, Sendable, Codable, CaseIterable {
    case queued
    case running
    case waitingForResource = "waiting-for-resource"
    case completed
    case cancelled
    case failed
}

/// A value snapshot of one recipe job. Surfaces and intents pass this; they never own cancellation
/// of another process's work.
public struct JobHandle: Hashable, Sendable, Codable, Identifiable {
    public var id: JobID { jobID }
    public let jobID: JobID
    public let recipeID: RecipeID
    public let kind: String
    public var state: JobState
    public var checkpoint: Int
    public var completedUnits: Int
    public var totalUnits: Int?
    public var summary: String

    public init(
        jobID: JobID = JobID(),
        recipeID: RecipeID,
        kind: String = "recipe-run",
        state: JobState = .queued,
        checkpoint: Int = 0,
        completedUnits: Int = 0,
        totalUnits: Int? = nil,
        summary: String = ""
    ) {
        self.jobID = jobID
        self.recipeID = recipeID
        self.kind = kind
        self.state = state
        self.checkpoint = checkpoint
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
        self.summary = summary
    }

    public var isTerminal: Bool {
        switch state {
        case .completed, .cancelled, .failed: true
        case .queued, .running, .waitingForResource: false
        }
    }
}
