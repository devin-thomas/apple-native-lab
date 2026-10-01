import Foundation
import LabDomain

/// LAB-023's shared names: the experiment's ID in the catalog, its title, and its symbol.
public enum TabletopExperiment {
    public static let id = "LAB-023"
    public static let title = "Tabletop Reality"
    public static let symbol = "cube.transparent"
}

/// A color in the kit's fixed palette. The kit names colors; it never carries raw values, so a
/// fixture file cannot smuggle in anything but these.
public enum KitColor: String, Hashable, Sendable, Codable, CaseIterable {
    case oak, stone, roof, sail, chalk, glass, bark, leaf, brick, metal, water, lamp

    /// sRGB components in `0...1`.
    public var components: (red: Double, green: Double, blue: Double) {
        let bytes: (Double, Double, Double) = switch self {
        case .oak: (176, 132, 86)
        case .stone: (150, 148, 140)
        case .roof: (170, 60, 50)
        case .sail: (236, 230, 214)
        case .chalk: (240, 240, 236)
        case .glass: (160, 210, 230)
        case .bark: (110, 78, 52)
        case .leaf: (58, 120, 70)
        case .brick: (190, 110, 80)
        case .metal: (120, 126, 134)
        case .water: (70, 130, 190)
        case .lamp: (255, 210, 110)
        }
        return (bytes.0 / 255, bytes.1 / 255, bytes.2 / 255)
    }

    /// Whether the part glows rather than reflects, like the lantern's core.
    public var isEmissive: Bool { self == .lamp }
}

/// One procedural primitive of a fixture. Sizes and offsets are whole millimeters.
public struct KitPart: Hashable, Sendable {
    public enum Shape: String, Hashable, Sendable, Codable, CaseIterable {
        /// `size` is width, height, depth.
        case box
        /// `size` is diameter, height, diameter; the two diameters must match.
        case cylinder
        /// `size` is the base diameter, height, base diameter; the two diameters must match.
        case cone
        /// `size` is the diameter three times.
        case sphere
    }

    public let shape: Shape
    public let size: KitVector
    /// The center of the part, from the fixture's base center on the surface.
    public let offset: KitVector
    public let color: KitColor
}

/// Three whole-millimeter components: x right, y up, z toward the viewer.
public struct KitVector: Hashable, Sendable {
    public let x: Int
    public let y: Int
    public let z: Int

    public init(_ x: Int, _ y: Int, _ z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// One original object the kit can place: its catalog key, what people read, its footprint on
/// the surface, and the primitives that draw it.
public struct KitFixture: Hashable, Sendable, Identifiable {
    public let key: FixtureKey
    public let title: EntityTitle
    /// What the object looks like, for the accessibility list and VoiceOver.
    public let summary: String
    /// The radius of the circle the object occupies on the surface, in millimeters. Placement
    /// keeps footprints inside the table and apart from each other.
    public let radius: Int
    public let parts: [KitPart]

    public var id: FixtureKey { key }

    /// The height of the tallest part's top, in millimeters.
    public var height: Int {
        parts.map { $0.offset.y + $0.size.y / 2 }.max() ?? 0
    }
}

/// The surface the scene is built on. Its frame's origin is the center of its top.
public struct KitTable: Hashable, Sendable {
    public let title: EntityTitle
    public let width: Int
    public let depth: Int
    public let thickness: Int
    public let color: KitColor
}

/// One placement in the kit's starter scene.
public struct KitPlacement: Hashable, Sendable {
    public let fixture: FixtureKey
    public let x: Int
    public let z: Int
    public let yaw: Int
}

/// The bundled, original tabletop kit: a table, the fixtures a person can place on it, and a
/// starter scene. Every object is a handful of procedural primitives in a fixed palette; there are
/// no meshes, textures, or captured assets.
///
/// The kit is a fixture file. It is decoded strictly: an unknown key, a wrong format name or
/// version, a duplicate fixture key, a color outside the palette, or a size outside the limits
/// refuses the whole file.
public struct TabletopKit: Hashable, Sendable {
    public static let format = "native-lab-tabletop-kit"
    public static let version = 1
    public static let maximumFixtures = 12
    public static let maximumParts = 8
    /// Every part dimension, in millimeters.
    public static let partSizes = 4...400
    /// Every part offset component, in millimeters.
    public static let partReach = 400
    public static let radii = 20...200
    public static let tableSizes = 200...3_000
    public static let summaryLength = 1...200

    public let title: String
    public let table: KitTable
    public let fixtures: [KitFixture]
    public let starter: [KitPlacement]

    public func fixture(_ key: FixtureKey) -> KitFixture? {
        fixtures.first { $0.key == key }
    }

    /// Where the bundled kit file is.
    static var bundledURL: URL? { Bundle.module.url(forResource: "tabletop-kit", withExtension: "json") }

    /// The kit bundled with this module.
    public static func bundled() throws(KitError) -> TabletopKit {
        guard let url = bundledURL, let data = try? Data(contentsOf: url) else { throw .missing }
        return try decode(data)
    }

    /// Decodes and validates a kit file.
    public static func decode(_ data: Data) throws(KitError) -> TabletopKit {
        let file: KitFile
        do {
            file = try JSONDecoder().decode(KitFile.self, from: data)
        } catch let error as KitError {
            throw error
        } catch let DecodingError.keyNotFound(key, _) {
            throw .malformed("missing \(key.stringValue)")
        } catch {
            throw .malformed("not a kit document")
        }
        return try file.validated()
    }
}

/// Why a kit file was refused. Nothing from a refused file is used.
public enum KitError: Error, Hashable, Sendable {
    case missing
    case malformed(String)
    case unsupportedFormat
    case unknownKey(String)
    case invalidValue(String)

    public var message: String {
        switch self {
        case .missing: "This build is missing its tabletop kit."
        case .malformed(let detail): "The tabletop kit is not valid: \(detail)."
        case .unsupportedFormat: "The tabletop kit uses a format this build does not read."
        case .unknownKey(let key): "The tabletop kit has a field this build does not know: \(key)."
        case .invalidValue(let detail): "The tabletop kit has an invalid value: \(detail)."
        }
    }
}

// MARK: - The file

private struct KitFile: Decodable {
    let format: String
    let version: Int
    let title: String
    let table: TableFile
    let fixtures: [FixtureFile]
    let starter: [PlacementFile]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case format, version, title, table, fixtures, starter
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(decoder, CodingKeys.allCases.map(\.rawValue), in: "kit")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        version = try container.decode(Int.self, forKey: .version)
        title = try container.decode(String.self, forKey: .title)
        table = try container.decode(TableFile.self, forKey: .table)
        fixtures = try container.decode([FixtureFile].self, forKey: .fixtures)
        starter = try container.decode([PlacementFile].self, forKey: .starter)
    }

    func validated() throws(KitError) -> TabletopKit {
        guard format == TabletopKit.format, version == TabletopKit.version else { throw .unsupportedFormat }
        guard (1...80).contains(title.count) else { throw .invalidValue("title") }
        guard (1...TabletopKit.maximumFixtures).contains(fixtures.count) else { throw .invalidValue("fixtures count") }
        let table = try self.table.validated()
        var validFixtures: [KitFixture] = []
        for fixture in fixtures {
            let valid = try fixture.validated()
            guard !validFixtures.contains(where: { $0.key == valid.key }) else { throw .invalidValue("duplicate fixture \(valid.key)") }
            validFixtures.append(valid)
        }
        var placements: [KitPlacement] = []
        for placement in starter {
            let valid = try placement.validated()
            guard validFixtures.contains(where: { $0.key == valid.fixture }) else { throw .invalidValue("starter names \(valid.fixture)") }
            placements.append(valid)
        }
        guard placements.count <= TabletopKit.maximumFixtures else { throw .invalidValue("starter count") }
        return TabletopKit(title: title, table: table, fixtures: validFixtures, starter: placements)
    }
}

private struct TableFile: Decodable {
    let title: String
    let width: Int
    let depth: Int
    let thickness: Int
    let color: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case title, width, depth, thickness, color
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(decoder, CodingKeys.allCases.map(\.rawValue), in: "table")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        width = try container.decode(Int.self, forKey: .width)
        depth = try container.decode(Int.self, forKey: .depth)
        thickness = try container.decode(Int.self, forKey: .thickness)
        color = try container.decode(String.self, forKey: .color)
    }

    func validated() throws(KitError) -> KitTable {
        guard let title = try? EntityTitle(title) else { throw .invalidValue("table title") }
        guard TabletopKit.tableSizes.contains(width), TabletopKit.tableSizes.contains(depth) else { throw .invalidValue("table size") }
        guard (5...200).contains(thickness) else { throw .invalidValue("table thickness") }
        guard let color = KitColor(rawValue: color) else { throw .invalidValue("table color") }
        return KitTable(title: title, width: width, depth: depth, thickness: thickness, color: color)
    }
}

private struct FixtureFile: Decodable {
    let key: String
    let title: String
    let summary: String
    let radius: Int
    let parts: [PartFile]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case key, title, summary, radius, parts
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(decoder, CodingKeys.allCases.map(\.rawValue), in: "fixture")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        radius = try container.decode(Int.self, forKey: .radius)
        parts = try container.decode([PartFile].self, forKey: .parts)
    }

    func validated() throws(KitError) -> KitFixture {
        guard let key = try? FixtureKey(key) else { throw .invalidValue("fixture key") }
        guard let title = try? EntityTitle(title) else { throw .invalidValue("title of \(key)") }
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TabletopKit.summaryLength.contains(trimmed.count),
              !trimmed.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { throw .invalidValue("summary of \(key)") }
        guard TabletopKit.radii.contains(radius) else { throw .invalidValue("radius of \(key)") }
        guard (1...TabletopKit.maximumParts).contains(parts.count) else { throw .invalidValue("parts of \(key)") }
        var valid: [KitPart] = []
        for part in parts { valid.append(try part.validated(in: key)) }
        return KitFixture(key: key, title: title, summary: trimmed, radius: radius, parts: valid)
    }
}

private struct PartFile: Decodable {
    let shape: String
    let size: [Int]
    let offset: [Int]
    let color: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case shape, size, offset, color
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(decoder, CodingKeys.allCases.map(\.rawValue), in: "part")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shape = try container.decode(String.self, forKey: .shape)
        size = try container.decode([Int].self, forKey: .size)
        offset = try container.decode([Int].self, forKey: .offset)
        color = try container.decode(String.self, forKey: .color)
    }

    func validated(in fixture: FixtureKey) throws(KitError) -> KitPart {
        guard let shape = KitPart.Shape(rawValue: shape) else { throw .invalidValue("shape in \(fixture)") }
        guard let color = KitColor(rawValue: color) else { throw .invalidValue("color in \(fixture)") }
        guard size.count == 3, size.allSatisfy(TabletopKit.partSizes.contains) else { throw .invalidValue("part size in \(fixture)") }
        guard offset.count == 3, offset.allSatisfy({ abs($0) <= TabletopKit.partReach }) else {
            throw .invalidValue("part offset in \(fixture)")
        }
        let round = switch shape {
        case .box: true
        case .cylinder, .cone: size[0] == size[2]
        case .sphere: size[0] == size[1] && size[1] == size[2]
        }
        guard round else { throw .invalidValue("\(shape.rawValue) proportions in \(fixture)") }
        return KitPart(
            shape: shape, size: KitVector(size[0], size[1], size[2]), offset: KitVector(offset[0], offset[1], offset[2]), color: color
        )
    }
}

private struct PlacementFile: Decodable {
    let fixture: String
    let x: Int
    let z: Int
    let yaw: Int

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case fixture, x, z, yaw
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(decoder, CodingKeys.allCases.map(\.rawValue), in: "starter")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fixture = try container.decode(String.self, forKey: .fixture)
        x = try container.decode(Int.self, forKey: .x)
        z = try container.decode(Int.self, forKey: .z)
        yaw = try container.decode(Int.self, forKey: .yaw)
    }

    func validated() throws(KitError) -> KitPlacement {
        guard let key = try? FixtureKey(fixture) else { throw .invalidValue("starter fixture") }
        guard (0..<360).contains(yaw), abs(x) <= AnchorPose.reach, abs(z) <= AnchorPose.reach else {
            throw .invalidValue("starter pose of \(key)")
        }
        return KitPlacement(fixture: key, x: x, z: z, yaw: yaw)
    }
}

private struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Refuses an object with a key outside `allowed`, naming the first one found.
private func rejectUnknownKeys(_ decoder: any Decoder, _ allowed: [String], in object: String) throws {
    let keys = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
    if let unknown = keys.sorted().first(where: { !allowed.contains($0) }) {
        throw KitError.unknownKey("\(object).\(unknown)")
    }
}
