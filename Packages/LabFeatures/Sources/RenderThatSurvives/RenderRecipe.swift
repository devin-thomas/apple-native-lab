import Foundation
import LabDomain

/// A deterministic render: frame size, rate, length, how the work is split into durable segments,
/// and the encoder's bit rate. Every frame is generated from these numbers alone, so the fixture
/// needs no source media and two runs draw the same pixels.
public struct RenderRecipe: Hashable, Sendable, Codable, Identifiable {
    /// How fast frames are produced.
    public enum Pacing: String, Hashable, Sendable, Codable {
        /// As fast as the device can draw and encode.
        case asFastAsPossible = "as-fast-as-possible"
        /// No faster than playback speed, one second of video per second, as a live render
        /// would. The long fixture uses it so there is time to leave the app and return.
        case realTime = "real-time"
    }

    public static let sizeLimits = (width: 16...1920, height: 16...1080)
    public static let frameRateLimits = 1...60
    public static let frameCountLimits = 1...3_600
    public static let segmentLengthLimits = 1...600
    public static let bitRateLimits = 50_000...8_000_000

    /// A slug that also names the output file.
    public let id: String
    public let title: String
    public let width: Int
    public let height: Int
    public let framesPerSecond: Int
    public let frameCount: Int
    /// Frames per durable segment. Each segment is a checkpoint.
    public let framesPerSegment: Int
    public let pacing: Pacing
    /// Average bits per second for the H.264 encoder.
    public let bitRate: Int

    public init(
        id: String,
        title: String,
        width: Int,
        height: Int,
        framesPerSecond: Int,
        frameCount: Int,
        framesPerSegment: Int,
        pacing: Pacing,
        bitRate: Int
    ) throws(RecipeProblem) {
        guard JobKind(rawValue: id) != nil else { throw .invalid(.id) }
        guard (1...80).contains(title.count), !title.contains(where: \.isNewline) else { throw .invalid(.title) }
        guard Self.sizeLimits.width.contains(width), width.isMultiple(of: 2) else { throw .invalid(.width) }
        guard Self.sizeLimits.height.contains(height), height.isMultiple(of: 2) else { throw .invalid(.height) }
        guard Self.frameRateLimits.contains(framesPerSecond) else { throw .invalid(.framesPerSecond) }
        guard Self.frameCountLimits.contains(frameCount) else { throw .invalid(.frameCount) }
        guard Self.segmentLengthLimits.contains(framesPerSegment), framesPerSegment <= frameCount else {
            throw .invalid(.framesPerSegment)
        }
        guard Self.bitRateLimits.contains(bitRate) else { throw .invalid(.bitRate) }
        self.id = id
        self.title = title
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.frameCount = frameCount
        self.framesPerSegment = framesPerSegment
        self.pacing = pacing
        self.bitRate = bitRate
    }

    // MARK: Derived

    /// The published file's name, inside the experiment's output folder.
    public var outputName: String { "\(id).mov" }

    public var segmentCount: Int { (frameCount + framesPerSegment - 1) / framesPerSegment }

    /// The frames of one segment.
    public func frames(ofSegment index: Int) -> Range<Int> {
        let start = index * framesPerSegment
        return start..<min(start + framesPerSegment, frameCount)
    }

    public var durationSeconds: Double { Double(frameCount) / Double(framesPerSecond) }

    /// The job's durable units: one per segment, and one for assembling and publishing.
    public var jobUnits: Int { segmentCount + 1 }

    /// A generous estimate of the encoded size: the bit rate over the duration, a quarter more for
    /// rate overshoot, and 64 KB of container per file.
    public var estimatedOutputBytes: Int64 {
        Int64((Double(bitRate) / 8 * durationSeconds * 1.25).rounded(.up)) + 65_536
    }

    /// Space a run needs at its peak: every segment and the assembled copy at once, plus 1 MB.
    public var requiredBytes: Int64 {
        estimatedOutputBytes * 2 + Int64(segmentCount) * 65_536 + 1_048_576
    }

    /// "2.0 s · 160×90 · 24 fps".
    public var shape: String {
        "\(String(format: "%.1f", durationSeconds)) s · \(width)×\(height) · \(framesPerSecond) fps"
    }

    // MARK: Decoding

    /// The largest recipe document read.
    public static let maximumDocumentBytes = 16_384

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, title, width, height, framesPerSecond, frameCount, framesPerSegment, pacing, bitRate
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            title: container.decode(String.self, forKey: .title),
            width: container.decode(Int.self, forKey: .width),
            height: container.decode(Int.self, forKey: .height),
            framesPerSecond: container.decode(Int.self, forKey: .framesPerSecond),
            frameCount: container.decode(Int.self, forKey: .frameCount),
            framesPerSegment: container.decode(Int.self, forKey: .framesPerSegment),
            pacing: container.decode(Pacing.self, forKey: .pacing),
            bitRate: container.decode(Int.self, forKey: .bitRate)
        )
    }

    /// Reads a recipe list from untrusted bytes: strict JSON first (no duplicate keys, no
    /// ill-formed text, bounded size and depth), then every field's own limits. An unknown field
    /// is refused rather than ignored, so a recipe never means more than this build reads.
    public static func recipes(from data: Data) throws(RecipeProblem) -> [RenderRecipe] {
        do {
            try StrictJSON.validate(data, maximumDepth: 4, maximumBytes: maximumDocumentBytes)
        } catch {
            throw .malformed
        }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) } catch { throw .malformed }
        guard let root = object as? [String: Any], Set(root.keys) == ["recipes"],
              let list = root["recipes"] as? [[String: Any]], !list.isEmpty, list.count <= 16
        else { throw .malformed }
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        for entry in list where !Set(entry.keys).isSubset(of: known) { throw .unknownField }
        let recipes: [RenderRecipe]
        do {
            recipes = try JSONDecoder().decode(RecipeList.self, from: data).recipes
        } catch let problem as RecipeProblem {
            throw problem
        } catch {
            throw .malformed
        }
        guard Set(recipes.map(\.id)).count == recipes.count else { throw .duplicateID }
        return recipes
    }

    private struct RecipeList: Decodable {
        let recipes: [RenderRecipe]
    }
}

/// Why a recipe document was refused. Nothing was started.
public enum RecipeProblem: Error, Hashable, Sendable {
    public enum Field: String, Hashable, Sendable {
        case id, title, width, height, framesPerSecond, frameCount, framesPerSegment, bitRate
    }

    case malformed
    case unknownField
    case duplicateID
    case invalid(Field)

    public var message: String {
        switch self {
        case .malformed: "The recipe is not a well-formed recipe list."
        case .unknownField: "The recipe has a field this build does not read."
        case .duplicateID: "Two recipes share one name."
        case .invalid(let field): "The recipe's \(field.rawValue) is outside what this lab renders."
        }
    }
}
