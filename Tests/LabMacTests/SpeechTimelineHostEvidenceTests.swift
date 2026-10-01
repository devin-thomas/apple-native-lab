import CryptoKit
import Foundation
import LabDomain
import LabStore
import LabSupport
import SpeechTimeline
import Testing
@testable import NativeLab

/// LAB-013-B step 1 with its evidence: the complete Speech Timeline interaction in the sandboxed
/// Mac app, from clean state, through the app's own `SpeechTimelineModel`, `LabLibrary`, and a
/// fresh SQLite store and experiment folder. Each test attaches an `EvidenceRecord` of what it
/// observed, with the toolchain read from this app bundle. To keep them, run with a result bundle
/// and export the attachments:
///
///     [TEST_RUNNER_LAB_LIVE_SPEECH=1] xcodebuild … -scheme LabMac-Core \
///       -only-testing:LabMacTests/SpeechTimelineHostEvidenceTests -resultBundlePath <bundle> \
///       LAB_SOURCE_REVISION=<sha> test
///     xcrun xcresulttool export attachments --path <bundle> --output-path <folder>
///
/// No test here opens a microphone. The fixture interaction gets past Record with a permission
/// source that reports the microphone allowed and a scripted capture; the live tests use this
/// build's real permission stager, which falls back.
@MainActor
@Suite struct SpeechTimelineHostEvidenceTests {
    static let interactionCheck = "Speech Timeline's complete interaction in the Mac host from clean state: the unavailable path and caption fallback, transcription with provisional text, corrections, both exports, a recording paused by a route change and resumed, saves with app-UI receipts, and both resets beside the person's items"

    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "SpeechTimelineHostEvidenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    @Test func theInteractionRunsInTheAppFromCleanState() async throws {
        let started = Date()
        var observations: [String] = []
        var differences: [String] = []
        func check(_ same: Bool, _ what: String) {
            #expect(same, "\(what)")
            if same { observations.append(what) } else { differences.append(what) }
        }
        let library = try await SpeechHostLab.startedLibrary(in: folder)
        let collection = try #require(await SpeechHostLab.model(in: folder).createCollection(titled: "Listening notes", in: library))
        let own = ItemDraft(in: collection, title: try EntityTitle("Kept by the person"), note: try ItemNote("Not a transcript."))
        _ = try await library.submit(.createItem(draft: own), requestID: RequestID(), authority: .userAction, names: [:])

        // 1. The transcriber unavailable: stated, the on-device routes closed, the fallback works.
        let unavailable = SpeechHostLab.model(in: folder, recognizer: NoTranscriberHere())
        await unavailable.refreshSupport()
        check(unavailable.support?.statement(for: "en-US") == "On-device transcription is not available on this device."
              && !unavailable.canTranscribe && !unavailable.canTranscribeSample, "unavailable: stated, and Transcribe, Import Audio, and Record are closed")
        unavailable.loadSampleCaptions()
        check(unavailable.source == .captions && unavailable.timeline.segments.count == 4
              && unavailable.timeline.segments.allSatisfy { $0.source == .captionImport }, "the caption fixture: 4 segments labeled as imported captions")
        let cue = unavailable.timeline.segments[0]
        check(unavailable.correct(cue.id, to: "The kettle clicked off at seven sharp.")
              && unavailable.timeline.segment(cue.id)?.range == cue.range, "a caption correction kept its time")
        check(unavailable.annotate(start: 8_000, end: 9_500, text: "Added by hand.")
              && !unavailable.annotate(start: 1_000, end: 2_000, text: "Overlaps."), "an annotation was added and an overlapping one refused")
        let captionsSave = await unavailable.save(to: collection, in: library)
        check(captionsSave?.receipt.status == .committed && captionsSave?.receipt.admitted.adapter == .appUI, "the fallback saved with an app-UI receipt")

        // 2. Transcription (scripted recognizer with the observed sequence): provisional, then final.
        let audio = folder.appending(path: "chosen.caf")
        try Data("audio bytes the scripted recognizer does not decode".utf8).write(to: audio)
        let model = SpeechHostLab.model(in: folder, capture: ScriptedRuns([
            [.update(speechGuess(0, 900, "The kettle")), .update(speechFinal(0, 1_700, "The kettle clicked off at 7.")),
             .update(speechGuess(1_700, 2_400, "Blue tape")), CaptureStop.routeChange(reason: 2)!],
            [.update(speechFinal(0, 2_200, "Blue tape marks the 2nd shelf."))],
        ]), stager: SpeechHostLab.microphoneAllowed())
        await model.refreshSupport()
        model.importAudio(from: audio)
        try await SpeechHostLab.waitUntilIdle(model)
        let run = try #require(model.lastRun)
        check(run.failure == nil && run.provisionalShown == 4 && model.timeline.segments.count == 2 && model.timeline.provisional == nil,
              "transcription: 4 guesses shown, 2 segments, no guess left")
        let audioHash = Self.sha256(try Data(contentsOf: audio))
        check(model.audio.origin == .importedFile && model.audio.sha256 == audioHash,
              "the audio reference is the copy's SHA-256, not its name")

        // 3. Corrections keep time through both exports.
        let segment = model.timeline.segments[0]
        check(model.correct(segment.id, to: "Blue tape marks the second shelf.") && model.timeline.segment(segment.id)?.range == segment.range,
              "a transcript correction kept its time")
        let cues = try CaptionDocument.parse(model.captionExport())
        let exported = try TimelineExport.decode(try model.timelineExport())
        check(cues.map(\.range) == model.timeline.segments.map(\.range) && cues[0].text == "Blue tape marks the second shelf.",
              "the caption export kept the times and the corrected text")
        check(exported.timeline.segments == model.timeline.segments && exported.timeline.segments[0].recognized == "Blue tape marks the 2nd shelf.",
              "the timeline export kept times, word times, and the recognized text")
        let transcriptSave = await model.save(to: collection, in: library)
        let again = await model.save(to: collection, in: library)
        check(transcriptSave?.receipt.status == .committed && again?.id == transcriptSave?.id, "the transcript saved once; Save again returned the same receipt")

        // 4. This build's Record with the real permission stager falls back without capture.
        let closed = ScriptedRuns([[.update(speechFinal(0, 1_000, "Never."))]])
        let thisBuild = SpeechHostLab.model(in: folder, capture: closed)
        await thisBuild.refreshSupport()
        await thisBuild.record()
        let closedStarts = await closed.starts
        check(closedStarts == 0 && thisBuild.message?.hasSuffix(Capability.microphone.fallback.summary) == true,
              "this build's Record fell back with its reason and opened nothing")

        // 5. Record past the gate (scripted capture): a route change pauses, Resume continues.
        await model.record()
        try await SpeechHostLab.waitUntilIdle(model)
        check(model.message?.hasPrefix("Recording paused because the audio route changed: the audio device in use was disconnected. 1 segment kept.") == true
              && SpeechTimelineModel.announcement(for: model.recording, segments: 1)?.priority == .high,
              "the route change paused the recording, kept its segment, and was announced")
        await model.record()
        try await SpeechHostLab.waitUntil { model.activity == .recording }
        await model.stopRecording()
        try await SpeechHostLab.waitUntilIdle(model)
        check(model.timeline.segments.map(\.range) == [speechRange(0, 1_700), speechRange(1_700, 3_900)],
              "Resume continued the same timeline after the kept segment")
        let recordingSave = await model.save(to: collection, in: library)
        check(recordingSave?.receipt.status == .committed, "the recording saved with an app-UI receipt")

        // 6. Both resets leave the person's items alone.
        let service = try await library.openedService()
        let before = try await service.items(try ItemFilter(collectionID: collection), as: LabDataService.appUI)
        check(before.count == 4, "the collection holds 3 saved transcripts and the person's own item")
        await model.resetExperiment()
        let reset = await library.resetDemo()
        let after = try await service.items(try ItemFilter(collectionID: collection), as: LabDataService.appUI)
        check(reset?.receipt.status == .committed && after == before && model.timeline.isEmpty,
              "the experiment's Reset and Reset Demo left all 4 items unchanged")

        // 7. The store, read directly.
        let store = try await SQLiteOperationStore(url: folder.appending(path: LabStoreLocation.fileName))
        let stored = try await store.items(in: collection)
        var committed = 0
        for save in [captionsSave, transcriptSave, recordingSave] {
            guard let requestID = save?.receipt.requestID,
                  let receipt = try await store.receipt(for: requestID) else { continue }
            if receipt.status == .committed && receipt.admitted.adapter == .appUI && receipt.admitted.operation.kind == .createItem { committed += 1 }
        }
        check(stored.count == 4 && stored.allSatisfy { $0.namespace == .user } && committed == 3,
              "the store holds the 4 items as the person's own, and each save's app-UI create-item receipt")

        let captionsData = try Data(contentsOf: try #require(SpeechFixture.sampleCaptions.url(in: .main)))
        let scriptData = try Data(contentsOf: try #require(SpeechFixture.sampleScript.url(in: .main)))
        let record = try EvidenceRecord(
            subject: "LAB-013",
            check: Self.interactionCheck,
            date: started,
            provenance: .current,
            execution: .fixture,
            inputs: [
                "captions:app-bundle/speech-sample-captions.vtt@sha256:\(Self.sha256(captionsData))",
                "script:app-bundle/speech-sample-script.txt@sha256:\(Self.sha256(scriptData))",
                "recognizer:scripted, the update sequence the transcriber produced on the development Mac (LAB-013-A)",
                "capture:scripted, two runs: a route change (old device unavailable) after one final and one guess, then one final and Stop",
            ],
            steps: [
                "xcodebuild -scheme LabMac-Core -only-testing:LabMacTests/SpeechTimelineHostEvidenceTests test",
                "A fresh SQLite store in the app container; Create Collection; one item of the person's own",
                "The transcriber faked unavailable: read the statement; Import Sample Captions; correct a cue; annotate; Save",
                "A scripted recognizer: Import Audio… (a copy in the experiment folder); correct; Export Captions and Export Timeline, read back; Save twice",
                "Record with this build's real permission stager",
                "Record with a permission source reporting the microphone allowed and a scripted capture: a route change; Resume Recording; Stop Recording; Save",
                "Reset Speech Timeline; Reset Demo; the collection and the store read again",
            ],
            outcome: differences.isEmpty
                ? .passed(observed: "All \(observations.count) checks matched. " + observations.joined(separator: "; ") + ".")
                : .failed(observed: "\(differences.count) of \(observations.count + differences.count) checks failed: " + differences.joined(separator: "; ") + "."),
            limitations: [
                "Fixture path: hosted tests in the sandboxed Mac app, on a fresh store in the app container. It supports implemented at most.",
                "The recognizer and the capture are scripted. No microphone was opened, no audio route changed, and no system interruption happened: the route change is the event the capture would send.",
                "The views were not driven here; the session model the views call was. SpeechTimelineViewTests presses the rendered fallback through accessibility.",
                "No physical iPhone or iPad and no iOS simulator ran in this check.",
            ]
        )
        Attachment.record(try Self.json(record), named: "LAB-013-speech-timeline-host-interaction.json")
        #expect(record.result == .passed)
        #expect(record.provenance.xcodeBuild != "unknown" && record.provenance.sdkName.hasPrefix("macosx"))
        #expect(record.supportedState == .implemented)
    }

    /// Live recording in this build, with the real permission stager: blocked on the owner's
    /// decision, never attempted. The test refuses to press Record if this build ever declares the
    /// microphone purpose string, because then the system would prompt.
    @Test func liveRecordingIsBlockedInThisBuild() async throws {
        let started = Date()
        let info = Bundle.main.infoDictionary ?? [:]
        guard info["NSMicrophoneUsageDescription"] == nil else {
            Issue.record("this build declares NSMicrophoneUsageDescription; recording is an owner decision and must be qualified by a person, not this test")
            return
        }
        let capture = ScriptedRuns([[.update(speechFinal(0, 1_000, "Never."))]])
        let model = SpeechHostLab.model(in: folder, capture: capture)
        await model.refreshSupport()
        await model.record()
        let starts = await capture.starts
        let message = model.message ?? ""
        #expect(starts == 0)
        #expect(message.hasSuffix(Capability.microphone.fallback.summary))
        let record = try EvidenceRecord(
            subject: "LAB-013",
            check: "Speech Timeline's live recording path (Record, then OnDeviceSpeechCapture through RecordingGate) in the sandboxed Mac app with this build's real permission stager",
            date: started,
            provenance: .current,
            execution: try Execution(observing: DeviceSnapshot.current),
            inputs: ["build:LabMac-Core source build, Info.plist without NSMicrophoneUsageDescription, no com.apple.security.device.audio-input entitlement"],
            steps: [
                "xcodebuild -scheme LabMac-Core -only-testing:LabMacTests/SpeechTimelineHostEvidenceTests/liveRecordingIsBlockedInThisBuild test",
                "Confirm the app's Info.plist declares no microphone purpose string, so the stager cannot prompt",
                "Press Record through SpeechTimelineModel.record() with PermissionStager.live() and a capture that only counts starts",
            ],
            outcome: .blocked(reason: "Blocked on an owner decision, not failed: live recording needs NSMicrophoneUsageDescription in the source builds and com.apple.security.device.audio-input in the Mac host's entitlements and Config/ProductPolicy.txt, and neither is declared. Record fell back without a prompt, with \(starts) captures started: “\(message)” OnDeviceSpeechCapture, its route-change and interruption observers, and a real route change have never run."),
            limitations: [
                "A blocked record supports no state. It shows the closed route is stated and safe in this build, not that recording works.",
                "The development Mac's own permission state was read by the live stager; no prompt was shown and no microphone was opened.",
                "No physical iPhone or iPad and no iOS simulator ran in this check.",
            ]
        )
        Attachment.record(try Self.json(record), named: "LAB-013-speech-timeline-recording-blocked-mac-app.json")
        #expect(record.result == .blocked)
        #expect(record.supportedState == nil)
    }

    /// The live on-device path inside the sandboxed app, with a record: the synthesizer speaks the
    /// script into the experiment's folder and `SpeechAnalyzer` transcribes it; a correction keeps
    /// its time through both exports and the save. Opt-in, because it needs the transcriber and an
    /// installed English (US) model: `TEST_RUNNER_LAB_LIVE_SPEECH=1`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LAB_LIVE_SPEECH"] == "1"))
    func theSandboxedAppTranscribesCorrectsAndSavesOnDevice() async throws {
        let started = Date()
        let execution = try Execution(observing: DeviceSnapshot.current)
        let library = try await SpeechHostLab.startedLibrary(in: folder)
        let model = SpeechHostLab.model(in: folder, recognizer: OnDeviceSpeechRecognizer())
        await model.refreshSupport()
        try #require(model.canTranscribeSample, "the transcriber or the en-US model is unavailable here")
        var problems: [String] = []

        // Sample the timeline while it changes, as the view would show it.
        let clock = ContinuousClock()
        let start = clock.now
        model.transcribeSample()
        var sampled = 0
        var overlapping = 0
        while model.isBusy {
            if let guess = model.timeline.provisional {
                sampled += 1
                if model.timeline.segments.contains(where: { $0.range.overlaps(guess.range) }) { overlapping += 1 }
            }
            try #require(clock.now - start < .seconds(90), "the transcription did not finish")
            try await Task.sleep(for: .milliseconds(5))
        }
        let elapsed = clock.now - start
        let run = try #require(model.lastRun)
        let segments = model.timeline.segments
        if let failure = run.failure { problems.append("the run failed: \(failure.message)") }
        if segments.count < 3 { problems.append("only \(segments.count) segments") }
        if overlapping > 0 { problems.append("\(overlapping) sampled screens showed a guess over finalized audio") }
        if model.timeline.provisional != nil { problems.append("provisional text remained") }
        if !segments.allSatisfy({ $0.source == .onDeviceTranscriber }) { problems.append("a segment is not labeled as on-device transcription") }

        var corrected = 0
        for segment in segments {
            if model.correct(segment.id, to: "Corrected \(segment.id.rawValue).") && model.timeline.segment(segment.id)?.range == segment.range { corrected += 1 }
        }
        if corrected != segments.count { problems.append("\(segments.count - corrected) corrections moved or were refused") }
        let cues = try CaptionDocument.parse(model.captionExport())
        if cues.map(\.range) != segments.map(\.range) { problems.append("the caption export moved a time") }
        let exported = try TimelineExport.decode(try model.timelineExport())
        if exported.timeline.segments.map(\.range) != segments.map(\.range) || exported.timeline.segments.map(\.recognized) != segments.map(\.recognized) {
            problems.append("the timeline export lost a time or the recognized text")
        }
        let collection = try #require(await model.createCollection(titled: "Transcripts", in: library))
        let saved = await model.save(to: collection, in: library)
        if saved?.receipt.status != .committed || saved?.receipt.admitted.adapter != .appUI { problems.append("the save did not commit as the app UI") }

        let lines = segments.map { "\($0.range) “\($0.recognized)” (\($0.words.count) word times)" }
        let detail = "SpeechTimelineModel.transcribeSample in the sandboxed app: the synthesizer's clip (\(model.audio.durationMilliseconds ?? 0) ms, sha256 \(model.audio.sha256 ?? "none")) transcribed in \(Self.milliseconds(elapsed)) ms including the synthesis; "
            + "\(run.provisionalShown) provisional snapshots, \(run.staleDropped) stale guesses dropped, \(run.refusedFinals) finals refused or repeated; "
            + "\(segments.count) segments: " + lines.joined(separator: "; ")
            + ". The screen was sampled every 5 ms: \(sampled) samples showed a guess, \(overlapping) with a guess over finalized audio. "
            + "All \(corrected) segments corrected without moving; both exports kept every range and recognized text; the save committed as the app UI."
        let scriptData = try Data(contentsOf: try #require(SpeechFixture.sampleScript.url(in: .main)))
        let record = try EvidenceRecord(
            subject: "LAB-013",
            check: "Speech Timeline's on-device path in the sandboxed Mac app: the sample spoken by this Mac's synthesizer, transcribed by SpeechAnalyzer through the app's session model, every segment corrected, both exports read back, and a save",
            date: started,
            provenance: .current,
            execution: execution,
            inputs: ["script:app-bundle/speech-sample-script.txt@sha256:\(Self.sha256(scriptData))", "language:en-US"],
            steps: [
                "TEST_RUNNER_LAB_LIVE_SPEECH=1 xcodebuild -scheme LabMac-Core -only-testing:LabMacTests/SpeechTimelineHostEvidenceTests test",
                "A fresh SQLite store and experiment folder in the app container",
                "Speak and Transcribe the Sample (SpeechTimelineModel.transcribeSample with OnDeviceSpeechRecognizer); sample the timeline every 5 ms while it runs",
                "Correct every segment; Export Captions and Export Timeline, read back; Create Collection; Save",
            ],
            outcome: problems.isEmpty ? .passed(observed: detail) : .failed(observed: problems.joined(separator: "; ") + ". " + detail),
            limitations: [
                "Physical path only in that the real transcriber ran in the real app on this Mac's own hardware. A test drove the session model, not a person in the window, and it says nothing about an iPhone or iPad.",
                "The audio is synthesized speech from the committed script, not a person, and no microphone was opened.",
                "Sampling every 5 ms can miss a snapshot; the package's live test checks every snapshot the flow reports.",
                "Timings are single intervals on a shared build machine, not a benchmark.",
            ]
        )
        Attachment.record(try Self.json(record), named: "LAB-013-speech-timeline-live-mac-app.json")
        #expect(problems.isEmpty, "\(problems.joined(separator: "; "))")
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    private static func json(_ record: EvidenceRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return String(decoding: try encoder.encode(record), as: UTF8.self) + "\n"
    }
}

/// A Mac without the transcriber, as the iOS 27.0 simulator reports itself.
private struct NoTranscriberHere: SpeechFileRecognizing {
    func languages() async -> LanguageSupport { LanguageSupport(transcriberAvailable: false, supported: [], installed: []) }
    func transcribe(file: URL, language: String, onUpdate: @escaping @Sendable (RecognizerUpdate) async -> Void) async throws(RecognitionFailure) -> Int {
        throw .transcriberUnavailable
    }
}
