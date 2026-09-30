import Foundation
import LabCatalog
import LabSupport
import Testing

/// Runs inside the built Watch app, so it checks what actually shipped in the bundle.
@Suite struct LabWatchSmokeTests {
    @Test func packagedCatalogLoadsInsideTheApp() throws {
        #expect(try ExperimentCatalog.bundled().experiments.count == 48)
        #expect(try ExperimentRegistry.bundled().experiments.count == 48)
    }

    @Test func bundleRecordsRealToolchainProvenance() {
        let provenance = BuildProvenance.current
        #expect(provenance.sdkName.hasPrefix("watch"))
        #expect(provenance.xcodeBuild != "unknown")
        #expect(provenance.buildProfile == "Companions")
        #expect(provenance.minimumOS == "26.0")
        #expect(Bundle.main.object(forInfoDictionaryKey: "LabSourceRevision") is String)
    }

    @Test func deviceSnapshotDescribesThisWatch() {
        let device = DeviceSnapshot.current
        #expect(device.platform == "watchOS")
        #expect(device.modelIdentifier != "unknown")
        #expect(LabPlatform.current == .watchOS)
    }

    /// A Source build declares no purpose string, and watchOS ends an app that asks for a
    /// protected resource without one, so probes that finish here asked for nothing.
    @Test func readinessSnapshotRunsWithoutPrompts() async {
        if Bundle.main.object(forInfoDictionaryKey: "LabDistributionLane") as? String == "Source" {
            let source = LiveCapabilitySource()
            #expect(!source.declaresPurposeString("NSMicrophoneUsageDescription"))
            #expect(!source.declaresPurposeString("NSBluetoothAlwaysUsageDescription"))
            #expect(!source.declaresPurposeString("NSNearbyInteractionUsageDescription"))
        }
        let registry = CapabilityRegistry.live()
        #expect(registry.platform == .watchOS)
        let reports = await registry.probeAll()

        #expect(reports.map(\.capability) == [.microphone, .ultraWideband, .bluetooth])
        #expect(LiveCapabilitySource.compiledProbes == Set(registry.probed))
        #expect(reports.allSatisfy { $0.isProbed && !$0.isDeviceVerified })
        #expect(registry.excludedReports().map(\.capability) == Capability.excluded(on: .watchOS))
        #expect(LiveCapabilitySource().permissionStatus(.microphone) != .notReadable)
        #expect(LiveCapabilitySource().permissionStatus(.bluetooth) != .notReadable)
    }
}
