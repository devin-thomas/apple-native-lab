import Foundation
import LabDomain
import LabSupport
import SpeechTimeline
import Testing
@testable import NativeLab

/// LAB-013 in the sandboxed Mac host: Speech Timeline's session model over `LabLibrary` and
/// `LabDataService`, on a fresh SQLite store and a temporary experiment folder per test, never the
/// app's real store. No test opens a microphone: every model here gets a capture that only counts.
@MainActor
@Suite struct SpeechTimelineHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "SpeechTimelineHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func startedLibrary() async throws -> LabLibrary {
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        return library
    }

    private func model(
        recognizer: any SpeechFileRecognizing = UnavailableRecognizer(),
        capture: CountingCapture = CountingCapture(),
        stager: PermissionStager = .live()
    ) -> SpeechTimelineModel {
        let experimentFolder = folder.appending(path: "Speech Timeline")
        return SpeechTimelineModel(
            recognizer: recognizer, installer: RefusingInstaller(), capture: capture, stager: stager,
            locateFolder: {
                try FileManager.default.createDirectory(at: experimentFolder, withIntermediateDirectories: true)
                return experimentFolder
            }
        )
    }

    private func waitUntilIdle(_ model: SpeechTimelineModel, limit: Duration = .seconds(60)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + limit
        while model.isBusy {
            try #require(clock.now < deadline, "the model stayed busy past \(limit)")
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func theAppBundlesTheScriptAndTheCaptions() throws {
        let script = try SpeechFixture.script(at: try #require(SpeechFixture.sampleScript.url(in: .main)))
        #expect(script.count == 4)
        let captions = try SpeechFixture.captions(at: try #require(SpeechFixture.sampleCaptions.url(in: .main)))
        #expect(captions.segments.count == 4)
    }

    /// The fallback completes the interaction in the host with the transcriber unavailable:
    /// captions in, a correction and an annotation, a new collection, and a save that leaves an
    /// app-UI receipt in the inspector's list. The experiment's Reset keeps the saved item.
    @Test func theFallbackCompletesTheInteractionWithoutTheTranscriber() async throws {
        let library = try await startedLibrary()
        let model = model()
        await model.refreshSupport()
        #expect(model.languageState == .transcriberUnavailable)
        #expect(!model.canTranscribe, "the on-device routes are closed")
        #expect(model.support?.statement(for: "en-US") == "On-device transcription is not available on this device.")

        model.loadSampleCaptions()
        #expect(model.source == .captions)
        #expect(model.timeline.segments.count == 4)
        let first = try #require(model.timeline.segments.first)
        #expect(model.correct(first.id, to: "The kettle clicked off at seven sharp."))
        #expect(model.timeline.segment(first.id)?.range == first.range, "the correction kept the caption's time")
        #expect(model.annotate(start: 8_000, end: 9_500, text: "Added by hand."))
        #expect(!model.annotate(start: 1_000, end: 2_000, text: "Overlaps the first caption."))

        let collection = try #require(await model.createCollection(titled: "Listening notes", in: library))
        let receiptsBefore = library.receipts.count
        let record = try #require(await model.save(to: collection, in: library))
        #expect(record.receipt.admitted.adapter == .appUI)
        #expect(record.receipt.status == .committed)
        #expect(library.receipts.count == receiptsBefore + 1)
        #expect(library.latestReceipt?.id == record.id, "the receipt joins the inspector's list")
        #expect(model.isSaved)

        // Pressing Save again for the same revision is a retry: the same receipt, no second item.
        let again = try #require(await model.save(to: collection, in: library))
        #expect(again.id == record.id)
        let service = try await library.openedService()
        let items = try await service.items(try ItemFilter(collectionID: collection), as: LabDataService.appUI)
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.note.value.hasPrefix("The kettle clicked off at seven sharp.\nBlue tape"))
        #expect(item.extras.json.contains("\"recognized\":\"The kettle clicked off at seven.\""))

        await model.resetExperiment()
        #expect(model.timeline.isEmpty)
        #expect(model.source == .none)
        #expect(try await service.item(item.id, as: LabDataService.appUI) == item, "Reset leaves the person's saved item alone")
    }

    /// This source build declares no microphone purpose string and no audio-input entitlement,
    /// so Record falls back with the reason and never reaches capture or a prompt.
    @Test func recordFallsBackInThisBuildWithoutOpeningTheMicrophone() async throws {
        let capture = CountingCapture()
        let model = model(recognizer: InstalledRecognizer(), capture: capture)
        await model.refreshSupport()
        await model.record()
        #expect(await capture.starts == 0)
        #expect(model.activity == .idle)
        let message = try #require(model.message)
        #expect(message.contains("NSMicrophoneUsageDescription") || message.contains("com.apple.security.device.audio-input") || message.contains("declined"),
                "the reason names what closed the route: \(message)")
        #expect(message.hasSuffix(Capability.microphone.fallback.summary))
    }

    @Test func theDestinationSurvivesAStorageRoundTrip() {
        #expect(SidebarDestination(storageKey: SidebarDestination.speechTimeline.storageKey) == .speechTimeline)
        #expect(SidebarDestination.speechTimeline.title == "Speech Timeline")
    }

    /// The live on-device path inside the sandboxed app: the synthesizer speaks the script into the
    /// experiment's folder and `SpeechAnalyzer` transcribes it, with no permission prompt. Opt-in,
    /// because it needs the transcriber and an installed English (US) model:
    /// `TEST_RUNNER_LAB_LIVE_SPEECH=1 xcodebuild test … -only-testing:LabMacTests/SpeechTimelineHostTests`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LAB_LIVE_SPEECH"] == "1"))
    func theSandboxedAppTranscribesTheSynthesizedSampleOnDevice() async throws {
        let library = try await startedLibrary()
        let model = model(recognizer: OnDeviceSpeechRecognizer())
        await model.refreshSupport()
        try #require(model.canTranscribeSample, "the transcriber or the en-US model is unavailable here")
        model.transcribeSample()
        try await waitUntilIdle(model)
        #expect(model.message == nil, "\(model.message ?? "")")
        #expect(model.source == .sampleClip)
        #expect(model.timeline.segments.count >= 3)
        #expect(model.timeline.provisional == nil)
        #expect(model.timeline.segments.allSatisfy { $0.source == .onDeviceTranscriber })
        #expect(model.audio.origin == .synthesizedSample)
        #expect(model.audio.sha256?.count == 64)
        #expect((model.lastRun?.provisionalShown ?? 0) > 0, "provisional text was shown before the segments were final")
        let collection = try #require(await model.createCollection(titled: "Transcripts", in: library))
        let record = try #require(await model.save(to: collection, in: library))
        #expect(record.receipt.admitted.adapter == .appUI)
    }
}

/// A recognizer on a device without the transcriber.
private struct UnavailableRecognizer: SpeechFileRecognizing {
    func languages() async -> LanguageSupport { LanguageSupport(transcriberAvailable: false, supported: [], installed: []) }
    func transcribe(file: URL, language: String, onUpdate: @escaping @Sendable (RecognizerUpdate) async -> Void) async throws(RecognitionFailure) -> Int {
        throw .transcriberUnavailable
    }
}

/// A recognizer that reports English installed, so Record is offered. It never transcribes.
private struct InstalledRecognizer: SpeechFileRecognizing {
    func languages() async -> LanguageSupport { LanguageSupport(transcriberAvailable: true, supported: ["en-US"], installed: ["en-US"]) }
    func transcribe(file: URL, language: String, onUpdate: @escaping @Sendable (RecognizerUpdate) async -> Void) async throws(RecognitionFailure) -> Int {
        throw .engineFailed
    }
}

private struct RefusingInstaller: SpeechModelInstalling {
    func install(language: String, progress: @escaping @Sendable (Double) -> Void) async throws(RecognitionFailure) {
        throw .downloadFailed
    }
}

/// Counts starts and never opens a microphone.
actor CountingCapture: SpeechCapturing {
    private(set) var starts = 0

    func start(language: String) async throws(RecognitionFailure) -> AsyncStream<CaptureEvent> {
        starts += 1
        return AsyncStream { $0.finish() }
    }

    func stop() async {}
}
