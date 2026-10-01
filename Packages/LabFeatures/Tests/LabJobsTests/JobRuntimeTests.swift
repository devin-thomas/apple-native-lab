import Foundation
import LabDomain
import LabJobs
import Synchronization
import Testing

let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

/// A service over an in-memory store, with a backend under the app-UI actor.
struct Lab {
    let store = InMemoryOperationStore()
    let service: OperationService
    let backend: ServiceJobBackend

    init() {
        service = OperationService(store: store)
        backend = ServiceJobBackend(service: service, actor: appUI)
    }

    func draft(_ title: String = "Export", total: Int? = 3) throws -> JobDraft {
        try JobDraft(kind: .render, title: EntityTitle(title), total: total)
    }
}

/// A backend whose next commits fail in the store, to model a commit whose outcome was lost.
final class FlakyBackend: JobBackend {
    let inner: any JobBackend
    let failures = Mutex(0)
    let commits = Mutex<[RequestID]>([])

    init(_ inner: any JobBackend) { self.inner = inner }

    func job(_ id: JobID) async throws(JobError) -> LabJob { try await inner.job(id) }
    func jobs(of kind: JobKind) async throws(JobError) -> [LabJob] { try await inner.jobs(of: kind) }

    func commit(_ operation: DomainOperation, requestID: RequestID) async throws(JobError) -> ActionReceipt {
        commits.withLock { $0.append(requestID) }
        let receipt = try await inner.commit(operation, requestID: requestID)
        let fail = failures.withLock { count in
            defer { count = max(0, count - 1) }
            return count > 0
        }
        // The commit landed, but the caller hears that it failed.
        if fail { throw .refused(.storeFailure(.commitFailed)) }
        return receipt
    }
}

/// LAB-032's reusable job runtime: the recorder, recovery, and stop signal over OperationService.
@Suite struct JobRecorderTests {
    @Test func aRecorderStartsCheckpointsAndFinishesAJobWithAReceiptPerStep() async throws {
        let lab = Lab()
        let (recorder, started) = try await JobRecorder.start(try lab.draft(), backend: lab.backend)
        #expect(started.summary == "Started render job “Export”.")
        try await recorder.advance(.checkpoint(completed: 1))
        try await recorder.advance(.checkpoint(completed: 2))
        let output = try JobOutput(name: "export.mov", byteCount: 10, sha256: String(repeating: "a", count: 64), summary: "")
        let finished = try await recorder.advance(.succeed(output: output))
        #expect(finished.summary == "Finished render job “Export” as “export.mov”.")
        let job = await recorder.job
        #expect(job.phase == .succeeded(output: output) && job.progress.completed == 3 && job.revision == .r(4))
    }

    @Test func aJobCancelledElsewhereStopsTheRecorderWithoutAnotherChange() async throws {
        let lab = Lab()
        let (recorder, _) = try await JobRecorder.start(try lab.draft(), backend: lab.backend)
        // Another window cancels through its own recorder.
        let other = JobRecorder(job: await recorder.job, backend: lab.backend)
        try await other.advance(.cancel)
        await #expect(throws: JobError.changedElsewhere(.cancelled)) {
            try await recorder.advance(.checkpoint(completed: 1))
        }
        #expect(await recorder.job.phase == .cancelled)
    }

    @Test func aJobRemovedByResetDemoStopsTheRecorder() async throws {
        let lab = Lab()
        let (recorder, _) = try await JobRecorder.start(try lab.draft(), backend: lab.backend)
        let seed = try DemoSeed(version: 1, collections: [CollectionDraft(title: try EntityTitle("Swatches"))], items: [])
        _ = try await lab.service.perform(OperationRequest(id: RequestID(), operation: .resetDemo(seed: seed), actor: appUI))
        await #expect(throws: JobError.changedElsewhere(nil)) {
            try await recorder.advance(.checkpoint(completed: 1))
        }
    }

    @Test func aCommitWhoseResultWasLostIsRetriedUnderItsRequestIDAndLandsOnce() async throws {
        let lab = Lab()
        let flaky = FlakyBackend(lab.backend)
        let (recorder, _) = try await JobRecorder.start(try lab.draft(), backend: flaky)
        flaky.failures.withLock { $0 = 1 }
        let receipt = try await recorder.advance(.checkpoint(completed: 1))
        let requests = flaky.commits.withLock { $0 }
        #expect(requests.count == 3 && requests[1] == requests[2])
        #expect(receipt.summary == "Saved render job “Export” at 1 of 3.")
        #expect(await recorder.job.revision == .r(2))
    }

    @Test func recoveryMarksOrphanedRunningJobsAndLeavesLiveAndStoppedOnes() async throws {
        let lab = Lab()
        let orphan = try await JobRecorder.start(try lab.draft("Orphan"), backend: lab.backend).recorder
        let live = try await JobRecorder.start(try lab.draft("Live"), backend: lab.backend).recorder
        let paused = try await JobRecorder.start(try lab.draft("Paused"), backend: lab.backend).recorder
        try await paused.advance(.interrupt(reason: .paused))
        let liveID = live.id

        let receipts = try await JobRecovery.reconcile(kind: .render, backend: lab.backend, isLive: { $0 == liveID })
        #expect(receipts.map(\.summary) == ["Stopped render job “Orphan” at 0 of 3 because the app stopped while it ran. It can resume."])
        #expect(try await lab.backend.job(orphan.id).phase == .interrupted(reason: .appStopped))
        #expect(try await lab.backend.job(live.id).phase == .running)
        #expect(try await lab.backend.job(paused.id).phase == .interrupted(reason: .paused))
        // Running it again finds nothing more to do.
        #expect(try await JobRecovery.reconcile(kind: .render, backend: lab.backend, isLive: { $0 == liveID }).isEmpty)
    }

    @Test func aModelToolBackendCannotStartAJob() async throws {
        let lab = Lab()
        let model = ServiceJobBackend(service: lab.service, actor: ActorScope(adapter: .modelTool, grants: Set(Permission.allCases)))
        await #expect(throws: JobError.self) { try await JobRecorder.start(try lab.draft(), backend: model) }
        #expect(await lab.store.jobs().isEmpty)
    }
}

@Suite struct StopSignalTests {
    @Test func aCancelWinsAndTheFirstInterruptionIsKept() {
        let signal = JobStopSignal()
        #expect(signal.current == nil)
        signal.request(.interrupt(.leftForeground))
        signal.request(.interrupt(.expired))
        #expect(signal.current == .interrupt(.leftForeground))
        signal.request(.cancel)
        signal.request(.interrupt(.paused))
        #expect(signal.current == .cancel)
    }
}

/// A capacity reading the test sets.
struct FixedCapacity: VolumeCapacityReading {
    let bytes: Int64?
    func availableBytes(at url: URL) throws -> Int64? { bytes }
}

@Suite struct DestinationAndPublicationTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "LabJobsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aFolderIsCreatedProvedWritableAndMeasured() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appending(path: "Nested/Renders", directoryHint: .isDirectory)
        let report = try DestinationCheck(capacity: FixedCapacity(bytes: 10_000)).prepare(target, needing: 4_000)
        #expect(report.needed == 4_000 && report.available == 10_000)
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path(percentEncoded: false)).isEmpty)
        // Unknown capacity is allowed and reported as unknown.
        #expect(try DestinationCheck(capacity: FixedCapacity(bytes: nil)).prepare(target, needing: 4_000).available == nil)
    }

    @Test func tooLittleSpaceAFileALinkAndAReadOnlyFolderAreRefused() throws {
        let root = try folder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appending(path: "locked").path(percentEncoded: false))
            try? FileManager.default.removeItem(at: root)
        }
        #expect(throws: DestinationProblem.insufficientSpace(needed: 5_000, available: 4_999)) {
            try DestinationCheck(capacity: FixedCapacity(bytes: 4_999)).prepare(root, needing: 5_000)
        }
        let file = root.appending(path: "file")
        try Data("x".utf8).write(to: file)
        #expect(throws: DestinationProblem.notAFolder) { try DestinationCheck().prepare(file, needing: 1) }
        let link = root.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        #expect(throws: DestinationProblem.notAFolder) { try DestinationCheck().prepare(link, needing: 1) }
        let locked = root.appending(path: "locked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path(percentEncoded: false))
        #expect(throws: DestinationProblem.unwritable) { try DestinationCheck().prepare(locked, needing: 1) }
    }

    @Test func publishingReplacesTheOldFileWholeAndReportsTheNewDigest() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "Output/movie.mov")
        let first = root.appending(path: "first.partial")
        try Data("first".utf8).write(to: first)
        let published = try AtomicPublication.publish(first, to: destination)
        #expect(published.byteCount == 5 && published.digest == ContentDigest.sha256(Data("first".utf8)))

        let second = root.appending(path: "second.partial")
        try Data("second render".utf8).write(to: second)
        let replaced = try AtomicPublication.publish(second, to: destination)
        #expect(try Data(contentsOf: destination) == Data("second render".utf8))
        #expect(replaced.digest == ContentDigest.sha256(Data("second render".utf8)))
        #expect(!FileManager.default.fileExists(atPath: second.path(percentEncoded: false)))

        // A staged file that is missing leaves the published one untouched.
        #expect(throws: (any Error).self) { try AtomicPublication.publish(root.appending(path: "missing"), to: destination) }
        #expect(try Data(contentsOf: destination) == Data("second render".utf8))
    }

    @Test func theForegroundRunwaySaysWhyItHasNoBackgroundTime() async {
        let lease = await ForegroundRunway(reason: .unavailable).begin(
            RunwayRequest(title: "Rendering", subtitle: "", wantsBackground: true), onExpiration: {}
        )
        #expect(lease.mode == .foregroundOnly(.unavailable))
        let off = await ForegroundRunway(reason: .unavailable).begin(
            RunwayRequest(title: "Rendering", subtitle: "", wantsBackground: false), onExpiration: {}
        )
        #expect(off.mode == .foregroundOnly(.turnedOff))
    }
}

extension Revision {
    static func r(_ value: Int) -> Revision { Revision(rawValue: value)! }
}
