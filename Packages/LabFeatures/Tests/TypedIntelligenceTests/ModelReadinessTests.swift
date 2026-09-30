import LabSupport
import Testing
@testable import TypedIntelligence

/// When the model is unavailable, the probe names the gate that closed the route, and the route is
/// the non-model fallback. Uses CORE-004's probe with a fake device.
@Suite struct ModelReadinessTests {
    struct FakeDevice: CapabilitySource {
        var model: LanguageModelReading
        var isSimulator: Bool { false }
        func permissionStatus(_ permission: PermissionKind) -> PermissionStatus { .notReadable }
        func hasCaptureDevice(_ kind: CaptureDeviceKind) -> Bool? { nil }
        func speechTranscription() async -> SpeechTranscriptionReading {
            SpeechTranscriptionReading(transcriberAvailable: nil, localeIdentifier: "en_US", asset: .unknown)
        }
        func languageModel() -> LanguageModelReading { model }
        func worldTracking() -> WorldTrackingReading? { nil }
        func ultraWideband() -> UltraWidebandReading? { nil }
        func entitlement(_ key: String) -> EntitlementReading { .notReadable }
        func declaresPurposeString(_ key: String) -> Bool { false }
    }

    private func readiness(_ availability: LanguageModelReading.Availability, locale: Bool? = true) async -> ModelReadiness {
        let reading = LanguageModelReading(availability: availability, supportsCurrentLocale: locale, localeIdentifier: "en_US")
        return await ModelReadiness.probe(CapabilityRegistry(platform: .macOS, source: FakeDevice(model: reading)))
    }

    @Test func anAvailableModelOpensTheModelRoute() async {
        let open = await readiness(.available)
        #expect(open.route == .model)
        #expect(open.failedGates.isEmpty)
        #expect(open.explanation == nil)
    }

    @Test(arguments: [
        (LanguageModelReading.Availability.deviceNotEligible, true as Bool?, GateKind.hardware, "deviceNotEligible"),
        (.appleIntelligenceNotEnabled, true, .service, "appleIntelligenceNotEnabled"),
        (.modelNotReady, true, .asset, "modelNotReady"),
        (.available, false, .service, "does not support"),
    ])
    func eachClosedGateIsNamed(availability: LanguageModelReading.Availability, locale: Bool?, gate: GateKind, words: String) async throws {
        let closed = await readiness(availability, locale: locale)
        #expect(closed.route == .fallback)
        #expect(closed.readiness == .unavailable)
        #expect(closed.failedGates.map(\.kind) == [gate])
        let explanation = try #require(closed.explanation)
        #expect(explanation.contains(words))
        #expect(explanation.hasPrefix(gate.title))
        #expect(closed.fallback.summary.contains("sample parser"))
        #expect(closed.fallback.experiments == ["LAB-010"])
    }

    @Test func anUnmeasuredModelIsNeverTreatedAsReady() async {
        for availability in [LanguageModelReading.Availability.notCompiled, .unrecognized("future")] {
            let unknown = await readiness(availability, locale: nil)
            #expect(unknown.route == .fallback)
            #expect(unknown.readiness == .unknown)
            #expect(unknown.explanation != nil)
        }
    }

    @Test func extractionFailuresExplainTheModelGate() {
        #expect(ExtractionFailure.modelUnavailable(.appleIntelligenceNotEnabled).message.contains("turned off"))
        #expect(ExtractionFailure.modelUnavailable(.deviceNotEligible).message.contains("cannot run"))
        #expect(ExtractionFailure.modelUnavailable(.modelNotReady).message.contains("not ready"))
        for failure in [ExtractionFailure.refused, .unsupportedLanguage, .contextTooLarge, .busy, .malformedOutput] {
            #expect(failure.message.contains("sample parser"), "\(failure) points to the fallback")
        }
    }
}
