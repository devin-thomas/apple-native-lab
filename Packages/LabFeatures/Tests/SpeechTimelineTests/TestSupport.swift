import Foundation
import LabDomain
import LabSupport
import Synchronization
import Testing
@testable import SpeechTimeline

/// Files in this repository, found from this source file's location.
enum Repository {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // SpeechTimelineTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LabFeatures
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent()

    static func speech(_ name: String) -> URL {
        root.appending(path: "Fixtures/speech/\(name)")
    }

    static func fixture(_ fixture: SpeechFixture) -> URL {
        speech(fixture.fileName)
    }
}

func range(_ start: Int, _ end: Int) -> MediaTimeRange {
    // Test ranges are literals known to be valid.
    try! MediaTimeRange(startMilliseconds: start, endMilliseconds: end)
}

func provisional(_ start: Int, _ end: Int, _ text: String) -> RecognizerUpdate {
    .provisional(range: range(start, end), text: text)
}

func final(_ start: Int, _ end: Int, _ text: String, words: [TimedWord] = []) -> RecognizerUpdate {
    .final(range: range(start, end), text: text, words: words)
}

/// The update sequence `SpeechTranscriber` produced for a synthesized clip of two sentences on
/// the development Mac (LAB-013-A probe), rounded to milliseconds: growing guesses over a range,
/// a final result for its first part, then a new guess from the finalization time.
enum ObservedSequence {
    static let updates: [RecognizerUpdate] = [
        provisional(1_680, 5_520, "Blue tape"),
        provisional(1_680, 5_520, "Blue tape marks the 2"),
        provisional(1_680, 5_520, "Blue tape marks the 2nd shelf."),
        final(1_680, 3_960, "Blue tape marks the 2nd shelf.", words: [
            TimedWord(range: range(1_680, 1_920), text: "Blue"),
            TimedWord(range: range(1_920, 2_340), text: "tape"),
            TimedWord(range: range(2_340, 2_700), text: "marks"),
            TimedWord(range: range(2_700, 2_820), text: "the"),
            TimedWord(range: range(2_820, 3_120), text: "2nd"),
            TimedWord(range: range(3_120, 3_900), text: "shelf."),
        ]),
        provisional(3_960, 5_520, "Water"),
        provisional(3_960, 5_520, "Water the fern on Thursday."),
        final(3_960, 5_520, "Water the fern on Thursday."),
    ]
}

/// A recognizer that replays scripted updates, optionally waiting between them, then finishes or
/// fails as told. It counts calls, so a test can show nothing ran.
final class ScriptedRecognizer: SpeechFileRecognizing {
    let updates: [RecognizerUpdate]
    let support: LanguageSupport
    let failure: RecognitionFailure?
    let pause: Duration?
    private let calls = Mutex(0)

    init(
        _ updates: [RecognizerUpdate] = ObservedSequence.updates,
        support: LanguageSupport = LanguageSupport(transcriberAvailable: true, supported: ["en-US", "fr-FR"], installed: ["en-US"]),
        failure: RecognitionFailure? = nil,
        pause: Duration? = nil
    ) {
        self.updates = updates
        self.support = support
        self.failure = failure
        self.pause = pause
    }

    var callCount: Int { calls.withLock { $0 } }

    func languages() async -> LanguageSupport { support }

    func transcribe(
        file: URL,
        language: String,
        onUpdate: @escaping @Sendable (RecognizerUpdate) async -> Void
    ) async throws(RecognitionFailure) -> Int {
        calls.withLock { $0 += 1 }
        switch support.state(for: language) {
        case .installed: break
        case .downloadable: throw .modelNotInstalled(language)
        case .unsupported: throw .unsupportedLanguage(language)
        case .transcriberUnavailable: throw support.transcriberAvailable == nil ? .notCompiled : .transcriberUnavailable
        }
        for update in updates {
            if Task.isCancelled { throw .cancelled }
            await onUpdate(update)
            if let pause {
                do { try await Task.sleep(for: pause) } catch { throw .cancelled }
            }
        }
        if let failure { throw failure }
        return 5_520
    }
}

/// Permission facts without a device. Nothing here prompts.
struct FakeCapabilitySource: CapabilitySource {
    var microphone: PermissionStatus = .notDetermined
    var purposeStrings: Set<String> = ["NSMicrophoneUsageDescription"]
    var entitlements: Set<String> = ["com.apple.security.device.audio-input"]

    var isSimulator: Bool { false }
    func permissionStatus(_ permission: PermissionKind) -> PermissionStatus {
        permission == .microphone ? microphone : .notDetermined
    }
    func hasCaptureDevice(_ kind: CaptureDeviceKind) -> Bool? { true }
    func speechTranscription() async -> SpeechTranscriptionReading {
        SpeechTranscriptionReading(transcriberAvailable: true, localeIdentifier: "en_US", asset: .installed)
    }
    func languageModel() -> LanguageModelReading {
        LanguageModelReading(availability: .notCompiled, supportsCurrentLocale: nil, localeIdentifier: "en_US")
    }
    func worldTracking() -> WorldTrackingReading? { nil }
    func ultraWideband() -> UltraWidebandReading? { nil }
    func entitlement(_ key: String) -> EntitlementReading { entitlements.contains(key) ? .present : .absent }
    func declaresPurposeString(_ key: String) -> Bool { purposeStrings.contains(key) }
}

/// Counts every system prompt the stager shows, and answers with a fixed status.
final class CountingRequester: PermissionRequesting {
    let answer: PermissionStatus
    private let requests = Mutex<[PermissionKind]>([])

    init(answer: PermissionStatus = .authorized) { self.answer = answer }

    var requested: [PermissionKind] { requests.withLock { $0 } }

    func request(_ permission: PermissionKind) async -> PermissionStatus {
        requests.withLock { $0.append(permission) }
        return answer
    }
}

/// A capture that replays scripted events and records whether it was started and stopped.
actor ScriptedCapture: SpeechCapturing {
    private let events: [CaptureEvent]
    private(set) var starts = 0
    private(set) var stops = 0

    init(_ events: [CaptureEvent]) { self.events = events }

    func start(language: String) async throws(RecognitionFailure) -> AsyncStream<CaptureEvent> {
        starts += 1
        let events = events
        return AsyncStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    func stop() async { stops += 1 }
}

/// A save backend over a real operation service and an in-memory store, committing as the app UI
/// the way the hosts do through `LabLibrary.submit`.
struct ServiceSpeechBackend: SpeechTimelineBackend {
    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    let service: OperationService
    let actor: ActorScope

    func destinations() async throws(SpeechSaveError) -> [LabCollection] { [] }

    func commit(_ save: TranscriptSave) async throws(SpeechSaveError) -> ActionReceipt {
        do {
            return try await service.perform(OperationRequest(id: save.requestID, operation: save.operation, actor: actor))
        } catch {
            throw .refused(error)
        }
    }
}

/// A store and service with one collection of the person's own.
struct Lab {
    let store = InMemoryOperationStore()
    let service: OperationService
    let collection = CollectionDraft(title: try! EntityTitle("Listening notes"))

    init() {
        service = OperationService(store: store)
    }

    static func withCollection() async throws -> Lab {
        let lab = Lab()
        _ = try await lab.service.perform(OperationRequest(
            id: RequestID(), operation: .createCollection(draft: lab.collection), actor: ServiceSpeechBackend.appUI
        ))
        return lab
    }

    var appUI: ServiceSpeechBackend { ServiceSpeechBackend(service: service, actor: ServiceSpeechBackend.appUI) }
}

/// A timeline built from the observed sequence.
func observedTimeline() -> TranscriptTimeline {
    var timeline = TranscriptTimeline()
    for update in ObservedSequence.updates { timeline.apply(update) }
    return timeline
}
