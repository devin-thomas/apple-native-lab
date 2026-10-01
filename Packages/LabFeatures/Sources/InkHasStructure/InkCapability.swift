/// Which input paths this host offers, and which Pencil-only gestures stay absent.
///
/// Non-Pencil users finish the task through mouse/touch drawing and typed notes. Advanced Pencil
/// hardware features (squeeze, barrel-roll customization, hover-only tools) are not wired: they
/// are absent from the UI, not shown as broken controls.
public struct InkCapability: Hashable, Sendable {
    public let pencilKitCanvasAvailable: Bool
    public let mouseOrTouchDrawingAvailable: Bool
    public let typedNotesAvailable: Bool
    /// Gesture names that exist in Pencil hardware docs but are intentionally not offered here.
    public let unsupportedPencilGestures: [String]

    public init(
        pencilKitCanvasAvailable: Bool,
        mouseOrTouchDrawingAvailable: Bool = true,
        typedNotesAvailable: Bool = true,
        unsupportedPencilGestures: [String] = InkCapability.defaultAbsentGestures
    ) {
        self.pencilKitCanvasAvailable = pencilKitCanvasAvailable
        self.mouseOrTouchDrawingAvailable = mouseOrTouchDrawingAvailable
        self.typedNotesAvailable = typedNotesAvailable
        self.unsupportedPencilGestures = unsupportedPencilGestures
    }

    /// Squeeze, hover tools, and double-tap customization stay off the surface.
    public static let defaultAbsentGestures = [
        "pencil-squeeze",
        "pencil-hover-only-tool",
        "pencil-double-tap-customization",
    ]

    /// iPhone and iPad: PencilKit canvas with `drawingPolicy = anyInput`, plus typed notes.
    public static let phone = InkCapability(pencilKitCanvasAvailable: true)

    /// Mac: no `PKCanvasView` in the installed macOS SDK; pointer drawing and typed notes.
    public static let mac = InkCapability(pencilKitCanvasAvailable: false)

    /// A host that cannot draw still offers typed notes as the declared fallback.
    public static let typedNotesOnly = InkCapability(
        pencilKitCanvasAvailable: false,
        mouseOrTouchDrawingAvailable: false,
        typedNotesAvailable: true
    )

    public var canCompleteTask: Bool {
        typedNotesAvailable || mouseOrTouchDrawingAvailable || pencilKitCanvasAvailable
    }

    public var fallbackSummary: String {
        "Mouse/touch annotations and typed notes."
    }
}
