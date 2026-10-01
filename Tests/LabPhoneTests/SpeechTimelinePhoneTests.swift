import Foundation
import LabDomain
import LabSupport
import SpeechTimeline
import Testing
@testable import NativeLab

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

/// LAB-013-B inside the built iPhone app: the session model the screen uses, with this device's
/// real transcriber reading and this build's real permission stager, over a fresh SQLite store.
/// Where the transcriber is unavailable (the iOS 27.0 simulator), the interaction completes through
/// the fallback; Record falls back with its reason. No microphone is opened.
@MainActor
@Suite struct SpeechTimelinePhoneQualificationTests {
    @Test func theSessionCompletesThroughTheStatedRouteInsideTheApp() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "SpeechTimelinePhoneQualification-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let capture = StartCounter()
        let experimentFolder = folder.appending(path: "Speech Timeline")
        let model = SpeechTimelineModel(capture: capture, locateFolder: {
            try FileManager.default.createDirectory(at: experimentFolder, withIntermediateDirectories: true)
            return experimentFolder
        })
        await model.refreshSupport()
        if model.support?.transcriberAvailable != true {
            #expect(model.support?.statement(for: SpeechFixture.language) == "On-device transcription is not available on this device.")
            #expect(!model.canTranscribe && !model.canTranscribeSample, "the on-device routes are closed and say why")
        }

        model.loadSampleCaptions()
        #expect(model.timeline.segments.count == 4 && model.timeline.segments.allSatisfy { $0.source == .captionImport })
        let first = model.timeline.segments[0]
        #expect(model.correct(first.id, to: "The kettle clicked off at seven sharp."))
        #expect(model.timeline.segment(first.id)?.range == first.range, "the correction kept its time")
        #expect(model.annotate(start: 8_000, end: 9_500, text: "Added by hand."))
        let cues = try CaptionDocument.parse(model.captionExport())
        #expect(cues.map(\.range) == model.timeline.segments.map(\.range))

        let collection = try #require(await model.createCollection(titled: "Listening notes", in: library))
        let record = try #require(await model.save(to: collection, in: library))
        #expect(record.receipt.status == .committed && record.receipt.admitted.adapter == .appUI)

        await model.record()
        #expect(await capture.starts == 0)
        #expect(model.message?.hasSuffix(Capability.microphone.fallback.summary) == true, "\(model.message ?? "")")

        await model.resetExperiment()
        let service = try await library.openedService()
        let items = try await service.items(try ItemFilter(collectionID: collection), as: LabDataService.appUI)
        #expect(items.count == 1 && items[0].note.value.hasPrefix("The kettle clicked off at seven sharp."), "Reset kept the saved transcript")
    }
}

/// Counts starts and never opens a microphone.
private actor StartCounter: SpeechCapturing {
    private(set) var starts = 0

    func start(language: String) async throws(RecognitionFailure) -> AsyncStream<CaptureEvent> {
        starts += 1
        return AsyncStream { $0.finish() }
    }

    func stop() async {}
}
