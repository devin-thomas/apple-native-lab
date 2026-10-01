import Foundation
import ScreeningRoom

/// The fixture clips as files in this build, and the record of what they should be.
public enum BundledClips {
    /// The bundled file for a clip, or `nil` when this build does not carry it.
    public static func url(for clip: MediaAsset) -> URL? {
        Bundle.module.url(forResource: clip.resourceName, withExtension: clip.fileExtension, subdirectory: "Clips")
    }

    /// One entry of `Clips/clips.json`, which the fixture generator wrote beside the clips.
    public struct Record: Hashable, Sendable, Decodable {
        public let file: String
        public let bytes: Int
        public let sha256: String
    }

    /// The generator's record of every clip's size and SHA-256.
    public static func records() throws -> [Record] {
        struct Manifest: Decodable {
            let generator: String
            let clips: [Record]
        }
        guard let url = Bundle.module.url(forResource: "clips", withExtension: "json", subdirectory: "Clips") else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url)).clips
    }
}
