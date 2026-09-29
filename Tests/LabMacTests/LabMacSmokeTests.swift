import LabCatalog
import LabSupport
import Testing

/// Runs inside the built Mac app, so it checks what actually shipped in the bundle.
@Suite struct LabMacSmokeTests {
    @Test func packagedCatalogLoadsInsideTheApp() throws {
        let catalog = try ExperimentCatalog.bundled()
        #expect(catalog.experiments.count == 48)
    }

    @Test func bundleRecordsRealToolchainProvenance() {
        let provenance = BuildProvenance.current
        #expect(provenance.sdkName.hasPrefix("macosx"))
        #expect(provenance.xcodeBuild != "unknown")
        #expect(provenance.buildProfile == "CoreLocal")
        #expect(provenance.minimumOS == "26.0")
    }

    @Test func deviceSnapshotRunsWithoutPrompts() {
        let device = DeviceSnapshot.current
        #expect(device.platform == "macOS")
        #expect(device.modelIdentifier != "unknown")
    }
}
