import Foundation
import LabDomain
import LabJobs
import Synchronization
import Testing

// LAB-032-B: the job contract that Live Session Beacon (LAB-005), Object Forge (LAB-025), and
// Capture With Consent (LAB-033) reuse. Each needs only a new `JobKind` and its own worker, so
// these tests run the runtime with kinds other than `render` and pin the lifecycle table, the
// progress rules, the receipts, and the file helpers they will rely on.

/// The kinds a later lab might name. None is declared in the domain; any slug works.
enum LaterKinds {
    static let reconstruction = JobKind(rawValue: "object-reconstruction")!
    static let capture = JobKind(rawValue: "capture")!
}

@Suite struct JobKindContractQualification {
    @Test func aNewKindRunsTheWholeLifecycleWithReceiptsNamingIt() async throws {
        let lab = Lab()
        let draft = try JobDraft(kind: LaterKinds.reconstruction, title: EntityTitle("Teapot scan"), total: 4)
        let (recorder, started) = try await JobRecorder.start(draft, backend: lab.backend)
        try await recorder.advance(.checkpoint(completed: 2))
        try await recorder.advance(.interrupt(reason: .leftForeground))
        try await recorder.advance(.resume)
        let output = try JobOutput(name: "teapot.usdz", byteCount: 2_048, sha256: String(repeating: "b", count: 64), summary: "A model")
        let finished = try await recorder.advance(.succeed(output: output))

        #expect(started.summary == "Started object-reconstruction job “Teapot scan”.")
        #expect(finished.summary == "Finished object-reconstruction job “Teapot scan” as “teapot.usdz”.")
        let job = await recorder.job
        #expect(job.jobKind == LaterKinds.reconstruction && job.progress.completed == 4)
        #expect(try await lab.backend.jobs(of: LaterKinds.reconstruction).map(\.id) == [draft.id])
        #expect(try await lab.backend.jobs(of: .render).isEmpty)
    }

    @Test func anUnknownTotalIsIndeterminateAndStillOnlyMovesForward() async throws {
        let lab = Lab()
        let draft = try JobDraft(kind: LaterKinds.capture, title: EntityTitle("Consent clip"), total: nil)
        let (recorder, _) = try await JobRecorder.start(draft, backend: lab.backend)
        let saved = try await recorder.advance(.checkpoint(completed: 7))
        #expect(saved.summary == "Saved capture job “Consent clip” at 7.")
        let job = await recorder.job
        #expect(job.progress.total == nil && job.progress.fraction == nil && job.progress.phrase == "7")
        await #expect(throws: JobError.refused(.ruleViolation(.jobProgress(draft.id)))) {
            try await recorder.advance(.checkpoint(completed: 3))
        }
        // Finishing an indeterminate job keeps its count rather than inventing a total.
        let output = try JobOutput(name: "clip.mov", byteCount: 1, sha256: String(repeating: "c", count: 64), summary: "")
        try await recorder.advance(.succeed(output: output))
        #expect(await recorder.job.progress == (try JobProgress(completed: 7, total: nil)))
    }

    @Test func recoveryOnlyTouchesTheKindItIsAskedAbout() async throws {
        let lab = Lab()
        let render = try await JobRecorder.start(try lab.draft("Render"), backend: lab.backend).recorder
        let capture = try await JobRecorder.start(
            try JobDraft(kind: LaterKinds.capture, title: EntityTitle("Capture"), total: 2), backend: lab.backend
        ).recorder
        let receipts = try await JobRecovery.reconcile(kind: LaterKinds.capture, backend: lab.backend, isLive: { _ in false })
        #expect(receipts.map(\.summary) == ["Stopped capture job “Capture” at 0 of 2 because the app stopped while it ran. It can resume."])
        #expect(try await lab.backend.job(capture.id).phase == .interrupted(reason: .appStopped))
        #expect(try await lab.backend.job(render.id).phase == .running)
    }

    @Test func kindsAreShortLowercaseSlugs() {
        for valid in ["render", "object-reconstruction", "capture", "a1", String(repeating: "k", count: 40)] {
            #expect(JobKind(rawValue: valid) != nil, "\(valid)")
        }
        for invalid in ["", "Render", "two--hyphens", "-lead", "trail-", "with space", "café", String(repeating: "k", count: 41)] {
            #expect(JobKind(rawValue: invalid) == nil, "\(invalid)")
        }
    }
}

/// The lifecycle table in `JobTransition`, every phase against every step, through the service.
@Suite struct JobLifecycleTableQualification {
    static let transitions: [(String, JobTransition)] = [
        ("checkpoint", .checkpoint(completed: 2)),
        ("interrupt", .interrupt(reason: .paused)),
        ("resume", .resume),
        ("cancel", .cancel),
        ("fail", .fail(failure: try! JobFailure(code: "test-failure", message: "It failed."))),
        ("succeed", .succeed(output: try! JobOutput(name: "out.bin", byteCount: 1, sha256: String(repeating: "d", count: 64), summary: ""))),
    ]

    /// Which steps each phase allows, from the table in `JobTransition`.
    static let allowed: [JobPhase.Name: Set<String>] = [
        .running: ["checkpoint", "interrupt", "cancel", "fail", "succeed"],
        .interrupted: ["resume", "cancel", "fail"],
        .succeeded: [], .failed: [], .cancelled: [],
    ]

    /// A job of a later kind brought to `phase` at 1 of 3.
    func job(in phase: JobPhase.Name, lab: Lab) async throws -> LabJob {
        let draft = try JobDraft(kind: LaterKinds.reconstruction, title: EntityTitle("Table"), total: 3)
        let (recorder, _) = try await JobRecorder.start(draft, backend: lab.backend)
        try await recorder.advance(.checkpoint(completed: 1))
        switch phase {
        case .running: break
        case .interrupted: try await recorder.advance(.interrupt(reason: .expired))
        case .succeeded: try await recorder.advance(Self.transitions[5].1)
        case .failed: try await recorder.advance(Self.transitions[4].1)
        case .cancelled: try await recorder.advance(.cancel)
        }
        return await recorder.job
    }

    @Test(arguments: JobPhase.Name.allCases)
    func eachPhaseAllowsExactlyItsSteps(_ phase: JobPhase.Name) async throws {
        for (name, transition) in Self.transitions {
            let lab = Lab()
            let before = try await job(in: phase, lab: lab)
            let request = OperationRequest(
                id: RequestID(), operation: .updateJob(id: before.id, expected: before.revision, transition: transition), actor: appUI
            )
            let allowed = Self.allowed[phase]!.contains(name)
            let result: Result<ActionReceipt, OperationError>
            do { result = .success(try await lab.service.perform(request)) } catch { result = .failure(error) }
            switch result {
            case .success(let receipt):
                #expect(allowed, "\(phase) allowed \(name)")
                #expect(receipt.status == .committed && receipt.undo == nil, "\(phase) \(name)")
                #expect(try await lab.backend.job(before.id).revision == before.revision.next())
            case .failure(let error):
                #expect(!allowed, "\(phase) refused \(name): \(error)")
                let expected: OperationError = phase == .succeeded || phase == .failed || phase == .cancelled
                    ? .ruleViolation(.jobFinished(before.id))
                    : .ruleViolation(.jobPhase(before.id, current: phase))
                #expect(error == expected, "\(phase) \(name)")
                #expect(try await lab.backend.job(before.id) == before, "a refusal changes nothing")
            }
        }
    }

    @Test func checkpointsMoveForwardWithinTheTotal() async throws {
        let lab = Lab()
        let job = try await job(in: .running, lab: lab)
        func checkpoint(_ completed: Int) async -> OperationError? {
            let current = try? await lab.backend.job(job.id)
            let request = OperationRequest(
                id: RequestID(), operation: .updateJob(id: job.id, expected: current!.revision, transition: .checkpoint(completed: completed)),
                actor: appUI
            )
            do { _ = try await lab.service.perform(request); return nil } catch { return error }
        }
        #expect(await checkpoint(1) == .ruleViolation(.noChanges(.job(job.id))))
        #expect(await checkpoint(0) == .ruleViolation(.jobProgress(job.id)))
        #expect(await checkpoint(4) == .ruleViolation(.jobProgress(job.id)))
        #expect(await checkpoint(3) == nil)
    }

    @Test func aStepAtAStaleRevisionGetsAConflictReceiptAndChangesNothing() async throws {
        let lab = Lab()
        let stale = try await job(in: .running, lab: lab)
        _ = try await JobRecorder(job: stale, backend: lab.backend).advance(.checkpoint(completed: 2))
        let current = try await lab.backend.job(stale.id)
        let receipt = try await lab.backend.commit(.updateJob(id: stale.id, expected: stale.revision, transition: .cancel), requestID: RequestID())
        #expect(receipt.conflict != nil)
        #expect(try await lab.backend.job(stale.id) == current)
    }
}

@Suite struct JobRuntimeContractQualification {
    @Test func aRetriedStartWithTheSameDraftAndRequestRecordsOneJobAndOneReceipt() async throws {
        let lab = Lab()
        let draft = try JobDraft(kind: LaterKinds.capture, title: EntityTitle("Retry"), total: 1)
        let request = RequestID()
        let first = try await JobRecorder.start(draft, backend: lab.backend, requestID: request)
        let second = try await JobRecorder.start(draft, backend: lab.backend, requestID: request)
        #expect(first.receipt == second.receipt)
        #expect(await lab.store.jobs().count == 1)
        // The same ID for a different draft is a reused request, refused.
        let other = try JobDraft(kind: LaterKinds.capture, title: EntityTitle("Other"), total: 1)
        await #expect(throws: JobError.refused(.requestIDReused(request))) {
            try await JobRecorder.start(other, backend: lab.backend, requestID: request)
        }
    }

    @Test func aModelToolMayReadJobsButNeverChangeThem() async throws {
        let lab = Lab()
        let (recorder, _) = try await JobRecorder.start(try lab.draft(), backend: lab.backend)
        let model = ServiceJobBackend(service: lab.service, actor: ActorScope(adapter: .modelTool, grants: Set(Permission.allCases)))
        #expect(try await model.job(recorder.id).phase == .running)
        let job = await recorder.job
        do {
            _ = try await model.commit(.updateJob(id: job.id, expected: job.revision, transition: .cancel), requestID: RequestID())
            Issue.record("a model tool changed a job")
        } catch {
            guard case .refused(.unauthorized) = error else { Issue.record("\(error)"); return }
        }
        #expect(try await lab.backend.job(job.id) == job)
    }

    @Test func everyStepIsAReceiptUnderTheCallersAdapterWithNoUndo() async throws {
        let lab = Lab()
        let intent = ServiceJobBackend(service: lab.service, actor: ActorScope(adapter: .appIntent, grants: Set(Permission.allCases)))
        let (recorder, started) = try await JobRecorder.start(try lab.draft(), backend: intent)
        let steps = [
            started,
            try await recorder.advance(.checkpoint(completed: 1)),
            try await recorder.advance(.interrupt(reason: .paused)),
            try await recorder.advance(.cancel),
        ]
        #expect(steps.allSatisfy { $0.admitted.adapter == .appIntent && $0.undo == nil && $0.status == .committed })
        #expect(steps.map(\.admitted.operation.kind) == [.startJob, .updateJob, .updateJob, .updateJob])
    }

    @Test func aStopSignalHitFromManyThreadsKeepsCancelAndTheFirstInterruption() async {
        for _ in 0..<50 {
            let signal = JobStopSignal()
            await withTaskGroup(of: Void.self) { group in
                for index in 0..<32 {
                    group.addTask {
                        signal.request(index == 17 ? .cancel : .interrupt(index.isMultiple(of: 2) ? .paused : .expired))
                    }
                }
            }
            #expect(signal.current == .cancel)
        }
        let signal = JobStopSignal()
        signal.request(.interrupt(.expired))
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<32 { group.addTask { signal.request(.interrupt(.paused)) } }
        }
        #expect(signal.current == .interrupt(.expired))
    }

    @Test func aReaderAlwaysSeesAWholeFileWhilePublicationsReplaceIt() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "LabJobsPublish-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "Output/movie.mov")
        let versions = [Data(repeating: 0x41, count: 256 * 1024), Data(repeating: 0x42, count: 192 * 1024)]
        let staged = root.appending(path: "staged.partial")
        try versions[0].write(to: staged)
        _ = try AtomicPublication.publish(staged, to: destination)

        let done = Mutex(false)
        let reads = Mutex<(whole: Int, other: Int)>((0, 0))
        let reader = Task.detached {
            while !done.withLock({ $0 }) {
                guard let data = try? Data(contentsOf: destination) else {
                    reads.withLock { $0.other += 1 }
                    continue
                }
                reads.withLock { if versions.contains(data) { $0.whole += 1 } else { $0.other += 1 } }
            }
        }
        for round in 1...200 {
            try versions[round % 2].write(to: staged)
            _ = try AtomicPublication.publish(staged, to: destination)
        }
        done.withLock { $0 = true }
        await reader.value
        let (whole, other) = reads.withLock { $0 }
        #expect(whole > 0)
        #expect(other == 0, "\(other) reads saw a missing or partial file")
    }

    @Test func theForegroundRunwayNamesEveryReasonAndNeverExpires() async {
        for reason in ForegroundOnlyReason.allCases {
            let expired = Mutex(false)
            let lease = await ForegroundRunway(reason: reason).begin(
                RunwayRequest(title: "Job", subtitle: "", wantsBackground: true), onExpiration: { expired.withLock { $0 = true } }
            )
            #expect(lease.mode == .foregroundOnly(reason))
            #expect(lease.mode.summary.contains(reason.clause))
            lease.report(completed: 1, total: 2)
            lease.finish(success: false)
            #expect(!expired.withLock { $0 })
        }
    }

    #if os(macOS)
    @Test func theMacWorkersLeaseRunsWhileTheAppRunsAndEndsOnce() async {
        let lease = await MacWorkerRunway().begin(RunwayRequest(title: "Job", subtitle: "", wantsBackground: true), onExpiration: {})
        #expect(lease.mode == .whileAppRuns)
        lease.finish(success: true)
        lease.finish(success: false)
    }
    #endif
}
