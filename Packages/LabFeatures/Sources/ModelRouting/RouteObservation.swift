import Foundation

/// Snapshot of what the observatory shows: on-device availability, PCC eligibility, policy, and
/// the route that would run for the current request.
public struct RouteObservation: Hashable, Sendable {
    public let policy: RoutingPolicy
    public let onDevice: OnDeviceAvailability
    public let pcc: PCCEligibility
    public let decision: RouteDecision
    public let preview: OutgoingFieldPreview?

    public init(
        policy: RoutingPolicy,
        onDevice: OnDeviceAvailability,
        pcc: PCCEligibility,
        decision: RouteDecision,
        preview: OutgoingFieldPreview?
    ) {
        self.policy = policy
        self.onDevice = onDevice
        self.pcc = pcc
        self.decision = decision
        self.preview = preview
    }
}

/// The route chosen for one request, with an explained reason.
public struct RouteDecision: Hashable, Sendable {
    public let route: InferenceRoute
    /// Why this route was chosen, naming closed gates when relevant.
    public let reason: String
    public let closedGates: [RouteGate]

    public init(route: InferenceRoute, reason: String, closedGates: [RouteGate] = []) {
        self.route = route
        self.reason = reason
        self.closedGates = closedGates
    }
}

/// Why the observatory refused or could not complete a step.
public enum ModelRoutingError: Error, Hashable, Sendable {
    case invalidInput(String)
    case unavailable(String)
    case cancelled
    case cloudRefused(String)
    case consent(ConsentError)

    public var message: String {
        switch self {
        case .invalidInput(let detail): detail
        case .unavailable(let detail): detail
        case .cancelled: "Cancelled. Nothing was changed in the lab; an in-flight delivery may be unconfirmed."
        case .cloudRefused(let detail): detail
        case .consent(let error): error.message
        }
    }
}

/// Deterministic local generation for the fallback path. No model and no network.
public enum LocalFallbackGenerator {
    /// A short, labeled summary of the fixture prompt. Never claims to be a model answer.
    public static func summarize(_ prompt: String) throws(ModelRoutingError) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw .invalidInput("The prompt is empty. Nothing was generated.")
        }
        guard trimmed.count <= RoutingPrompt.maximumLength else {
            throw .invalidInput(
                "The prompt is longer than \(RoutingPrompt.maximumLength) characters. Nothing was generated."
            )
        }
        if trimmed.unicodeScalars.contains(where: { $0.value < 0x20 && $0 != "\n" && $0 != "\t" }) {
            throw .invalidInput("The prompt holds a control character. Nothing was generated.")
        }
        let words = trimmed.split { $0.isWhitespace || $0.isNewline }.prefix(12)
        let head = words.joined(separator: " ")
        return "Local summary (not a model, not cloud): \(words.count) words starting “\(head)”."
    }
}

/// Bounds for an observatory prompt.
public enum RoutingPrompt {
    public static let maximumLength = 2_000

    public static func validated(_ text: String) throws(ModelRoutingError) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw .invalidInput("The prompt is empty.")
        }
        guard trimmed.count <= maximumLength else {
            throw .invalidInput("The prompt is longer than \(maximumLength) characters.")
        }
        if trimmed.unicodeScalars.contains(where: { $0.value < 0x20 && $0 != "\n" && $0 != "\t" }) {
            throw .invalidInput("The prompt holds a control character.")
        }
        return trimmed
    }
}
