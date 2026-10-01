import Testing
@testable import SpeechTimeline

/// The timeline's rules: provisional text apart from finalized segments, never both at once, and
/// corrections that keep the original media time.
@Suite struct TimelineTests {
    // MARK: Provisional and final

    @Test func provisionalTextIsShownApartFromFinalizedSegments() {
        var timeline = TranscriptTimeline()
        #expect(timeline.apply(provisional(0, 1_200, "The kettle")) == .provisionalShown)
        #expect(timeline.segments.isEmpty)
        #expect(timeline.provisional == ProvisionalText(range: range(0, 1_200), text: "The kettle"))
        #expect(timeline.plainText.isEmpty, "provisional text is never part of the transcript's text")
        #expect(timeline.revision == 0, "a guess is not a change a person could save")

        #expect(timeline.apply(provisional(0, 1_600, "The kettle clicked off")) == .provisionalShown)
        #expect(timeline.provisional?.text == "The kettle clicked off", "a new guess replaces the previous one")
    }

    @Test func finalSegmentsDoNotDuplicateProvisionalText() {
        var timeline = TranscriptTimeline()
        var outcomes: [UpdateOutcome] = []
        // After every update, no word is both finalized and provisional.
        for update in ObservedSequence.updates {
            outcomes.append(timeline.apply(update))
            if let guess = timeline.provisional {
                for segment in timeline.segments {
                    #expect(!guess.range.overlaps(segment.range), "a guess overlapping finalized audio is never shown")
                }
            }
        }
        #expect(outcomes.filter { if case .finalized = $0 { true } else { false } }.count == 2)
        #expect(timeline.provisional == nil, "the last final result closed the last guess")
        #expect(timeline.segments.map(\.text) == ["Blue tape marks the 2nd shelf.", "Water the fern on Thursday."])
        #expect(timeline.plainText == "Blue tape marks the 2nd shelf.\nWater the fern on Thursday.")
        #expect(timeline.plainText.components(separatedBy: "Water").count == 2, "\"Water\" appears once, not once per guess")
    }

    @Test func aFinalResultClosesTheGuessItCovers() {
        var timeline = TranscriptTimeline()
        timeline.apply(provisional(1_680, 5_520, "Blue tape marks the 2nd shelf. Water"))
        timeline.apply(final(1_680, 3_960, "Blue tape marks the 2nd shelf."))
        // The guess ran past the final result's end, but its text includes the finalized words, so
        // it is removed; the recognizer sends a new guess for the rest.
        #expect(timeline.provisional == nil)
        #expect(timeline.finalizedThroughMilliseconds == 3_960)
    }

    @Test func aGuessForFinalizedAudioIsDropped() {
        var timeline = TranscriptTimeline()
        timeline.apply(final(0, 2_000, "The kettle clicked off at 7."))
        #expect(timeline.apply(provisional(0, 2_000, "The kettle clicked off at 7.")) == .staleProvisionalDropped)
        #expect(timeline.apply(provisional(500, 1_500, "clicked")) == .staleProvisionalDropped)
        #expect(timeline.provisional == nil)
        #expect(timeline.apply(provisional(2_000, 2_600, "Blue")) == .provisionalShown)
    }

    @Test func aRepeatedFinalIsIgnoredAndAnOverlappingOneIsRefused() {
        var timeline = TranscriptTimeline()
        timeline.apply(final(0, 2_000, "The kettle clicked off at 7."))
        #expect(timeline.apply(final(0, 2_000, "The kettle clicked off at 7.")) == .duplicateFinalIgnored)
        #expect(timeline.apply(final(1_000, 3_000, "off at seven, blue tape")) == .overlappingFinalRefused)
        #expect(timeline.segments.count == 1)
    }

    @Test func anEmptyFinalAddsNothingButClosesTheGuess() {
        var timeline = TranscriptTimeline()
        timeline.apply(provisional(0, 800, "uh"))
        #expect(timeline.apply(final(0, 800, "   ")) == .emptyFinalIgnored)
        #expect(timeline.segments.isEmpty)
        #expect(timeline.provisional == nil)
    }

    @Test func finalsArriveOutOfOrderAndStaySorted() {
        var timeline = TranscriptTimeline()
        timeline.apply(final(4_000, 5_000, "Third."))
        timeline.apply(final(0, 1_000, "First."))
        timeline.apply(final(2_000, 3_000, "Second."))
        #expect(timeline.segments.map(\.text) == ["First.", "Second.", "Third."])
        #expect(timeline.segments.map(\.id.rawValue) == [2, 3, 1], "IDs follow arrival; order follows media time")
    }

    @Test func wordTimesOutsideTheSegmentAreNotKept() {
        var timeline = TranscriptTimeline()
        timeline.apply(final(1_000, 2_000, "Blue tape", words: [
            TimedWord(range: range(1_000, 1_400), text: "Blue"),
            TimedWord(range: range(1_400, 2_400), text: "tape"),
        ]))
        #expect(timeline.segments[0].words.map(\.text) == ["Blue"])
    }

    // MARK: Corrections

    @Test func correctionsPreserveTheOriginalMediaTimestamps() throws {
        var timeline = observedTimeline()
        let original = try #require(timeline.segments.first)
        let revision = timeline.revision

        try timeline.correct(original.id, to: "Blue tape marks the second shelf.")
        let corrected = try #require(timeline.segment(original.id))
        #expect(corrected.text == "Blue tape marks the second shelf.")
        #expect(corrected.range == original.range, "the segment still points at the same audio")
        #expect(corrected.words == original.words, "word times describe the audio, not the correction")
        #expect(corrected.recognized == "Blue tape marks the 2nd shelf.", "what the recognizer said is kept")
        #expect(corrected.source == .onDeviceTranscriber)
        #expect(corrected.isCorrected)
        #expect(timeline.revision == revision + 1)
        #expect(timeline.segment(at: 2_900)?.id == original.id, "scrubbing to the audio still finds the corrected text")

        try timeline.revert(original.id)
        #expect(timeline.segment(original.id) == original)
    }

    @Test func aCorrectionIsValidatedAndARefusalChangesNothing() {
        var timeline = observedTimeline()
        let before = timeline
        let id = timeline.segments[0].id
        #expect(throws: TimelineError.emptyText) { try timeline.correct(id, to: "   ") }
        #expect(throws: TimelineError.controlCharacters) { try timeline.correct(id, to: "two\nlines") }
        #expect(throws: TimelineError.textTooLong(limit: SpeechTimelineLimits.segmentText)) {
            try timeline.correct(id, to: String(repeating: "a", count: SpeechTimelineLimits.segmentText + 1))
        }
        #expect(throws: TimelineError.unknownSegment(SegmentID(99))) { try timeline.correct(SegmentID(99), to: "x") }
        #expect(timeline == before)
    }

    // MARK: Manual annotation (the fallback)

    @Test func annotationsAddLabeledSegmentsWithoutOverlap() throws {
        var timeline = TranscriptTimeline()
        let first = try timeline.annotate(range(0, 1_800), text: "The kettle clicked off at seven.")
        try timeline.annotate(range(1_800, 3_900), text: "Blue tape marks the second shelf.")
        #expect(timeline.segments.map(\.source) == [.manual, .manual])
        #expect(throws: TimelineError.overlaps(first)) { try timeline.annotate(range(1_000, 2_000), text: "Overlap") }
        #expect(timeline.segments.count == 2)
    }

    @Test func invalidRangesAreRefused() {
        #expect(throws: TimelineError.invalidRange) { try MediaTimeRange(startMilliseconds: 1_000, endMilliseconds: 1_000) }
        #expect(throws: TimelineError.invalidRange) { try MediaTimeRange(startMilliseconds: -1, endMilliseconds: 10) }
        #expect(throws: TimelineError.invalidRange) { try MediaTimeRange(startSeconds: .nan, endSeconds: 1) }
        #expect(throws: TimelineError.mediaTooLong) {
            try MediaTimeRange(startMilliseconds: 0, endMilliseconds: SpeechTimelineLimits.mediaDuration + 1)
        }
    }

    // MARK: Scrubbing

    @Test func scrubbingFindsTheSegmentPlayingOrTheLastOneBefore() {
        let timeline = observedTimeline()
        #expect(timeline.segment(at: 0) == nil, "nothing has started before the first segment")
        #expect(timeline.segment(at: 1_680)?.text == "Blue tape marks the 2nd shelf.")
        #expect(timeline.segment(at: 3_959)?.text == "Blue tape marks the 2nd shelf.")
        #expect(timeline.segment(at: 3_960)?.text == "Water the fern on Thursday.", "a range's end is exclusive")
        #expect(timeline.segment(at: 60_000)?.text == "Water the fern on Thursday.")
        #expect(MediaClock.format(65_250) == "1:05.2")
        #expect(MediaClock.webVTT(3_723_004) == "01:02:03.004")
        #expect(MediaClock.spoken(61_000) == "1 minute 1 second")
    }
}
