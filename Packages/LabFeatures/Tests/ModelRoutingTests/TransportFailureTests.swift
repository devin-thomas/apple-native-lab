import Testing
@testable import ModelRouting

@Suite struct TransportFailureTests {
    @Test func failureRecordsUnconfirmedDeliveryWithoutErrorText() async throws {
        let flow = ModelRoutingFlow(
            resolver: RouteResolver(policy: .cloudAllowed, pcc: openPCC()),
            transport: FailingTransport()
        )
        let preview = try #require(await flow.observe(prompt: "private-marker").preview)
        _ = try await flow.grantConsent(for: preview)
        await #expect(throws: ModelRoutingError.self) {
            try await flow.runCloud(prompt: "private-marker")
        }
        let last = try #require(await flow.receipts.last)
        #expect(last.outcome == .unavailable)
        #expect(last.summary.contains("unconfirmed"))
        #expect(!last.summary.contains("private-marker"))
        await #expect(throws: ModelRoutingError.consent(.missing)) {
            try await flow.runCloud(prompt: "private-marker")
        }
        #expect(await flow.cloudSendAttempts == 1)
    }
}

private actor FailingTransport: CloudTransport {
    var requestCount = 0
    struct Failure: Error {}
    func send(_ preview: OutgoingFieldPreview) async throws -> CloudSendResult {
        requestCount += 1
        throw Failure()
    }
}
