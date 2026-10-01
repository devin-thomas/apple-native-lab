import LabCatalog
import LabDomain
import SpeechTimeline
import SwiftUI
import UniformTypeIdentifiers

/// Speech Timeline on one page (LAB-013): the sources on top, then the timeline, its scrubber, and
/// saving. iPhone and iPad push it from the experiment's catalog page; the Mac shows the same parts
/// in its window columns (`Apps/Mac/Window/SpeechTimelineColumns.swift`).
struct SpeechTimelineScreen: View {
    @State private var model: SpeechTimelineModel

    init(model: SpeechTimelineModel = .shared) {
        _model = State(initialValue: model)
    }

    var body: some View {
        List {
            SpeechSourcesSections(model: model)
            SpeechTimelineSections(model: model)
        }
        .navigationTitle("Speech Timeline")
        .task { await model.refreshSupport() }
    }
}

// MARK: Sources

/// Language, the on-device routes, and the fallback. Nothing here opens the microphone except
/// Record, and nothing downloads except Download.
struct SpeechSourcesSections: View {
    let model: SpeechTimelineModel
    @State private var importingAudio = false
    @State private var importingCaptions = false
    @State private var confirmingReset = false

    var body: some View {
        Section {
            LanguagePicker(model: model)
            if let support = model.support {
                Label(support.statement(for: model.language), systemImage: symbol(for: model.languageState))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Reading which languages this device can transcribe…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if model.languageState == .downloadable {
                Button("Download Model", systemImage: "arrow.down.circle") { model.downloadModel() }
                    .disabled(model.isBusy)
                    .accessibilityHint("Asks the system to download the on-device model for this language. Nothing else starts a download.")
            }
            if case .downloading(let fraction) = model.activity {
                ProgressView(value: fraction) {
                    Text("Downloading the model")
                }
            }
        } header: {
            Text("Language")
        } footer: {
            Text("Transcription runs on this device only. There is no server route; when a language is not supported here, use captions or annotate by hand.")
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            Button("Speak and Transcribe the Sample", systemImage: "waveform") { model.transcribeSample() }
                .disabled(model.isBusy || !model.canTranscribeSample)
                .accessibilityHint("This device's speech synthesizer speaks the sample script, then the on-device transcriber reads it.")
            Button("Import Audio…", systemImage: "square.and.arrow.down") { importingAudio = true }
                .disabled(!model.canTranscribe)
            RecordButton(model: model)
            if model.activity == .transcribing || model.activity == .preparingClip {
                HStack {
                    ProgressView()
                    Text(model.activity == .preparingClip ? "Speaking the sample…" : "Transcribing on this device…")
                    Spacer()
                    Button("Stop") { model.cancel() }
                }
            }
        } header: {
            Text("Transcribe")
        } footer: {
            Text(model.recording.summary(segments: model.timeline.segments.count))
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            Button("Import Sample Captions", systemImage: "captions.bubble") { model.loadSampleCaptions() }
                .disabled(model.isBusy)
            Button("Import Captions…", systemImage: "doc.text") { importingCaptions = true }
                .disabled(model.isBusy)
            Button("Annotate by Hand", systemImage: "pencil.line") { model.startManual() }
                .disabled(model.isBusy)
        } header: {
            Text("Fallback")
        } footer: {
            Text("Works without the transcriber: import WebVTT captions or type segments against the timeline. Both are labeled as not recognition.")
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            Button("Reset Speech Timeline…", systemImage: "arrow.counterclockwise", role: .destructive) { confirmingReset = true }
        } footer: {
            Text("Removes the sample clip, imported audio, and the timeline on screen. Saved transcripts in your collections stay.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("Reset Speech Timeline?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { Task { await model.resetExperiment() } }
        } message: {
            Text("The sample clip, imported audio, and the timeline on screen are removed. Saved transcripts are not changed.")
        }
        .fileImporter(isPresented: $importingAudio, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { model.importAudio(from: url) }
        }
        .fileImporter(isPresented: $importingCaptions, allowedContentTypes: SpeechExportDocument.captionTypes) { result in
            if case .success(let url) = result { model.importCaptions(from: url) }
        }
    }

    private func symbol(for state: LanguageSupport.State?) -> String {
        switch state {
        case .installed?: "checkmark.circle"
        case .downloadable?: "arrow.down.circle"
        case .unsupported?, .transcriberUnavailable?: "exclamationmark.triangle"
        case nil: "questionmark.circle"
        }
    }
}

struct LanguagePicker: View {
    @Bindable var model: SpeechTimelineModel

    var body: some View {
        Picker("Language", selection: $model.language) {
            ForEach(model.languageChoices, id: \.self) { identifier in
                Text(LanguageSupport.name(identifier)).tag(identifier)
            }
        }
        .disabled(model.isBusy)
    }
}

/// Record and Stop. Record is the only control that may ask for the microphone.
struct RecordButton: View {
    let model: SpeechTimelineModel

    var body: some View {
        if model.activity == .recording {
            Button("Stop Recording", systemImage: "stop.circle") { Task { await model.stopRecording() } }
        } else {
            Button(model.source == .recording ? "Resume Recording" : "Record", systemImage: "mic") {
                Task { await model.record() }
            }
            .disabled(!model.canTranscribe)
            .accessibilityHint("Asks for the microphone only now, then transcribes on this device as you speak. No audio is kept.")
        }
    }
}

// MARK: The timeline

/// The scrubber, the segments with the provisional text after them, annotation, and saving.
struct SpeechTimelineSections: View {
    let model: SpeechTimelineModel
    /// Called with a save's receipt, so the Mac can open it in the inspector.
    var onReceipt: (ReceiptRecord) -> Void = { _ in }

    var body: some View {
        Section {
            Label(model.source.label, systemImage: "info.circle")
                .font(.callout)
            if let message = model.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Scrubber(model: model)
        } header: {
            Text("Timeline")
        }

        Section {
            if model.timeline.isEmpty {
                Text("No segments yet. Transcribe the sample, import captions, or annotate by hand.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.timeline.segments) { segment in
                SegmentRow(model: model, segment: segment)
            }
            if let guess = model.timeline.provisional {
                ProvisionalRow(guess: guess)
            }
        } header: {
            Text("Segments")
        } footer: {
            Text(segmentsFooter)
                .fixedSize(horizontal: false, vertical: true)
        }

        AnnotationSection(model: model)
        SaveSection(model: model, onReceipt: onReceipt)
    }

    private var segmentsFooter: String {
        var parts = ["Provisional text is shown in italics and is never saved or exported."]
        if model.timeline.correctedCount > 0 {
            parts.append("\(model.timeline.correctedCount) corrected; each keeps its original time.")
        }
        if let run = model.lastRun {
            parts.append("Last run: \(run.provisionalShown) provisional updates, \(SpeechTimelineModel.count(run.timeline.segments.count)) finalized.")
        }
        return parts.joined(separator: " ")
    }
}

/// Play, pause, and a slider over the media time.
struct Scrubber: View {
    @Bindable var model: SpeechTimelineModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                    model.isPlaying ? model.pause() : model.play()
                }
                .labelStyle(.iconOnly)
                .disabled(!model.canPlay)
                .help(model.canPlay ? "Play from the playhead" : "No audio to play: captions and recordings are scrubbed as text")
                Slider(
                    value: Binding(get: { Double(model.playhead) }, set: { model.seek(to: Int($0)) }),
                    in: 0...Double(model.scrubLength)
                ) {
                    Text("Playhead")
                }
                .accessibilityValue(MediaClock.spoken(model.playhead))
                Text("\(MediaClock.format(model.playhead)) / \(MediaClock.format(model.scrubLength))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if let current = model.currentSegment {
                Text(current.text)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("At the playhead: \(current.text)")
            }
        }
    }
}

struct SegmentRow: View {
    let model: SpeechTimelineModel
    let segment: TranscriptSegment
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        let isCurrent = model.currentSegment?.id == segment.id
        Button {
            model.seek(to: segment.range.startMilliseconds)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(segment.range.description)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(segment.text)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(segment.source.label)
                    if segment.isCorrected { Text("Corrected from “\(segment.recognized)”") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Moves the playhead to this segment.")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityAction(named: "Correct") { beginEditing() }
        .accessibilityAction(named: "Play from Here") { model.play(from: segment.range.startMilliseconds) }
        .contextMenu {
            Button("Correct…", systemImage: "pencil") { beginEditing() }
            if segment.isCorrected {
                Button("Revert to Recognized Text", systemImage: "arrow.uturn.backward") { model.revert(segment.id) }
            }
            Button("Play from Here", systemImage: "play") { model.play(from: segment.range.startMilliseconds) }
                .disabled(!model.canPlay)
        }
        .swipeActions {
            Button("Correct", systemImage: "pencil") { beginEditing() }
        }
        .sheet(isPresented: $editing) {
            CorrectionSheet(segment: segment, text: $draft) { text in
                model.correct(segment.id, to: text)
            }
        }
    }

    private var accessibilityText: String {
        var parts = ["From \(MediaClock.spoken(segment.range.startMilliseconds)) to \(MediaClock.spoken(segment.range.endMilliseconds))", segment.text, segment.source.label]
        if segment.isCorrected { parts.append("corrected") }
        return parts.joined(separator: ", ")
    }

    private func beginEditing() {
        draft = segment.text
        editing = true
    }
}

/// The recognizer's current guess, after the segments and clearly not one of them.
struct ProvisionalRow: View {
    let guess: ProvisionalText

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(guess.range.description) · provisional, still changing")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(guess.text)
                .italic()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Provisional, still changing: \(guess.text)")
    }
}

/// Edits one segment's text. The time is shown and cannot be changed here.
struct CorrectionSheet: View {
    let segment: TranscriptSegment
    @Binding var text: String
    let apply: (String) -> Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Text", text: $text, axis: .vertical)
                } header: {
                    Text("Segment \(segment.range.description)")
                } footer: {
                    Text("A correction changes the text only. The segment keeps its time in the audio, and the recognized text “\(segment.recognized)” is kept beside it.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("Correct Segment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if apply(text) { dismiss() } }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 240)
    }
}

/// Adds a segment typed by hand for a time range with no segment yet.
struct AnnotationSection: View {
    let model: SpeechTimelineModel
    @State private var start = ""
    @State private var end = ""
    @State private var text = ""

    var body: some View {
        Section {
            TextField("Start, in seconds", text: $start)
            TextField("End, in seconds", text: $end)
            TextField("Text", text: $text)
            Button("Add Segment", systemImage: "plus") {
                if let range = milliseconds, model.annotate(start: range.0, end: range.1, text: text) {
                    start = end
                    end = ""
                    text = ""
                }
            }
            .disabled(milliseconds == nil || text.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
            Button("Use Playhead as Start", systemImage: "arrow.down.to.line") {
                start = String(format: "%.1f", Double(model.playhead) / 1_000)
            }
        } header: {
            Text("Annotate")
        } footer: {
            Text("Annotations are labeled as typed by hand. A range that overlaps another segment is refused.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var milliseconds: (Int, Int)? {
        guard let startSeconds = Double(start.replacingOccurrences(of: ",", with: ".")),
              let endSeconds = Double(end.replacingOccurrences(of: ",", with: ".")),
              startSeconds.isFinite, endSeconds.isFinite else { return nil }
        return (Int((startSeconds * 1_000).rounded()), Int((endSeconds * 1_000).rounded()))
    }
}

/// Saving to one of the person's collections through the operation service, and the exports.
struct SaveSection: View {
    let model: SpeechTimelineModel
    var onReceipt: (ReceiptRecord) -> Void = { _ in }
    @Environment(LabLibrary.self) private var library
    @State private var collectionID: CollectionID?
    @State private var newCollection = ""
    @State private var exporting: SpeechExportDocument?

    var body: some View {
        Section {
            if model.collections.isEmpty {
                TextField("New collection title", text: $newCollection)
                Button("Create Collection", systemImage: "folder.badge.plus") {
                    Task {
                        collectionID = await model.createCollection(titled: newCollection, in: library)
                        if collectionID != nil { newCollection = "" }
                    }
                }
                .disabled(newCollection.trimmingCharacters(in: .whitespaces).isEmpty || !library.canAct)
            } else {
                Picker("Collection", selection: $collectionID) {
                    Text("Choose…").tag(CollectionID?.none)
                    ForEach(model.collections) { collection in
                        Text(collection.title.value).tag(Optional(collection.id))
                    }
                }
            }
            Button(model.isSaved ? "Saved" : "Save to Collection", systemImage: model.isSaved ? "checkmark" : "tray.and.arrow.down") {
                guard let collectionID else { return }
                Task {
                    if let record = await model.save(to: collectionID, in: library) { onReceipt(record) }
                }
            }
            .disabled(collectionID == nil || model.timeline.segments.isEmpty || model.isBusy || model.isSaved || !library.canAct)
            .accessibilityHint("Adds one item with the transcript and its timing, as a change with a receipt.")
            if let saved = model.lastSave {
                Text(saved.record.receipt.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Export Captions…", systemImage: "captions.bubble") {
                exporting = SpeechExportDocument(data: model.captionExport(), kind: .captions)
            }
            .disabled(model.timeline.segments.isEmpty)
            Button("Export Timeline…", systemImage: "square.and.arrow.up") {
                exporting = (try? model.timelineExport()).map { SpeechExportDocument(data: $0, kind: .timeline) }
            }
            .disabled(model.timeline.segments.isEmpty)
        } header: {
            Text("Save and Export")
        } footer: {
            Text("Only finalized segments are saved or exported. The timeline export names the audio by its SHA-256, never by its file name.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { await model.loadCollections(from: library) }
        .fileExporter(
            isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
            document: exporting,
            contentType: exporting?.kind.contentType ?? .json,
            defaultFilename: exporting?.kind.fileName
        ) { _ in
            exporting = nil
        }
    }
}

/// An export's bytes for the system save panel.
struct SpeechExportDocument: FileDocument {
    enum Kind {
        case captions
        case timeline

        var contentType: UTType {
            switch self {
            case .captions: SpeechExportDocument.captionTypes[0]
            case .timeline: .json
            }
        }

        var fileName: String {
            switch self {
            case .captions: "speech-timeline.vtt"
            case .timeline: "speech-timeline.json"
            }
        }
    }

    static let captionTypes: [UTType] = [UTType(filenameExtension: "vtt", conformingTo: .plainText) ?? .plainText, .plainText]
    static var readableContentTypes: [UTType] { [.json] + captionTypes }

    let data: Data
    let kind: Kind

    init(data: Data, kind: Kind) {
        self.data = data
        self.kind = kind
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: The catalog page's entry

/// The entry on the experiment's catalog page: pushed on iPhone, the sidebar destination on the Mac.
struct SpeechTimelineEntry: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == SpeechTimeline.experimentID {
            VStack(alignment: .leading, spacing: 6) {
                #if os(iOS)
                NavigationLink {
                    SpeechTimelineScreen()
                } label: {
                    Label("Open Speech Timeline", systemImage: "waveform.and.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                #else
                Button("Open Speech Timeline", systemImage: "waveform.and.magnifyingglass") {
                    window?.destination = .speechTimeline
                }
                .controlSize(.large)
                .disabled(window == nil)
                #endif
                Text("Runs in this build: on-device transcription of a clip this device speaks from the sample script, or of audio you import, where the transcriber and the language's model are available; caption import and annotation everywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
