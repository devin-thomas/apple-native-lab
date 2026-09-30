import CryptoKit
import Foundation
import ScreeningRoom
@testable import ScreeningRoomPlayback
import Testing

/// LAB-031: the bundled clips are the generator's, byte for byte.
@Suite struct BundledClipTests {
    @Test func everyClipIsBundledAndMatchesTheGeneratorsRecord() throws {
        let records = try BundledClips.records()
        #expect(records.map(\.file) == ScreeningClips.all.map(\.fileName))
        for clip in ScreeningClips.all {
            let url = try #require(BundledClips.url(for: clip), "\(clip.fileName) is not bundled")
            let data = try Data(contentsOf: url)
            let record = try #require(records.first { $0.file == clip.fileName })
            #expect(data.count == record.bytes)
            #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == record.sha256)
        }
        #expect(records.map(\.bytes).reduce(0, +) < 100_000, "the fixtures stay small")
    }
}
