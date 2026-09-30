import LabDomain

/// One meaningful thing in the scene, as the accessibility list and VoiceOver present it.
public struct SceneEntry: Hashable, Sendable, Identifiable {
    public enum Subject: Hashable, Sendable {
        case table
        case anchor(AnchorID)
    }

    public let subject: Subject
    /// The object's name.
    public let label: String
    /// Where it is and which way it faces, or for the table, its size and what it holds.
    public let value: String
    /// What the object looks like.
    public let detail: String

    public var id: Subject { subject }
}

/// Describes the scene in words: the table and every object on it, with its place and heading.
///
/// The list is the scene's accessible form and its non-visual route. It names every lab-owned
/// anchor the store holds, including one whose fixture this build's kit does not know, so
/// nothing on the table is ever missing from it.
public enum SceneDescription {
    public static func entries(kit: TabletopKit, anchors: [LabAnchor]) -> [SceneEntry] {
        let table = kit.table
        let count = anchors.count == 1 ? "1 object" : "\(anchors.count) objects"
        let tableEntry = SceneEntry(
            subject: .table,
            label: table.title.value,
            value: "\(centimeters(table.width)) by \(centimeters(table.depth)), \(count)",
            detail: "The surface everything stands on. Its center is the scene's origin; its front edge faces you."
        )
        return [tableEntry] + anchors.map { anchor in
            SceneEntry(
                subject: .anchor(anchor.id),
                label: anchor.title.value,
                value: position(of: anchor.pose),
                detail: kit.fixture(anchor.fixture)?.summary ?? "An object this build's kit does not draw."
            )
        }
    }

    /// Where a pose is on the table, and which way it faces, in words.
    public static func position(of pose: AnchorPose) -> String {
        [across(pose.x), depth(pose.z), heading(pose.yaw)].joined(separator: ", ")
    }

    static func across(_ x: Int) -> String {
        guard abs(x) >= 5 else { return "centered left to right" }
        return "\(centimeters(abs(x))) \(x < 0 ? "left" : "right") of center"
    }

    static func depth(_ z: Int) -> String {
        guard abs(z) >= 5 else { return "centered front to back" }
        return "\(centimeters(abs(z))) \(z > 0 ? "toward you" : "away from you")"
    }

    /// The heading to the nearest eighth of a turn. At yaw 0 an object's front faces the viewer;
    /// yaw turns it counterclockwise seen from above, so 90 faces right.
    static func heading(_ yaw: Int) -> String {
        let names = ["facing you", "facing front right", "facing right", "facing back right",
                     "facing away", "facing back left", "facing left", "facing front left"]
        let name = names[((yaw + 22) / 45) % 8]
        return yaw == 0 ? name : "\(name), turned \(yaw)°"
    }

    /// Millimeters as centimeters, with one decimal only when it is not zero.
    static func centimeters(_ millimeters: Int) -> String {
        let whole = millimeters / 10
        let tenth = millimeters % 10
        return tenth == 0 ? "\(whole) cm" : "\(whole).\(tenth) cm"
    }
}
