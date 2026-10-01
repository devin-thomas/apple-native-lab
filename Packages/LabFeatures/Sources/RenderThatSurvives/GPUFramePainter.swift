#if !os(watchOS)
import CoreImage
import CoreVideo
import Foundation
import Metal

/// Whether a GPU can draw frames now, and the painter that uses it.
///
/// The GPU path is optional. It is used only when a Metal device exists, the person has not
/// turned it off, and the app may use the GPU at this moment: on iPhone and iPad an app in the
/// background may not, unless it holds a background-GPU entitlement, which this lab does not
/// request. Otherwise frames are drawn by `CPUFramePainter`, which produces the same bytes.
public struct GPUAccess: Sendable {
    /// The painter, or `nil` when there is no Metal device.
    public let painter: (any FramePainter)?
    /// Whether the GPU may be used right now. Checked before every frame.
    public let isAllowedNow: @Sendable () -> Bool

    public init(painter: (any FramePainter)?, isAllowedNow: @escaping @Sendable () -> Bool) {
        self.painter = painter
        self.isAllowedNow = isAllowedNow
    }

    /// The system default Metal device, if there is one.
    public static func live(isAllowedNow: @escaping @Sendable () -> Bool = { true }) -> GPUAccess {
        GPUAccess(painter: GPUFramePainter.systemDefault(), isAllowedNow: isAllowedNow)
    }

    /// No GPU: every frame takes the CPU path.
    public static let unavailable = GPUAccess(painter: nil, isAllowedNow: { false })

    /// Why frames are not using the GPU right now, or `nil` when they may.
    public func blocker(preferGPU: Bool) -> GPUBlocker? {
        if !preferGPU { return .turnedOff }
        if painter == nil { return .noDevice }
        if !isAllowedNow() { return .notAllowedNow }
        return nil
    }
}

/// Why a frame took the CPU path.
public enum GPUBlocker: String, Hashable, Sendable {
    case turnedOff = "turned-off"
    case noDevice = "no-device"
    case notAllowedNow = "not-allowed-now"

    public var clause: String {
        switch self {
        case .turnedOff: "the GPU path is turned off"
        case .noDevice: "this device has no Metal GPU"
        case .notAllowedNow: "the app is in the background, where it may not use the GPU"
        }
    }
}

/// The GPU painter: Core Image composites the pattern's rectangles on the Metal device and
/// renders straight into the encoder's pixel buffer. Color management is off, so each 8-bit color
/// arrives unchanged and the bytes match the CPU painter's.
public final class GPUFramePainter: FramePainter, @unchecked Sendable {
    // CIContext is thread-safe for rendering; the painter keeps no other state.
    private let context: CIContext

    init(device: any MTLDevice) {
        context = CIContext(mtlDevice: device, options: [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .workingFormat: NSNumber(value: CIFormat.RGBA8.rawValue),
            .cacheIntermediates: false,
        ])
    }

    public static func systemDefault() -> GPUFramePainter? {
        MTLCreateSystemDefaultDevice().map(GPUFramePainter.init(device:))
    }

    public var path: RenderPath { .gpu }

    public func paint(_ pattern: FramePattern, frame: Int, into buffer: CVPixelBuffer) throws(PaintFailure) {
        let height = pattern.recipe.height
        var image = CIImage.empty()
        for rect in pattern.rects(forFrame: frame) {
            // Core Image's origin is the bottom-left corner; the pattern's is the top-left.
            let flipped = CGRect(x: rect.x, y: height - rect.y - rect.height, width: rect.width, height: rect.height)
            let color = CIColor(
                red: CGFloat(rect.color.red) / 255, green: CGFloat(rect.color.green) / 255, blue: CGFloat(rect.color.blue) / 255
            )
            image = CIImage(color: color).cropped(to: flipped).composited(over: image)
        }
        let bounds = CGRect(x: 0, y: 0, width: pattern.recipe.width, height: height)
        context.render(image, to: buffer, bounds: bounds, colorSpace: nil)
    }
}
#endif
