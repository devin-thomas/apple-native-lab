import Foundation
import SpeechTimeline
import Testing

/// LAB-013 inside the built iPhone app: the bundled fixtures, this device's transcriber reading, and
/// whichever route that reading opens. No microphone is opened.
@Suite struct SpeechTimelinePhoneTests {
    @Test func theOnDeviceRouteOrItsStatedFallbackRunsInsideTheApp() async throws {
        let script = try SpeechFixture.script(at: try #require(SpeechFixture.sampleScript.url(in: .main)))
        let captions = try SpeechFixture.captions(at: try #require(SpeechFixture.sampleCaptions.url(in: .main)))
        #expect(captions.segments.count == script.count, "the caption fallback loads from the app bundle")

        let flow = SpeechTimelineFlow(recognizer: OnDeviceSpeechRecognizer())
        let support = await flow.languages()
        let folder = FileManager.default.temporaryDirectory.appending(path: "SpeechTimelinePhoneTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = folder.appending(path: "sample-clip.caf")
        let duration = try await SampleClipRenderer.render(script, language: SpeechFixture.language, to: clip)
        #expect(duration > 1_000, "the synthesizer spoke the script inside the app")

        let run = await flow.transcribe(file: clip, language: SpeechFixture.language)
        switch support.state(for: SpeechFixture.language) {
        case .installed:
            #expect(run.failure == nil)
            #expect(!run.timeline.segments.isEmpty)
        case .transcriberUnavailable:
            // The iOS 27.0 simulator reports SpeechTranscriber.isAvailable false (LAB-013-A).
            #expect(run.failure == .transcriberUnavailable)
            #expect(run.timeline.isEmpty)
            #expect(support.statement(for: SpeechFixture.language) == "On-device transcription is not available on this device.")
        case .downloadable:
            #expect(run.failure == .modelNotInstalled(SpeechFixture.language), "transcription never downloads a model")
        case .unsupported:
            #expect(run.failure == .unsupportedLanguage(SpeechFixture.language))
        }
    }
}
