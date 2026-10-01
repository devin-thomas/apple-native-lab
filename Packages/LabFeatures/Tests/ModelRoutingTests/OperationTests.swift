import Foundation
import LabDomain
import Testing
@testable import ModelRouting

@Suite struct AuthorizationReceiptTests {
    @Test func sensitiveLocalAnnotationSharesTheDomainReceiptPath() async throws {
        let lab = try await RoutingLab.seeded()
        let prompt = try Repository.fixturePrompt()
        let (summary, usage) = try await lab.flow.runLocalFallback(prompt: prompt)
        #expect(usage.outcome == .completedLocal)

        let items = try await lab.backend.demoItems()
        let target = try #require(items.first { $0.title.value == "Tracing vellum" })
        let operation = try LocalFallbackCommit.operation(for: target, summary: summary)

        // Propose as the model-tool adapter; commit as the app UI under a new request ID.
        let proposal = try await lab.backend.propose(operation)
        #expect(proposal.operation == operation)

        let requestID = RequestID()
        let receipt = try await lab.backend.commit(operation, requestID: requestID)
        #expect(receipt.conflict == nil)
        #expect(receipt.admitted.adapter == .appUI)
        #expect(receipt.requestID == requestID)
        #expect(receipt.summary.contains("Tracing vellum") || receipt.summary.contains("Updated"))

        let updated = try #require(await lab.store.item(target.id))
        #expect(updated.note.value.contains("Local summary"))
        #expect(updated.revision == target.revision.next())
    }

    @Test func theProposerCannotCommit() async throws {
        let lab = try await RoutingLab.seeded()
        let items = try await lab.backend.demoItems()
        let target = try #require(items.first)
        let operation = try LocalFallbackCommit.operation(
            for: target,
            summary: "Local summary (not a model, not cloud): test."
        )
        await #expect(throws: OperationError.self) {
            try await lab.service.perform(
                OperationRequest(id: RequestID(), operation: operation, actor: ModelRouting.proposer)
            )
        }
        let unchanged = try #require(await lab.store.item(target.id))
        #expect(unchanged.revision == target.revision)
    }
}

@Suite struct CancellationInvalidUnavailableTests {
    @Test func invalidInputIsRefusedBeforeAnyCloudOrWrite() async throws {
        let transport = CountingCloudTransport()
        let flow = ModelRoutingFlow(transport: transport)
        await #expect(throws: ModelRoutingError.self) {
            try await flow.observe(prompt: " ")
        }
        await #expect(throws: ModelRoutingError.self) {
            try await flow.runLocalFallback(prompt: "a\u{0}b")
        }
        await #expect(throws: ModelRoutingError.self) {
            try await flow.runManual(prompt: "ok", answer: "")
        }
        #expect(await transport.requestCount == 0)
        #expect(await flow.receipts.isEmpty)
    }

    @Test func cancelledCloudPathRecordsCancellation() async throws {
        let flow = ModelRoutingFlow(
            resolver: RouteResolver(
                policy: .cloudAllowed,
                onDevice: .unknown,
                pcc: openPCC()
            ),
            transport: CountingCloudTransport()
        )
        let prompt = try Repository.fixturePrompt()
        let observation = try await flow.observe(prompt: prompt)
        _ = try await flow.grantConsent(for: observation.preview!)

        let transport = CancellingTransport()
        let cancellingFlow = ModelRoutingFlow(
            resolver: RouteResolver(policy: .cloudAllowed, onDevice: .unknown, pcc: openPCC()),
            transport: transport
        )
        _ = try await cancellingFlow.grantConsent(for: observation.preview!)
        await #expect(throws: ModelRoutingError.cancelled) {
            try await cancellingFlow.runCloud(prompt: prompt)
        }
        let last = try #require(await cancellingFlow.receipts.last)
        #expect(last.outcome == .cancelled)
        #expect(await transport.requestCount == 1)
    }

    @Test func unavailablePCCStaysOnLocalFallback() throws {
        let pcc = PCCEligibility(
            entitlement: RouteGate(.entitlement, .open, "open"),
            program: RouteGate(.program, .open, "open"),
            distribution: RouteGate(.distribution, .open, "open"),
            availability: RouteGate(
                .availability, .closed,
                "PrivateCloudComputeLanguageModel.availability reports .deviceNotEligible."
            ),
            quota: QuotaState.belowLimit(approaching: false).gate
        )
        let decision = RouteResolver(
            policy: .cloudAllowed,
            onDevice: OnDeviceAvailability(isAvailable: false, detail: "on-device off"),
            pcc: pcc
        ).decide(wantingLargerModel: true)
        #expect(decision.route == .localFallback)
        #expect(decision.reason.contains("deviceNotEligible") || decision.reason.contains("Local fallback"))
    }
}

@Suite struct PrivacyAndPreviewTests {
    @Test func usageReceiptsHoldFieldNamesNotPromptText() async throws {
        let flow = ModelRoutingFlow(
            resolver: RouteResolver(policy: .cloudAllowed, onDevice: .unknown, pcc: openPCC()),
            transport: CountingCloudTransport(),
            diagnostics: DiagnosticsLog(sinks: [CollectingDiagnosticSink()])
        )
        let prompt = try Repository.fixturePrompt()
        let observation = try await flow.observe(prompt: prompt)
        let preview = try #require(observation.preview)
        #expect(preview.fields.map(\.name) == ["prompt", "locale", "model", "sampling"])
        #expect(preview.fields.contains { $0.name == "prompt" && $0.value == prompt })

        _ = try await flow.grantConsent(for: preview)
        let (_, receipt) = try await flow.runCloud(prompt: prompt)
        #expect(receipt.outgoingFieldNames == ["prompt", "locale", "model", "sampling"])
        #expect(receipt.outgoingFieldLengths == preview.fields.map(\.characterCount))
        // The receipt summary and encoded-looking fields must not embed the prompt body.
        #expect(!receipt.summary.contains("vellum"))
        #expect(!receipt.summary.contains("field-notebook"))
    }

    @Test func pccEligibilityIsSeparateFromOnDeviceAvailability() {
        let onDevice = OnDeviceAvailability(isAvailable: true, detail: "on-device ready")
        let pcc = PCCEligibility.coreLocalDefault(
            availability: RouteGate(.availability, .open, "PCC available"),
            quota: QuotaState.belowLimit(approaching: false).gate
        )
        #expect(onDevice.isAvailable)
        #expect(!pcc.isFullyOpen)
        #expect(pcc.entitlement.state == .closed)

        let decision = RouteResolver(policy: .cloudAllowed, onDevice: onDevice, pcc: pcc)
            .decide(wantingLargerModel: true)
        #expect(decision.route == .onDevice)
        #expect(decision.closedGates.contains { $0.kind == .entitlement })
    }

    @Test func openGatesWithConsentReachTheTransportOnce() async throws {
        let transport = CountingCloudTransport()
        let flow = ModelRoutingFlow(
            resolver: RouteResolver(
                policy: .cloudAllowed,
                onDevice: .unknown,
                pcc: openPCC()
            ),
            transport: transport
        )
        let prompt = try Repository.fixturePrompt()
        let observation = try await flow.observe(prompt: prompt)
        #expect(observation.decision.route == .privateCloudCompute)
        _ = try await flow.grantConsent(for: observation.preview!)
        let (result, receipt) = try await flow.runCloud(prompt: prompt)
        #expect(result.accepted)
        #expect(receipt.outcome == .cloudSent)
        #expect(await flow.cloudSendAttempts == 1)
        #expect(await transport.requestCount == 1)
    }

    @Test func resetDemoClearsOnlyExperimentOwnedState() async throws {
        let flow = ModelRoutingFlow()
        _ = try await flow.runLocalFallback(prompt: try Repository.fixturePrompt())
        #expect(await flow.receipts.count == 1)
        await flow.resetDemo()
        #expect(await flow.receipts.isEmpty)
        #expect(await flow.cloudSendAttempts == 0)
    }

    @Test func fixtureIsTheBundledFile() throws {
        let fromDisk = try Repository.fixturePrompt()
        let fromBundle = try RoutingFixture.samplePrompt.load(from: Bundle.module)
        #expect(fromDisk == fromBundle)
        #expect(fromDisk.contains("tracing vellum"))
    }
}

private actor CancellingTransport: CloudTransport {
    var requestCount = 0
    func send(_ preview: OutgoingFieldPreview) async throws -> CloudSendResult {
        requestCount += 1
        throw CancellationError()
    }
}

@Suite struct ConsentBoundaryTests {
    @Test func unknownGateFailsClosed() async throws {
        let open = openPCC()
        let unknown = PCCEligibility(
            entitlement: open.entitlement, program: open.program, distribution: open.distribution,
            availability: RouteGate(.availability, .unknown, "Not measured"), quota: open.quota
        )
        #expect(unknown.explanation?.contains("Not measured") == true)
        let flow = ModelRoutingFlow(resolver: RouteResolver(policy: .cloudAllowed, pcc: unknown))
        let prompt = try Repository.fixturePrompt()
        let observation = try await flow.observe(prompt: prompt)
        #expect(observation.decision.route == .localFallback)
        #expect(observation.decision.closedGates.contains { $0.state == .unknown })
        _ = try await flow.grantConsent(for: observation.preview!)
        await #expect(throws: ModelRoutingError.self) { try await flow.runCloud(prompt: prompt) }
        #expect(await flow.cloudSendAttempts == 0)
    }

    @Test func missingExpiredChangedAndConsumedConsentNeverSendTwice() async throws {
        let transport = CountingCloudTransport()
        let flow = ModelRoutingFlow(
            resolver: RouteResolver(policy: .cloudAllowed, pcc: openPCC()), transport: transport
        )
        let prompt = try Repository.fixturePrompt()
        let preview = try #require(await flow.observe(prompt: prompt).preview)
        await #expect(throws: ModelRoutingError.consent(.missing)) { try await flow.runCloud(prompt: prompt) }
        _ = try await flow.grantConsent(for: preview, lifetime: .zero)
        await #expect(throws: ModelRoutingError.consent(.expired)) { try await flow.runCloud(prompt: prompt) }
        _ = try await flow.grantConsent(for: preview)
        await #expect(throws: ModelRoutingError.consent(.digestMismatch)) { try await flow.runCloud(prompt: prompt + " changed") }
        #expect(await transport.requestCount == 0)
        _ = try await flow.runCloud(prompt: prompt)
        await #expect(throws: ModelRoutingError.consent(.missing)) { try await flow.runCloud(prompt: prompt) }
        #expect(await transport.requestCount == 1)
    }

    @Test func localReceiptDoesNotCopyPromptDerivedSummary() async throws {
        let flow = ModelRoutingFlow()
        let (summary, receipt) = try await flow.runLocalFallback(prompt: "unique-private-marker")
        #expect(summary.contains("unique-private-marker"))
        #expect(!receipt.summary.contains("unique-private-marker"))
    }

    @Test func digestCannotAliasEmbeddedDelimiters() {
        let one = OutgoingFieldPreview(fields: [.init(name: "a", value: "b\nc=d")])
        let two = OutgoingFieldPreview(fields: [.init(name: "a", value: "b"), .init(name: "c", value: "d")])
        #expect(one.digest != two.digest)
    }

    @Test func duplicateCommitReplaysAndStaleCommitChangesNothing() async throws {
        let lab = try await RoutingLab.seeded()
        let target = try #require(await lab.backend.demoItems().first)
        let operation = try LocalFallbackCommit.operation(for: target, summary: "Reviewed summary")
        let request = RequestID()
        let first = try await lab.backend.commit(operation, requestID: request)
        let duplicate = try await lab.backend.commit(operation, requestID: request)
        #expect(first.operationID == duplicate.operationID)
        let stale = try await lab.backend.commit(operation, requestID: RequestID())
        #expect(stale.conflict != nil)
        let updated = try #require(await lab.store.item(target.id))
        #expect(updated.revision == target.revision.next())
    }
}
