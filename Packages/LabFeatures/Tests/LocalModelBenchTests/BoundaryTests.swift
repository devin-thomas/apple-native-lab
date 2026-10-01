import Foundation
import Testing
@testable import LocalModelBench

/// This module must not pull a model framework into the default build.
@Suite struct BoundaryTests {
    @Test func sourcesDoNotImportAModelRuntimeOrTheNetwork() throws {
        let folder = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/LocalModelBench", directoryHint: .isDirectory)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 5)
        let forbidden = [
            "import CoreML", "import FoundationModels", "import MLX", "MLModel.load",
            "URLSession", "URLRequest", "import Network",
        ]
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for symbol in forbidden {
                #expect(!source.contains(symbol), "\(file.lastPathComponent) mentions \(symbol)")
            }
        }
    }
}
