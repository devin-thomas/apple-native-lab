import Foundation
import LabDomain

/// Resolves where a request would run and records a usage receipt without raw prompt telemetry.
///
/// Cloud-off (`RoutingPolicy.localOnly`) never calls the cloud transport. Missing entitlement and
/// exhausted quota are explained gates that fall back locally; neither opens a paid provider.
public struct RouteResolver: Sendable {
    public var policy: RoutingPolicy
    public var onDevice: OnDeviceAvailability
    public var pcc: PCCEligibility

    public init(
        policy: RoutingPolicy = .localOnly,
        onDevice: OnDeviceAvailability = .unknown,
        pcc: PCCEligibility = .coreLocalDefault()
    ) {
        self.policy = policy
        self.onDevice = onDevice
        self.pcc = pcc
    }

    /// Observes routes for a prompt without sending anything.
    public func observe(prompt: String) throws(ModelRoutingError) -> RouteObservation {
        let text = try RoutingPrompt.validated(prompt)
        let preview = OutgoingFieldPreview.fixture(prompt: text)
        let decision = decide(wantingLargerModel: true)
        // The outgoing preview is always built so the person can see what would leave under a
        // cloud-allowed policy, even when the current decision stays local.
        return RouteObservation(
            policy: policy,
            onDevice: onDevice,
            pcc: pcc,
            decision: decision,
            preview: preview
        )
    }

    /// Chooses a route. Prefer PCC only when policy allows and every PCC gate is open.
    public func decide(wantingLargerModel: Bool) -> RouteDecision {
        let policyGate = RouteGate(
            .policy,
            policy == .localOnly ? .closed : .open,
            policy == .localOnly
                ? "Policy is local-only. Cloud requests are off."
                : "Policy allows cloud when every other gate is open."
        )

        if policy == .localOnly {
            return localDecision(reason: policyGate.detail, closed: [policyGate])
        }

        guard wantingLargerModel else {
            return localDecision(reason: "A larger model was not requested.", closed: [])
        }

        var closed = pcc.gates.filter { !$0.isOpen }
        if policyGate.state == .closed { closed.insert(policyGate, at: 0) }

        if let entitlement = closed.first(where: { $0.kind == .entitlement }) {
            return localDecision(
                reason: "Missing entitlement is an explained gate. \(entitlement.detail) Local fallback stays available.",
                closed: closed
            )
        }
        if let quota = closed.first(where: { $0.kind == .quota }) {
            return localDecision(
                reason: "\(quota.detail) No paid provider is offered.",
                closed: closed
            )
        }
        if !closed.isEmpty {
            let first = closed[0]
            return localDecision(
                reason: "\(first.kind.title): \(first.detail) Local fallback stays available.",
                closed: closed
            )
        }

        return RouteDecision(
            route: .privateCloudCompute,
            reason: "Every Private Cloud Compute gate is open. Consent and an outgoing-field review are still required before anything leaves the device.",
            closedGates: []
        )
    }

    private func localDecision(reason: String, closed: [RouteGate]) -> RouteDecision {
        if onDevice.isAvailable {
            return RouteDecision(
                route: .onDevice,
                reason: reason + " On-device model is available.",
                closedGates: closed
            )
        }
        return RouteDecision(
            route: .localFallback,
            reason: reason + " On-device: \(onDevice.detail) Using local generation or a manual workflow.",
            closedGates: closed
        )
    }
}

/// Runs observatory steps: observe, preview, consent, local fallback, and optional cloud send.
public actor ModelRoutingFlow {
    private var resolver: RouteResolver
    private let transport: any CloudTransport
    private let diagnostics: DiagnosticsLog?
    private(set) var usage: [UsageReceipt] = []
    private var consent: ConsentGrant?
    private var cloudRequestsAttempted = 0

    public init(
        resolver: RouteResolver = RouteResolver(),
        transport: any CloudTransport = RefusingCloudTransport(),
        diagnostics: DiagnosticsLog? = nil
    ) {
        self.resolver = resolver
        self.transport = transport
        self.diagnostics = diagnostics
    }

    public var policy: RoutingPolicy { resolver.policy }
    public var receipts: [UsageReceipt] { usage }

    public var transportRequestCount: Int {
        get async { await transport.requestCount }
    }

    /// Cloud sends this flow asked the transport to perform. Under local-only it stays zero.
    public var cloudSendAttempts: Int { cloudRequestsAttempted }

    public func setPolicy(_ policy: RoutingPolicy) {
        resolver.policy = policy
        consent = nil
    }

    public func update(onDevice: OnDeviceAvailability? = nil, pcc: PCCEligibility? = nil) {
        if let onDevice { resolver.onDevice = onDevice }
        if let pcc { resolver.pcc = pcc }
        consent = nil
    }

    public func observe(prompt: String) throws(ModelRoutingError) -> RouteObservation {
        try resolver.observe(prompt: prompt)
    }

    /// Issues consent for the exact outgoing preview after the person reviews it.
    public func grantConsent(
        for preview: OutgoingFieldPreview,
        lifetime: Duration = .seconds(120)
    ) throws(ModelRoutingError) -> ConsentGrant {
        guard resolver.policy == .cloudAllowed else { throw .consent(.cloudOff) }
        let grant = ConsentGrant(previewDigest: preview.digest, lifetime: lifetime)
        consent = grant
        record(
            UsageReceipt(
                route: .privateCloudCompute,
                policy: resolver.policy,
                outcome: .observed,
                outgoing: preview,
                summary: "Consent granted for \(preview.fields.count) outgoing fields. Nothing has left the device yet."
            )
        )
        return grant
    }

    /// Completes the interaction on the local fallback path. No cloud, no third-party key.
    public func runLocalFallback(
        prompt: String
    ) throws(ModelRoutingError) -> (summary: String, receipt: UsageReceipt) {
        try Self.throwIfCancelled()
        let text = try RoutingPrompt.validated(prompt)
        let summary = try LocalFallbackGenerator.summarize(text)
        let decision = resolver.decide(wantingLargerModel: false)
        let receipt = UsageReceipt(
            route: .localFallback,
            policy: resolver.policy,
            outcome: .completedLocal,
            closedGates: decision.closedGates,
            summary: "Local fallback completed from \(text.count) prompt characters. Nothing left this device."
        )
        record(receipt)
        diagnostics?.record(
            "route.local",
            outcome: .succeeded,
            subject: ModelRouting.diagnosticSubject,
            counts: ["fields": 0, "prompt-chars": text.count]
        )
        return (summary, receipt)
    }

    /// Completes the manual workflow: the person supplies the answer. Still no cloud.
    public func runManual(prompt: String, answer: String) throws(ModelRoutingError) -> UsageReceipt {
        try Self.throwIfCancelled()
        _ = try RoutingPrompt.validated(prompt)
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw .invalidInput("The manual answer is empty. Nothing was recorded.")
        }
        guard trimmed.count <= RoutingPrompt.maximumLength else {
            throw .invalidInput("The manual answer is too long. Nothing was recorded.")
        }
        let receipt = UsageReceipt(
            route: .localFallback,
            policy: resolver.policy,
            outcome: .completedManual,
            summary: "Manual workflow recorded an answer of \(trimmed.count) characters. Nothing left this device."
        )
        record(receipt)
        diagnostics?.record(
            "route.manual",
            outcome: .succeeded,
            subject: ModelRouting.diagnosticSubject,
            counts: ["answer-chars": trimmed.count]
        )
        return receipt
    }

    /// Attempts a cloud send only after policy, eligibility, quota, and consent all open.
    public func runCloud(
        prompt: String
    ) async throws(ModelRoutingError) -> (result: CloudSendResult, receipt: UsageReceipt) {
        try Self.throwIfCancelled()
        let text = try RoutingPrompt.validated(prompt)
        let observation = try resolver.observe(prompt: text)

        guard resolver.policy == .cloudAllowed else {
            let receipt = refuseCloud(
                observation: observation,
                summary: "Cloud-off caused zero cloud requests. Policy is local-only."
            )
            throw ModelRoutingError.cloudRefused(receipt.summary)
        }

        let decision = observation.decision
        if decision.route != .privateCloudCompute {
            let receipt = refuseCloud(observation: observation, summary: decision.reason)
            throw ModelRoutingError.cloudRefused(receipt.summary)
        }

        let preview = observation.preview!
        let existingConsent = consent
        guard let grant = existingConsent, grant.isValid(for: preview.digest) else {
            let error: ConsentError
            if existingConsent == nil {
                error = .missing
            } else if existingConsent?.previewDigest != preview.digest {
                error = .digestMismatch
            } else {
                error = .expired
            }
            let receipt = UsageReceipt(
                route: .privateCloudCompute,
                policy: resolver.policy,
                outcome: .cloudRefused,
                outgoing: preview,
                closedGates: [RouteGate(.consent, .closed, error.message)],
                summary: error.message
            )
            record(receipt)
            throw .consent(error)
        }

        // A consent grant authorizes one attempt, including across actor reentrancy.
        consent = nil
        let requestPolicy = resolver.policy
        cloudRequestsAttempted += 1
        let result: CloudSendResult
        do {
            result = try await transport.send(preview)
        } catch is CancellationError {
            let receipt = UsageReceipt(
                route: .privateCloudCompute,
                policy: resolver.policy,
                outcome: .cancelled,
                outgoing: preview,
                summary: ModelRoutingError.cancelled.message
            )
            record(receipt)
            throw .cancelled
        } catch {
            record(UsageReceipt(
                route: .privateCloudCompute, policy: requestPolicy, outcome: .unavailable,
                outgoing: preview, summary: "Cloud transport failed; delivery is unconfirmed. Nothing was changed in the lab."
            ))
            throw .unavailable("Cloud transport failed; delivery is unconfirmed. Nothing was changed in the lab.")
        }

        let receipt = UsageReceipt(
            route: .privateCloudCompute,
            policy: requestPolicy,
            outcome: result.accepted ? .cloudSent : .cloudRefused,
            outgoing: preview,
            summary: result.accepted
                ? "Cloud transport accepted the previewed fields."
                : "Cloud transport refused the previewed fields. Nothing left this device."
        )
        record(receipt)
        let promptChars = preview.fields.first(where: { $0.name == "prompt" })?.characterCount ?? 0
        diagnostics?.record(
            "route.cloud",
            outcome: result.accepted ? .succeeded : .rejected,
            subject: ModelRouting.diagnosticSubject,
            counts: ["fields": preview.fields.count, "prompt-chars": promptChars]
        )
        return (result, receipt)
    }

    public func cancelRecording() {
        let receipt = UsageReceipt(
            route: resolver.decide(wantingLargerModel: true).route,
            policy: resolver.policy,
            outcome: .cancelled,
            summary: ModelRoutingError.cancelled.message
        )
        record(receipt)
    }

    /// Removes only this experiment's recorded usage and consent. Does not touch the lab store.
    public func resetDemo() {
        usage.removeAll()
        consent = nil
        cloudRequestsAttempted = 0
    }

    private func refuseCloud(observation: RouteObservation, summary: String) -> UsageReceipt {
        let route: InferenceRoute = observation.decision.route == .privateCloudCompute
            ? .localFallback
            : observation.decision.route
        let receipt = UsageReceipt(
            route: route,
            policy: resolver.policy,
            outcome: .cloudRefused,
            outgoing: observation.preview,
            closedGates: observation.decision.closedGates,
            summary: summary
        )
        record(receipt)
        return receipt
    }

    private func record(_ receipt: UsageReceipt) {
        usage.append(receipt)
    }

    private static func throwIfCancelled() throws(ModelRoutingError) {
        do {
            try Task.checkCancellation()
        } catch {
            throw ModelRoutingError.cancelled
        }
    }
}
