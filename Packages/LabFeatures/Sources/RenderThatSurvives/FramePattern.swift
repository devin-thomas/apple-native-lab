import CoreVideo
import Foundation
import LabDomain

/// An opaque 8-bit color in the frame buffer's byte order (blue, green, red, alpha).
public struct PixelColor: Hashable, Sendable {
    public let blue: UInt8
    public let green: UInt8
    public let red: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// The fixture's palette: six saturated backgrounds, then ink and paper.
    static let backgrounds: [PixelColor] = [
        PixelColor(red: 208, green: 64, blue: 48), PixelColor(red: 224, green: 160, blue: 32),
        PixelColor(red: 64, green: 160, blue: 72), PixelColor(red: 32, green: 144, blue: 176),
        PixelColor(red: 72, green: 88, blue: 200), PixelColor(red: 160, green: 72, blue: 176),
    ]
    static let ink = PixelColor(red: 16, green: 16, blue: 20)
    static let paper = PixelColor(red: 244, green: 244, blue: 240)
    static let unlit = PixelColor(red: 56, green: 56, blue: 60)
    static let lit = PixelColor(red: 250, green: 214, blue: 64)
}

/// One filled rectangle, in pixels from the top-left corner.
public struct PatternRect: Hashable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let color: PixelColor

    func contains(x px: Int, y py: Int) -> Bool {
        px >= x && px < x + width && py >= y && py < y + height
    }
}

/// The fixture's frames, generated from the recipe and the frame number alone.
///
/// Each frame is a stack of rectangles, drawn in order: a background whose color changes every
/// second; a strip of one cell per segment with the frame's own segment lit, so a viewer can see
/// that segments are in order; a progress bar; and a square that moves one step per frame. The
/// CPU and GPU painters draw the same rectangles and must produce the same bytes.
public struct FramePattern: Hashable, Sendable {
    public let recipe: RenderRecipe

    public init(recipe: RenderRecipe) {
        self.recipe = recipe
    }

    public func rects(forFrame frame: Int) -> [PatternRect] {
        let width = recipe.width
        let height = recipe.height
        let background = PixelColor.backgrounds[(frame / recipe.framesPerSecond) % PixelColor.backgrounds.count]
        var rects = [PatternRect(x: 0, y: 0, width: width, height: height, color: background)]

        let stripHeight = max(2, height / 8)
        let segments = recipe.segmentCount
        let segment = frame / recipe.framesPerSegment
        for index in 0..<segments {
            let left = index * width / segments
            let right = (index + 1) * width / segments
            // A one-pixel gap between cells when there is room for one.
            let gap = right - left > 2 ? 1 : 0
            rects.append(PatternRect(
                x: left, y: 0, width: right - left - gap, height: stripHeight,
                color: index == segment ? .lit : .unlit
            ))
        }

        let barHeight = max(2, height / 10)
        let barWidth = max(1, width * (frame + 1) / recipe.frameCount)
        rects.append(PatternRect(x: 0, y: height - barHeight, width: barWidth, height: barHeight, color: .paper))

        let side = max(2, height / 4)
        let travel = max(1, width - side)
        let step = max(1, width / 64)
        let position = (frame * step) % (2 * travel)
        let x = position < travel ? position : 2 * travel - position
        rects.append(PatternRect(x: x, y: (height - side) / 2, width: side, height: side, color: .ink))
        return rects
    }

    /// The color the topmost rectangle gives one pixel.
    public func color(atX x: Int, y: Int, frame: Int) -> PixelColor {
        rects(forFrame: frame).last { $0.contains(x: x, y: y) }?.color ?? PixelColor.backgrounds[0]
    }

    /// A few points that together cover every layer of a frame, for checking a painted buffer
    /// without reading all of it.
    func samplePoints(forFrame frame: Int) -> [(x: Int, y: Int)] {
        let rects = rects(forFrame: frame)
        return rects.map { ($0.x + $0.width / 2, $0.y + $0.height / 2) }
            + [(0, 0), (recipe.width - 1, recipe.height - 1), (recipe.width / 2, recipe.height / 2)]
    }
}

/// Draws a frame into a 32-bit BGRA pixel buffer.
public protocol FramePainter: Sendable {
    var path: RenderPath { get }
    func paint(_ pattern: FramePattern, frame: Int, into buffer: CVPixelBuffer) throws(PaintFailure)
}

/// Which hardware drew a frame.
public enum RenderPath: String, Hashable, Sendable, Codable {
    /// Core Image on the Metal device.
    case gpu
    /// Plain memory writes on the CPU: the supported path when no GPU can be used.
    case cpu
}

public struct PaintFailure: Error, Hashable, Sendable {
    public let path: RenderPath
}

/// The CPU painter: fills each rectangle row by row. It needs nothing but memory, so it works
/// with no Metal device, in the background, and in a test process.
public struct CPUFramePainter: FramePainter {
    public init() {}

    public var path: RenderPath { .cpu }

    public func paint(_ pattern: FramePattern, frame: Int, into buffer: CVPixelBuffer) throws(PaintFailure) {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferGetWidth(buffer) == pattern.recipe.width,
              CVPixelBufferGetHeight(buffer) == pattern.recipe.height,
              CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess
        else { throw PaintFailure(path: .cpu) }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw PaintFailure(path: .cpu) }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for rect in pattern.rects(forFrame: frame) {
            let pixel = UInt32(rect.color.blue) | UInt32(rect.color.green) << 8 | UInt32(rect.color.red) << 16 | 0xFF00_0000
            for row in rect.y..<(rect.y + rect.height) {
                let start = base.advanced(by: row * stride + rect.x * 4).assumingMemoryBound(to: UInt32.self)
                start.update(repeating: pixel.littleEndian, count: rect.width)
            }
        }
    }
}

/// Checks a painted buffer against the pattern at its sample points.
public enum FrameCheck {
    public static func matches(_ buffer: CVPixelBuffer, _ pattern: FramePattern, frame: Int) -> Bool {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return false }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for point in pattern.samplePoints(forFrame: frame) {
            let bytes = base.advanced(by: point.y * stride + point.x * 4).assumingMemoryBound(to: UInt8.self)
            let expected = pattern.color(atX: point.x, y: point.y, frame: frame)
            guard bytes[0] == expected.blue, bytes[1] == expected.green, bytes[2] == expected.red, bytes[3] == 0xFF else {
                return false
            }
        }
        return true
    }

    /// The SHA-256 of a buffer's visible pixels, row by row without padding.
    public static func digest(of buffer: CVPixelBuffer) -> String {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return "" }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let rowBytes = CVPixelBufferGetWidth(buffer) * 4
        var hasher = ContentHasher()
        for row in 0..<CVPixelBufferGetHeight(buffer) {
            hasher.update(UnsafeRawBufferPointer(start: base.advanced(by: row * stride), count: rowBytes))
        }
        return hasher.finalize().hex
    }
}
