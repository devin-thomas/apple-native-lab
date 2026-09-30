import AVFoundation
import Foundation
import LabDomain
import LabSupport
import Observation
import SpeechTimeline

/// The Speech Timeline session (LAB-013): one timeline, the audio it refers to, and what is
/// running, kept outside any view.
///
/// There is one model for the app, so leaving the experiment and coming back, switching windows,
/// or rotating the phone never drops a transcript or a recording in progress. Transcription runs
/// off the main actor through `SpeechTimelineFlow` and is cancellable. The microphone is reached
/// only from `record()`, through `RecordingGate`. A model download starts only from
/// `downloadModel()`. Saving is the only step that writes to the store.
@MainActor
@Observable
final class SpeechTimelineModel {
    static let shared = SpeechTimelineModel()

    enum Activity: Equatable {
        case idle
        case preparingClip
        case transcribing
        case recording
        case downloading(Double)
    }

    /// Where the timeline on screen came from. Shown beside it, so a caption import or a hand
    /// annotation is never read as recognition.
    enum Source: Equatable {
        case none
        case sampleClip
        case importedAudio
        case captions
        case manual
        case recording

        var label: String {
            switch self {
            case .none: "Nothing loaded"
            case .sampleClip: "Sample clip, synthesized on this device, transcribed on device"
            case .importedAudio: "Your audio file, transcribed on device"
            case .captions: "Imported captions (not recognition)"
            case .manual: "Annotated by hand (not recognition)"
            case .recording: "Recording, transcribed on device as you speak"
            }
        }
    }

    private(set) var activity: Activity = .idle
    private(set) var source: Source = .none
    private(set) var timeline = TranscriptTimeline()
    private(set) var audio: AudioReference = .none
    private(set) var audioURL: URL?
    private(set) var audioDuration: Int?
    private(set) var support: LanguageSupport?
    private(set) var recording = RecordingSession()
    /// Why the last step failed or what it left, as a sentence for the person.
    private(set) var message: String?
    /// The last transcription's counts, for the "How this works" line.
    private(set) var lastRun: TranscriptionRun?
    /// The playhead, in milliseconds of the audio or timeline.
    var playhead = 0
    private(set) var isPlaying = false
    private(set) var collections: [LabCollection] = []
    /// The receipt of the latest save and the timeline revision it captured.
    private(set) var lastSave: (revision: Int, record: ReceiptRecord)?
    var language = SpeechFixture.language

    @ObservationIgnored private let flow: SpeechTimelineFlow
    @ObservationIgnored private let installer: any SpeechModelInstalling
    @ObservationIgnored private let capture: any SpeechCapturing
    @ObservationIgnored private let gate: RecordingGate
    @ObservationIgnored private let locateFolder: () throws -> URL
    @ObservationIgnored private let bundle: Bundle
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var runToken = 0
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var playheadTask: Task<Void, Never>?
    /// The save prepared for a revision and collection, kept so pressing Save again is a retry.
    @ObservationIgnored private var pendingSave: TranscriptSave?

    init(
        recognizer: any SpeechFileRecognizing = OnDeviceSpeechRecognizer(),
        installer: any SpeechModelInstalling = OnDeviceModelInstaller(),
        capture: any SpeechCapturing = OnDeviceSpeechCapture(),
        stager: PermissionStager = .live(),
        locateFolder: @escaping () throws -> URL = SpeechTimelineFolder.url,
        bundle: Bundle = .main
    ) {
        flow = SpeechTimelineFlow(recognizer: recognizer, diagnostics: SpeechTimelineDiagnostics.log)
        self.installer = installer
        self.capture = capture
        gate = RecordingGate(stager: stager)
        self.locateFolder = locateFolder
        self.bundle = bundle
    }

    // MARK: State for views

    var isBusy: Bool { activity != .idle }

    var languageState: LanguageSupport.State? { support?.state(for: language) }

    var canTranscribe: Bool { !isBusy && languageState == .installed }

    /// The sample is in the fixtures' language, whatever the picker shows.
    var canTranscribeSample: Bool {
        SampleClipRenderer.isCompiled && support?.state(for: SpeechFixture.language) == .installed
    }

    /// The media time the scrubber covers: the audio, or the timeline when there is no audio.
    var scrubLength: Int { max(audioDuration ?? 0, timeline.endMilliseconds, 1) }

    var currentSegment: TranscriptSegment? { timeline.segment(at: playhead) }

    /// Whether the save on record still matches the timeline on screen.
    var isSaved: Bool { lastSave?.revision == timeline.revision && !timeline.segments.isEmpty }

    /// Languages to offer: every supported one, plus the fixtures' language, so an unsupported
    /// choice is stated rather than hidden.
    var languageChoices: [String] {
        let supported = support?.supported ?? []
        return Array(Set(supported + [SpeechFixture.language, LanguageSupport.normalized(Locale.current.identifier)])).sorted {
            LanguageSupport.name($0).localizedStandardCompare(LanguageSupport.name($1)) == .orderedAscending
        }
    }

    // MARK: Readiness

    /// Reads which languages this device can transcribe. Never prompts and never downloads.
    func refreshSupport() async {
        support = await flow.languages()
    }

    // MARK: Transcription

    /// Speaks the sample script with this device's synthesizer, then transcribes the clip.
    func transcribeSample() {
        guard !isBusy else { return }
        let token = beginRun(.preparingClip)
        work = Task {
            do {
                let folder = try locateFolder()
                guard let scriptURL = SpeechFixture.sampleScript.url(in: bundle) else { throw SpeechFixtureError.unreadable }
                let script = try SpeechFixture.script(at: scriptURL)
                let clip = folder.appending(path: SpeechTimelineFolder.sampleClip)
                let duration = try await SampleClipRenderer.render(script, language: SpeechFixture.language, to: clip)
                guard token == runToken else { return }
                language = SpeechFixture.language
                let reference = try await Self.reference(for: clip, origin: .synthesizedSample, duration: duration)
                guard token == runToken else { return }
                await transcribe(clip, reference: reference, source: .sampleClip, token: token)
            } catch {
                guard token == runToken else { return }
                finish(message: Self.describe(error))
            }
        }
    }

    /// Copies a file the person chose into the experiment's folder, then transcribes the copy.
    func importAudio(from url: URL) {
        guard !isBusy else { return }
        let token = beginRun(.transcribing)
        work = Task {
            do {
                let copy = try await Self.copyIntoFolder(url, folder: try locateFolder())
                let reference = try await Self.reference(for: copy, origin: .importedFile, duration: nil)
                guard token == runToken else { return }
                await transcribe(copy, reference: reference, source: .importedAudio, token: token)
            } catch {
                guard token == runToken else { return }
                finish(message: Self.describe(error))
            }
        }
    }

    /// Stops a transcription or a clip in progress. Finalized segments stay.
    func cancel() {
        work?.cancel()
    }

    private func transcribe(_ file: URL, reference: AudioReference, source: Source, token: Int) async {
        activity = .transcribing
        self.source = source
        audioURL = file
        audio = reference
        timeline = TranscriptTimeline()
        lastSave = nil
        let run = await flow.transcribe(file: file, language: language) { [weak self] snapshot in
            await self?.show(snapshot, token: token)
        }
        guard token == runToken else { return }
        timeline = run.timeline
        lastRun = run
        audioDuration = run.durationMilliseconds
        audio = AudioReference(origin: reference.origin, sha256: reference.sha256,
                               durationMilliseconds: run.durationMilliseconds, fileType: reference.fileType)
        finish(message: run.failure?.message)
        LabAnnouncement(text: run.failure?.message ?? "Transcribed \(Self.count(run.timeline.segments.count)).").post()
    }

    private func show(_ snapshot: TranscriptTimeline, token: Int) {
        guard token == runToken else { return }
        timeline = snapshot
    }

    // MARK: The fallback: captions and annotation

    func loadSampleCaptions() {
        guard let url = SpeechFixture.sampleCaptions.url(in: bundle) else {
            message = SpeechFixtureError.unreadable.message
            return
        }
        importCaptions(from: url)
    }

    /// Reads a WebVTT file into a timeline of caption segments. A refused file changes nothing.
    func importCaptions(from url: URL) {
        guard !isBusy else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= SpeechTimelineLimits.documentBytes else {
                message = CaptionError.tooLarge(limit: SpeechTimelineLimits.documentBytes).message
                return
            }
            let imported = try CaptionDocument.timeline(from: CaptionDocument.parse(Data(contentsOf: url)))
            runToken += 1
            timeline = imported
            source = .captions
            lastSave = nil
            if audioURL == nil { audio = .none }
            message = "Imported \(Self.count(imported.segments.count)) from captions. They are not recognition."
        } catch let error as CaptionError {
            message = error.message
        } catch {
            message = "The caption file could not be read. Nothing changed."
        }
    }

    /// Starts an empty timeline to annotate by hand. The loaded audio, if any, stays for scrubbing.
    func startManual() {
        guard !isBusy else { return }
        runToken += 1
        timeline = TranscriptTimeline()
        source = .manual
        lastSave = nil
        message = nil
    }

    @discardableResult
    func annotate(start: Int, end: Int, text: String) -> Bool {
        do {
            let range = try MediaTimeRange(startMilliseconds: start, endMilliseconds: end)
            try timeline.annotate(range, text: text)
            if source == .none { source = .manual }
            message = nil
            return true
        } catch {
            message = error.message
            return false
        }
    }

    // MARK: Corrections

    @discardableResult
    func correct(_ id: SegmentID, to text: String) -> Bool {
        do {
            try timeline.correct(id, to: text)
            message = nil
            return true
        } catch {
            message = error.message
            return false
        }
    }

    func revert(_ id: SegmentID) {
        try? timeline.revert(id)
    }

    // MARK: Recording

    /// The person pressed Record. Only here may the microphone be asked for.
    func record() async {
        guard !isBusy else { return }
        switch await gate.decide() {
        case .fallback(let reason, let fallback):
            message = "\(reason) \(fallback.summary)"
            LabAnnouncement(text: message ?? reason, priority: .high).post()
            return
        case .record:
            break
        }
        if source != .recording {
            runToken += 1
            timeline = TranscriptTimeline()
            recording = RecordingSession()
            audioURL = nil
            audioDuration = nil
            lastSave = nil
        }
        let token = runToken
        audio = AudioReference(origin: .recording, sha256: nil, durationMilliseconds: nil, fileType: nil)
        source = .recording
        activity = .recording
        message = nil
        recording.beginRun(on: timeline)
        let events: AsyncStream<CaptureEvent>
        do {
            events = try await capture.start(language: language)
        } catch {
            recording.handle(.failed(error), timeline: &timeline)
            finish(message: error.message)
            return
        }
        work = Task {
            for await event in events {
                guard token == runToken else { return }
                recording.handle(event, timeline: &timeline)
            }
            guard token == runToken else { return }
            finish(message: recording.summary(segments: timeline.segments.count))
        }
    }

    func stopRecording() async {
        await capture.stop()
    }

    // MARK: Model download

    /// Downloads the chosen language's on-device model. Only this button starts a download.
    func downloadModel() {
        guard !isBusy, languageState == .downloadable else { return }
        activity = .downloading(0)
        let language = language
        work = Task {
            do {
                try await installer.install(language: language) { fraction in
                    Task { @MainActor in
                        guard case .downloading = self.activity else { return }
                        self.activity = .downloading(fraction)
                    }
                }
                await refreshSupport()
                finish(message: "The model for \(LanguageSupport.name(language)) is installed.")
            } catch {
                finish(message: Self.describe(error))
            }
        }
    }

    // MARK: Saving and exporting

    func loadCollections(from library: LabLibrary) async {
        do {
            collections = try await LibrarySpeechBackend(library: library).destinations()
        } catch {
            collections = []
            message = error.message
        }
    }

    /// Creates a collection of the person's own through the operation service.
    @discardableResult
    func createCollection(titled title: String, in library: LabLibrary) async -> CollectionID? {
        let draft: CollectionDraft
        do {
            draft = CollectionDraft(title: try EntityTitle(title))
        } catch {
            message = "A collection needs a title of 1 to \(EntityTitle.maximumLength) characters."
            return nil
        }
        do {
            _ = try await library.submit(
                .createCollection(draft: draft), requestID: RequestID(), authority: .userAction,
                names: [.collection(draft.id): draft.title.value]
            )
        } catch {
            message = SpeechSaveError(error).message
            return nil
        }
        await loadCollections(from: library)
        return draft.id
    }

    /// Saves the finalized segments as one item in `collectionID`, through the operation service
    /// as the app UI. Pressing Save again for the same revision and collection is a retry.
    @discardableResult
    func save(to collectionID: CollectionID, in library: LabLibrary) async -> ReceiptRecord? {
        let save: TranscriptSave
        if let pending = pendingSave, pending.revision == timeline.revision, pending.collectionID == collectionID {
            save = pending
        } else {
            do {
                save = try TranscriptSave.prepare(
                    timeline, audio: audio, language: language, title: saveTitle, into: collectionID
                )
            } catch {
                message = error.message
                return nil
            }
            pendingSave = save
        }
        do {
            let receipt = try await LibrarySpeechBackend(library: library).commit(save)
            guard let record = library.receipt(id: receipt.operationID) else { return nil }
            lastSave = (save.revision, record)
            message = save.noteWasShortened
                ? "Saved. The item's note holds the start of the text; its extras hold every segment."
                : nil
            LabAnnouncement(receipt: ReceiptPresentation(record)).post()
            return record
        } catch {
            message = error.message
            LabAnnouncement(failure: error.message).post()
            return nil
        }
    }

    var saveTitle: String {
        switch source {
        case .sampleClip: "Transcript: sample clip"
        case .importedAudio: "Transcript: imported audio"
        case .captions: "Captions"
        case .manual: "Annotated timeline"
        case .recording: "Transcript: recording"
        case .none: "Transcript"
        }
    }

    func captionExport() -> Data {
        Data(CaptionDocument.render(timeline).utf8)
    }

    func timelineExport() throws -> Data {
        try TimelineExport(timeline: timeline, audio: audio, language: language).encoded()
    }

    // MARK: Playback and scrubbing

    var canPlay: Bool { audioURL != nil && !isBusy }

    func play(from milliseconds: Int? = nil) {
        guard let audioURL, !isBusy else { return }
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            if player?.url != audioURL { player = try AVAudioPlayer(contentsOf: audioURL) }
            if let milliseconds { playhead = milliseconds }
            player?.currentTime = Double(playhead) / 1_000
            player?.play()
            isPlaying = true
            followPlayhead()
        } catch {
            message = "The audio could not be played."
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        playheadTask?.cancel()
    }

    /// Moves the playhead, as the scrubber or a segment does.
    func seek(to milliseconds: Int) {
        playhead = min(max(0, milliseconds), scrubLength)
        if isPlaying { player?.currentTime = Double(playhead) / 1_000 }
    }

    private func followPlayhead() {
        playheadTask?.cancel()
        playheadTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player else { return }
                self.playhead = Int(player.currentTime * 1_000)
                if !player.isPlaying {
                    self.isPlaying = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    // MARK: Reset

    /// Removes only this experiment's own state: the clip, any imported audio copy, and the
    /// session on screen. Saved transcripts are the person's items and stay.
    func resetExperiment() async {
        runToken += 1
        work?.cancel()
        if activity == .recording { await capture.stop() }
        pause()
        player = nil
        if let folder = try? locateFolder() { try? FileManager.default.removeItem(at: folder) }
        timeline = TranscriptTimeline()
        recording = RecordingSession()
        source = .none
        audio = .none
        audioURL = nil
        audioDuration = nil
        lastRun = nil
        lastSave = nil
        pendingSave = nil
        playhead = 0
        activity = .idle
        message = "Speech Timeline was reset. Saved transcripts in your collections were not changed."
    }

    // MARK: Internals

    private func beginRun(_ activity: Activity) -> Int {
        runToken += 1
        pause()
        self.activity = activity
        message = nil
        return runToken
    }

    private func finish(message: String?) {
        activity = .idle
        work = nil
        self.message = message
    }

    static func count(_ segments: Int) -> String { segments == 1 ? "1 segment" : "\(segments) segments" }

    static func describe(_ error: any Error) -> String {
        switch error {
        case let error as RecognitionFailure: error.message
        case let error as SampleClipError: error.message
        case let error as SpeechFixtureError: error.message
        case let error as ImportedAudioError: error.message
        default: "The audio could not be prepared. Nothing changed."
        }
    }

    /// Hashes a clip off the main actor.
    @concurrent
    nonisolated static func reference(for file: URL, origin: AudioReference.Origin, duration: Int?) async throws -> AudioReference {
        try AudioReference.file(at: file, origin: origin, durationMilliseconds: duration)
    }

    /// Copies a chosen file into the folder, replacing the previous import, within the size limit,
    /// off the main actor.
    @concurrent
    nonisolated static func copyIntoFolder(_ url: URL, folder: URL) async throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= SpeechTimelineLimits.audioBytes else { throw ImportedAudioError.tooLarge }
        let fileType = String(url.pathExtension.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(8))
        let copy = folder.appending(path: "imported-audio" + (fileType.isEmpty ? "" : ".\(fileType)"))
        for existing in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where existing.lastPathComponent.hasPrefix("imported-audio") {
            try? FileManager.default.removeItem(at: existing)
        }
        do {
            try FileManager.default.copyItem(at: url, to: copy)
        } catch {
            throw ImportedAudioError.unreadable
        }
        return copy
    }
}

enum ImportedAudioError: Error {
    case tooLarge
    case unreadable

    var message: String {
        switch self {
        case .tooLarge: RecognitionFailure.audioTooLarge.message
        case .unreadable: RecognitionFailure.audioUnreadable.message
        }
    }
}
