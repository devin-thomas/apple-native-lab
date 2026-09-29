import Foundation
import Testing
@testable import LabSupport

@Suite struct ImplementationStateTests {
    @Test func vocabularyMatchesTheSpecification() {
        #expect(ImplementationState.allCases.map(\.rawValue) == [
            "specified", "spiked", "implemented", "device-verified", "release-ready", "blocked",
        ])
    }

    @Test func onlyRunningStatesAreLive() {
        #expect(ImplementationState.allCases.filter(\.isLive) == [.implemented, .deviceVerified, .releaseReady])
    }

    @Test func unknownStateIsRejected() throws {
        let data = Data(#""verified-on-simulator""#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ImplementationState.self, from: data) }
    }
}

@Suite struct BuildProvenanceTests {
    @Test func readsXcodeRecordedToolchain() {
        let provenance = BuildProvenance(infoDictionary: [
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1",
            "LabSourceRevision": "abc1234",
            "LabBuildProfile": "CoreLocal",
            "DTSDKName": "macosx27.0",
            "DTXcode": "2700",
            "DTXcodeBuild": "27A266a",
            "LSMinimumSystemVersion": "26.0",
        ])
        #expect(provenance.sourceRevision == "abc1234")
        #expect(provenance.xcodeVersion == "27.0")
        #expect(provenance.minimumOS == "26.0")
    }

    @Test func missingValuesAreUnknownNotInvented() {
        let provenance = BuildProvenance(infoDictionary: ["LabSourceRevision": ""])
        #expect(provenance.sourceRevision == "unknown")
        #expect(provenance.sdkName == "unknown")
    }

    @Test func formatsPatchVersions() {
        #expect(BuildProvenance.readableXcodeVersion("2631") == "26.3.1")
        #expect(BuildProvenance.readableXcodeVersion("beta") == "beta")
    }
}
