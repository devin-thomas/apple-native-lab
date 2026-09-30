#if !os(watchOS)
@preconcurrency import AVFoundation
import Foundation
import LabJobs

/// What a finished movie holds, read back from the file itself.
public struct MovieFacts: Hashable, Sendable {
    public let frameCount: Int
    public let width: Int
    public let height: Int
    /// Seconds, from the file's own duration.
    public let duration: Double
}

/// Joins finished segments into one movie without re-encoding, then checks the result.
///
/// The segments are laid end to end in a composition and exported with the passthrough preset,
/// so their samples are copied, not encoded again. The export writes a `.partial` file in the job's
/// work folder; nothing reaches the output folder until the movie is checked and published.
struct SegmentAssembler {
    let recipe: RenderRecipe
    let stop: JobStopSignal

    func assemble(_ segments: [URL], to staged: URL) async throws(EncodeStop) {
        try? FileManager.default.removeItem(at: staged)
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    let composition = AVMutableComposition()
                    guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                        throw EncodeStop.failed("The movie could not be assembled.")
                    }
                    var cursor = CMTime.zero
                    for url in segments {
                        let asset = AVURLAsset(url: url)
                        guard let source = try await asset.loadTracks(withMediaType: .video).first else {
                            throw EncodeStop.failed("A saved segment has no video.")
                        }
                        let duration = try await asset.load(.duration)
                        try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: cursor)
                        cursor = cursor + duration
                    }
                    guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                        throw EncodeStop.failed("The movie could not be assembled.")
                    }
                    try await session.export(to: staged, as: .mov)
                }
                // Stop requests arrive as a signal, not as task cancellation, so the worker can
                // still record why it stopped. This watcher turns one into a cancelled export.
                group.addTask { [stop] in
                    while true {
                        if let request = stop.current { throw EncodeStop.requested(request) }
                        try await Task.sleep(for: .milliseconds(25))
                    }
                }
                try await group.next()
                group.cancelAll()
            }
        } catch let stop as EncodeStop {
            try? FileManager.default.removeItem(at: staged)
            throw stop
        } catch {
            try? FileManager.default.removeItem(at: staged)
            if let error = error as NSError?, SegmentEncoder.isOutOfSpace(error) { throw .outOfSpace }
            throw .failed("The movie could not be assembled.")
        }
    }

    /// Reads a movie's frame count, size, and duration from the file, counting its samples.
    static func facts(of url: URL) async throws -> MovieFacts {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CocoaError(.fileReadCorruptFile) }
        let size = try await track.load(.naturalSize)
        let duration = try await asset.load(.duration)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw CocoaError(.fileReadCorruptFile) }
        var frames = 0
        while let sample = output.copyNextSampleBuffer() {
            frames += CMSampleBufferGetNumSamples(sample)
        }
        guard reader.status == .completed else { throw CocoaError(.fileReadCorruptFile) }
        return MovieFacts(
            frameCount: frames, width: Int(size.width.rounded()), height: Int(size.height.rounded()),
            duration: duration.seconds
        )
    }
}
#endif
