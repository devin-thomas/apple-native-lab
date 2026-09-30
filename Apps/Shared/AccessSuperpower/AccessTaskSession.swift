import AccessSuperpower
import LabDomain
import Observation
import SwiftUI

/// LAB-035's shared names: the experiment's ID in the catalog and its title.
enum AccessSuperpowerExperiment {
    static let id = "LAB-035"
    static let title = "Access as a Superpower"
    static let symbol = "accessibility"
}

/// One person's progress through the Access as a Superpower task, on one screen or window.
///
/// Every way of finishing the task (the visible buttons, the chart's VoiceOver actions, the list's
/// Return key on the Mac, the context menus) calls `restore(_:in:)`. It judges the restore against
/// the tally the person saw, commits `restoreItem` through `LabLibrary.submit` as the app UI (the
/// same operation service, grant, and receipt as every other in-app change), and announces the
/// receipt and the task result in one sentence. A press while a restore runs is ignored, and a
/// retry after a failure reuses the failed request, so one decision commits at most once.
@MainActor
@Observable
final class AccessTaskSession {
    /// The archived sample chosen in the list, if any.
    var selectedSampleID: ItemID?
    /// The last restore made here that committed, with what it meant for the task.
    private(set) var outcome: Outcome?
    /// The last practice change or refusal, as a sentence.
    private(set) var message: String?
    private(set) var isRunning = false

    struct Outcome: Hashable {
        let task: TaskOutcome
        let record: ReceiptRecord
    }

    @ObservationIgnored private var requests: [ItemID: RequestID] = [:]
    @ObservationIgnored private var practiceRun: Task<Void, Never>?

    /// The demo collections as the library last read them through the service.
    static func tally(_ library: LabLibrary) -> ArchiveTally {
        ArchiveTally(library.collections.map { ($0.collection, $0.items) })
    }

    /// The last restore's outcome while it stands: `nil` once that sample is archived again, for
    /// example by its receipt's Undo, because the task can then be done again.
    func currentOutcome(in library: LabLibrary) -> Outcome? {
        guard let outcome, let found = Self.tally(library).sample(outcome.task.sampleID), !found.sample.isArchived else { return nil }
        return outcome
    }

    func status(in library: LabLibrary) -> TaskStatus {
        AccessibleTask.status(of: Self.tally(library), after: currentOutcome(in: library)?.task)
    }

    func canRestore(in library: LabLibrary) -> Bool {
        library.phase == .ready && !isRunning && !library.isWorking
    }

    // MARK: The task's one operation

    /// Restores one archived demo sample through the operation service and says what it meant for
    /// the task. Returns the receipt, or `nil` when nothing was submitted or the service refused it.
    @discardableResult
    func restore(_ id: ItemID, in library: LabLibrary) async -> ReceiptRecord? {
        guard canRestore(in: library) else { return nil }
        let tally = Self.tally(library)
        let operation: DomainOperation
        do {
            operation = try AccessibleTask.restoreOperation(for: id, in: tally)
        } catch {
            message = error.message
            LabAnnouncement(failure: error.message).post()
            return nil
        }
        let judged = AccessibleTask.judge(restoring: id, in: tally)
        let requestID = requests[id] ?? RequestID()
        requests[id] = requestID
        isRunning = true
        defer { isRunning = false }
        do {
            let record = try await library.submit(operation, requestID: requestID, authority: .userAction, names: [:])
            requests[id] = nil
            if record.receipt.conflict == nil, let judged {
                outcome = Outcome(task: judged, record: record)
                message = nil
            } else {
                message = record.receipt.summary
            }
            if selectedSampleID == id { selectedSampleID = nil }
            Self.announcement(for: record, task: record.receipt.conflict == nil ? judged : nil).post()
            return record
        } catch {
            let sentence = Self.describe(error)
            message = sentence
            LabAnnouncement(failure: sentence).post()
            return nil
        }
    }

    /// The receipt's announcement with the task's result added, so one sentence carries both.
    static func announcement(for record: ReceiptRecord, task: TaskOutcome?) -> LabAnnouncement {
        let receipt = LabAnnouncement(receipt: ReceiptPresentation(record))
        guard let task else { return receipt }
        return LabAnnouncement(text: "\(receipt.text) \(task.sentence)", priority: receipt.priority)
    }

    // MARK: Practice data (the experiment's own fixture state)

    /// Archives the practice samples that are not archived yet, one receipt each.
    func setUpPractice(in library: LabLibrary) {
        runPractice(archiving: true, in: library)
    }

    /// Restores the practice samples that are still archived. Nothing else is touched.
    func resetPractice(in library: LabLibrary) {
        runPractice(archiving: false, in: library)
    }

    /// Stops a practice change between two commits. Those already made keep their receipts.
    func cancelPractice() {
        practiceRun?.cancel()
    }

    func practiceCounts(in library: LabLibrary) -> (toArchive: Int, toRestore: Int) {
        let tally = Self.tally(library)
        return (PracticeSet.standard.setUpOperations(in: tally).count, PracticeSet.standard.resetOperations(in: tally).count)
    }

    private func runPractice(archiving: Bool, in library: LabLibrary) {
        guard canRestore(in: library) else { return }
        let tally = Self.tally(library)
        let operations = archiving
            ? PracticeSet.standard.setUpOperations(in: tally)
            : PracticeSet.standard.resetOperations(in: tally)
        isRunning = true
        outcome = nil
        selectedSampleID = nil
        practiceRun = Task {
            defer { isRunning = false }
            do {
                let run = try await PracticeRun.perform(operations) { operation in
                    let record = try await library.submit(operation, requestID: RequestID(), authority: .userAction, names: [:])
                    return record.receipt
                }
                let sentence = PracticeRun.sentence(archiving: archiving, run, of: operations.count)
                message = sentence
                LabAnnouncement(text: sentence).post()
            } catch {
                let sentence = Self.describe(error)
                message = sentence
                LabAnnouncement(failure: sentence).post()
            }
        }
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case let failure as LabLibrary.SubmitFailure:
            switch failure {
            case .unavailable(let reason): reason
            case .refused(let refusal): LibraryMessages.describe(refusal)
            }
        default:
            LibraryMessages.describe(error)
        }
    }
}
