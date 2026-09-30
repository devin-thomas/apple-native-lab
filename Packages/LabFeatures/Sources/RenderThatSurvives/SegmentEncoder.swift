#if !os(watchOS)
@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import LabJobs

/// What drew the frames of one run, for its report.
public struct PathTally: Hashable, Sendable {
    public var gpu = 0
    public var cpu = 0
    /// GPU frames that failed their check and were drawn again on the CPU.
    public var gpuRedrawn = 0
    /// Why the most recent CPU frame did not use the GPU, if any did not.
    public var lastBlocker: GPUBlocker?

    public init() {}

    mutating func add(_ other: PathTally) {
        gpu += other.gpu
        cpu += other.cpu
        gpuRedrawn += other.gpuRedrawn
        lastBlocker = other.lastBlocker ?? lastBlocker
    }

    /// "GPU 36, CPU 12".
    public var phrase: String { "GPU \(gpu), CPU \(cpu)" }
}

/// Why encoding stopped early.
enum EncodeStop: Error {
    case requested(JobStopSignal.Request)
    case outOfSpace
    case failed(String)
}

/// Encodes a range of frames into one QuickTime movie of H.264 video.
///
/// Every segment is its own file that starts with a key frame, so finished segments are durable
/// checkpoints and a resumed job can join them without re-encoding. The file is written to a
/// `.partial` name and renamed only when the writer finished, so a stopped or crashed encode never
/// leaves something that looks like a finished segment.
struct SegmentEncoder {
    let pattern: FramePattern
    let preferGPU: Bool
    let gpu: GPUAccess
    let stop: JobStopSignal
    /// Called after each frame is appended, with its number.
    let onFrame: @Sendable (Int, RenderPath) -> Void
    /// Real-time pacing: the instant the run's first frame was due, and how many frames came
    /// before this segment in this run.
    let pace: Pace?

    struct Pace {
        let start: ContinuousClock.Instant
        let framesBefore: Int
    }

    func encode(segment index: Int, to url: URL) async throws(EncodeStop) -> PathTally {
        let recipe = pattern.recipe
        let frames = recipe.frames(ofSegment: index)
        let partial = url.deletingPathExtension().appendingPathExtension("partial.mov")
        try? FileManager.default.removeItem(at: partial)

        let writer: AVAssetWriter
        do { writer = try AVAssetWriter(outputURL: partial, fileType: .mov) } catch { throw .failed("The encoder could not open its file.") }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: recipe.width,
            AVVideoHeightKey: recipe.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: recipe.bitRate,
                AVVideoMaxKeyFrameIntervalKey: recipe.framesPerSegment,
                AVVideoAllowFrameReorderingKey: false,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: recipe.width,
            kCVPixelBufferHeightKey as String: recipe.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        guard writer.canAdd(input) else { throw .failed("The encoder refused the video settings.") }
        writer.add(input)
        guard writer.startWriting() else { throw Self.failure(of: writer, partial: partial) }
        writer.startSession(atSourceTime: .zero)

        var tally = PathTally()
        let cpu = CPUFramePainter()
        do throws(EncodeStop) {
            for (offset, frame) in frames.enumerated() {
                if let request = stop.current { throw EncodeStop.requested(request) }
                if let pace {
                    let due = pace.start + .seconds(Double(pace.framesBefore + offset) / Double(recipe.framesPerSecond))
                    if due > .now { try? await Task.sleep(until: due, clock: .continuous) }
                }
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing else { throw Self.failure(of: writer, partial: partial) }
                    try? await Task.sleep(for: .milliseconds(2))
                }
                guard let pool = adaptor.pixelBufferPool else { throw Self.failure(of: writer, partial: partial) }
                var created: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created) == kCVReturnSuccess, let buffer = created else {
                    throw EncodeStop.failed("The encoder ran out of frame buffers.")
                }
                let path = try paint(frame, into: buffer, cpu: cpu, tally: &tally)
                let time = CMTime(value: CMTimeValue(offset), timescale: CMTimeScale(recipe.framesPerSecond))
                guard adaptor.append(buffer, withPresentationTime: time) else { throw Self.failure(of: writer, partial: partial) }
                onFrame(frame, path)
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw Self.failure(of: writer, partial: partial) }
        } catch {
            if writer.status == .writing { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: partial)
            throw error
        }

        do {
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: partial, to: url)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw .failed("A finished segment could not be kept.")
        }
        return tally
    }

    /// Paints one frame on the GPU when it may, checks it, and falls back to the CPU painter.
    private func paint(_ frame: Int, into buffer: CVPixelBuffer, cpu: CPUFramePainter, tally: inout PathTally) throws(EncodeStop) -> RenderPath {
        if gpu.blocker(preferGPU: preferGPU) == nil, let painter = gpu.painter {
            if (try? painter.paint(pattern, frame: frame, into: buffer)) != nil, FrameCheck.matches(buffer, pattern, frame: frame) {
                tally.gpu += 1
                return .gpu
            }
            tally.gpuRedrawn += 1
        } else {
            tally.lastBlocker = gpu.blocker(preferGPU: preferGPU)
        }
        do { try cpu.paint(pattern, frame: frame, into: buffer) } catch { throw .failed("A frame could not be drawn.") }
        tally.cpu += 1
        return .cpu
    }

    private static func failure(of writer: AVAssetWriter, partial: URL) -> EncodeStop {
        if let error = writer.error as NSError?, Self.isOutOfSpace(error) { return .outOfSpace }
        return .failed("The encoder stopped: \(writer.status == .failed ? "it reported a failure" : "it was not writing").")
    }

    static func isOutOfSpace(_ error: NSError) -> Bool {
        if error.domain == AVFoundationErrorDomain, error.code == AVError.Code.diskFull.rawValue { return true }
        if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteOutOfSpaceError { return true }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOSPC) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return isOutOfSpace(underlying) }
        return false
    }
}
#endif
