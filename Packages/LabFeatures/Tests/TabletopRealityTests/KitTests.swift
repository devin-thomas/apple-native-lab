import Foundation
import LabDomain
import Testing
@testable import TabletopReality

/// The bundled kit is original, small, and valid; a kit file with anything unexpected is refused
/// whole.
@Suite struct KitTests {
    @Test func theBundledKitIsSmallOriginalPrimitivesThatFitTheTable() throws {
        let kit = try TabletopKit.bundled()
        #expect(kit.fixtures.map(\.key.value) == ["windmill", "lighthouse", "cottage", "pine", "water-tower", "lantern"])
        #expect(kit.table.width == 900 && kit.table.depth == 600)
        #expect(kit.starter.count == 4)
        for fixture in kit.fixtures {
            #expect(fixture.parts.count <= TabletopKit.maximumParts)
            #expect(fixture.radius * 2 < min(kit.table.width, kit.table.depth))
            #expect(fixture.height > 0 && fixture.height <= 400)
            #expect(!fixture.summary.isEmpty)
        }
        // Every starter object fits the empty table together.
        let planner = TabletopPlanner(kit: kit, anchors: [], tracking: .virtualScene)
        #expect(try planner.setOutStarter().count == kit.starter.count)
    }

    @Test func theBundledFileIsTheSmallFileItClaimsToBe() throws {
        let url = try #require(TabletopKit.bundledURL)
        let size = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        #expect(size < 8_192)
    }

    @Test(arguments: [
        (#""format": "native-lab-tabletop-kit""#, #""format": "other-kit""#, KitError.unsupportedFormat),
        (#""version": 1"#, #""version": 2"#, KitError.unsupportedFormat),
        (#""title": "Harbor village","#, #""title": "Harbor village", "camera": true,"#, KitError.unknownKey("kit.camera")),
        (#""color": "oak""#, #""color": "magenta""#, KitError.invalidValue("table color")),
        (#""radius": 65"#, #""radius": 5"#, KitError.invalidValue("radius of windmill")),
        (#""size": [100, 140, 100]"#, #""size": [100, 900, 100]"#, KitError.invalidValue("part size in windmill")),
        (#""size": [120, 70, 120]"#, #""size": [120, 70, 60]"#, KitError.invalidValue("cone proportions in windmill")),
        (#""shape": "box", "size": [14"#, #""shape": "mesh", "size": [14"#, KitError.invalidValue("shape in windmill")),
        (#""key": "lighthouse""#, #""key": "windmill""#, KitError.invalidValue("duplicate fixture windmill")),
        (#""fixture": "pine""#, #""fixture": "rocket""#, KitError.invalidValue("starter names rocket")),
        (#""key": "pine""#, #""key": "Pine Tree""#, KitError.invalidValue("fixture key")),
        (#""offset": [0, 70, 0]"#, #""offset": [0, 70, 0], "url": "https://example.invalid""#, KitError.unknownKey("part.url")),
    ])
    func aKitWithAnythingUnexpectedIsRefusedWhole(original: String, replacement: String, expected: KitError) throws {
        let text = try Self.bundledText()
        #expect(text.contains(original))
        let edited = text.replacingOccurrences(of: original, with: replacement, options: [], range: text.range(of: original))
        #expect(throws: expected) { try TabletopKit.decode(Data(edited.utf8)) }
    }

    @Test func aSummaryWithAControlCharacterOrTooManyFixturesIsRefused() throws {
        let text = try Self.bundledText()
        let control = text.replacingOccurrences(of: "four cloth sails", with: "four\\u0007 cloth sails")
        #expect(throws: KitError.invalidValue("summary of windmill")) { try TabletopKit.decode(Data(control.utf8)) }
        #expect(throws: KitError.self) { try TabletopKit.decode(Data("[]".utf8)) }
        #expect(throws: KitError.malformed("missing starter")) {
            try TabletopKit.decode(Data(#"{"format":"native-lab-tabletop-kit","version":1,"title":"t","table":{"title":"T","width":900,"depth":600,"thickness":30,"color":"oak"},"fixtures":[]}"#.utf8))
        }
    }

    static func bundledText() throws -> String {
        let url = try #require(TabletopKit.bundledURL)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
