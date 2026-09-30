/// Why a spatial payload value was rejected (LAB-023 Tabletop Reality).
///
/// Kept apart from `ValidationError`, whose cases other adapters list exhaustively: a pose or a
/// fixture key is only ever built by a spatial adapter, which reports these itself.
public enum SpatialValidationError: Error, Hashable, Sendable {
    /// A coordinate lies farther than `AnchorPose.reach` millimeters from the frame's origin.
    case outOfReach(limit: Int)
    /// A fixture key is empty, too long, or has a character outside `a-z`, `0-9`, and `-`.
    case invalidFixtureKey
}

/// Where a lab-owned anchor sits in its scene's frame, and which way it faces.
///
/// Whole millimeters and whole degrees, so a pose compares, encodes, and round-trips exactly, and
/// a receipt never records floating-point noise. The frame is the scene's own, not a device's
/// world: x points right, y up, and z toward the viewer, with the origin at the center of the
/// surface the scene is built on. A live AR adapter anchors that origin to a real surface; a
/// virtual scene draws it. `yaw` turns counterclockwise about y, seen from above, in `0..<360`.
public struct AnchorPose: Hashable, Sendable, Codable, CustomStringConvertible {
    /// How far from the origin any coordinate may be, in millimeters. A tabletop uses a small
    /// fraction of it; the bound only keeps a stored pose physical.
    public static let reach = 5_000

    public static let origin = AnchorPose(unchecked: 0, 0, 0, 0)

    public let x: Int
    public let y: Int
    public let z: Int
    public let yaw: Int

    /// - Parameter yaw: Any whole number of degrees. It is stored in `0..<360`.
    public init(x: Int, y: Int = 0, z: Int, yaw: Int = 0) throws(SpatialValidationError) {
        guard [x, y, z].allSatisfy({ abs($0) <= Self.reach }) else { throw .outOfReach(limit: Self.reach) }
        self.init(unchecked: x, y, z, ((yaw % 360) + 360) % 360)
    }

    private init(unchecked x: Int, _ y: Int, _ z: Int, _ yaw: Int) {
        self.x = x
        self.y = y
        self.z = z
        self.yaw = yaw
    }

    /// Whether only the heading differs from `other`.
    public func differsOnlyInYaw(from other: AnchorPose) -> Bool {
        x == other.x && y == other.y && z == other.z && yaw != other.yaw
    }

    private enum CodingKeys: String, CodingKey {
        case x, y, z, yaw
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let yaw = try container.decode(Int.self, forKey: .yaw)
        guard (0..<360).contains(yaw) else {
            throw DecodingError.dataCorruptedError(forKey: .yaw, in: container, debugDescription: "A stored yaw is in 0..<360.")
        }
        let x = try container.decode(Int.self, forKey: .x)
        let y = try container.decode(Int.self, forKey: .y)
        let z = try container.decode(Int.self, forKey: .z)
        guard let pose = try? AnchorPose(x: x, y: y, z: z, yaw: yaw) else {
            throw DecodingError.dataCorruptedError(forKey: .x, in: container, debugDescription: "A stored pose is within reach.")
        }
        self = pose
    }

    public var description: String { "(\(x), \(y), \(z)) mm, \(yaw)°" }
}

/// Names one original fixture a lab-owned anchor shows, such as `windmill`.
///
/// The domain stores the key and never interprets it: the experiment that placed the anchor owns
/// the catalog the key refers to. Lowercase letters, digits, and hyphens, 1 to 40 of them.
public struct FixtureKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public static let maximumLength = 40

    public let value: String

    public init(_ raw: String) throws(SpatialValidationError) {
        let allowed = raw.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
        guard !raw.isEmpty, raw.count <= Self.maximumLength, allowed else { throw .invalidFixtureKey }
        value = raw
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let key = try? FixtureKey(container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a fixture key.")
        }
        self = key
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public var description: String { value }
}

/// The content of a new lab-owned anchor. The caller chooses the ID, so a retry names the same
/// anchor, and an undone removal places the same anchor again.
public struct AnchorDraft: Hashable, Sendable, Codable {
    public let id: AnchorID
    public let fixture: FixtureKey
    /// What people read and what assistive technologies speak for the anchor.
    public let title: EntityTitle
    public let pose: AnchorPose

    public init(id: AnchorID = AnchorID(), fixture: FixtureKey, title: EntityTitle, pose: AnchorPose) {
        self.id = id
        self.fixture = fixture
        self.title = title
        self.pose = pose
    }
}

/// One object an experiment placed in a spatial scene (LAB-023 Tabletop Reality).
///
/// An anchor is lab-owned state, never a person's content, so it always belongs to the demo
/// namespace: Reset Demo removes every anchor, and removing one never reaches user data. It holds
/// only the fixture it shows, its title, and its pose in the scene's frame. It holds no camera
/// image, no mapping data, and no world coordinates: those belong to a live adapter and stay on
/// the device that measured them.
public struct LabAnchor: DomainEntity, Identifiable {
    public static let kind = EntityKind.anchor

    public let id: AnchorID
    public let fixture: FixtureKey
    public let title: EntityTitle
    public let pose: AnchorPose
    public let revision: Revision

    public init(id: AnchorID, fixture: FixtureKey, title: EntityTitle, pose: AnchorPose, revision: Revision = .initial) {
        self.id = id
        self.fixture = fixture
        self.title = title
        self.pose = pose
        self.revision = revision
    }

    /// Always `demo`: an anchor is lab state that Reset Demo removes.
    public var namespace: DataNamespace { .demo }

    public var reference: EntityReference { .anchor(id) }

    /// The draft that places this anchor again as it is now: the undo of its removal.
    public var draft: AnchorDraft { AnchorDraft(id: id, fixture: fixture, title: title, pose: pose) }

    /// The next revision at a new pose.
    func revised(pose: AnchorPose) -> LabAnchor {
        LabAnchor(id: id, fixture: fixture, title: title, pose: pose, revision: revision.next())
    }
}
