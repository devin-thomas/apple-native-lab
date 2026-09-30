import Foundation
import LabDomain
import Testing
@testable import SpeechTimeline

/// The fixtures are the files their README names, no audio is committed, and the module has no
/// route to a server: recognition is `SpeechAnalyzer` on this device, and only the installer asks
/// the system for a model.
@Suite struct FixtureAndRouteTests {
    static let sources = Repository.root.appending(path: "Packages/LabFeatures/Sources/SpeechTimeline")

    @Test func theFixturesAreTheFilesTheREADMENames() throws {
        let expected = [
            "speech-sample-script.txt": "c03523b47c45768c621061b257719e1b97e2a311a44dfc00f6ff69265e52cdf0",
            "speech-sample-captions.vtt": "1615650c15788f53d1d009d6f8a83ad354a4d3b5b0ba3874d8402ebe5e19ee4b",
            "speech-captions-overlapping.vtt": "f6233e796c341d04310a7400e28ac29df6cace8f0ff1902e13752c8f6fb860b6",
            "speech-captions-malformed.vtt": "8dfc449148580259a7fc217d9b6ecfc77b9fa22c0244c7a59db7f344cd5737f7",
        ]
        let readme = try String(contentsOf: Repository.speech("README.md"), encoding: .utf8)
        for (name, hash) in expected {
            #expect(ContentDigest.sha256(try Data(contentsOf: Repository.speech(name))).hex == hash, "\(name) changed")
            #expect(readme.contains(hash), "the README names \(name)'s hash")
        }
        let present = try FileManager.default.contentsOfDirectory(atPath: Repository.speech("").path())
        #expect(Set(present) == Set(expected.keys).union(["README.md"]), "no audio or other file is committed")
    }

    @Test func noSourceReachesAServerOrTheOlderRecognizer() throws {
        let forbidden = ["SFSpeechRecognizer", "SFSpeechURLRecognitionRequest", "SFSpeechAudioBufferRecognitionRequest",
                         "URLSession", "URLRequest", "import Network", "requiresOnDeviceRecognition"]
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.sources.path()).filter { $0.hasSuffix(".swift") }
        #expect(files.count >= 10)
        for file in files {
            let text = try String(contentsOf: Self.sources.appending(path: file), encoding: .utf8)
            for word in forbidden {
                #expect(!text.contains(word), "\(file) mentions \(word)")
            }
            if file != "OnDeviceSpeech.swift" {
                #expect(!text.contains("assetInstallationRequest"), "\(file) must not start a model download")
            }
        }
    }
}
