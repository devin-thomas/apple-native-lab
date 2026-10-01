#if os(iOS)
import AVFAudio
#endif
import Foundation
import LabDomain
import LabSupport
import Testing
@testable import SpeechTimeline

// LAB-013-B qualification: the experiment's three acceptance criteria pushed past the cases
// LAB-013-A covered, step 3 (denial, cancellation, stale and duplicate state, and Reset Demo beside
// saved transcripts), and step 1, a replay of the whole fixture interaction from clean state.
// Fixture path: scripted recognizer and capture streams, a fake permission source with a counting
// requester, and an in-memory store behind `OperationService`. No microphone is opened. The Mac
// hosted tests repeat the interaction through the app's session model and SQLite
// (`SpeechTimelineQualificationHostTests`, `SpeechTimelineHostEvidenceTests`).

/// A seeded generator, so every generated stream can be replayed from its seed.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE5_E4B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Recognizer-shaped update streams with words that never repeat, so a word shown twice is a
/// duplicate by construction.
///
/// Each sentence is guessed as it grows, sometimes reaching into the next sentence's first words,
/// then finalized with word times; the next guess starts at the finalization time, as the
/// transcriber did on the development Mac. Into that shape the generator mixes what a recognizer
/// or a busy device could deliver: the same final twice, a late guess from before a final that
/// reaches back over it, a guess wholly inside finalized audio, an empty final over a silence, and
/// an empty guess.
struct GeneratedStream {
    var updates: [RecognizerUpdate] = []
    /// Each sentence's text, in order: what the timeline must hold once the stream ends.
    var sentences: [String] = []
    /// Each sentence's range.
    var ranges: [MediaTimeRange] = []

    init(seed: UInt64, sentenceCount: ClosedRange<Int> = 2...6) {
        var random = SplitMix64(seed: seed)
        let count = Int.random(in: sentenceCount, using: &random)
        var words: [[TimedWord]] = []
        var cursor = Int.random(in: 0...400, using: &random)
        for sentence in 0..<count {
            var line: [TimedWord] = []
            for word in 0..<Int.random(in: 2...7, using: &random) {
                let length = Int.random(in: 120...480, using: &random)
                line.append(TimedWord(range: range(cursor, cursor + length), text: "s\(seed % 1_000)x\(sentence)w\(word)"))
                cursor += length + Int.random(in: 0...40, using: &random)
            }
            words.append(line)
            // A pause between sentences, sometimes long enough to be finalized as silence.
            cursor += Int.random(in: 0...900, using: &random)
        }
        sentences = words.map { $0.map(\.text).joined(separator: " ") }
        ranges = words.map { range($0.first!.range.startMilliseconds, $0.last!.range.endMilliseconds) }

        for (index, line) in words.enumerated() {
            let start = ranges[index].startMilliseconds
            let next = index + 1 < words.count ? words[index + 1] : []
            let lookahead = Int.random(in: 0...min(2, next.count), using: &random)
            let guessed = line + next.prefix(lookahead)
            for shown in 1...guessed.count {
                let span = guessed.prefix(shown)
                updates.append(.provisional(range: range(start, span.last!.range.endMilliseconds), text: span.map(\.text).joined(separator: " ")))
                if Int.random(in: 0..<12, using: &random) == 0 {
                    updates.append(.provisional(range: range(start, span.last!.range.endMilliseconds), text: " "))
                }
            }
            let final = RecognizerUpdate.final(range: ranges[index], text: sentences[index], words: line)
            updates.append(final)
            switch Int.random(in: 0..<6, using: &random) {
            case 0:
                updates.append(final)
            case 1:
                // A late guess from before the final, reaching back over it into what follows.
                let reach = (next.first?.range.endMilliseconds ?? ranges[index].endMilliseconds + 300)
                updates.append(.provisional(range: range(start, reach), text: guessed.map(\.text).joined(separator: " ")))
            case 2:
                updates.append(.provisional(range: range(start, ranges[index].endMilliseconds), text: sentences[index]))
            case 3:
                if let following = next.first, following.range.startMilliseconds - ranges[index].endMilliseconds > 200 {
                    updates.append(.final(range: range(ranges[index].endMilliseconds, following.range.startMilliseconds), text: "", words: []))
                }
            default:
                break
            }
        }
    }
}

/// Checks that hold after every update, whatever arrived: segments in order without overlap, no
/// guess over a finalized segment, and, for generated streams whose words never repeat, no word
/// shown twice across the segments and the guess.
func expectTimelineInvariants(_ timeline: TranscriptTimeline, _ context: String, uniqueWords: Bool = true, sourceLocation: SourceLocation = #_sourceLocation) {
    for (earlier, later) in zip(timeline.segments, timeline.segments.dropFirst()) {
        #expect(earlier.range.endMilliseconds <= later.range.startMilliseconds, "segments overlap or are out of order: \(context)", sourceLocation: sourceLocation)
    }
    if let guess = timeline.provisional {
        #expect(!timeline.segments.contains { $0.range.overlaps(guess.range) }, "a guess over finalized audio: \(context)", sourceLocation: sourceLocation)
    }
    guard uniqueWords else { return }
    let shown = timeline.segments.flatMap { $0.text.split(separator: " ") } + (timeline.provisional?.text.split(separator: " ") ?? [])
    #expect(Set(shown).count == shown.count, "a word is shown twice: \(context)", sourceLocation: sourceLocation)
}

// MARK: - Criterion 1: route changes do not silently lose the session

@Suite struct RouteChangeQualification {
    /// Every way a capture can stop on its own, as the session receives it.
    static let stops: [CaptureEvent] = [
        CaptureStop.routeChange(reason: 1)!,
        CaptureStop.routeChange(reason: 2)!,
        CaptureStop.routeChange(reason: 7)!,
        CaptureStop.routeChange(reason: 8)!,
        CaptureStop.engineConfigurationChanged,
        CaptureStop.interruption(type: 1)!,
        .failed(.engineFailed),
    ]

    @Test func theCaptureStopsForEveryChangeThatCanSilenceTheMicrophone() {
        #expect(CaptureStop.routeChange(reason: 1) == .routeChanged(reason: "a new audio device was connected"))
        #expect(CaptureStop.routeChange(reason: 2) == .routeChanged(reason: "the audio device in use was disconnected"))
        #expect(CaptureStop.routeChange(reason: 7) == .routeChanged(reason: "no audio input is available"))
        #expect(CaptureStop.routeChange(reason: 8) == .routeChanged(reason: "the audio route's configuration changed"))
        // Unknown, a category change or override the app made, and a wake from sleep leave the
        // microphone working; if one did stop the engine, its configuration change stops capture.
        for reason: UInt in [0, 3, 4, 6, 99] {
            #expect(CaptureStop.routeChange(reason: reason) == nil, "reason \(reason)")
        }
        #expect(CaptureStop.interruption(type: 1) == .interrupted)
        #expect(CaptureStop.interruption(type: 0) == nil, "an ended interruption waits for Resume Recording")
        #expect(CaptureStop.engineConfigurationChanged == .routeChanged(reason: "the audio device configuration changed"))
    }

    #if os(iOS)
    /// The raw values `CaptureStop` reads are the iOS SDK's own. Runs in the iOS simulator.
    @Test func theRawValuesAreTheSDKs() {
        #expect(AVAudioSessionRawValues.newDevice == 1)
        #expect(AVAudioSessionRawValues.oldDeviceUnavailable == 2)
        #expect(AVAudioSessionRawValues.noSuitableRoute == 7)
        #expect(AVAudioSessionRawValues.routeConfigurationChange == 8)
        #expect(AVAudioSessionRawValues.interruptionBegan == 1)
        #expect(AVAudioSessionRawValues.interruptionEnded == 0)
    }
    #endif

    /// Each way of stopping, at each point of a run: before any result, during a guess, right after
    /// a final, and after a repeated final. What was finalized stays, the guess goes and is counted,
    /// the summary names the reason and what was kept, nothing after the stop is applied, and Resume
    /// continues the same timeline after the kept segments.
    @Test(arguments: stops)
    func everyStopKeepsTheSessionAtEveryPoint(_ stop: CaptureEvent) {
        let run: [RecognizerUpdate] = [
            provisional(0, 900, "The kettle"),
            final(0, 1_700, "The kettle clicked off at 7."),
            final(0, 1_700, "The kettle clicked off at 7."),
            provisional(1_700, 2_600, "Blue tape"),
            final(1_700, 3_900, "Blue tape marks the 2nd shelf."),
        ]
        for cut in 0...run.count {
            var session = RecordingSession()
            var timeline = TranscriptTimeline()
            session.beginRun(on: timeline)
            for update in run.prefix(cut) { session.handle(.update(update), timeline: &timeline) }
            let kept = timeline.segments
            let guessShowing = timeline.provisional != nil
            session.handle(stop, timeline: &timeline)
            // Anything the capture still sends is not applied until the next run.
            #expect(session.handle(.update(final(4_000, 5_000, "Late.")), timeline: &timeline) == nil)

            #expect(timeline.segments == kept, "cut \(cut): every finalized segment is kept")
            #expect(timeline.provisional == nil, "cut \(cut): unfinished text is not kept as if it were final")
            #expect(session.discardedProvisionals == (guessShowing ? 1 : 0))
            let summary = session.summary(segments: timeline.segments.count)
            #expect(summary.contains(kept.count == 1 ? "1 segment kept" : "\(kept.count) segments kept"), "\(summary)")
            switch stop {
            case .routeChanged(let reason):
                #expect(session.state == .paused(.routeChanged(reason)))
                #expect(summary.hasPrefix("Recording paused because the audio route changed: \(reason)."))
                #expect(summary.hasSuffix("Resume continues the same timeline."))
            case .interrupted:
                #expect(session.state == .paused(.interrupted))
                #expect(summary.hasSuffix("Resume continues the same timeline."))
            case .failed(let failure):
                #expect(session.state == .failed(failure))
                #expect(summary.hasPrefix(failure.message))
            default:
                Issue.record("not a stop: \(stop)")
            }

            session.beginRun(on: timeline)
            session.handle(.update(final(0, 1_000, "Resumed.")), timeline: &timeline)
            let resumed = timeline.segments.last
            #expect(resumed?.text == "Resumed.")
            #expect(resumed?.range.startMilliseconds == (kept.last?.range.endMilliseconds ?? 0), "cut \(cut): the next run continues the timeline")
            #expect(Array(timeline.segments.dropLast()) == kept)
            expectTimelineInvariants(timeline, "cut \(cut)")
        }
    }

    /// Many runs in a row, each stopped at a generated point by a generated cause. After every
    /// event: nothing finalized is lost, nothing overlaps, and no word shows twice.
    @Test(arguments: [UInt64(1), 7, 42, 1_013, 65_537])
    func aSessionSurvivesManyStopsInARow(_ seed: UInt64) {
        var random = SplitMix64(seed: seed)
        var session = RecordingSession()
        var timeline = TranscriptTimeline()
        var expected: [String] = []
        var discarded = 0
        for runIndex in 0..<20 {
            let stream = GeneratedStream(seed: seed &* 1_000 &+ UInt64(runIndex), sentenceCount: 1...3)
            let cut = Int.random(in: 0...stream.updates.count, using: &random)
            let stop = Self.stops.randomElement(using: &random)!
            session.beginRun(on: timeline)
            let start = timeline.endMilliseconds
            for update in stream.updates.prefix(cut) {
                session.handle(.update(update), timeline: &timeline)
                expectTimelineInvariants(timeline, "seed \(seed) run \(runIndex)")
            }
            // The finals delivered before the stop, once each.
            var delivered: [String] = []
            for case .final(_, let text, _) in stream.updates.prefix(cut) where !text.trimmingCharacters(in: .whitespaces).isEmpty && !delivered.contains(text) {
                delivered.append(text)
            }
            if timeline.provisional != nil { discarded += 1 }
            session.handle(stop, timeline: &timeline)
            expected += delivered
            #expect(timeline.segments.map(\.text) == expected, "seed \(seed) run \(runIndex)")
            #expect(timeline.provisional == nil)
            #expect(session.discardedProvisionals == discarded)
            #expect(timeline.segments.filter { $0.range.startMilliseconds >= start }.count == delivered.count, "this run's segments follow the earlier ones")
            #expect(session.summary(segments: timeline.segments.count).contains("\(timeline.segments.count) segment"))
        }
        #expect(session.runs == 20)
    }

    /// The route change left no microphone, so Resume fails to start. The session says so and
    /// still holds every segment.
    @Test func aResumeThatCannotStartKeepsTheSegments() {
        var session = RecordingSession()
        var timeline = TranscriptTimeline()
        session.beginRun(on: timeline)
        session.handle(.update(final(0, 1_700, "The kettle clicked off at 7.")), timeline: &timeline)
        session.handle(CaptureStop.routeChange(reason: 2)!, timeline: &timeline)
        session.beginRun(on: timeline)
        session.handle(.failed(.audioUnreadable), timeline: &timeline)
        #expect(session.state == .failed(.audioUnreadable))
        #expect(timeline.segments.map(\.text) == ["The kettle clicked off at 7."])
        #expect(session.summary(segments: timeline.segments.count) == "The audio could not be read. Nothing was transcribed. 1 segment kept.")
    }
}

#if os(iOS)
/// The iOS SDK's raw values for the enums `CaptureStop` maps.
enum AVAudioSessionRawValues {
    static let newDevice = AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
    static let oldDeviceUnavailable = AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
    static let noSuitableRoute = AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue
    static let routeConfigurationChange = AVAudioSession.RouteChangeReason.routeConfigurationChange.rawValue
    static let interruptionBegan = AVAudioSession.InterruptionType.began.rawValue
    static let interruptionEnded = AVAudioSession.InterruptionType.ended.rawValue
}
#endif

// MARK: - Criterion 2: final segments do not duplicate provisional text

@Suite struct ProvisionalFinalQualification {
    /// 300 generated streams. After every update no word is shown twice, no guess sits over a
    /// finalized segment, and the segments stay in order; at the end the transcript is exactly the
    /// sentences, once each.
    @Test func generatedStreamsNeverShowAWordTwice() {
        var refused = 0
        var dropped = 0
        for seed in UInt64(1)...300 {
            let stream = GeneratedStream(seed: seed)
            var timeline = TranscriptTimeline()
            for (index, update) in stream.updates.enumerated() {
                switch timeline.apply(update) {
                case .duplicateFinalIgnored, .overlappingFinalRefused: refused += 1
                case .staleProvisionalDropped: dropped += 1
                default: break
                }
                expectTimelineInvariants(timeline, "seed \(seed) update \(index)")
            }
            timeline.discardProvisional()
            #expect(timeline.plainText == stream.sentences.joined(separator: "\n"), "seed \(seed)")
            #expect(timeline.segments.map(\.range) == stream.ranges, "seed \(seed)")
        }
        #expect(refused > 0 && dropped > 0, "the streams included repeated finals and late guesses")
    }

    /// The case the generator found: a guess delivered after a final, starting before it and
    /// running past it. Its text holds the finalized words, so it is dropped.
    @Test func aLateGuessReachingBackOverAFinalizedSegmentIsDropped() {
        var timeline = TranscriptTimeline()
        timeline.apply(final(0, 1_700, "The kettle clicked off at 7."))
        timeline.apply(provisional(1_700, 2_200, "Blue"))
        #expect(timeline.apply(provisional(900, 2_600, "off at 7. Blue tape")) == .staleProvisionalDropped)
        #expect(timeline.provisional?.text == "Blue", "the current guess stays")
        #expect(timeline.apply(provisional(1_700, 2_600, "Blue tape")) == .provisionalShown)
        expectTimelineInvariants(timeline, "after the late guess")
    }

    /// At every snapshot of the observed sequence, the caption export, the timeline export, and a
    /// prepared save hold the finalized segments and nothing of the guess.
    @Test func noSnapshotExportsOrSavesProvisionalText() throws {
        var timeline = TranscriptTimeline()
        for update in ObservedSequence.updates {
            timeline.apply(update)
            let rendered = CaptionDocument.render(timeline)
            if timeline.segments.isEmpty {
                #expect(rendered == "WEBVTT\n", "no cue before the first final")
            } else {
                #expect(try CaptionDocument.parse(Data(rendered.utf8)).map(\.text) == timeline.segments.map(\.text))
            }
            let (export, _) = try TimelineExport.decode(try TimelineExport(timeline: timeline, audio: .none, language: "en-US").encoded())
            #expect(export.segments == timeline.segments)
            if !timeline.segments.isEmpty, let guess = timeline.provisional {
                let save = try TranscriptSave.prepare(timeline, audio: .none, language: "en-US", title: "Transcript", into: CollectionID())
                guard case .createItem(let draft) = save.operation else { return }
                #expect(draft.note.value == timeline.plainText)
                #expect(!draft.note.value.contains(guess.text) && !draft.extras.json.contains(guess.text), "the guess \(guess.text) is not saved")
            }
        }
    }
}

// MARK: - Criterion 3: transcript corrections preserve the original media timestamps

@Suite struct CorrectionTimestampQualification {
    static let corrections = [
        "Blue tape marks the second shelf.",
        "釉薬の棚 · 유약 · שלום · مرحبا",
        "cre\u{300}me bru\u{302}le\u{301}e 👩🏽‍🔬",
        "Salt & <pepper> --> \"quoted\"",
        String(repeating: "a", count: SpeechTimelineLimits.segmentText),
    ]

    /// Timelines from every source: recognition, captions, annotation, and a recording resumed
    /// after a route change, whose times were moved onto the one timeline.
    static func timelines() throws -> [(String, TranscriptTimeline)] {
        var annotated = TranscriptTimeline()
        try annotated.annotate(range(0, 1_200), text: "Typed by hand.")
        try annotated.annotate(range(1_200, 2_400), text: "Typed again.")

        var session = RecordingSession()
        var recorded = TranscriptTimeline()
        session.beginRun(on: recorded)
        session.handle(.update(final(0, 1_700, "The kettle clicked off at 7.")), timeline: &recorded)
        session.handle(CaptureStop.routeChange(reason: 2)!, timeline: &recorded)
        session.beginRun(on: recorded)
        session.handle(.update(final(0, 2_200, "Blue tape marks the 2nd shelf.", words: [
            TimedWord(range: range(0, 400), text: "Blue"), TimedWord(range: range(400, 900), text: "tape"),
        ])), timeline: &recorded)

        return [
            ("recognized", observedTimeline()),
            ("captions", try SpeechFixture.captions(at: Repository.fixture(.sampleCaptions))),
            ("annotated", annotated),
            ("recorded", recorded),
        ]
    }

    /// Every segment of every timeline, corrected to every text: its range, word times, recognized
    /// text, and source stay; the caption export, the timeline export, and a saved item give back
    /// the same times; scrubbing to its audio finds it; revert restores it exactly.
    @Test func correctionsKeepEveryTimeThroughEveryExport() async throws {
        let lab = try await Lab.withCollection()
        for (name, original) in try Self.timelines() {
            for correction in Self.corrections {
                var timeline = original
                for segment in original.segments { try timeline.correct(segment.id, to: correction) }
                for (before, after) in zip(original.segments, timeline.segments) {
                    #expect(after.range == before.range && after.words == before.words, "\(name)")
                    #expect(after.recognized == before.recognized && after.source == before.source, "\(name)")
                    #expect(after.text == correction)
                    #expect(timeline.segment(at: before.range.startMilliseconds)?.id == before.id, "\(name): scrubbing finds the corrected segment")
                    #expect(timeline.segment(at: before.range.endMilliseconds - 1)?.id == before.id)
                }

                let cues = try CaptionDocument.parse(Data(CaptionDocument.render(timeline).utf8))
                #expect(cues.map(\.range) == original.segments.map(\.range), "\(name): caption times")
                #expect(cues.map(\.text) == timeline.segments.map(\.text), "\(name): caption text")

                let (_, restored) = try TimelineExport.decode(try TimelineExport(timeline: timeline, audio: .none, language: "en-US").encoded())
                #expect(restored.segments == timeline.segments, "\(name): the timeline export keeps times, words, and both texts")

                let save = try TranscriptSave.prepare(timeline, audio: .none, language: "en-US", title: "Corrected", into: lab.collection.id)
                _ = try await lab.appUI.commit(save)
                let item = try #require(await lab.store.item(save.itemID))
                let extras = try #require(try JSONSerialization.jsonObject(with: Data(item.extras.json.utf8)) as? [String: Any])
                let saved = try JSONSerialization.data(withJSONObject: try #require(extras[TranscriptSave.extrasKey]))
                #expect(try TimelineExport.decode(saved).timeline.segments == timeline.segments, "\(name): the saved item")

                for segment in original.segments { try timeline.revert(segment.id) }
                #expect(timeline.segments == original.segments, "\(name): revert restores every segment exactly")
            }
        }
    }

    /// Times at the edges: the first millisecond, a 1 ms segment, the 3-hour limit, hours in
    /// WebVTT, and seconds rounded to milliseconds once.
    @Test func timesAtTheEdgesSurviveACorrectionAndBothExports() throws {
        let limit = SpeechTimelineLimits.mediaDuration
        var timeline = try TranscriptTimeline(segments: [
            TranscriptSegment(id: SegmentID(1), range: range(0, 1), text: "First.", source: .captionImport, words: []),
            TranscriptSegment(id: SegmentID(2), range: try MediaTimeRange(startSeconds: 1.0004, endSeconds: 1.0005), text: "Rounded.", source: .captionImport, words: []),
            TranscriptSegment(id: SegmentID(3), range: range(3_723_004, 3_723_999), text: "An hour in.", source: .captionImport, words: []),
            TranscriptSegment(id: SegmentID(4), range: range(limit - 1_000, limit), text: "Last.", source: .captionImport, words: []),
        ])
        #expect(timeline.segments[1].range == range(1_000, 1_001), "rounded once, to the nearest millisecond")
        let original = timeline.segments
        for segment in original { try timeline.correct(segment.id, to: "Corrected \(segment.id.rawValue).") }
        let rendered = CaptionDocument.render(timeline)
        #expect(rendered.contains("01:02:03.004 --> 01:02:03.999"))
        #expect(rendered.contains("02:59:59.000 --> 03:00:00.000"))
        #expect(try CaptionDocument.parse(Data(rendered.utf8)).map(\.range) == original.map(\.range))
        #expect(try TimelineExport.decode(try TimelineExport(timeline: timeline, audio: .none, language: "en-US").encoded()).timeline.segments.map(\.range) == original.map(\.range))
    }

    /// A correction is one line. Line and paragraph separators are refused like a line break, and a
    /// refused correction changes nothing, including the revision.
    @Test func aRefusedCorrectionChangesNothing() throws {
        var timeline = observedTimeline()
        let before = timeline
        let id = timeline.segments[0].id
        for text in ["two\nlines", "two\u{2028}lines", "two\u{2029}paragraphs", "next\u{85}line", "tab\tinside", "   "] {
            #expect(throws: TimelineError.self, "\(text.debugDescription)") { try timeline.correct(id, to: text) }
        }
        #expect(timeline == before)
        try timeline.correct(id, to: "Blue tape marks the 2nd shelf.")
        #expect(timeline.revision == before.revision, "correcting to the same text is not a change")
    }
}

// MARK: - Step 3: denial, cancellation, stale and duplicate state, and Reset Demo

@Suite struct SpeechTimelineBoundaryQualification {
    /// Every closed microphone route falls back with its own sentence and the documented fallback.
    /// Only a first-time question shows the system prompt, once.
    @Test func everyClosedMicrophoneRouteFallsBackWithItsSentence() async {
        let cases: [(String, FakeCapabilitySource, LabPlatform, PermissionStatus, Int)] = [
            ("denied earlier", FakeCapabilitySource(microphone: .denied), .iOS, .authorized, 0),
            ("restricted", FakeCapabilitySource(microphone: .restricted), .iOS, .authorized, 0),
            ("unreadable", FakeCapabilitySource(microphone: .notReadable), .iOS, .authorized, 0),
            ("declined now", FakeCapabilitySource(), .iOS, .denied, 1),
            ("no purpose string", FakeCapabilitySource(purposeStrings: []), .iOS, .authorized, 0),
            ("no Mac entitlement", FakeCapabilitySource(entitlements: []), .macOS, .authorized, 0),
        ]
        var sentences: Set<String> = []
        for (name, source, platform, answer, prompts) in cases {
            let requester = CountingRequester(answer: answer)
            let gate = RecordingGate(stager: PermissionStager(platform: platform, source: source, requester: requester))
            guard case .fallback(let reason, let route) = await gate.decide() else {
                Issue.record("\(name): the microphone must stay closed")
                continue
            }
            #expect(route == Capability.microphone.fallback, "\(name)")
            #expect(route.experiments.contains(SpeechTimeline.experimentID))
            #expect(requester.requested.count == prompts, "\(name): \(prompts) prompts")
            sentences.insert(reason)
        }
        #expect(sentences.count == cases.count, "each closed route names its own reason")
    }

    /// Record pressed several times at once while the question is open shows one prompt.
    @Test func concurrentRecordPressesShareOnePrompt() async {
        let requester = CountingRequester(answer: .authorized)
        let gate = RecordingGate(stager: PermissionStager(platform: .iOS, source: FakeCapabilitySource(), requester: requester))
        let decisions = await withTaskGroup(of: RecordingDecision.self) { group in
            for _ in 0..<6 { group.addTask { await gate.decide() } }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(decisions.allSatisfy { $0 == .record(systemAsks: false) })
        #expect(requester.requested == [.microphone])
    }

    /// Stopped before the recognizer's first result: nothing was finalized, so there is nothing to
    /// save, and the reason says the stop kept what was final.
    @Test func cancellingBeforeTheFirstResultLeavesNothingToSave() async {
        let flow = SpeechTimelineFlow(recognizer: ScriptedRecognizer(pause: .milliseconds(400)))
        let task = Task {
            try? await Task.sleep(for: .milliseconds(30))
            return await flow.transcribe(file: URL(fileURLWithPath: "/dev/null"), language: "en-US")
        }
        task.cancel()
        let run = await task.value
        #expect(run.failure == .cancelled)
        #expect(run.timeline.isEmpty)
        #expect(throws: SpeechSaveError.nothingToSave) {
            try TranscriptSave.prepare(run.timeline, audio: .none, language: "en-US", title: "Transcript", into: CollectionID())
        }
    }

    /// The same save pressed from several places at once commits one item, and every press gets
    /// the same receipt.
    @Test func aSaveRetriedConcurrentlyCommitsOnce() async throws {
        let lab = try await Lab.withCollection()
        let save = try TranscriptSave.prepare(observedTimeline(), audio: .none, language: "en-US", title: "Transcript", into: lab.collection.id)
        let backend = lab.appUI
        let receipts = try await withThrowingTaskGroup(of: ActionReceipt.self) { group in
            for _ in 0..<6 { group.addTask { try await backend.commit(save) } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(Set(receipts).count == 1)
        #expect(await lab.store.items(in: lab.collection.id).count == 1)
    }

    /// A save captures the revision it was prepared from. A correction made afterwards is not
    /// carried into it; it needs its own save, so a stale save never claims the new text.
    @Test func aSavePreparedBeforeACorrectionKeepsItsRevision() async throws {
        let lab = try await Lab.withCollection()
        var timeline = observedTimeline()
        let earlier = try TranscriptSave.prepare(timeline, audio: .none, language: "en-US", title: "Transcript", into: lab.collection.id)
        try timeline.correct(timeline.segments[0].id, to: "Blue tape marks the second shelf.")
        #expect(earlier.revision < timeline.revision)
        _ = try await lab.appUI.commit(earlier)
        let item = try #require(await lab.store.item(earlier.itemID))
        #expect(item.note.value.hasPrefix("Blue tape marks the 2nd shelf."))
        #expect(!item.extras.json.contains("second shelf"))
    }

    /// Reset Demo through the operation service replaces the demo samples and leaves the person's
    /// saved transcripts exactly as they were.
    @Test func resetDemoLeavesSavedTranscriptsAlone() async throws {
        let lab = try await Lab.withCollection()
        let seed = try DemoSeed(
            version: 1,
            collections: [CollectionDraft(title: EntityTitle("Demo"))],
            items: []
        )
        _ = try await lab.service.perform(OperationRequest(id: RequestID(), operation: .resetDemo(seed: seed), actor: ServiceSpeechBackend.appUI))
        let save = try TranscriptSave.prepare(observedTimeline(), audio: .none, language: "en-US", title: "Transcript", into: lab.collection.id)
        _ = try await lab.appUI.commit(save)
        let before = try #require(await lab.store.item(save.itemID))
        #expect(before.namespace == .user)

        let reset = try await lab.service.perform(OperationRequest(id: RequestID(), operation: .resetDemo(seed: seed), actor: ServiceSpeechBackend.appUI))
        #expect(reset.status == .committed)
        #expect(await lab.store.item(save.itemID) == before)
    }
}

// MARK: - Step 1: the complete fixture interaction from clean state

/// The whole interaction, replayed from a clean store and fresh fixtures, twice. Each replay
/// writes one line per observation; the two replays must give the same lines and the same
/// fingerprint, so the interaction is deterministic apart from its random identifiers, which the
/// lines leave out.
@Suite struct SpeechTimelineInteractionReplay {
    static func replay() async throws -> [String] {
        var lines: [String] = []
        func note(_ line: String) { lines.append(line) }
        func sha(_ data: Data) -> String { ContentDigest.sha256(data).hex }

        let lab = try await Lab.withCollection()

        // 1. Readiness: languages, stated, never downloaded.
        let flow = SpeechTimelineFlow(recognizer: ScriptedRecognizer())
        let support = await flow.languages()
        for language in ["en-US", "fr-FR", "tlh"] { note("language \(language): \(support.state(for: language))") }

        // 2. Transcribe the sample: guesses improve, segments finalize.
        let recorder = SnapshotRecorder()
        let run = await flow.transcribe(file: URL(fileURLWithPath: "/dev/null"), language: "en-US") { await recorder.add($0) }
        let snapshots = await recorder.snapshots
        note("transcribed: \(run.failure.map { "\($0)" } ?? "finished"), \(snapshots.count) snapshots, \(run.provisionalShown) guesses, \(run.timeline.segments.count) segments")
        // Ordinary sentences repeat words such as "the", so only the ranges are checked here.
        for snapshot in snapshots { expectTimelineInvariants(snapshot, "replay snapshot", uniqueWords: false) }
        var timeline = run.timeline

        // 3. Correct one segment, annotate the end by hand.
        let corrected = timeline.segments[0]
        try timeline.correct(corrected.id, to: "Blue tape marks the second shelf.")
        try timeline.annotate(range(5_520, 7_300), text: "The spare key is in the green tin.")
        for segment in timeline.segments { note("segment \(segment.id) \(segment.range) \(segment.source.rawValue) “\(segment.text)” from “\(segment.recognized)”") }

        // 4. Export both ways and read both back.
        let captions = Data(CaptionDocument.render(timeline).utf8)
        let audio = AudioReference(origin: .synthesizedSample, sha256: String(repeating: "c", count: 64), durationMilliseconds: 7_373, fileType: "caf")
        let document = try TimelineExport(timeline: timeline, audio: audio, language: "en-US").encoded()
        note("captions sha256 \(sha(captions)); timeline sha256 \(sha(document))")
        #expect(try CaptionDocument.parse(captions).map(\.range) == timeline.segments.map(\.range))
        #expect(try TimelineExport.decode(document).timeline.segments == timeline.segments)

        // 5. Save as the app UI, then press Save again.
        let save = try TranscriptSave.prepare(timeline, audio: audio, language: "en-US", title: "Transcript: sample clip", into: lab.collection.id)
        let receipt = try await lab.appUI.commit(save)
        let retried = try await lab.appUI.commit(save)
        let item = try #require(await lab.store.item(save.itemID))
        note("saved: \(receipt.status) \(receipt.admitted.adapter.rawValue) \(receipt.admitted.operation.kind.rawValue), retry same receipt \(receipt == retried); note sha256 \(sha(Data(item.note.value.utf8))); extras sha256 \(sha(Data(item.extras.json.utf8)))")

        // 6. The fallback: the caption fixture, corrected and saved.
        var fallback = try SpeechFixture.captions(at: Repository.fixture(.sampleCaptions))
        try fallback.correct(fallback.segments[0].id, to: "The kettle clicked off at seven sharp.")
        let fallbackSave = try TranscriptSave.prepare(fallback, audio: .none, language: "en-US", title: "Captions", into: lab.collection.id)
        _ = try await lab.appUI.commit(fallbackSave)
        note("fallback: \(fallback.segments.map { "\($0.range)" }.joined(separator: ", ")); captions sha256 \(sha(Data(CaptionDocument.render(fallback).utf8)))")

        // 7. Record, with the microphone allowed by a fake: a route change, then Resume and Stop.
        let requester = CountingRequester(answer: .authorized)
        let gate = RecordingGate(stager: PermissionStager(platform: .iOS, source: FakeCapabilitySource(), requester: requester))
        note("record: \(await gate.decide()), \(requester.requested.count) prompt")
        var session = RecordingSession()
        var recorded = TranscriptTimeline()
        for events in [
            [CaptureEvent.update(provisional(0, 900, "The kettle")), .update(final(0, 1_700, "The kettle clicked off at 7.")),
             .update(provisional(1_700, 2_400, "Blue tape")), CaptureStop.routeChange(reason: 2)!],
            [.update(final(0, 2_200, "Blue tape marks the 2nd shelf.")), .ended],
        ] {
            let capture = ScriptedCapture(events)
            session.beginRun(on: recorded)
            for await event in try await capture.start(language: "en-US") { session.handle(event, timeline: &recorded) }
            note("recording: \(session.summary(segments: recorded.segments.count))")
        }
        note("recorded: \(recorded.segments.map { "\($0.range) \($0.text)" }.joined(separator: "; "))")
        let recordedSave = try TranscriptSave.prepare(recorded, audio: AudioReference(origin: .recording, sha256: nil, durationMilliseconds: nil, fileType: nil), language: "en-US", title: "Transcript: recording", into: lab.collection.id)
        _ = try await lab.appUI.commit(recordedSave)

        // 8. Reset Demo: the three saved transcripts stay as they were.
        let saved = await lab.store.items(in: lab.collection.id)
        let seed = try DemoSeed(version: 1, collections: [CollectionDraft(title: EntityTitle("Demo"))], items: [])
        let reset = try await lab.service.perform(OperationRequest(id: RequestID(), operation: .resetDemo(seed: seed), actor: ServiceSpeechBackend.appUI))
        let after = await lab.store.items(in: lab.collection.id)
        note("reset demo: \(reset.status); \(saved.count) saved transcripts, unchanged \(Set(after) == Set(saved))")
        return lines
    }

    @Test func theInteractionReplaysIdenticallyFromCleanState() async throws {
        let first = try await Self.replay()
        let second = try await Self.replay()
        #expect(first == second)
        let fingerprint = ContentDigest.sha256(Data(first.joined(separator: "\n").utf8)).hex
        #expect(fingerprint == ContentDigest.sha256(Data(second.joined(separator: "\n").utf8)).hex)
        // The facts the lines must record.
        #expect(first.contains("language tlh: unsupported"))
        #expect(first.contains { $0.hasPrefix("transcribed: finished, 8 snapshots, 5 guesses, 2 segments") })
        #expect(first.contains { $0.hasPrefix("saved: committed app-ui create-item, retry same receipt true") })
        #expect(first.contains("record: record(systemAsks: false), 1 prompt"))
        #expect(first.contains { $0.hasPrefix("recording: Recording paused because the audio route changed: the audio device in use was disconnected. 1 segment kept.") })
        #expect(first.contains("recorded: 0:00.0–0:01.7 The kettle clicked off at 7.; 0:01.7–0:03.9 Blue tape marks the 2nd shelf."))
        #expect(first.contains("reset demo: committed; 3 saved transcripts, unchanged true"))
    }
}

/// Collects the timeline snapshots the flow reports.
actor SnapshotRecorder {
    private(set) var snapshots: [TranscriptTimeline] = []
    func add(_ timeline: TranscriptTimeline) { snapshots.append(timeline) }
}
