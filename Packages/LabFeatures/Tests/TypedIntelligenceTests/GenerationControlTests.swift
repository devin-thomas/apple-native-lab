import Foundation
import LabDomain
import Testing
@testable import TypedIntelligence

/// LAB-010-A: generation is cancellable and time-bounded, and neither path leaves a proposal.
@Suite struct GenerationControlTests {
    static let validDraft = ExtractionDraft(
        sampleTitle: "Cobalt swatch", newTitle: "Cobalt swatch (bleeds)", addedNote: "Bleeds.", evidence: ["stayed tacky for hours"]
    )

    @Test func aDraftThatIgnoresCancellationIsAbandonedAtTheLimit() async throws {
        let lab = try await Lab.seeded(timeLimit: .milliseconds(200))
        let finishedLate = Flag()
        let stalled = ScriptedExtractor { _ throws(ExtractionFailure) -> ExtractionDraft in
            await uncancellableWait(2)
            finishedLate.set()
            return Self.validDraft
        }
        let clock = ContinuousClock()
        let start = clock.now
        let result = await lab.flow.draft(try Repository.note(.ambiguousNote), with: stalled, candidates: try await lab.candidates())
        let elapsed = clock.now - start
        #expect(throws: ExtractionFailure.timedOut(limit: .milliseconds(200))) { try result.get() }
        #expect(elapsed < .seconds(1), "returned at the limit, not when the extractor finished")
        #expect(!finishedLate.isSet)
        #expect(lab.store.appliedCount == 0)
        let event = try #require(lab.events.events.last)
        #expect(event.phase == "intelligence.draft.model" && event.outcome == .failed && event.category == .unavailable)
    }

    @Test func cancellingTheCallerStopsTheDraftPromptly() async throws {
        let lab = try await Lab.seeded(timeLimit: .seconds(30))
        let sawCancellation = Flag()
        let cooperative = ScriptedExtractor { _ throws(ExtractionFailure) -> ExtractionDraft in
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                sawCancellation.set()
                throw .cancelled
            }
            return Self.validDraft
        }
        let note = try Repository.note(.ambiguousNote)
        let candidates = try await lab.candidates()
        let task = Task { await lab.flow.draft(note, with: cooperative, candidates: candidates) }
        try await Task.sleep(for: .milliseconds(100))
        let clock = ContinuousClock()
        let start = clock.now
        task.cancel()
        let result = await task.value
        #expect(clock.now - start < .seconds(1))
        #expect(throws: ExtractionFailure.cancelled) { try result.get() }
        // The extractor's own task was cancelled too, not left running.
        for _ in 0..<50 where !sawCancellation.isSet { try await Task.sleep(for: .milliseconds(20)) }
        #expect(sawCancellation.isSet)
        #expect(lab.store.appliedCount == 0)
        #expect(lab.events.events.last?.outcome == .cancelled)
    }

    @Test func cancellingAnExtractorThatIgnoresItStillReturnsAtOnce() async throws {
        let lab = try await Lab.seeded(timeLimit: .seconds(30))
        let stubborn = ScriptedExtractor { _ throws(ExtractionFailure) -> ExtractionDraft in
            await uncancellableWait(2)
            return Self.validDraft
        }
        let note = try Repository.note(.ambiguousNote)
        let candidates = try await lab.candidates()
        let task = Task { await lab.flow.draft(note, with: stubborn, candidates: candidates) }
        try await Task.sleep(for: .milliseconds(50))
        let clock = ContinuousClock()
        let start = clock.now
        task.cancel()
        let result = await task.value
        #expect(clock.now - start < .milliseconds(500))
        #expect(throws: ExtractionFailure.cancelled) { try result.get() }
        #expect(lab.store.appliedCount == 0)
    }

    @Test func anAlreadyCancelledTaskDraftsNothing() async throws {
        let lab = try await Lab.seeded()
        let ran = Flag()
        let extractor = ScriptedExtractor { _ throws(ExtractionFailure) -> ExtractionDraft in
            ran.set()
            return Self.validDraft
        }
        let note = try Repository.note(.ambiguousNote)
        let candidates = try await lab.candidates()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await lab.flow.draft(note, with: extractor, candidates: candidates)
        }
        let result = await task.value
        #expect(throws: ExtractionFailure.cancelled) { try result.get() }
        #expect(!ran.isSet, "the extractor never started")
        #expect(lab.store.appliedCount == 0)
    }

    @Test func aQuickDraftWithinTheLimitSucceeds() async throws {
        let lab = try await Lab.seeded(timeLimit: .seconds(2))
        let result = await lab.flow.draft(
            try Repository.note(.ambiguousNote), with: ScriptedExtractor(returning: Self.validDraft), candidates: try await lab.candidates()
        )
        #expect(try result.get().isApprovable)
        let event = try #require(lab.events.events.last)
        #expect(event.outcome == .succeeded)
        #expect(event.counts.contains { $0.name == "approvable" && $0.value == 1 })
    }

    @Test func noSamplesMeansNoDraft() async throws {
        let lab = try await Lab.seeded()
        let ran = Flag()
        let extractor = ScriptedExtractor { _ throws(ExtractionFailure) -> ExtractionDraft in
            ran.set()
            return Self.validDraft
        }
        let result = await lab.flow.draft(try Repository.note(.ambiguousNote), with: extractor, candidates: [])
        #expect(throws: ExtractionFailure.noSamples) { try result.get() }
        #expect(!ran.isSet)
    }

    @Test func theModelIsCheckedAgainForEveryRequest() async throws {
        // The real extractor reads availability per request. When the model is unavailable here it
        // fails with that reason; when it is available, the check passes and the draft proceeds.
        let reason = OnDeviceModelExtractor.unavailability()
        guard let reason else { return }
        let lab = try await Lab.seeded()
        let result = await lab.flow.draft(try Repository.note(.ambiguousNote), with: OnDeviceModelExtractor(), candidates: try await lab.candidates())
        #expect(throws: ExtractionFailure.modelUnavailable(reason)) { try result.get() }
    }
}
