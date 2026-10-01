@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import LabDomain
import LabJobs
@testable import RenderThatSurvives
import Synchronization
import Testing

/// What a published movie holds, read back from its file.
///
/// The H.264 encoder is not bit-for-bit repeatable: two renders of the same frames give files with
/// different bytes, sometimes of different sizes. So a movie is compared by what its decoded frames show.
/// Each frame is decoded and, at the center of every rectangle of its pattern that is at least
/// 6 pixels on each side, its color is matched to the nearest color of the fixture's palette.
/// A frame matches when every point shows the color its own frame number calls for: the right
/// background for its second, its own segment lit, the progress bar, and the moving square. A
/// frame out of order, missing, or repeated fails.
struct EncodedMovie: Hashable {
    let frameCount: Int
    /// Frames whose decoded content is not their own frame's pattern.
    let mismatchedFrames: [Int]
    /// SHA-256 over every frame's matched palette colors, in order. Equal for two movies that show
    /// the same frames.
    let contentDigest: String
    /// SHA-256 of the whole file.
    let fileDigest: String
    let byteCount: Int64

    static let palette: [PixelColor] = PixelColor.backgrounds + [.ink, .paper, .unlit, .lit]

    static func read(_ url: URL, recipe: RenderRecipe = Recipes.short) async throws -> EncodedMovie {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        try #require(reader.startReading())
        let pattern = FramePattern(recipe: recipe)
        var hasher = ContentHasher()
        var frame = 0
        var mismatched: [Int] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let (indices, matches) = classify(buffer, pattern: pattern, frame: frame)
            hasher.update(Data(indices))
            if !matches { mismatched.append(frame) }
            frame += 1
        }
        try #require(reader.status == .completed)
        let file = try AtomicPublication.digest(of: url)
        return EncodedMovie(
            frameCount: frame, mismatchedFrames: mismatched, contentDigest: hasher.finalize().hex,
            fileDigest: file.digest.hex, byteCount: file.byteCount
        )
    }

    /// The palette index decoded at each sample point, and whether all are the expected ones.
    private static func classify(_ buffer: CVPixelBuffer, pattern: FramePattern, frame: Int) -> ([UInt8], Bool) {
        guard frame < pattern.recipe.frameCount,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess
        else { return ([], false) }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return ([], false) }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var indices: [UInt8] = []
        var matches = true
        for rect in pattern.rects(forFrame: frame) where rect.width >= 6 && rect.height >= 6 {
            let x = rect.x + rect.width / 2
            let y = rect.y + rect.height / 2
            let bytes = base.advanced(by: y * stride + x * 4).assumingMemoryBound(to: UInt8.self)
            let seen = nearest(blue: bytes[0], green: bytes[1], red: bytes[2])
            indices.append(UInt8(seen))
            if palette[seen] != pattern.color(atX: x, y: y, frame: frame) { matches = false }
        }
        return (indices, matches)
    }

    private static func nearest(blue: UInt8, green: UInt8, red: UInt8) -> Int {
        func distance(_ color: PixelColor) -> Int {
            let r = Int(color.red) - Int(red), g = Int(color.green) - Int(green), b = Int(color.blue) - Int(blue)
            return r * r + g * g + b * b
        }
        return palette.indices.min { distance(palette[$0]) < distance(palette[$1]) }!
    }
}

/// A painter that claims the GPU path but draws the wrong bytes, so every frame fails its check.
struct MisdrawingPainter: FramePainter {
    var path: RenderPath { .gpu }

    func paint(_ pattern: FramePattern, frame: Int, into buffer: CVPixelBuffer) throws(PaintFailure) {
        // Paints the next frame instead: close enough to look right, wrong at the sample points.
        try CPUFramePainter().paint(pattern, frame: (frame + pattern.recipe.framesPerSecond) % pattern.recipe.frameCount, into: buffer)
    }
}

/// A painter that claims the GPU path and fails every frame, as a lost device would.
struct FailingPainter: FramePainter {
    var path: RenderPath { .gpu }

    func paint(_ pattern: FramePattern, frame: Int, into buffer: CVPixelBuffer) throws(PaintFailure) {
        throw PaintFailure(path: .gpu)
    }
}

/// A painter on the GPU path that draws correct frames: stands in for a Metal device in a
/// process that may not have one.
struct CPUFramePainterOnGPUPath: FramePainter {
    var path: RenderPath { .gpu }

    func paint(_ pattern: FramePattern, frame: Int, into buffer: CVPixelBuffer) throws(PaintFailure) {
        try CPUFramePainter().paint(pattern, frame: frame, into: buffer)
    }
}

/// A backend that runs a hook after each commit it passes on, before the committer hears back.
final class HookedBackend: JobBackend {
    let inner: any JobBackend
    private let hook = Mutex<(@Sendable (DomainOperation) async -> Void)?>(nil)

    init(_ inner: any JobBackend) { self.inner = inner }

    func afterCommit(_ body: @escaping @Sendable (DomainOperation) async -> Void) { hook.withLock { $0 = body } }

    func job(_ id: JobID) async throws(JobError) -> LabJob { try await inner.job(id) }
    func jobs(of kind: JobKind) async throws(JobError) -> [LabJob] { try await inner.jobs(of: kind) }

    func commit(_ operation: DomainOperation, requestID: RequestID) async throws(JobError) -> ActionReceipt {
        let receipt = try await inner.commit(operation, requestID: requestID)
        if let body = hook.withLock({ $0 }) { await body(operation) }
        return receipt
    }
}

/// A backend that can lose its store mid-run, as an app whose store closed would.
final class SwitchableBackend: JobBackend {
    let inner: any JobBackend
    private let closed = Mutex(false)

    init(_ inner: any JobBackend) { self.inner = inner }

    func close() { closed.withLock { $0 = true } }
    func reopen() { closed.withLock { $0 = false } }

    private func check() throws(JobError) {
        if closed.withLock({ $0 }) { throw .unavailable(reason: "The lab store is closed.") }
    }

    func job(_ id: JobID) async throws(JobError) -> LabJob {
        try check()
        return try await inner.job(id)
    }

    func jobs(of kind: JobKind) async throws(JobError) -> [LabJob] {
        try check()
        return try await inner.jobs(of: kind)
    }

    func commit(_ operation: DomainOperation, requestID: RequestID) async throws(JobError) -> ActionReceipt {
        try check()
        return try await inner.commit(operation, requestID: requestID)
    }
}

extension Bench {
    /// A second studio over the same store and folder, as the app has after a relaunch: no
    /// worker from the first one is live in it.
    func relaunched(gpu: GPUAccess = .unavailable) -> RenderStudio {
        let hooks = hooks
        return RenderStudio(
            backend: backend, workspace: workspace, destination: DestinationCheck(capacity: FixedCapacity(bytes: 1 << 34)),
            gpu: gpu, runway: runway, onStage: { id, stage in await hooks.reached(id, stage) }
        )
    }

    func movie(_ recipe: RenderRecipe = Recipes.short) async throws -> EncodedMovie {
        try await EncodedMovie.read(workspace.output(for: recipe), recipe: recipe)
    }
}

extension Recipes {
    /// A short recipe paced at playback speed: two segments of one second each, so a stop can be
    /// sent in the middle of a segment by time.
    static var pacedPair: RenderRecipe {
        try! RenderRecipe(
            id: "paced-pair", title: "Paced pair", width: 160, height: 90, framesPerSecond: 24,
            frameCount: 48, framesPerSegment: 24, pacing: .realTime, bitRate: 300_000
        )
    }
}

/// Every stage the short recipe passes through, in order.
let shortRecipeStages: [RenderStage] = (0..<4).flatMap { [RenderStage.segmentStarted($0), .segmentSaved($0)] }
    + [.assembling, .aboutToPublish]
