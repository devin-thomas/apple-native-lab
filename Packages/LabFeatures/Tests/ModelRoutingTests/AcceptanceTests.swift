import Foundation
import LabDomain
import Testing
@testable import ModelRouting

@Suite struct CloudOffTests {
    @Test func cloudOffCausesZeroCloudRequests() async throws {
        let transport = CountingCloudTransport()
        let flow = ModelRoutingFlow(
            resolver: RouteResolver(
                policy: .localOnly,
                onDevice: OnDeviceAvailability(isAvailable: true, detail: "available"),
                pcc: openPCC()
            ),
            transport: transport
        )
        let prompt = try Repository.fixturePrompt()

        let observation = try await flow.observe(prompt: prompt)
        #expect(observation.policy == .localOnly)
        #expect(observation.decision.route != .privateCloudCompute)
        #expect(observation.decision.closedGates.contains { $0.kind == .policy })

        await #expect(throws: ModelRoutingError.self) {
            try await flow.runCloud(prompt: prompt)
        }
        #expect(await flow.cloudSendAttempts == 0)
        #expect(await transport.requestCount == 0)

        // Even with open PCC gates and a consent attempt, local-only refuses before consent.
        await #expect(throws: ModelRoutingError.self) {
            try await flow.grantConsent(for: observation.preview!)
        }
        #expect(await transport.requestCount == 0)
    }

    @Test func cloudAllowedStillNeedsGatesBeforeAnySend() async throws {
        let transport = CountingCloudTransport()
        let flow = ModelRoutingFlow(
            resolver: RouteResolver(
                policy: .cloudAllowed,
                onDevice: OnDeviceAvailability(isAvailable: false, detail: "off"),
                pcc: closedEntitlementPCC()
            ),
            transport: transport
        )
        let prompt = try Repository.fixturePrompt()
        await #expect(throws: ModelRoutingError.self) {
            try await flow.runCloud(prompt: prompt)
        }
        #expect(await flow.cloudSendAttempts == 0)
        #expect(await transport.requestCount == 0)
    }
}

@Suite struct EntitlementGateTests {
    @Test func missingEntitlementIsAnExplainedGate() throws {
        let resolver = RouteResolver(
            policy: .cloudAllowed,
            onDevice: OnDeviceAvailability(isAvailable: true, detail: "available"),
            pcc: closedEntitlementPCC()
        )
        let decision = resolver.decide(wantingLargerModel: true)
        #expect(decision.route == .onDevice)
        #expect(decision.closedGates.contains { $0.kind == .entitlement && $0.state == .closed })
        #expect(decision.reason.contains(ModelRouting.pccEntitlement))
        #expect(decision.reason.contains("Local fallback stays available"))
    }

    @Test func coreLocalDefaultClosesEntitlementProgramAndDistribution() {
        let pcc = PCCEligibility.coreLocalDefault()
        #expect(pcc.entitlement.state == .closed)
        #expect(pcc.program.state == .closed)
        #expect(pcc.distribution.state == .closed)
        #expect(pcc.explanation?.contains("Entitlement") == true)
    }
}

@Suite struct QuotaExhaustionTests {
    @Test func exhaustedQuotaNeverSwitchesToAPaidProvider() async throws {
        let transport = CountingCloudTransport()
        let flow = ModelRoutingFlow(
            resolver: RouteResolver(
                policy: .cloudAllowed,
                onDevice: OnDeviceAvailability(isAvailable: false, detail: "unavailable"),
                pcc: openPCC(quota: .limitReached)
            ),
            transport: transport
        )
        let prompt = try Repository.fixturePrompt()
        let observation = try await flow.observe(prompt: prompt)
        #expect(observation.decision.route == .localFallback)
        #expect(observation.decision.closedGates.contains { $0.kind == .quota })
        #expect(observation.decision.reason.contains("No paid provider"))
        #expect(!PaidProvider.isOffered)
        #expect(PaidProvider.supportedProviders.isEmpty)

        await #expect(throws: ModelRoutingError.self) {
            try await flow.runCloud(prompt: prompt)
        }
        #expect(await flow.cloudSendAttempts == 0)
        #expect(await transport.requestCount == 0)

        // Local fallback still completes the interaction.
        let (summary, receipt) = try await flow.runLocalFallback(prompt: prompt)
        #expect(summary.contains("Local summary"))
        #expect(receipt.outcome == .completedLocal)
        #expect(receipt.route == .localFallback)
    }
}

@Suite struct FallbackTests {
    @Test func localGenerationCompletesWithoutAThirdPartyKey() async throws {
        let flow = ModelRoutingFlow(
            resolver: RouteResolver(
                policy: .localOnly,
                onDevice: OnDeviceAvailability(isAvailable: false, detail: "off"),
                pcc: .coreLocalDefault()
            )
        )
        let prompt = try Repository.fixturePrompt()
        let (summary, receipt) = try await flow.runLocalFallback(prompt: prompt)
        #expect(summary.contains("not a model"))
        #expect(summary.contains("not cloud"))
        #expect(receipt.outcome == .completedLocal)
        #expect(await flow.transportRequestCount == 0)
    }

    @Test func manualWorkflowCompletesWithoutAThirdPartyKey() async throws {
        let flow = ModelRoutingFlow()
        let prompt = try Repository.fixturePrompt()
        let receipt = try await flow.runManual(prompt: prompt, answer: "Tracing vellum, by hand.")
        #expect(receipt.outcome == .completedManual)
        #expect(receipt.summary.contains("Nothing left this device"))
        #expect(await flow.transportRequestCount == 0)
    }
}
