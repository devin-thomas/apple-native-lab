import Testing
@testable import LabSupport

@Suite struct ProbePlanTests {
    private func frameworks(on platform: LabPlatform) -> Set<String> {
        Set(Capability.probed(on: platform).compactMap { $0.framework(on: platform) })
    }

    @Test func watchOSExcludesFrameworksItDoesNotSupport() {
        let probed = Capability.probed(on: .watchOS)
        #expect(!probed.contains(.worldTracking))
        #expect(!probed.contains(.sceneReconstruction))
        #expect(!probed.contains(.onDeviceLanguageModel))
        #expect(!probed.contains(.speechRecognition))
        #expect(!probed.contains(.camera))
        #expect(frameworks(on: .watchOS) == ["AVFAudio", "NearbyInteraction", "CoreBluetooth"])
    }

    @Test func macOSHasNoARKitOrNearbyInteractionProbe() {
        let probed = Capability.probed(on: .macOS)
        #expect(!probed.contains(.worldTracking))
        #expect(!probed.contains(.sceneReconstruction))
        #expect(!probed.contains(.ultraWideband))
        #expect(!frameworks(on: .macOS).contains("ARKit"))
        #expect(!frameworks(on: .macOS).contains("NearbyInteraction"))
    }

    @Test func tvOSProbesOnlyBluetoothAndLocalNetwork() {
        #expect(Capability.probed(on: .tvOS) == [.bluetooth, .localNetwork])
    }

    @Test func visionOSIsOutsideThePlan() {
        #expect(Capability.probed(on: .visionOS).isEmpty)
    }

    @Test func iOSProbesEveryCapability() {
        #expect(Capability.probed(on: .iOS) == Capability.allCases)
    }

    @Test func probedAndExcludedPartitionEveryPlatform() {
        for platform in LabPlatform.allCases {
            let probed = Set(Capability.probed(on: platform))
            let excluded = Set(Capability.excluded(on: platform))
            #expect(probed.isDisjoint(with: excluded))
            #expect(probed.union(excluded) == Set(Capability.allCases))
        }
    }

    /// Ties the plan to what this host's compiler actually built. Running the package tests on
    /// another platform's simulator checks that platform too.
    @Test func compiledProbesMatchThePlanForThisPlatform() {
        #expect(LiveCapabilitySource.compiledProbes == Set(Capability.probed(on: .current)))
    }

    @Test func everyCapabilityHasADocumentedFallback() {
        for capability in Capability.allCases {
            let fallback = capability.fallback
            #expect(!fallback.summary.isEmpty)
            #expect(!fallback.experiments.isEmpty)
            #expect(fallback.experiments.allSatisfy { $0.wholeMatch(of: /LAB-\d{3}/) != nil })
        }
    }

    @Test func probedSymbolsAreNamedForEveryProbe() {
        for platform in LabPlatform.allCases {
            for capability in Capability.probed(on: platform) where capability != .localNetwork {
                #expect(!capability.probedSymbols(on: platform).isEmpty, "\(capability) on \(platform)")
            }
        }
    }

    @Test func noProbedSymbolIsARequest() {
        let promptingNames = ["request", "CBCentralManager(", "CBPeripheralManager(", "NISession()", ".run(", "NWConnection", "NWBrowser"]
        for platform in LabPlatform.allCases {
            for capability in Capability.allCases {
                for symbol in capability.probedSymbols(on: platform) {
                    #expect(!promptingNames.contains { symbol.contains($0) }, "\(symbol)")
                }
            }
        }
    }
}

@Suite struct NoPromptProbeTests {
    @Test func probingEveryPlatformNeverRequests() async {
        for platform in LabPlatform.allCases {
            let trap = PromptTrapSource()
            let registry = CapabilityRegistry(platform: platform, source: trap)
            let reports = await registry.probeAll()
            #expect(reports.map(\.capability) == Capability.probed(on: platform))
            #expect(trap.spy.requests.isEmpty, "Probing \(platform) asked for \(trap.spy.requests)")
        }
    }

    @Test func undeterminedPermissionsStayUndeterminedAfterProbing() async {
        let trap = PromptTrapSource()
        let reports = await CapabilityRegistry(platform: .iOS, source: trap).probeAll()
        let permissionStates = reports.compactMap { $0.gate(.permission)?.state }
        #expect(permissionStates.allSatisfy { $0 == .needsAction || $0 == .unknown })
        #expect(trap.spy.requests.isEmpty)
    }

    /// Runs the real frameworks on this host. It reads statuses only, so it cannot prompt;
    /// it checks structure, not this machine's particular answers.
    @Test(.timeLimit(.minutes(1)))
    func liveProbesOnThisHostCompleteWithoutClaimingVerification() async {
        let registry = CapabilityRegistry.live()
        let reports = await registry.probeAll()
        #expect(reports.map(\.capability) == Capability.probed(on: .current))
        for report in reports {
            #expect(!report.isDeviceVerified)
            #expect(report.gate(.osAPI)?.state == .met)
            if LiveCapabilitySource().isSimulator && report.capability.isPhysicalSensor {
                #expect(report.gate(.hardware)?.state != .met, "\(report.capability) claimed simulator hardware")
            }
            if report.gates.contains(where: { $0.kind != .verification && $0.state == .unknown }) {
                #expect(!report.readiness.isReady)
            }
        }
    }
}
