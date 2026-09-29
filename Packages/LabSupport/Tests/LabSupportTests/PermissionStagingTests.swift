import Testing
@testable import LabSupport

@Suite struct PermissionStagingTests {
    private func stage(
        _ capability: Capability,
        on platform: LabPlatform = .iOS,
        answers: [PermissionKind: PermissionStatus] = [:],
        _ configure: (inout FakeCapabilitySource) -> Void = { _ in }
    ) async -> (PermissionOutcome, [PermissionKind]) {
        var source = FakeCapabilitySource()
        configure(&source)
        let spy = SpyRequester(answers: answers)
        let stager = PermissionStager(platform: platform, source: source, requester: spy)
        let outcome = await stager.request(for: action(capability))
        return (outcome, spy.requests)
    }

    @Test func deniedRoutesToTheFallbackWithoutAskingAgain() async {
        let (outcome, requests) = await stage(.camera) { $0.statuses[.camera] = .denied }
        #expect(outcome == .fallback(Capability.camera.fallback, reason: .denied))
        #expect(requests.isEmpty)
    }

    @Test func restrictedRoutesToTheFallbackWithoutAsking() async {
        let (outcome, requests) = await stage(.speechRecognition) { $0.statuses[.speechRecognition] = .restricted }
        #expect(outcome == .fallback(Capability.speechRecognition.fallback, reason: .restricted))
        #expect(requests.isEmpty)
    }

    @Test func allowedReturnsWithoutAsking() async {
        let (outcome, requests) = await stage(.microphone) { $0.statuses[.microphone] = .authorized }
        #expect(outcome == .granted)
        #expect(requests.isEmpty)
    }

    @Test func undeterminedAsksOnceAndHonorsTheAnswer() async {
        let (granted, asked) = await stage(.camera, answers: [.camera: .authorized])
        #expect(granted == .granted)
        #expect(asked == [.camera])

        let (declined, askedAgain) = await stage(.worldTracking, answers: [.camera: .denied])
        #expect(declined == .fallback(Capability.worldTracking.fallback, reason: .declinedNow))
        #expect(askedAgain == [.camera])
    }

    @Test func missingPurposeStringFallsBackInsteadOfCrashing() async {
        let (outcome, requests) = await stage(.camera) { $0.purposeStrings = [] }
        #expect(outcome == .fallback(Capability.camera.fallback, reason: .missingPurposeString("NSCameraUsageDescription")))
        #expect(requests.isEmpty)
    }

    @Test func missingMacEntitlementFallsBackInsteadOfAsking() async {
        let (outcome, requests) = await stage(.camera, on: .macOS) {
            $0.entitlements["com.apple.security.device.camera"] = .absent
        }
        #expect(outcome == .fallback(Capability.camera.fallback, reason: .missingEntitlement("com.apple.security.device.camera")))
        #expect(requests.isEmpty)
    }

    @Test(arguments: [Capability.bluetooth, .ultraWideband, .localNetwork])
    func sessionOnlyPermissionsAreLeftToTheSystem(_ capability: Capability) async {
        let (outcome, requests) = await stage(capability)
        #expect(outcome == .systemAsksOnUse(ifDeclined: capability.fallback))
        #expect(requests.isEmpty)
    }

    @Test func deniedBluetoothStillFallsBack() async {
        let (outcome, _) = await stage(.bluetooth) { $0.statuses[.bluetooth] = .denied }
        #expect(outcome == .fallback(Capability.bluetooth.fallback, reason: .denied))
    }

    @Test func capabilityWithoutPermissionNeedsNothing() async {
        let (outcome, requests) = await stage(.onDeviceLanguageModel)
        #expect(outcome == .notRequired)
        #expect(outcome.fallbackRoute == nil)
        #expect(requests.isEmpty)
    }

    @Test func concurrentRequestsShareOnePrompt() async {
        let spy = SpyRequester(answers: [.microphone: .authorized], delay: .milliseconds(50))
        let stager = PermissionStager(platform: .iOS, source: FakeCapabilitySource(), requester: spy)
        async let first = stager.request(for: action(.microphone))
        async let second = stager.request(for: action(.microphone))
        let outcomes = await [first, second]
        #expect(outcomes == [.granted, .granted])
        #expect(spy.requests == [.microphone])
    }
}
