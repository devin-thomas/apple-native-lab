import Foundation

/// A recorded route and usage outcome with no raw prompt, note, or model output.
///
/// Field names and character counts may appear; values never do. This is the experiment's
/// `UsageReceipt`, separate from a domain `ActionReceipt` that proves a store commit.
public struct UsageReceipt: Hashable, Sendable, Identifiable {
    public enum Outcome: String, Hashable, Sendable, Codable {
        case observed
        case completedLocal
        case completedManual
        case cloudRefused
        case cloudSent
        case cancelled
        case invalidInput
        case unavailable
    }

    public let id: UUID
    public let recordedAt: Date
    public let route: InferenceRoute
    public let policy: RoutingPolicy
    public let outcome: Outcome
    /// Outgoing field names and lengths only when a cloud preview was built.
    public let outgoingFieldNames: [String]
    public let outgoingFieldLengths: [Int]
    /// Closed gate kinds that decided the route, if any.
    public let closedGateKinds: [RouteGate.Kind]
    /// One sentence for the UI. Never contains the prompt.
    public let summary: String

    public init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        route: InferenceRoute,
        policy: RoutingPolicy,
        outcome: Outcome,
        outgoing: OutgoingFieldPreview? = nil,
        closedGates: [RouteGate] = [],
        summary: String
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.route = route
        self.policy = policy
        self.outcome = outcome
        if let outgoing {
            outgoingFieldNames = outgoing.fields.map(\.name)
            outgoingFieldLengths = outgoing.fields.map(\.characterCount)
        } else {
            outgoingFieldNames = []
            outgoingFieldLengths = []
        }
        closedGateKinds = closedGates.map(\.kind)
        self.summary = summary
    }
}
