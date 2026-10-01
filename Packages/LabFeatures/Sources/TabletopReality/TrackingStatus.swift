/// How well the scene is anchored to the world right now.
///
/// The live AR adapter maps ARKit's camera tracking state onto these cases. The virtual scene has
/// nothing to track, so it is always `virtualScene`. A tracking replay feeds recorded cases to the
/// same gate and is labeled as a replay wherever it shows.
public enum TrackingStatus: Hashable, Sendable {
    /// The non-AR scene: drawn, not tracked. Every interaction is available.
    case virtualScene
    /// The AR route was chosen but its session has not produced a frame yet.
    case notStarted
    /// Tracking is good. Every interaction is available.
    case normal
    /// Tracking works but its poses are not trustworthy yet or any more.
    case limited(LimitedReason)
    /// The session stopped delivering frames, for example while the app was in the background
    /// or another app held the camera.
    case interrupted
    /// Tracking is not available at all.
    case notAvailable

    public enum LimitedReason: String, Hashable, Sendable, CaseIterable {
        case initializing
        case excessiveMotion
        case insufficientFeatures
        case relocalizing
    }

    /// Whether placing, moving, and turning objects may run. Anything that depends on a precise
    /// pose waits for trustworthy tracking.
    public var allowsPrecision: Bool {
        switch self {
        case .virtualScene, .normal: true
        case .notStarted, .limited, .interrupted, .notAvailable: false
        }
    }

    public var title: String {
        switch self {
        case .virtualScene: "Virtual table"
        case .notStarted: "Starting"
        case .normal: "Tracking normally"
        case .limited(.initializing): "Getting ready"
        case .limited(.excessiveMotion): "Moving too fast"
        case .limited(.insufficientFeatures): "Not enough detail"
        case .limited(.relocalizing): "Finding the table again"
        case .interrupted: "Interrupted"
        case .notAvailable: "Tracking unavailable"
        }
    }

    /// What is happening and what to do, in one or two sentences.
    public var guidance: String {
        switch self {
        case .virtualScene:
            "The table is drawn on screen, not tracked in a room. Every control works."
        case .notStarted:
            "The camera is starting. Placing and moving wait until tracking is normal."
        case .normal:
            "Tracking is normal. Placing, moving, and turning are available."
        case .limited(.initializing):
            "Move the device slowly across the table so the camera can find its surface. Placing and moving wait until tracking is normal."
        case .limited(.excessiveMotion):
            "Slow down. Placing and moving are paused until tracking is normal again."
        case .limited(.insufficientFeatures):
            "Point the camera at a textured, well-lit surface. Placing and moving are paused until tracking is normal again."
        case .limited(.relocalizing):
            "Look at the table from where you were before. Placing and moving are paused until the table is found again."
        case .interrupted:
            "The camera stopped. Placing and moving are paused; the objects keep their places on the table."
        case .notAvailable:
            "This device cannot track the world. Use the virtual table instead."
        }
    }
}

/// What a person can do with the scene.
public enum TabletopInteraction: String, Hashable, Sendable, CaseIterable {
    case place
    case move
    case turn
    case setOutStarter
    case select
    case remove
    case clear

    /// Whether the interaction needs a precise, trustworthy pose.
    public var isPrecision: Bool {
        switch self {
        case .place, .move, .turn, .setOutStarter: true
        case .select, .remove, .clear: false
        }
    }
}

/// Suspends precision interactions while tracking is not trustworthy.
///
/// Selecting, reading the list, removing, and clearing stay available in every state: none of
/// them depends on where the camera thinks the table is, and removal keeps an undo.
public enum InteractionGate {
    public static func allows(_ interaction: TabletopInteraction, under status: TrackingStatus) -> Bool {
        !interaction.isPrecision || status.allowsPrecision
    }

    public static func check(_ interaction: TabletopInteraction, under status: TrackingStatus) throws(TabletopError) {
        guard allows(interaction, under: status) else { throw .trackingSuspended(status) }
    }
}
