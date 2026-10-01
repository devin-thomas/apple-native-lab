import Foundation
import Observation

/// Something that plays the kernel: the realtime AVAudioEngine output, or the offline manual
/// rendering output the tests drive.
///
/// `start` chooses the format, prepares the kernel for it (while nothing renders), and starts
/// rendering. `stop` stops rendering before it returns, so the kernel may be prepared again. An
/// output reports route, format, and interruption changes through `events`.
@MainActor
public protocol AudioOutput: AnyObject {
    func start(rendering kernel: AudioKernel) throws(AudioOutputError) -> OutputDescription
    func stop()
    var events: (@MainActor (AudioOutputEvent) -> Void)? { get set }
}

public enum AudioOutputEvent: Hashable, Sendable {
    /// The output's route or format changed and its engine stopped. The graph must be rebuilt.
    case configurationChanged
    /// Another app or the system took the audio session.
    case interrupted
    /// The interruption ended; `shouldResume` is the system's hint.
    case interruptionEnded(shouldResume: Bool)
}

public enum AudioOutputError: Error, Hashable, Sendable {
    /// This build or platform has no live output adapter.
    case unavailable(reason: String)
    /// The system reports no usable output right now.
    case noOutput
    case kernel(AudioKernelError)
    /// The engine or session refused to start; the text is the system's description.
    case startFailed(String)

    public var message: String {
        switch self {
        case .unavailable(let reason): reason
        case .noOutput: "There is no audio output right now."
        case .kernel(let error): error.message
        case .startFailed(let description): "Live audio did not start: \(description)"
        }
    }
}

public enum PlaybackState: Hashable, Sendable {
    case stopped
    case playing(OutputDescription)
    /// The output changed under the graph; the workshop is rebuilding it.
    case recovering
    /// The system interrupted playback. Play resumes it.
    case interrupted
    /// Live output failed. Offline processing still works.
    case failed(String)

    public var isPlaying: Bool { if case .playing = self { true } else { false } }

    public var title: String {
        switch self {
        case .stopped: "Stopped"
        case .playing: "Playing"
        case .recovering: "Recovering"
        case .interrupted: "Interrupted"
        case .failed: "Unavailable"
        }
    }
}

/// Live playback of the kernel through an output, with recovery.
///
/// When the output's route or sample rate changes, the output stops and reports it; playback
/// prepares the kernel for the new format and starts again. The kernel fades in from silence on
/// every start, so a recovery never jumps in level, and the parameters, including panic mute and
/// bypass, carry over untouched because they live in the kernel, not in the engine.
@MainActor
@Observable
public final class LivePlayback {
    public private(set) var state: PlaybackState = .stopped
    /// How many times the graph was rebuilt after an output change.
    public private(set) var recoveries = 0
    /// The last recovery's outcome, for the log.
    public private(set) var lastRecovery: String?

    public let kernel: AudioKernel
    @ObservationIgnored private let output: (any AudioOutput)?
    @ObservationIgnored private let unavailableReason: String
    /// Recovery starts the output again at most this many times before it gives up.
    public static let recoveryAttempts = 3

    /// `output` is `nil` where the platform has no live adapter; `play` then explains why.
    public init(kernel: AudioKernel, output: (any AudioOutput)?, unavailableReason: String = "Live audio is not available in this build.") {
        self.kernel = kernel
        self.output = output
        self.unavailableReason = unavailableReason
        output?.events = { [weak self] event in self?.handle(event) }
    }

    public var isAvailable: Bool { output != nil }

    public func play() {
        guard let output else {
            state = .failed(unavailableReason)
            return
        }
        guard !state.isPlaying else { return }
        do {
            state = .playing(try output.start(rendering: kernel))
        } catch {
            output.stop()
            state = .failed(error.message)
        }
    }

    public func stop() {
        output?.stop()
        state = .stopped
    }

    func handle(_ event: AudioOutputEvent) {
        switch event {
        case .configurationChanged:
            guard state.isPlaying || state == .recovering else { return }
            recover()
        case .interrupted:
            guard state.isPlaying else { return }
            output?.stop()
            state = .interrupted
        case .interruptionEnded(let shouldResume):
            guard state == .interrupted else { return }
            if shouldResume { play() } else { state = .stopped }
        }
    }

    private func recover() {
        guard let output else { return }
        state = .recovering
        output.stop()
        var lastError: AudioOutputError?
        for attempt in 1...Self.recoveryAttempts {
            do {
                let description = try output.start(rendering: kernel)
                recoveries += 1
                lastRecovery = "Rebuilt the graph for \(description.summary) (attempt \(attempt))."
                state = .playing(description)
                return
            } catch {
                output.stop()
                lastError = error
            }
        }
        let reason = lastError?.message ?? AudioOutputError.noOutput.message
        lastRecovery = "Could not rebuild the graph: \(reason)"
        state = .failed(reason)
    }
}
