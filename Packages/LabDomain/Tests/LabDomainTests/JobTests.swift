import Foundation
import LabDomain
import Testing

/// LAB-032 Render That Survives: a job records the truth about finite work through
/// `OperationService`, so a surface that shows it after the app returns shows what was committed.
/// Every step is authorized, leaves a receipt, never claims an undo, and follows one lifecycle.
@Suite struct JobTests {
    static let id = JobID(rawValue: uuid(800))

    private func draft(total: Int? = 4, namespace: DataNamespace = .demo) throws -> JobDraft {
        try JobDraft(id: Self.id, kind: .render, title: "Short color bars", total: total, namespace: namespace)
    }

    private func update(_ transition: JobTransition, expected: Int) -> DomainOperation {
        .updateJob(id: Self.id, expected: .r(expected), transition: transition)
    }

    private func output() throws -> JobOutput {
        try JobOutput(name: "short-bars.mov", byteCount: 2_048, sha256: String(repeating: "0f", count: 32), summary: "2.0 s")
    }

    @Test func startingAJobRecordsItRunningWithAReceiptAndNoUndo() async throws {
        let lab = Harness()
        let receipt = try await lab.perform(.startJob(draft: try draft()))
        #expect(receipt.status == .committed)
        #expect(receipt.changes.map(\.entity) == [.job(Self.id)])
        #expect(receipt.changes.map(\.newRevision) == [.initial])
        #expect(receipt.summary == "Started render job “Short color bars”.")
        #expect(receipt.undo == nil)
        let job = try await lab.service.findJob(Self.id, as: .appUI)
        let none = try JobProgress(completed: 0, total: 4)
        #expect(job.phase == .running && job.progress == none)
        #expect(job.namespace == .demo && job.jobKind == .render)
    }

    @Test func aJobCheckpointsStopsResumesAndFinishesWithOneReceiptPerStep() async throws {
        let lab = Harness()
        _ = try await lab.perform(.startJob(draft: try draft()))
        let saved = try await lab.perform(update(.checkpoint(completed: 2), expected: 1))
        #expect(saved.summary == "Saved render job “Short color bars” at 2 of 4.")
        let stopped = try await lab.perform(update(.interrupt(reason: .expired), expected: 2))
        #expect(stopped.summary == "Stopped render job “Short color bars” at 2 of 4 because its time in the background ran out. It can resume.")
        let resumed = try await lab.perform(update(.resume, expected: 3))
        #expect(resumed.summary == "Resumed render job “Short color bars” from 2 of 4.")
        _ = try await lab.perform(update(.checkpoint(completed: 3), expected: 4))
        let finished = try await lab.perform(update(.succeed(output: try output()), expected: 5))
        #expect(finished.summary == "Finished render job “Short color bars” as “short-bars.mov”.")
        #expect([saved, stopped, resumed, finished].allSatisfy { $0.undo == nil })

        let job = try await lab.service.findJob(Self.id, as: .appUI)
        let published = try output()
        let complete = try JobProgress(completed: 4, total: 4)
        #expect(job.phase == .succeeded(output: published))
        #expect(job.progress == complete)
        #expect(job.revision == .r(6))
        #expect(await lab.store.appliedCommits == 6)
    }

    @Test func aFinishedJobNeverChangesAgain() async throws {
        for ending in [JobTransition.cancel, .fail(failure: try JobFailure(code: "encoder-failed", message: "The encoder stopped."))] {
            let lab = Harness()
            _ = try await lab.perform(.startJob(draft: try draft()))
            _ = try await lab.perform(update(ending, expected: 1))
            for next in [JobTransition.resume, .cancel, .checkpoint(completed: 1), .succeed(output: try output())] {
                await #expect(throws: OperationError.ruleViolation(.jobFinished(Self.id))) {
                    try await lab.perform(update(next, expected: 2))
                }
            }
            #expect(await lab.store.appliedCommits == 2)
        }
    }

    @Test func eachTransitionNeedsItsPhase() async throws {
        let lab = Harness()
        _ = try await lab.perform(.startJob(draft: try draft()))
        await #expect(throws: OperationError.ruleViolation(.jobPhase(Self.id, current: .running))) {
            try await lab.perform(update(.resume, expected: 1))
        }
        _ = try await lab.perform(update(.interrupt(reason: .paused), expected: 1))
        for transition in [JobTransition.checkpoint(completed: 1), .interrupt(reason: .expired), .succeed(output: try output())] {
            await #expect(throws: OperationError.ruleViolation(.jobPhase(Self.id, current: .interrupted))) {
                try await lab.perform(update(transition, expected: 2))
            }
        }
        // An interrupted job can still be cancelled without resuming it.
        let cancelled = try await lab.perform(update(.cancel, expected: 2))
        #expect(cancelled.summary == "Cancelled render job “Short color bars”.")
    }

    @Test func progressOnlyMovesForwardAndStaysWithinTheTotal() async throws {
        let lab = Harness()
        _ = try await lab.perform(.startJob(draft: try draft()))
        _ = try await lab.perform(update(.checkpoint(completed: 2), expected: 1))
        await #expect(throws: OperationError.ruleViolation(.noChanges(.job(Self.id)))) {
            try await lab.perform(update(.checkpoint(completed: 2), expected: 2))
        }
        await #expect(throws: OperationError.ruleViolation(.jobProgress(Self.id))) {
            try await lab.perform(update(.checkpoint(completed: 1), expected: 2))
        }
        await #expect(throws: OperationError.ruleViolation(.jobProgress(Self.id))) {
            try await lab.perform(update(.checkpoint(completed: 5), expected: 2))
        }
        #expect(await lab.store.appliedCommits == 2)
    }

    @Test func aJobWithAnUnknownTotalCountsUpAndFinishesAtItsCount() async throws {
        let lab = Harness()
        _ = try await lab.perform(.startJob(draft: try draft(total: nil)))
        let saved = try await lab.perform(update(.checkpoint(completed: 7), expected: 1))
        #expect(saved.summary == "Saved render job “Short color bars” at 7.")
        _ = try await lab.perform(update(.succeed(output: try output()), expected: 2))
        let job = try await lab.service.findJob(Self.id, as: .appUI)
        #expect(job.progress.total == nil && job.progress.completed == 7 && job.progress.fraction == nil)
    }

    @Test func aStaleWorkerGetsAConflictReceiptAfterAPersonCancelled() async throws {
        let lab = Harness()
        _ = try await lab.perform(.startJob(draft: try draft()))
        _ = try await lab.perform(update(.cancel, expected: 1))
        // The worker still holds revision 1 and tries to save its next checkpoint.
        let stale = try await lab.perform(update(.checkpoint(completed: 1), expected: 1))
        let conflict = try #require(stale.conflict)
        #expect(conflict.entity == .job(Self.id) && conflict.expected == .initial && conflict.current == .r(2))
        #expect(stale.changes.isEmpty && stale.undo == nil)
        #expect(try await lab.service.findJob(Self.id, as: .appUI).phase == .cancelled)
    }

    @Test func aRetryOfTheSameRequestReturnsItsReceiptAndStartsNothingTwice() async throws {
        let lab = Harness()
        let requestID = RequestID()
        let first = try await lab.perform(.startJob(draft: try draft()), id: requestID)
        #expect(try await lab.perform(.startJob(draft: try draft()), id: requestID) == first)
        await #expect(throws: OperationError.ruleViolation(.alreadyExists(.job(Self.id)))) {
            try await lab.perform(.startJob(draft: try draft()))
        }
        #expect(await lab.store.appliedCommits == 1)
    }

    @Test func aModelToolCanReadAndProposeButNeverCommitAJobChange() async throws {
        let lab = Harness()
        await #expect(throws: OperationError.self) {
            try await lab.service.perform(OperationRequest(id: RequestID(), operation: .startJob(draft: try draft()), actor: .modelTool))
        }
        _ = try await lab.perform(.startJob(draft: try draft()))
        let proposal = try await lab.service.propose(update(.cancel, expected: 1), as: .modelTool)
        #expect(proposal.isReady && proposal.summary == "Cancel render job “Short color bars”.")
        #expect(try await lab.service.findJobs(kind: .render, as: .modelTool).map(\.id) == [Self.id])
        #expect(try await lab.service.findJobs(kind: JobKind(rawValue: "export"), as: .appUI).isEmpty)
        #expect(await lab.store.appliedCommits == 1)
    }

    @Test func resetDemoRemovesDemoJobsOnlyAndCountsThemApart() async throws {
        let lab = Harness()
        let seed = try DemoSeed(version: 1, collections: [CollectionDraft(id: CollectionID(rawValue: uuid(802)), title: "Swatches")], items: [])
        _ = try await lab.perform(.resetDemo(seed: seed))
        let userJob = JobID(rawValue: uuid(801))
        _ = try await lab.perform(.startJob(draft: try draft()))
        _ = try await lab.perform(.startJob(draft: try JobDraft(id: userJob, kind: .render, title: "Mine", total: 1, namespace: .user)))
        let reset = try await lab.perform(.resetDemo(seed: seed))
        #expect(reset.removed == [EntityReference.job(Self.id)])
        #expect(reset.summary == "Reset the demo to its original 1 collection and 0 items: removed 1 job.")
        await #expect(throws: OperationError.notFound(.job(Self.id))) { try await lab.service.findJob(Self.id, as: .appUI) }
        #expect(try await lab.service.findJob(userJob, as: .appUI).namespace == .user)
    }

    @Test func jobValuesValidateThemselves() throws {
        #expect(JobKind(rawValue: "render") == .render)
        for bad in ["", "Render", "re nder", "-render", "render-", "re--nder", String(repeating: "a", count: 41)] {
            #expect(JobKind(rawValue: bad) == nil)
        }
        #expect(throws: ValidationError.progressOutOfRange) { try JobProgress(completed: 3, total: 2) }
        #expect(throws: ValidationError.progressOutOfRange) { try JobProgress(completed: -1, total: nil) }
        #expect(throws: ValidationError.progressOutOfRange) { try JobProgress(completed: 0, total: 0) }
        #expect(throws: ValidationError.progressOutOfRange) { try JobDraft(kind: .render, title: "X", total: 0) }
        #expect(throws: ValidationError.invalidSlug(in: .failureCode)) { try JobFailure(code: "Bad Code", message: "x") }
        #expect(throws: ValidationError.textLength(in: .failureMessage)) { try JobFailure(code: "x", message: "  ") }
        #expect(throws: ValidationError.controlCharacter(in: .failureMessage)) { try JobFailure(code: "x", message: "a\nb") }
        let digest = String(repeating: "0f", count: 32)
        for name in ["", ".hidden.mov", "../escape.mov", "folder/file.mov", "a:b.mov", " padded.mov", String(repeating: "a", count: 121)] {
            #expect(throws: ValidationError.unsafeFileName) { try JobOutput(name: name, byteCount: 1, sha256: digest, summary: "") }
        }
        #expect(throws: ValidationError.invalidDigest) { try JobOutput(name: "a.mov", byteCount: 1, sha256: "ABC", summary: "") }
        #expect(throws: ValidationError.negativeByteCount) { try JobOutput(name: "a.mov", byteCount: -1, sha256: digest, summary: "") }
    }

    @Test func aJobOperationKeepsAStableJSONShape() throws {
        let operation = update(.interrupt(reason: .leftForeground), expected: 3)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(operation), as: UTF8.self)
        #expect(json == #"{"updateJob":{"expected":3,"id":"00000000-0000-0000-0000-000000000800","transition":{"interrupt":{"reason":"left-foreground"}}}}"#)
        #expect(try JSONDecoder().decode(DomainOperation.self, from: Data(json.utf8)) == operation)
        // A hostile payload cannot smuggle an invalid value past decoding.
        let backwards = #"{"completed":5,"total":2}"#
        #expect(throws: ValidationError.progressOutOfRange) { try JSONDecoder().decode(JobProgress.self, from: Data(backwards.utf8)) }
    }
}
