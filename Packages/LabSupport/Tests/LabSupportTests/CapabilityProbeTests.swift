import Testing
@testable import LabSupport

@Suite struct CapabilityProbeTests {
    private func report(
        _ capability: Capability,
        on platform: LabPlatform = .iOS,
        _ configure: (inout FakeCapabilitySource) -> Void = { _ in }
    ) async -> CapabilityReport {
        var source = FakeCapabilitySource()
        configure(&source)
        return await CapabilityRegistry(platform: platform, source: source).report(for: capability)
    }

    @Test func deniedCameraRoutesToTheDocumentedFallback() async {
        let camera = await report(.camera) { $0.statuses[.camera] = .denied }
        #expect(camera.readiness == .denied)
        #expect(camera.gate(.permission)?.state == .denied)
        #expect(camera.route == .fallback(Capability.camera.fallback))
        #expect(camera.route.fallbackRoute?.experiments.contains("LAB-026") == true)
    }

    @Test func restrictedPermissionAlsoRoutesToTheFallback() async {
        let speech = await report(.speechRecognition) { $0.statuses[.speechRecognition] = .restricted }
        #expect(speech.readiness == .denied)
        #expect(speech.route == .fallback(Capability.speechRecognition.fallback))
    }

    @Test func deniedCameraAlsoClosesWorldTracking() async {
        let tracking = await report(.worldTracking) { $0.statuses[.camera] = .denied }
        #expect(tracking.gate(.hardware)?.state == .met)
        #expect(tracking.readiness == .denied)
        #expect(tracking.route == .fallback(Capability.worldTracking.fallback))
    }

    @Test func undeterminedPermissionNeedsAFeatureAction() async {
        let microphone = await report(.microphone)
        #expect(microphone.readiness == .needsAction)
        #expect(!microphone.readiness.isReady)
        #expect(microphone.route == .afterFeatureAction(ifDeclined: Capability.microphone.fallback))
    }

    @Test func allowedAndConfiguredIsAvailableButNotVerified() async {
        let camera = await report(.camera) { $0.statuses[.camera] = .authorized }
        #expect(camera.readiness == .available)
        #expect(camera.route == .live)
        #expect(!camera.isDeviceVerified)
        #expect(camera.gates.last == .noDeviceEvidence)
    }

    @Test func missingPurposeStringMakesTheBuildUnavailable() async {
        let camera = await report(.camera) {
            $0.statuses[.camera] = .authorized
            $0.purposeStrings = []
        }
        #expect(camera.readiness == .unavailable)
        #expect(camera.decidingGates.map(\.kind) == [.entitlement])
        #expect(camera.gate(.entitlement)?.detail.contains("NSCameraUsageDescription") == true)
    }

    @Test func macBuildNeedsSandboxDeviceEntitlements() async {
        let microphone = await report(.microphone, on: .macOS) {
            $0.statuses[.microphone] = .authorized
            $0.entitlements["com.apple.security.device.audio-input"] = .absent
        }
        #expect(microphone.readiness == .unavailable)
        #expect(microphone.gate(.entitlement)?.detail.contains("com.apple.security.device.audio-input") == true)

        let iPhone = await report(.microphone, on: .iOS) { $0.statuses[.microphone] = .authorized }
        #expect(iPhone.gate(.entitlement)?.detail.contains("com.apple.security") == false)
        #expect(iPhone.readiness == .available)
    }

    @Test func missingCameraHardwareIsUnavailable() async {
        let camera = await report(.camera, on: .macOS) {
            $0.captureDevices[.video] = false
            $0.statuses[.camera] = .authorized
        }
        #expect(camera.gate(.hardware)?.state == .unmet)
        #expect(camera.readiness == .unavailable)
    }

    @Test func localNetworkPermissionIsUnknownWithAReason() async {
        let lan = await report(.localNetwork, on: .iOS)
        let permission = lan.gate(.permission)
        #expect(permission?.state == .unknown)
        #expect(permission?.detail.contains("localNetworkDenied") == true)
        #expect(lan.readiness == .unknown)
        #expect(lan.route == .fallback(Capability.localNetwork.fallback))
    }

    @Test func bluetoothRadioStateStaysUnknown() async {
        let bluetooth = await report(.bluetooth) { $0.statuses[.bluetooth] = .authorized }
        #expect(bluetooth.gate(.hardware)?.state == .unknown)
        #expect(bluetooth.readiness == .unknown)
    }

    @Test func ultraWidebandNeedsTheChipAndAnUnreadablePermission() async {
        let noChip = await report(.ultraWideband) { $0.uwb = UltraWidebandReading(preciseDistance: false, direction: false) }
        #expect(noChip.readiness == .unavailable)

        let chip = await report(.ultraWideband)
        #expect(chip.gate(.hardware)?.state == .met)
        #expect(chip.gate(.permission)?.state == .unknown)
        #expect(chip.readiness == .unknown)
    }

    @Test func sceneReconstructionNeedsMeshSupport() async {
        let noMesh = await report(.sceneReconstruction) {
            $0.arkit = WorldTrackingReading(worldTracking: true, sceneReconstruction: false)
            $0.statuses[.camera] = .authorized
        }
        #expect(noMesh.gate(.hardware)?.state == .unmet)
        let tracking = await report(.worldTracking) {
            $0.arkit = WorldTrackingReading(worldTracking: true, sceneReconstruction: false)
            $0.statuses[.camera] = .authorized
        }
        #expect(tracking.readiness == .available)
    }

    @Test(arguments: [
        (LanguageModelReading.Availability.available, Bool?.some(true), CapabilityReadiness.available, GateKind?.none),
        (.available, false, .unavailable, .service),
        (.deviceNotEligible, nil, .unavailable, .hardware),
        (.appleIntelligenceNotEnabled, nil, .unavailable, .service),
        (.modelNotReady, true, .unavailable, .asset),
        (.unrecognized("futureReason"), nil, .unknown, .hardware),
    ])
    func languageModelReasonsMapToSeparateGates(
        availability: LanguageModelReading.Availability,
        locale: Bool?,
        expected: CapabilityReadiness,
        deciding: GateKind?
    ) async {
        let model = await report(.onDeviceLanguageModel, on: .macOS) {
            $0.model = LanguageModelReading(availability: availability, supportsCurrentLocale: locale, localeIdentifier: "en_US")
        }
        #expect(model.readiness == expected)
        #expect(model.decidingGates.first?.kind == deciding)
        #expect(model.gate(.permission) == nil, "The system model needs no permission.")
        #expect(model.gate(.entitlement) == nil)
    }

    @Test func speechAssetStatesAreSeparateFromPermission() async {
        let downloadable = await report(.speechRecognition) {
            $0.statuses[.speechRecognition] = .authorized
            $0.speech = SpeechTranscriptionReading(transcriberAvailable: true, localeIdentifier: "fr_FR", asset: .downloadable)
        }
        #expect(downloadable.gate(.asset)?.state == .needsAction)
        #expect(downloadable.readiness == .needsAction)

        let unsupported = await report(.speechRecognition) {
            $0.speech = SpeechTranscriptionReading(transcriberAvailable: true, localeIdentifier: "xx", asset: .unsupportedLocale)
        }
        #expect(unsupported.readiness == .unavailable)
        #expect(unsupported.gate(.asset)?.detail.contains("xx") == true)

        let noTranscriber = await report(.speechRecognition) {
            $0.speech = SpeechTranscriptionReading(transcriberAvailable: false, localeIdentifier: "en_US", asset: .unknown)
        }
        #expect(noTranscriber.gate(.hardware)?.state == .unmet)
        #expect(noTranscriber.gate(.asset)?.state == .unknown)
    }

    @Test func simulatedSensorsAreNotHardwareEvidence() async {
        // The iOS 27 simulator reports Ultra Wideband precise distance; that is not a chip.
        let uwb = await report(.ultraWideband) {
            $0.isSimulator = true
            $0.uwb = UltraWidebandReading(preciseDistance: true, direction: false)
        }
        #expect(uwb.gate(.hardware)?.state == .unknown)
        #expect(uwb.gate(.hardware)?.detail.hasPrefix("Simulator:") == true)

        let camera = await report(.camera) {
            $0.isSimulator = true
            $0.statuses[.camera] = .authorized
        }
        #expect(camera.gate(.hardware)?.state == .unknown)
        #expect(!camera.readiness.isReady)

        // A negative simulator reading still means it cannot run here.
        let tracking = await report(.worldTracking) {
            $0.isSimulator = true
            $0.arkit = WorldTrackingReading(worldTracking: false, sceneReconstruction: false)
        }
        #expect(tracking.gate(.hardware)?.state == .unmet)

        // The language model is software on the simulator's host, so it keeps its reading.
        let model = await report(.onDeviceLanguageModel) { $0.isSimulator = true }
        #expect(model.readiness == .available)
    }

    @Test func excludedCapabilityIsExplainedWithoutTouchingTheSource() async {
        let trap = PromptTrapSource()
        let registry = CapabilityRegistry(platform: .macOS, source: trap)
        let tracking = await registry.report(for: .worldTracking)
        #expect(!tracking.isProbed)
        #expect(tracking.gate(.osAPI)?.state == .unmet)
        #expect(tracking.readiness == .unavailable)
        #expect(tracking.route == .fallback(Capability.worldTracking.fallback))
        #expect(registry.excludedReports().map(\.capability) == [.worldTracking, .sceneReconstruction, .ultraWideband])
    }

    @Test func everyReportEndsWithTheUnverifiedGate() async {
        for platform in LabPlatform.allCases {
            let registry = CapabilityRegistry(platform: platform, source: FakeCapabilitySource())
            for report in await registry.probeAll() + registry.excludedReports() {
                #expect(report.gate(.verification) == .noDeviceEvidence)
                #expect(!report.isDeviceVerified)
                #expect(report.gates.map(\.kind) == report.gates.map(\.kind).sorted { $0.order < $1.order })
            }
        }
    }
}
