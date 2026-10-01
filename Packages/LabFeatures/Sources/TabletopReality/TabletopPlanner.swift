import LabDomain

/// Why a tabletop request did not reach the operation service, or what the service said. Each case
/// changed nothing.
public enum TabletopError: Error, Hashable, Sendable {
    /// Tracking is not trustworthy, so precision interactions wait.
    case trackingSuspended(TrackingStatus)
    case unknownFixture(FixtureKey)
    /// The object is no longer on the table.
    case unknownAnchor(AnchorID)
    /// The object's footprint would reach past the table's edge.
    case outsideTable
    /// The object's footprint would overlap the named object's.
    case overlaps(EntityTitle)
    case tableFull(limit: Int)
    /// No free spot on the table fits the object.
    case noRoom(EntityTitle)
    /// Every starter object's spot is taken.
    case starterBlocked
    /// The lab store cannot be used right now.
    case unavailable(String)
    /// The operation service refused the request.
    case refused(OperationError)
    /// Stopped between two commits. Those already made keep their receipts.
    case cancelled(completed: Int)

    public var message: String {
        switch self {
        case .trackingSuspended(let status):
            "\(status.title). Placing, moving, and turning wait until tracking is normal. Nothing was changed."
        case .unknownFixture(let key):
            "This build's kit has no object named \(key). Nothing was changed."
        case .unknownAnchor:
            "That object is no longer on the table."
        case .outsideTable:
            "That would put the object past the table's edge. Nothing was changed."
        case .overlaps(let title):
            "That would overlap \(title.value). Nothing was changed."
        case .tableFull(let limit):
            "The table holds at most \(limit) objects. Remove one first."
        case .noRoom(let title):
            "There is no free spot for \(title.value). Move or remove an object first."
        case .starterBlocked:
            "Every starter object's spot is taken. Clear the table first."
        case .unavailable(let reason):
            reason
        case .refused(.unauthorized):
            "The app is not allowed to make that change here. Nothing was changed."
        case .refused(.ruleViolation(.noChanges)):
            "Nothing would change."
        case .refused(.notFound):
            "That object is no longer on the table."
        case .refused(.storeFailure):
            "Native Lab could not read or save its data. Nothing was changed. Try again."
        case .refused:
            "The change was refused. Nothing was changed."
        case .cancelled(let completed):
            completed == 0 ? "Stopped. Nothing was changed." : "Stopped after \(completed) of the changes. Each one has its receipt."
        }
    }
}

/// A direction on the table, as the person facing its front sees it.
public enum TableDirection: String, Hashable, Sendable, CaseIterable {
    case left, right
    /// Toward the table's front edge and the viewer: +z.
    case towardYou
    /// Toward the table's back edge: -z.
    case awayFromYou

    public var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .towardYou: "Toward You"
        case .awayFromYou: "Away from You"
        }
    }

    var delta: (x: Int, z: Int) {
        switch self {
        case .left: (-1, 0)
        case .right: (1, 0)
        case .towardYou: (0, 1)
        case .awayFromYou: (0, -1)
        }
    }
}

/// How far one move goes.
public enum NudgeStep: Int, Hashable, Sendable, CaseIterable {
    case fine = 5
    case normal = 20
    case coarse = 100

    public var title: String { "\(rawValue) mm" }
}

/// Turns the tabletop's requests into lab-owned anchor operations, checking the tracking gate,
/// the kit, and the table's placement rules first.
///
/// It is a value over one snapshot: the kit, the anchors as last read through the service, and
/// the tracking status. It never commits. A host submits the operations it returns through its
/// operation service, where each one is authorized and recorded with its receipt; a stale
/// snapshot then becomes a conflict receipt rather than an overwrite.
public struct TabletopPlanner: Sendable {
    /// The most objects the table holds.
    public static let capacity = 12
    /// One turn step, in degrees.
    public static let turnStep = 15

    public let kit: TabletopKit
    public let anchors: [LabAnchor]
    public let tracking: TrackingStatus

    public init(kit: TabletopKit, anchors: [LabAnchor], tracking: TrackingStatus) {
        self.kit = kit
        self.anchors = anchors
        self.tracking = tracking
    }

    public func anchor(_ id: AnchorID) -> LabAnchor? {
        anchors.first { $0.id == id }
    }

    /// The footprint radius of an anchor's fixture. An anchor whose fixture this kit does not
    /// know keeps a conservative footprint, so nothing is placed on top of it.
    public func radius(of anchor: LabAnchor) -> Int {
        kit.fixture(anchor.fixture)?.radius ?? 100
    }

    // MARK: Requests

    /// Places a fixture with its base center at `(x, z)` on the table.
    public func place(
        _ key: FixtureKey,
        x: Int,
        z: Int,
        yaw: Int = 0,
        id: AnchorID = AnchorID()
    ) throws(TabletopError) -> DomainOperation {
        try InteractionGate.check(.place, under: tracking)
        guard let fixture = kit.fixture(key) else { throw .unknownFixture(key) }
        guard anchors.count < Self.capacity else { throw .tableFull(limit: Self.capacity) }
        let pose = try validPose(x: x, z: z, yaw: yaw, radius: fixture.radius, ignoring: nil)
        return .placeAnchor(draft: AnchorDraft(id: id, fixture: fixture.key, title: fixture.title, pose: pose))
    }

    /// Places a fixture at the free spot nearest the table's center, so the object can be placed
    /// without pointing: from a keyboard, Voice Control, or VoiceOver.
    public func placeAtFreeSpot(_ key: FixtureKey, id: AnchorID = AnchorID()) throws(TabletopError) -> DomainOperation {
        try InteractionGate.check(.place, under: tracking)
        guard let fixture = kit.fixture(key) else { throw .unknownFixture(key) }
        guard anchors.count < Self.capacity else { throw .tableFull(limit: Self.capacity) }
        guard let spot = freeSpot(for: fixture) else { throw .noRoom(fixture.title) }
        return try place(key, x: spot.x, z: spot.z, id: id)
    }

    /// Moves an object one step in a direction, keeping its heading.
    public func nudge(_ id: AnchorID, _ direction: TableDirection, by step: NudgeStep = .normal) throws(TabletopError) -> DomainOperation {
        try InteractionGate.check(.move, under: tracking)
        guard let anchor = anchor(id) else { throw .unknownAnchor(id) }
        let delta = direction.delta
        let pose = try validPose(
            x: anchor.pose.x + delta.x * step.rawValue, z: anchor.pose.z + delta.z * step.rawValue,
            yaw: anchor.pose.yaw, radius: radius(of: anchor), ignoring: id
        )
        return .moveAnchor(id: id, expected: anchor.revision, pose: pose)
    }

    /// Moves an object so its base center is at `(x, z)`, keeping its heading.
    public func move(_ id: AnchorID, toX x: Int, z: Int) throws(TabletopError) -> DomainOperation {
        try InteractionGate.check(.move, under: tracking)
        guard let anchor = anchor(id) else { throw .unknownAnchor(id) }
        let pose = try validPose(x: x, z: z, yaw: anchor.pose.yaw, radius: radius(of: anchor), ignoring: id)
        return .moveAnchor(id: id, expected: anchor.revision, pose: pose)
    }

    /// Turns an object counterclockwise, seen from above, by `degrees`; negative turns clockwise.
    public func turn(_ id: AnchorID, by degrees: Int) throws(TabletopError) -> DomainOperation {
        try InteractionGate.check(.turn, under: tracking)
        guard let anchor = anchor(id) else { throw .unknownAnchor(id) }
        let pose: AnchorPose
        do {
            pose = try AnchorPose(x: anchor.pose.x, y: anchor.pose.y, z: anchor.pose.z, yaw: anchor.pose.yaw + degrees)
        } catch {
            throw .outsideTable
        }
        return .moveAnchor(id: id, expected: anchor.revision, pose: pose)
    }

    /// Removes one object. Available whatever the tracking, and its receipt's undo places it again.
    public func remove(_ id: AnchorID) throws(TabletopError) -> DomainOperation {
        try InteractionGate.check(.remove, under: tracking)
        guard let anchor = anchor(id) else { throw .unknownAnchor(id) }
        return .removeAnchor(id: id, expected: anchor.revision)
    }

    /// One removal per object on the table, in title order. Only lab-owned anchors exist to be
    /// removed; nothing else is named.
    public func clear() throws(TabletopError) -> [DomainOperation] {
        try InteractionGate.check(.clear, under: tracking)
        return anchors.map { .removeAnchor(id: $0.id, expected: $0.revision) }
    }

    /// Places the kit's starter scene: every starter object whose spot is free, in order. The
    /// spots are checked against each other too, so the returned operations never collide.
    public func setOutStarter() throws(TabletopError) -> [DomainOperation] {
        try InteractionGate.check(.setOutStarter, under: tracking)
        var planner = self
        var operations: [DomainOperation] = []
        for placement in kit.starter {
            guard let operation = try? planner.place(placement.fixture, x: placement.x, z: placement.z, yaw: placement.yaw),
                  case .placeAnchor(let draft) = operation
            else { continue }
            operations.append(operation)
            planner = TabletopPlanner(
                kit: kit, anchors: planner.anchors + [LabAnchor(id: draft.id, fixture: draft.fixture, title: draft.title, pose: draft.pose)],
                tracking: tracking
            )
        }
        guard !operations.isEmpty else { throw .starterBlocked }
        return operations
    }

    // MARK: Placement rules

    /// The pose, if the footprint stays on the table and clear of every other object.
    func validPose(x: Int, z: Int, yaw: Int, radius: Int, ignoring ignored: AnchorID?) throws(TabletopError) -> AnchorPose {
        let halfWidth = kit.table.width / 2
        let halfDepth = kit.table.depth / 2
        guard abs(x) + radius <= halfWidth, abs(z) + radius <= halfDepth else { throw .outsideTable }
        for other in anchors where other.id != ignored {
            let dx = Double(other.pose.x - x)
            let dz = Double(other.pose.z - z)
            let apart = Double(radius + self.radius(of: other))
            if dx * dx + dz * dz < apart * apart { throw .overlaps(other.title) }
        }
        do {
            return try AnchorPose(x: x, y: 0, z: z, yaw: yaw)
        } catch {
            throw .outsideTable
        }
    }

    /// The free spot nearest the center on a 20 mm grid, scanning outward ring by ring and, within
    /// a ring, in a fixed order, so the same table always gives the same spot.
    func freeSpot(for fixture: KitFixture) -> (x: Int, z: Int)? {
        let grid = 20
        let rings = max(kit.table.width, kit.table.depth) / 2 / grid
        for ring in 0...rings {
            var candidates: [(x: Int, z: Int)] = []
            for i in -ring...ring {
                for j in -ring...ring where max(abs(i), abs(j)) == ring {
                    candidates.append((i * grid, j * grid))
                }
            }
            candidates.sort { ($0.x * $0.x + $0.z * $0.z, $0.z, $0.x) < ($1.x * $1.x + $1.z * $1.z, $1.z, $1.x) }
            for spot in candidates where (try? validPose(x: spot.x, z: spot.z, yaw: 0, radius: fixture.radius, ignoring: nil)) != nil {
                return spot
            }
        }
        return nil
    }
}
