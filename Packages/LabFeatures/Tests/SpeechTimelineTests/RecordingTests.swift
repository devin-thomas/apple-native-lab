import Foundation
import LabSupport
import Testing
@testable import SpeechTimeline

/// Recording asks for the microphone only after the person's Record action, through the lab's
/// permission stager, and a route change pauses the session without losing it.
@Suite struct RecordingTests {
    // MARK: The gate

    @Test func nothingAsksForTheMicrophoneUntilRecordIsPressed() async throws {
        let requester = CountingRequester(answer: .authorized)
        let stager = PermissionStager(platform: .iOS, source: FakeCapabilitySource(), requester: requester)
        let gate = RecordingGate(stager: stager)
        // Everything the experiment does before Record: read languages, transcribe a file, import
        // captions, annotate, and export.
        let flow = SpeechTimelineFlow(recognizer: ScriptedRecognizer())
        _ = await flow.languages()
        _ = await flow.transcribe(file: URL(fileURLWithPath: "/dev/null"), language: "en-US")
        var timeline = try SpeechFixture.captions(at: Repository.fixture(.sampleCaptions))
        try timeline.annotate(range(20_000, 21_000), text: "A note.")
        _ = CaptionDocument.render(timeline)
        #expect(requester.requested.isEmpty)

        #expect(await gate.decide() == .record(systemAsks: false))
        #expect(requester.requested == [.microphone], "Record asked once, for the microphone only")
    }

    @Test func aDeclinedPromptFallsBackAndIsNotAskedAgain() async {
        let requester = CountingRequester(answer: .denied)
        let gate = RecordingGate(stager: PermissionStager(platform: .iOS, source: FakeCapabilitySource(), requester: requester))
        guard case .fallback(let reason, let route) = await gate.decide() else {
            Issue.record("a declined prompt must fall back")
            return
        }
        #expect(reason == "Microphone access was declined.")
        #expect(route.experiments.contains(SpeechTimeline.experimentID))

        let later = RecordingGate(stager: PermissionStager(platform: .iOS, source: FakeCapabilitySource(microphone: .denied), requester: requester))
        #expect(await later.decide() == .fallback(reason: "Microphone access was declined earlier. The lab does not ask again.", fallback: Capability.microphone.fallback))
        #expect(requester.requested == [.microphone], "the earlier refusal is respected without a second prompt")
    }

    @Test func aBuildWithoutThePurposeStringOrEntitlementNeverAsks() async {
        let requester = CountingRequester()
        let noPurpose = RecordingGate(stager: PermissionStager(
            platform: .iOS, source: FakeCapabilitySource(purposeStrings: []), requester: requester))
        #expect(await noPurpose.decide() == .fallback(
            reason: "This build does not declare NSMicrophoneUsageDescription, so the lab does not ask for the microphone.",
            fallback: Capability.microphone.fallback))
        let noEntitlement = RecordingGate(stager: PermissionStager(
            platform: .macOS, source: FakeCapabilitySource(entitlements: []), requester: requester))
        #expect(await noEntitlement.decide() == .fallback(
            reason: "This build is not signed with com.apple.security.device.audio-input, so the sandbox would refuse the microphone.",
            fallback: Capability.microphone.fallback))
        #expect(requester.requested.isEmpty)
    }

    // MARK: The session

    @Test func routeChangesDoNotSilentlyLoseTheSession() async throws {
        let capture = ScriptedCapture([
            .update(provisional(0, 1_700, "The kettle clicked")),
            .update(final(0, 1_700, "The kettle clicked off at 7.")),
            .update(provisional(1_700, 2_600, "Blue tape")),
            .routeChanged(reason: "the audio device in use was disconnected"),
            // Nothing after a route change is applied.
            .update(final(1_700, 3_900, "Blue tape marks the 2nd shelf.")),
        ])
        var session = RecordingSession()
        var timeline = TranscriptTimeline()
        session.beginRun(on: timeline)
        for await event in try await capture.start(language: "en-US") {
            session.handle(event, timeline: &timeline)
        }
        #expect(session.state == .paused(.routeChanged("the audio device in use was disconnected")))
        #expect(timeline.segments.map(\.text) == ["The kettle clicked off at 7."], "every finalized segment is kept")
        #expect(timeline.provisional == nil, "unfinished text is not kept as if it were final")
        #expect(session.discardedProvisionals == 1)
        #expect(session.summary(segments: timeline.segments.count)
            == "Recording paused because the audio route changed: the audio device in use was disconnected. 1 segment kept. Unfinished text was removed once because it was never finalized. Resume continues the same timeline.")

        // Resume: the next run's time starts where the timeline ended.
        let resumed = ScriptedCapture([
            .update(final(0, 2_200, "Blue tape marks the 2nd shelf.")),
            .ended,
        ])
        session.beginRun(on: timeline)
        #expect(session.offsetMilliseconds == 1_700)
        for await event in try await resumed.start(language: "en-US") {
            session.handle(event, timeline: &timeline)
        }
        #expect(timeline.segments.map(\.range) == [range(0, 1_700), range(1_700, 3_900)])
        #expect(session.state == .paused(.stoppedByPerson))
        #expect(session.runs == 2)
    }

    @Test func anInterruptionPausesAndAFailureKeepsTheSegments() {
        var session = RecordingSession()
        var timeline = TranscriptTimeline()
        session.beginRun(on: timeline)
        session.handle(.update(final(0, 1_000, "One.")), timeline: &timeline)
        session.handle(.interrupted, timeline: &timeline)
        #expect(session.state == .paused(.interrupted))
        // Updates after a pause are ignored until the next run.
        #expect(session.handle(.update(final(1_000, 2_000, "Two.")), timeline: &timeline) == nil)
        session.beginRun(on: timeline)
        session.handle(.update(final(0, 500, "Two.")), timeline: &timeline)
        session.handle(.failed(.engineFailed), timeline: &timeline)
        #expect(session.state == .failed(.engineFailed))
        #expect(timeline.segments.map(\.text) == ["One.", "Two."])
        #expect(timeline.segments[1].range == range(1_000, 1_500))
    }

    @Test func aRecordingAfterAnnotationsStartsAfterThem() throws {
        var timeline = TranscriptTimeline()
        try timeline.annotate(range(0, 4_000), text: "Typed first.")
        var session = RecordingSession()
        session.beginRun(on: timeline)
        #expect(session.handle(.update(final(0, 1_000, "Spoken.")), timeline: &timeline) == .finalized(SegmentID(2)))
        #expect(timeline.segments.last?.range == range(4_000, 5_000))
    }
}
