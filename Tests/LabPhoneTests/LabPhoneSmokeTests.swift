import Foundation
import LabCatalog
import LabSupport
import Testing

/// Runs inside the built iPhone app, so it checks what actually shipped in the bundle.
@Suite struct LabPhoneSmokeTests {
    @Test func packagedCatalogLoadsInsideTheApp() throws {
        #expect(try ExperimentCatalog.bundled().experiments.count == 48)
        #expect(try ExperimentRegistry.bundled().experiments.count == 48)
    }

    @Test func bundleRecordsRealToolchainProvenance() {
        let provenance = BuildProvenance.current
        #expect(provenance.sdkName.hasPrefix("iphone"))
        #expect(provenance.xcodeBuild != "unknown")
        #expect(provenance.buildProfile == "CoreLocal")
        #expect(provenance.minimumOS == "26.0")
        #expect(Bundle.main.object(forInfoDictionaryKey: "LabSourceRevision") is String)
    }

    @Test func deviceSnapshotDescribesThisDevice() {
        let device = DeviceSnapshot.current
        #expect(device.platform == "iOS")
        #expect(device.modelIdentifier != "unknown")
        #expect(LabPlatform.current == .iOS)
    }

    /// A Source build declares no purpose string, and iOS ends an app that asks for a protected
    /// resource without one, so probes that finish here asked for nothing.
    @Test func readinessSnapshotRunsWithoutPrompts() async {
        if Bundle.main.object(forInfoDictionaryKey: "LabDistributionLane") as? String == "Source" {
            let source = LiveCapabilitySource()
            for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription",
                        "NSSpeechRecognitionUsageDescription", "NSBluetoothAlwaysUsageDescription",
                        "NSNearbyInteractionUsageDescription"] {
                #expect(!source.declaresPurposeString(key), "\(key)")
            }
        }
        let registry = CapabilityRegistry.live()
        #expect(registry.platform == .iOS)
        let reports = await registry.probeAll()

        #expect(reports.map(\.capability) == Capability.probed(on: .iOS))
        #expect(LiveCapabilitySource.compiledProbes == Set(registry.probed))
        #expect(reports.allSatisfy { $0.isProbed && !$0.isDeviceVerified })
        #expect(registry.excludedReports().map(\.capability) == Capability.excluded(on: .iOS))
    }
}
