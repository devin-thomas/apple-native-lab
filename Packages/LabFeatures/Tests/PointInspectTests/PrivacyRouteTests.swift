import CryptoKit
import Foundation
import Testing
@testable import PointInspect

@Suite struct PrivacyRouteTests {
    @Test func sourcesHaveNoNetworkOrCloudRoute() throws {
        let forbidden = [
            "PrivateCloudCompute", "URLSession", "URLRequest", "NWConnection", "import Network",
            "CloudKit", "pixelBuffer", "NSWorkspace", "openURL", "UIApplication",
        ]
        let folder = Repository.root.appending(path: "Packages/LabFeatures/Sources/PointInspect")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 8)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for symbol in forbidden {
                #expect(!source.contains(symbol), "\(file.lastPathComponent) mentions \(symbol)")
            }
        }
        let model = try String(contentsOf: folder.appending(path: "OnDeviceImageInterpreter.swift"), encoding: .utf8)
        #expect(model.contains("SystemLanguageModel.default"))
    }

    @Test func theFixtureIsTheFileTheEvidenceNames() throws {
        let data = try Data(contentsOf: Repository.root.appending(path: "Fixtures/point-inspect/swatch-card.png"))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "5878b4eb086241d408b0ab74bcb3d48c42b035fa93d1766b5d3a43ee9f4a7105")
        #expect(data.count == 115)
        let image = try SelectedImage(data: data, origin: .fixtureReplay)
        #expect(image.evidence.media == .png)
        #expect(image.evidence.digest == digest)
    }
}
