#if canImport(Speech) && (os(iOS) || os(macOS))
import Foundation
import LabDomain
import LabSupport
import Synchronization
import Testing
@testable import SpeechTimeline

/// The real on-device transcriber on the sample clip, which this device's speech synthesizer speaks
/// from the committed script at test time. No microphone is opened and no audio is committed.
/// Opt-in, because it needs the transcriber and an installed English (US) model, and the text is
/// the recognizer's, not a fixed answer:
///
///     LAB_LIVE_SPEECH=1 [LAB_LIVE_SPEECH_EVIDENCE_DIR=evidence/LAB-013 LAB_SOURCE_REVISION=… LAB_SDK_NAME=…
///     LAB_XCODE_VERSION=… LAB_XCODE_BUILD=…] swift test --package-path Packages/LabFeatures --filter LiveSpeechEvidenceTests
///
/// It asserts what the design guarantees: every snapshot keeps provisional text off finalized
/// audio, the run ends with no provisional text, segments and word times are valid and ordered,
/// and a correction keeps the live segment's time. Whether the words are right is recorded, not
/// asserted beyond a loose match.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LAB_LIVE_SPEECH"] == "1", "set LAB_LIVE_SPEECH=1 to run the on-device transcriber"))
struct LiveSpeechEvidenceTests {
    @Test func aLiveTranscriptionOfTheSynthesizedSampleBecomesAnEvidenceRecord() async throws {
        let environment = ProcessInfo.processInfo.environment
        let started = Date()
        let snapshot = DeviceSnapshot.current
        let execution = try Execution(observing: snapshot)
        let language = SpeechFixture.language

        let folder = FileManager.default.temporaryDirectory.appending(path: "lab-013-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = folder.appending(path: "sample-clip.caf")
        let script = try SpeechFixture.script(at: Repository.fixture(.sampleScript))

        let recognizer = OnDeviceSpeechRecognizer()
        let support = await recognizer.languages()
        let state = support.state(for: language)
        var problems: [String] = []
        var detail = "SpeechTranscriber.isAvailable \(support.transcriberAvailable.map(String.init) ?? "not compiled"); "
            + "\(support.supported.count) supported and \(support.installed.count) installed languages; \(support.statement(for: language)) "

        if state == .installed {
            let renderClock = ContinuousClock()
            let renderStart = renderClock.now
            let clipMilliseconds = try await SampleClipRenderer.render(script, language: language, to: clip)
            let renderElapsed = renderClock.now - renderStart
            let audio = try AudioReference.file(at: clip, origin: .synthesizedSample, durationMilliseconds: clipMilliseconds)

            let snapshots = Mutex<[TranscriptTimeline]>([])
            let flow = SpeechTimelineFlow(recognizer: recognizer)
            let clock = ContinuousClock()
            let start = clock.now
            let run = await flow.transcribe(file: clip, language: language) { timeline in
                snapshots.withLock { $0.append(timeline) }
            }
            let elapsed = clock.now - start
            let seen = snapshots.withLock { $0 }

            if let failure = run.failure { problems.append("the run failed: \(failure.message)") }
            var overlapping = 0
            for timeline in seen {
                if let guess = timeline.provisional, timeline.segments.contains(where: { $0.range.overlaps(guess.range) }) {
                    overlapping += 1
                }
            }
            if overlapping > 0 { problems.append("\(overlapping) snapshots showed a guess over finalized audio") }
            if run.timeline.provisional != nil { problems.append("provisional text remained after the run") }
            let segments = run.timeline.segments
            if segments.isEmpty { problems.append("no segment was finalized") }
            for (earlier, later) in zip(segments, segments.dropFirst()) where earlier.range.overlaps(later.range) {
                problems.append("segments \(earlier.id) and \(later.id) overlap")
            }
            for segment in segments where !segment.words.allSatisfy({ segment.range.startMilliseconds <= $0.range.startMilliseconds && $0.range.endMilliseconds <= segment.range.endMilliseconds }) {
                problems.append("segment \(segment.id) has a word outside its range")
            }
            if let last = segments.last, last.range.endMilliseconds > clipMilliseconds + 500 {
                problems.append("a segment ends after the clip")
            }
            // A correction on the live result keeps its time.
            var corrected = run.timeline
            if let first = segments.first {
                try corrected.correct(first.id, to: "Corrected by the test.")
                if corrected.segment(first.id)?.range != first.range { problems.append("a correction moved the segment") }
            }
            // A loose match: each script line's distinctive word appears in the transcript.
            let heard = run.timeline.plainText.lowercased()
            let keys = ["kettle", "tape", "fern", "tin"]
            let found = keys.filter { heard.contains($0) }
            if found.count < 3 { problems.append("only \(found.count) of the script's key words were heard") }

            let lines = segments.map { "\($0.range) “\($0.recognized)” (\($0.words.count) word times)" }
            detail += "The synthesizer spoke the \(script.count)-line script as a \(clipMilliseconds) ms clip in \(Self.milliseconds(renderElapsed)) ms "
                + "(sha256 \(audio.sha256 ?? "none")). SpeechTimelineFlow with OnDeviceSpeechRecognizer took \(Self.milliseconds(elapsed)) ms: "
                + "\(run.provisionalShown) provisional snapshots, \(run.staleDropped) stale guesses dropped, \(run.refusedFinals) finals refused or repeated, "
                + "\(segments.count) finalized segments: " + lines.joined(separator: "; ")
                + ". Key words heard: \(found.joined(separator: ", ")). No snapshot showed a guess over finalized audio: \(overlapping == 0)."
        }

        let outcome: RunOutcome = if state != .installed {
            .blocked(reason: detail + "No transcription was attempted, because the route is not open here. This test never downloads a model.")
        } else if problems.isEmpty {
            .passed(observed: detail)
        } else {
            .failed(observed: problems.joined(separator: "; ") + ". " + detail)
        }
        let pathLimitation: String = switch execution.path {
        case .physical:
            "Physical path only in that the transcriber ran on this machine's own hardware (DeviceSnapshot). A test process drove it, not a person in the app, and it says nothing about an iPhone or iPad."
        case .simulator:
            "Simulator path: the simulator runs the host Mac's speech stack. It is not device evidence."
        default:
            "Neither a physical device nor a simulator was detected."
        }
        let scriptHash = ContentDigest.sha256(try Data(contentsOf: Repository.fixture(.sampleScript))).hex
        let record = try EvidenceRecord(
            subject: "LAB-013-A",
            check: "Speech Timeline's on-device path: SpeechAnalyzer and SpeechTranscriber transcribed a clip this device's speech synthesizer spoke from the sample script, through SpeechTimelineFlow, with provisional text kept apart from finalized segments",
            date: started,
            provenance: BuildProvenance(
                sourceRevision: environment["LAB_SOURCE_REVISION"] ?? "unknown",
                sdkName: environment["LAB_SDK_NAME"] ?? "unknown",
                xcodeVersion: environment["LAB_XCODE_VERSION"] ?? "unknown",
                xcodeBuild: environment["LAB_XCODE_BUILD"] ?? "unknown"
            ),
            execution: execution,
            inputs: ["script:speech-sample-script@sha256:\(scriptHash)", "language:\(language)"],
            steps: [
                "LAB_LIVE_SPEECH=1 swift test --package-path Packages/LabFeatures --filter LiveSpeechEvidenceTests",
                "Read SpeechTranscriber.isAvailable, supportedLocales, and installedLocales; stop as blocked if the en-US model is not installed (nothing is downloaded)",
                "SampleClipRenderer: AVSpeechSynthesizer.write with this device's en-US voice, the script's lines joined, into a temporary CAF file",
                "SpeechTimelineFlow.transcribe with OnDeviceSpeechRecognizer: SpeechAnalyzer.analyzeSequence(from:) then finalizeAndFinish(through:), SpeechTranscriber with volatileResults and audioTimeRange",
                "Check every snapshot, the final timeline, word times, and a correction's range; delete the temporary clip",
            ],
            outcome: outcome,
            limitations: [
                pathLimitation,
                "The audio is synthesized speech, not a person speaking, and no microphone was opened. Recognition of real voices, rooms, and microphones is not covered.",
                "On-device by construction, not by network monitoring: the module has no server route (FixtureAndRouteTests), and the analyzer runs in the system's speech service, whose network activity was not observed.",
                "Timings are single intervals, not a benchmark. The synthesizer's voice and the recognizer's text are this machine's; other devices, voices, and OS builds may differ.",
            ]
        )
        #expect(problems.isEmpty, "\(problems.joined(separator: "; "))")
        if state != .installed { Issue.record("the on-device route is not open here (\(support.statement(for: language))); the record is blocked") }
        if let folder = environment["LAB_LIVE_SPEECH_EVIDENCE_DIR"] {
            for fact in ["LAB_SOURCE_REVISION", "LAB_SDK_NAME", "LAB_XCODE_VERSION", "LAB_XCODE_BUILD"] {
                try #require(environment[fact].map { !$0.isEmpty } == true, "a kept record names \(fact)")
            }
            let name = environment["LAB_LIVE_SPEECH_EVIDENCE_NAME"]
                ?? (execution.path == .simulator ? "speech-timeline-live-ios-simulator" : "speech-timeline-live-mac")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
            let url = URL(filePath: folder, directoryHint: .isDirectory).appending(path: "\(name).json")
            try (try encoder.encode(record) + Data("\n".utf8)).write(to: url)
            #expect(try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: url)) == record)
        }
    }

    static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }
}
#endif
