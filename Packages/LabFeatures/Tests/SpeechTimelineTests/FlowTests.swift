import Foundation
import LabDomain
import Synchronization
import Testing
@testable import SpeechTimeline

/// Transcribing a file through the flow: the timeline improves as results arrive, cancellation
/// keeps what was finalized, and the unavailable paths say why and change nothing.
@Suite struct FlowTests {
    static let file = URL(fileURLWithPath: "/dev/null")

    @Test func theTimelineImprovesWhileResultsArrive() async {
        let seen = Mutex<[TranscriptTimeline]>([])
        let flow = SpeechTimelineFlow(recognizer: ScriptedRecognizer())
        let run = await flow.transcribe(file: Self.file, language: "en-US") { timeline in
            seen.withLock { $0.append(timeline) }
        }
        #expect(run.failure == nil)
        #expect(run.durationMilliseconds == 5_520)
        #expect(run.timeline.segments.map(\.text) == ["Blue tape marks the 2nd shelf.", "Water the fern on Thursday."])
        #expect(run.provisionalShown == 5)
        #expect(run.staleDropped == 0)
        let snapshots = seen.withLock { $0 }
        #expect(snapshots.count == ObservedSequence.updates.count + 1, "one snapshot per result, then the final one")
        #expect(snapshots[2].provisional?.text == "Blue tape marks the 2nd shelf.", "provisional text shows as it improves")
        #expect(snapshots[2].segments.isEmpty)
    }

    @Test func cancellingKeepsTheFinalizedSegmentsAndDropsTheGuess() async {
        let recognizer = ScriptedRecognizer(pause: .milliseconds(300))
        let flow = SpeechTimelineFlow(recognizer: recognizer)
        let task = Task { await flow.transcribe(file: Self.file, language: "en-US") }
        // The observed sequence finalizes its first segment at the fourth result.
        try? await Task.sleep(for: .milliseconds(1_150))
        task.cancel()
        let clock = ContinuousClock()
        let start = clock.now
        let run = await task.value
        #expect(clock.now - start < .milliseconds(400), "cancellation returns promptly")
        #expect(run.failure == .cancelled)
        #expect(run.timeline.provisional == nil)
        #expect(run.timeline.segments.map(\.text) == ["Blue tape marks the 2nd shelf."])
        #expect(RecognitionFailure.cancelled.message == "Transcription stopped. The segments already finalized are kept.")
    }

    @Test func unsupportedLanguagesAreStatedAndNothingIsTranscribed() async {
        let recognizer = ScriptedRecognizer()
        let flow = SpeechTimelineFlow(recognizer: recognizer)
        let support = await flow.languages()
        #expect(support.state(for: "en_US") == .installed, "en_US and en-US name the same language")
        #expect(support.state(for: "fr-FR") == .downloadable)
        #expect(support.state(for: "tlh") == .unsupported)
        #expect(support.statement(for: "fr-FR").hasSuffix("supported on this device. Its model is not installed yet."))
        #expect(support.statement(for: "tlh").hasSuffix("not supported for on-device transcription on this device."))

        let unsupported = await flow.transcribe(file: Self.file, language: "tlh")
        #expect(unsupported.failure == .unsupportedLanguage("tlh"))
        #expect(unsupported.timeline.isEmpty)
        #expect(RecognitionFailure.unsupportedLanguage("tlh").message.hasSuffix("has no on-device transcription model on this device. Import captions or annotate by hand."))

        let notInstalled = await flow.transcribe(file: Self.file, language: "fr-FR")
        #expect(notInstalled.failure == .modelNotInstalled("fr-FR"), "a missing model is never downloaded by transcription")
    }

    @Test func anUnavailableTranscriberLeavesTheFallbackUsable() async throws {
        for support in [LanguageSupport.notCompiled, LanguageSupport(transcriberAvailable: false, supported: [], installed: [])] {
            let flow = SpeechTimelineFlow(recognizer: ScriptedRecognizer(support: support))
            let run = await flow.transcribe(file: Self.file, language: "en-US")
            #expect(run.failure == (support.transcriberAvailable == nil ? .notCompiled : .transcriberUnavailable))
            #expect(run.timeline.isEmpty)
            #expect(support.state(for: "en-US") == .transcriberUnavailable)
        }
        // The fallback still completes the interaction: import captions, correct one, save it.
        let lab = try await Lab.withCollection()
        var timeline = try SpeechFixture.captions(at: Repository.fixture(.sampleCaptions))
        try timeline.correct(timeline.segments[0].id, to: "The kettle clicked off at seven o'clock.")
        try timeline.annotate(range(8_000, 9_000), text: "A note added by hand.")
        let save = try TranscriptSave.prepare(timeline, audio: .none, language: SpeechFixture.language, title: "Captions", into: lab.collection.id)
        let receipt = try await lab.appUI.commit(save)
        #expect(receipt.status == .committed)
        let item = try #require(await lab.store.item(save.itemID))
        #expect(item.note.value.hasPrefix("The kettle clicked off at seven o'clock.\nBlue tape"))
        #expect(item.extras.json.contains("\"source\":\"caption-import\""))
        #expect(item.extras.json.contains("\"source\":\"manual\""))
    }

    @Test func aFailureMidwayKeepsWhatWasFinalized() async {
        let flow = SpeechTimelineFlow(recognizer: ScriptedRecognizer(Array(ObservedSequence.updates.prefix(5)), failure: .engineFailed))
        let run = await flow.transcribe(file: Self.file, language: "en-US")
        #expect(run.failure == .engineFailed)
        #expect(run.timeline.segments.count == 1)
        #expect(run.timeline.provisional == nil)
    }

    @Test func diagnosticsHoldCountsNotText() async {
        let sink = CollectingDiagnosticSink()
        let log = DiagnosticsLog(sinks: [sink])
        let flow = SpeechTimelineFlow(recognizer: ScriptedRecognizer(), diagnostics: log)
        _ = await flow.transcribe(file: Self.file, language: "en-US")
        let event = sink.events.last
        #expect(event?.phase == "speech.transcribe")
        #expect(event?.outcome == .succeeded)
        let encoded = String(decoding: (try? JSONEncoder().encode(sink.events)) ?? Data(), as: UTF8.self)
        #expect(!encoded.contains("Blue tape"))
        #expect(!encoded.contains("dev/null"))
    }
}
