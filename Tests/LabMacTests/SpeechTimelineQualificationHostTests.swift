import Foundation
import LabDomain
import LabStore
import LabSupport
import SpeechTimeline
import Synchronization
import Testing
@testable import NativeLab

/// LAB-013-B in the sandboxed Mac host: the qualification cases through the app's one session
/// model (`SpeechTimelineModel`), `LabLibrary`, and a fresh SQLite store and experiment folder per
/// test.
///
/// No microphone is opened. Where a case needs Record to get past the gate, the model gets a
/// permission source that reports the microphone allowed and a capture that replays scripted
/// events; this build's own Record, with the real stager, falls back (`SpeechTimelineHostTests`).
@MainActor
@Suite struct SpeechTimelineQualificationHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "SpeechTimelineQualificationHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    // MARK: Criterion 1: route changes do not silently lose the session

    /// A route change during a recording pauses it: the finalized segment stays, the guess goes, and
    /// the summary names the change on screen and is announced. Resume continues the same timeline,
    /// a correction keeps the resumed segment's time, and the save holds both segments.
    @Test func aRouteChangePausesTheRecordingSaysSoAndResumeContinuesIt() async throws {
        let library = try await SpeechHostLab.startedLibrary(in: folder)
        let capture = ScriptedRuns([
            [.update(speechGuess(0, 900, "The kettle")), .update(speechFinal(0, 1_700, "The kettle clicked off at 7.")),
             .update(speechGuess(1_700, 2_400, "Blue tape")), CaptureStop.routeChange(reason: 2)!],
            [.update(speechFinal(0, 2_200, "Blue tape marks the 2nd shelf."))],
        ])
        let model = SpeechHostLab.model(in: folder, capture: capture, stager: SpeechHostLab.microphoneAllowed())
        await model.refreshSupport()

        await model.record()
        try await SpeechHostLab.waitUntilIdle(model)
        let paused = "Recording paused because the audio route changed: the audio device in use was disconnected. 1 segment kept. Unfinished text was removed once because it was never finalized. Resume continues the same timeline."
        #expect(model.message == paused)
        #expect(model.recording.state == .paused(.routeChanged("the audio device in use was disconnected")))
        #expect(SpeechTimelineModel.announcement(for: model.recording, segments: model.timeline.segments.count) == LabAnnouncement(text: paused, priority: .high),
                "the pause is spoken, not only shown")
        #expect(model.timeline.segments.map(\.text) == ["The kettle clicked off at 7."])
        #expect(model.timeline.provisional == nil)
        #expect(model.source == .recording)

        // The Record button now reads Resume Recording, and pressing it continues the timeline.
        await model.record()
        try await SpeechHostLab.waitUntil { await capture.starts == 2 && model.activity == .recording }
        await model.stopRecording()
        try await SpeechHostLab.waitUntilIdle(model)
        #expect(model.recording.state == .paused(.stoppedByPerson))
        #expect(model.message == "Recording stopped. 2 segments kept. Unfinished text was removed once because it was never finalized.")
        #expect(SpeechTimelineModel.announcement(for: model.recording, segments: 2) == nil, "a stop the person pressed is not announced")
        #expect(model.timeline.segments.map(\.range) == [speechRange(0, 1_700), speechRange(1_700, 3_900)])

        let resumed = model.timeline.segments[1]
        #expect(model.correct(resumed.id, to: "Blue tape marks the second shelf."))
        #expect(model.timeline.segment(resumed.id)?.range == resumed.range)
        let collection = try #require(await model.createCollection(titled: "Recordings", in: library))
        let record = try #require(await model.save(to: collection, in: library))
        #expect(record.receipt.status == .committed && record.receipt.admitted.adapter == .appUI)
        let item = try await SpeechHostLab.onlyItem(in: collection, library: library)
        #expect(item.note.value == "The kettle clicked off at 7.\nBlue tape marks the second shelf.")
        #expect(item.extras.json.contains(#""range":{"endMs":3900,"startMs":1700},"recognized":"Blue tape marks the 2nd shelf.""#))
        #expect(item.extras.json.contains(#""origin":"recording""#))
    }

    /// The route change left no microphone, so Resume cannot start. The message names the failure
    /// and the segments still held, and it is announced.
    @Test func aResumeThatCannotStartKeepsTheSegmentsAndSaysSo() async throws {
        let capture = ScriptedRuns([
            [.update(speechFinal(0, 1_700, "The kettle clicked off at 7.")), CaptureStop.routeChange(reason: 7)!],
        ], failAfterRuns: .audioUnreadable)
        let model = SpeechHostLab.model(in: folder, capture: capture, stager: SpeechHostLab.microphoneAllowed())
        await model.refreshSupport()
        await model.record()
        try await SpeechHostLab.waitUntilIdle(model)
        #expect(model.message?.hasPrefix("Recording paused because the audio route changed: no audio input is available. 1 segment kept.") == true)

        await model.record()
        try await SpeechHostLab.waitUntilIdle(model)
        #expect(model.message == "The audio could not be read. Nothing was transcribed. 1 segment kept.")
        #expect(model.recording.state == .failed(.audioUnreadable))
        #expect(SpeechTimelineModel.announcement(for: model.recording, segments: 1)?.priority == .high)
        #expect(model.timeline.segments.map(\.text) == ["The kettle clicked off at 7."])
    }

    // MARK: Step 3: denial, cancellation, stale and duplicate state, and reset

    /// A microphone declined earlier falls back with its reason in the app, and nothing starts.
    @Test func aDeclinedMicrophoneFallsBackInTheApp() async throws {
        let capture = ScriptedRuns([])
        let model = SpeechHostLab.model(in: folder, capture: capture, stager: SpeechHostLab.microphoneAllowed(status: .denied))
        await model.refreshSupport()
        await model.record()
        #expect(await capture.starts == 0)
        #expect(model.message == "Microphone access was declined earlier. The lab does not ask again. \(Capability.microphone.fallback.summary)")
        #expect(model.activity == .idle && model.source == .none)
    }

    /// Record pressed twice before the gate answers starts one capture.
    @Test func twoRecordPressesStartOneCapture() async throws {
        let capture = ScriptedRuns([[.update(speechFinal(0, 1_000, "One."))], [.update(speechFinal(0, 1_000, "Two."))]])
        let model = SpeechHostLab.model(in: folder, capture: capture, stager: SpeechHostLab.microphoneAllowed())
        await model.refreshSupport()
        async let first: Void = model.record()
        async let second: Void = model.record()
        _ = await (first, second)
        try await SpeechHostLab.waitUntil { model.activity == .recording }
        #expect(await capture.starts == 1)
        await model.stopRecording()
        try await SpeechHostLab.waitUntilIdle(model)
        #expect(model.timeline.segments.map(\.text) == ["One."])
    }

    /// Stop during a transcription keeps what was finalized. A run the person replaced (Reset during
    /// a transcription) never writes into the timeline afterwards.
    @Test func aStoppedOrReplacedRunNeverOverwritesTheTimeline() async throws {
        let audio = folder.appending(path: "chosen.caf")
        try Data("not decoded by the scripted recognizer".utf8).write(to: audio)
        let model = SpeechHostLab.model(in: folder, recognizer: PacedRecognizer(pause: .milliseconds(250)))
        await model.refreshSupport()

        model.importAudio(from: audio)
        try await SpeechHostLab.waitUntil { model.timeline.segments.count == 1 }
        model.cancel()
        try await SpeechHostLab.waitUntilIdle(model)
        #expect(model.message == RecognitionFailure.cancelled.message)
        #expect(model.timeline.segments.map(\.text) == ["Blue tape marks the 2nd shelf."])
        #expect(model.timeline.provisional == nil)

        model.importAudio(from: audio)
        try await SpeechHostLab.waitUntil { model.timeline.provisional != nil }
        await model.resetExperiment()
        try await Task.sleep(for: .milliseconds(1_500))
        #expect(model.timeline.isEmpty, "the replaced run's later results were not shown")
        #expect(model.source == .none && model.activity == .idle)
        #expect(model.message == "Speech Timeline was reset. Saved transcripts in your collections were not changed.")
    }

    /// A new timeline is never saved as the one before it. Two caption imports both start at
    /// revision 0, so Save must prepare a new item for the second rather than retry the first.
    @Test func aReplacedTimelineIsSavedAsItself() async throws {
        let library = try await SpeechHostLab.startedLibrary(in: folder)
        let model = SpeechHostLab.model(in: folder)
        await model.refreshSupport()
        let collection = try #require(await model.createCollection(titled: "Captions", in: library))
        model.loadSampleCaptions()
        let first = try #require(await model.save(to: collection, in: library))
        let other = folder.appending(path: "other.vtt")
        try Data("WEBVTT\n\n00:00.000 --> 00:01.500\nA different caption file.\n".utf8).write(to: other)
        model.importCaptions(from: other)
        #expect(model.timeline.revision == 0 && !model.isSaved)
        let second = try #require(await model.save(to: collection, in: library))
        #expect(second.id != first.id, "the second timeline got its own save")
        let service = try await library.openedService()
        let items = try await service.items(try ItemFilter(collectionID: collection), as: LabDataService.appUI)
        #expect(Set(items.map(\.note.value)) == [
            "The kettle clicked off at seven.\nBlue tape marks the second shelf.\nWater the fern on Thursday.\nThe spare key is in the green tin.",
            "A different caption file.",
        ])
    }

    /// The experiment's Reset and the lab's Reset Demo each leave the person's saved transcript and
    /// an item they made elsewhere exactly as they were. The experiment's Reset removes its own
    /// folder, and nothing else of the person's.
    @Test func resetsLeaveThePersonsTranscriptsAndItemsAlone() async throws {
        let library = try await SpeechHostLab.startedLibrary(in: folder)
        let model = SpeechHostLab.model(in: folder)
        await model.refreshSupport()
        let collection = try #require(await model.createCollection(titled: "Listening notes", in: library))
        let own = ItemDraft(in: collection, title: try EntityTitle("Kept by the person"), note: try ItemNote("Not a transcript."))
        _ = try await library.submit(.createItem(draft: own), requestID: RequestID(), authority: .userAction, names: [:])

        model.loadSampleCaptions()
        #expect(model.correct(model.timeline.segments[0].id, to: "The kettle clicked off at seven sharp."))
        _ = try #require(await model.save(to: collection, in: library))
        let experimentFolder = folder.appending(path: "Speech Timeline")
        try FileManager.default.createDirectory(at: experimentFolder, withIntermediateDirectories: true)
        try Data("a clip".utf8).write(to: experimentFolder.appending(path: SpeechTimelineFolder.sampleClip))
        let service = try await library.openedService()
        let before = try await service.items(try ItemFilter(collectionID: collection), as: LabDataService.appUI)
        #expect(before.count == 2)

        await model.resetExperiment()
        #expect(!FileManager.default.fileExists(atPath: experimentFolder.path(percentEncoded: false)), "the experiment's own folder is removed")
        #expect(try await service.items(try ItemFilter(collectionID: collection), as: LabDataService.appUI) == before)

        let reset = try #require(await library.resetDemo())
        #expect(reset.receipt.status == .committed)
        #expect(try await service.items(try ItemFilter(collectionID: collection), as: LabDataService.appUI) == before)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: LabStoreLocation.fileName).path(percentEncoded: false)), "the store is untouched")
    }
}

// MARK: - Support

/// The pieces each Speech Timeline host test builds the same way.
@MainActor
enum SpeechHostLab {
    static func startedLibrary(in folder: URL) async throws -> LabLibrary {
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        return library
    }

    /// A model over `folder`, with English (US) installed unless another recognizer is given.
    static func model(
        in folder: URL,
        recognizer: any SpeechFileRecognizing = PacedRecognizer(pause: nil),
        capture: any SpeechCapturing = ScriptedRuns([]),
        stager: PermissionStager = .live()
    ) -> SpeechTimelineModel {
        let experimentFolder = folder.appending(path: "Speech Timeline")
        return SpeechTimelineModel(
            recognizer: recognizer, installer: NoDownload(), capture: capture, stager: stager,
            locateFolder: {
                try FileManager.default.createDirectory(at: experimentFolder, withIntermediateDirectories: true)
                return experimentFolder
            }
        )
    }

    /// A stager whose permission source reports the microphone in `status`, with the purpose
    /// string and the Mac entitlement declared, and a requester that would allow it. No prompt and
    /// no microphone: the capture it opens is scripted.
    static func microphoneAllowed(status: PermissionStatus = .authorized) -> PermissionStager {
        PermissionStager(platform: .macOS, source: MicrophoneDeclared(status: status), requester: AllowingRequester())
    }

    static func waitUntilIdle(_ model: SpeechTimelineModel, limit: Duration = .seconds(30)) async throws {
        try await waitUntil(limit: limit) { !model.isBusy }
    }

    static func waitUntil(limit: Duration = .seconds(30), _ condition: () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + limit
        while await !condition() {
            try #require(clock.now < deadline, "the condition did not hold within \(limit)")
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    static func onlyItem(in collection: CollectionID, library: LabLibrary) async throws -> LabItem {
        let service = try await library.openedService()
        let items = try await service.items(try ItemFilter(collectionID: collection), as: LabDataService.appUI)
        try #require(items.count == 1)
        return items[0]
    }
}

func speechRange(_ start: Int, _ end: Int) -> MediaTimeRange {
    try! MediaTimeRange(startMilliseconds: start, endMilliseconds: end)
}

func speechGuess(_ start: Int, _ end: Int, _ text: String) -> RecognizerUpdate {
    .provisional(range: speechRange(start, end), text: text)
}

func speechFinal(_ start: Int, _ end: Int, _ text: String) -> RecognizerUpdate {
    .final(range: speechRange(start, end), text: text, words: [])
}

/// A recognizer with English (US) installed that replays the update sequence the transcriber
/// produced on the development Mac (LAB-013-A), optionally pausing between results.
struct PacedRecognizer: SpeechFileRecognizing {
    static let updates: [RecognizerUpdate] = [
        speechGuess(1_680, 5_520, "Blue tape"),
        speechGuess(1_680, 5_520, "Blue tape marks the 2nd shelf."),
        speechFinal(1_680, 3_960, "Blue tape marks the 2nd shelf."),
        speechGuess(3_960, 5_520, "Water"),
        speechGuess(3_960, 5_520, "Water the fern on Thursday."),
        speechFinal(3_960, 5_520, "Water the fern on Thursday."),
    ]

    let pause: Duration?

    func languages() async -> LanguageSupport {
        LanguageSupport(transcriberAvailable: true, supported: ["en-US"], installed: ["en-US"])
    }

    func transcribe(file: URL, language: String, onUpdate: @escaping @Sendable (RecognizerUpdate) async -> Void) async throws(RecognitionFailure) -> Int {
        for update in Self.updates {
            if Task.isCancelled { throw .cancelled }
            await onUpdate(update)
            if let pause {
                do { try await Task.sleep(for: pause) } catch { throw .cancelled }
            }
        }
        return 5_520
    }
}

/// A capture that replays one scripted run per start. A run that does not end on its own stays
/// open until `stop()`, which sends `ended`, as the person pressing Stop Recording does. After the
/// scripted runs, a start fails with `failAfterRuns` if one is given.
actor ScriptedRuns: SpeechCapturing {
    private var runs: [[CaptureEvent]]
    private let failAfterRuns: RecognitionFailure?
    private var open: AsyncStream<CaptureEvent>.Continuation?
    private(set) var starts = 0

    init(_ runs: [[CaptureEvent]], failAfterRuns: RecognitionFailure? = nil) {
        self.runs = runs
        self.failAfterRuns = failAfterRuns
    }

    func start(language: String) async throws(RecognitionFailure) -> AsyncStream<CaptureEvent> {
        guard !runs.isEmpty else { throw failAfterRuns ?? .engineFailed }
        starts += 1
        let events = runs.removeFirst()
        let (stream, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        for event in events { continuation.yield(event) }
        switch events.last {
        case .routeChanged?, .interrupted?, .failed?, .ended?:
            continuation.finish()
        default:
            open = continuation
        }
        return stream
    }

    func stop() async {
        open?.yield(.ended)
        open?.finish()
        open = nil
    }
}

/// Reports the microphone in a given state, with its purpose string and the Mac entitlement.
struct MicrophoneDeclared: CapabilitySource {
    let status: PermissionStatus

    var isSimulator: Bool { false }
    func permissionStatus(_ permission: PermissionKind) -> PermissionStatus { permission == .microphone ? status : .notDetermined }
    func hasCaptureDevice(_ kind: CaptureDeviceKind) -> Bool? { true }
    func speechTranscription() async -> SpeechTranscriptionReading {
        SpeechTranscriptionReading(transcriberAvailable: true, localeIdentifier: "en_US", asset: .installed)
    }
    func languageModel() -> LanguageModelReading {
        LanguageModelReading(availability: .notCompiled, supportsCurrentLocale: nil, localeIdentifier: "en_US")
    }
    func worldTracking() -> WorldTrackingReading? { nil }
    func ultraWideband() -> UltraWidebandReading? { nil }
    func entitlement(_ key: String) -> EntitlementReading { .present }
    func declaresPurposeString(_ key: String) -> Bool { true }
}

/// Answers a prompt with "allowed" and counts it. Never shows anything.
final class AllowingRequester: PermissionRequesting {
    private let count = Mutex(0)
    var requests: Int { count.withLock { $0 } }

    func request(_ permission: PermissionKind) async -> PermissionStatus {
        count.withLock { $0 += 1 }
        return .authorized
    }
}

struct NoDownload: SpeechModelInstalling {
    func install(language: String, progress: @escaping @Sendable (Double) -> Void) async throws(RecognitionFailure) {
        throw .downloadFailed
    }
}
