import Foundation
import LabCatalog
import LabSupport
import Testing
@testable import NativeLabTV

/// Runs inside the built Apple TV app, so it checks what actually shipped in the bundle.
@Suite struct LabTVSmokeTests {
    @Test func packagedCatalogLoadsInsideTheApp() throws {
        let host = TVHost.load()
        #expect(host.catalogProblem == nil)
        #expect(host.registry?.experiments.count == 48)
        #expect(try ExperimentCatalog.bundled().experiments.count == 48)
    }

    @Test func bundleRecordsRealToolchainProvenance() {
        let provenance = BuildProvenance.current
        #expect(provenance.sdkName.hasPrefix("appletv"))
        #expect(provenance.xcodeBuild != "unknown")
        #expect(provenance.buildProfile == "Companions")
        #expect(provenance.minimumOS == "26.0")
        #expect(Bundle.main.object(forInfoDictionaryKey: "LabSourceRevision") is String)
    }

    @Test func deviceSnapshotDescribesThisAppleTV() {
        let device = DeviceSnapshot.current
        #expect(device.platform == "tvOS")
        #expect(device.modelIdentifier != "unknown")
        #expect(LabPlatform.current == .tvOS)
    }

    /// The Readiness screen's own board, measured inside the host. A Source build declares no
    /// purpose string, and tvOS ends an app that asks for a protected resource without one, so
    /// probes that finish here asked for nothing.
    @Test @MainActor func readinessSnapshotRunsWithoutPrompts() async {
        if Bundle.main.object(forInfoDictionaryKey: "LabDistributionLane") as? String == "Source" {
            #expect(!LiveCapabilitySource().declaresPurposeString("NSBluetoothAlwaysUsageDescription"))
        }
        let board = ReadinessBoard()
        #expect(board.freshness == .notMeasured)
        await board.refresh()

        #expect(board.probed == [.bluetooth, .localNetwork])
        #expect(LiveCapabilitySource.compiledProbes == Set(board.probed))
        #expect(Set(board.reports.keys) == Set(board.probed))
        #expect(board.reports.values.allSatisfy { $0.isProbed && !$0.isDeviceVerified })
        #expect(board.excluded.map(\.capability) == Capability.excluded(on: .tvOS))
        #expect(board.excluded.allSatisfy { $0.readiness == .unavailable })
        #expect(LiveCapabilitySource().permissionStatus(.bluetooth) != .notReadable)

        guard case .measured(let measuredAt) = board.freshness else {
            Issue.record("Expected a measured reading, found \(board.freshness)")
            return
        }
        board.markStale()
        #expect(board.freshness == .stale(measuredAt))
    }
}
