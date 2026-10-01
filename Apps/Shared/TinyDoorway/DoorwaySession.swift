import LabDomain
import Observation
import TinyDoorway

/// LAB-039's shared names.
enum TinyDoorwayExperiment {
    static let id = "LAB-039"
    static let title = "Tiny Doorway"
    static let symbol = "door.left.hand.open"
}

/// One person's progress through a Tiny Doorway visit on one screen or window.
///
/// Opening or pasting a link only validates. Confirming calls `DoorwayAction.visitOperation` and
/// commits through `LabLibrary.submit` as the app UI — the same operation service and receipt path
/// as every other in-app change. A link never becomes a grant.
@MainActor
@Observable
final class DoorwaySession {
    /// Text in the paste field.
    var draftURL = DemoLinks.visitDeepLink
    /// Whether the host treats the network as reachable. Offline is a toggle for the demo.
    var reachability: InvocationContext.Reachability = .online
    /// The last validation outcome.
    private(set) var validation: DoorwayValidation?
    /// The last confirmed visit's receipt and handoff, while it still stands.
    private(set) var outcome: Outcome?
    private(set) var message: String?
    private(set) var isRunning = false
    /// When true, the local information page is showing.
    private(set) var showsInformation = false

    struct Outcome: Hashable {
        let handoff: DoorwayHandoff
        let record: ReceiptRecord
        let itemTitle: String
    }

    @ObservationIgnored private var requests: [ItemID: RequestID] = [:]
    @ObservationIgnored private var resetRun: Task<Void, Never>?

    var clipStatus: DoorwayClipStatus { DoorwayClipStatus.current }

    func canAct(in library: LabLibrary) -> Bool {
        library.phase == .ready && !isRunning && !library.isWorking
    }

    /// Validates the draft URL (or a named fixture) without committing.
    func open(_ rawURL: String, source: InvocationContext.Source = .pasted, in library: LabLibrary) {
        showsInformation = false
        outcome = nil
        let context = InvocationContext(source: source, rawURL: rawURL, reachability: reachability)
        let result = DoorwayValidator.validate(context)
        validation = result
        switch result {
        case .proposal:
            message = nil
        case .informationPage:
            showsInformation = true
            message = nil
        case .refused(let error):
            message = error.message
            LabAnnouncement(failure: error.message).post()
        }
        _ = library // keep the signature aligned with other sessions that need readiness
    }

    func openFixture(_ url: String, in library: LabLibrary) {
        draftURL = url
        open(url, source: .fixtureReplay, in: library)
    }

    /// Confirms the current proposal: builds the visit operation and commits it.
    @discardableResult
    func confirm(in library: LabLibrary) async -> ReceiptRecord? {
        guard canAct(in: library), case .proposal(let proposal) = validation else { return nil }
        guard let item = library.item(id: proposal.itemID) else {
            message = DoorwayError.itemUnavailable(proposal.itemID.rawValue.uuidString).message
            LabAnnouncement(failure: message!).post()
            return nil
        }
        let operation: DomainOperation
        do {
            operation = try DoorwayAction.visitOperation(for: proposal, item: item)
        } catch {
            message = error.message
            LabAnnouncement(failure: error.message).post()
            return nil
        }
        let requestID = requests[proposal.itemID] ?? RequestID()
        requests[proposal.itemID] = requestID
        isRunning = true
        defer { isRunning = false }
        do {
            let record = try await library.submit(operation, requestID: requestID, authority: .userAction, names: [:])
            requests[proposal.itemID] = nil
            if record.receipt.conflict == nil {
                let handoff = DoorwayHandoff(proposal: proposal)
                outcome = Outcome(handoff: handoff, record: record, itemTitle: item.title.value)
                message = nil
                LabAnnouncement(receipt: ReceiptPresentation(record)).post()
            } else {
                message = record.receipt.summary
                LabAnnouncement(failure: record.receipt.summary).post()
            }
            return record
        } catch {
            let sentence = Self.describe(error)
            message = sentence
            LabAnnouncement(failure: sentence).post()
            return nil
        }
    }

    /// Strips visit markers from demo samples that still carry them.
    func resetVisits(in library: LabLibrary) {
        guard canAct(in: library) else { return }
        isRunning = true
        outcome = nil
        resetRun = Task {
            defer { isRunning = false }
            do {
                let items = library.collections.flatMap(\.items).filter { $0.namespace == .demo }
                let operations = DoorwayAction.resetVisitOperations(in: items)
                var count = 0
                for operation in operations {
                    if Task.isCancelled {
                        message = "Stopped after \(count) of \(operations.count). Each finished reset has its own receipt."
                        LabAnnouncement(text: message!).post()
                        return
                    }
                    _ = try await library.submit(operation, requestID: RequestID(), authority: .userAction, names: [:])
                    count += 1
                }
                let sentence = count == 0 ? "Nothing to reset." : "Removed \(count == 1 ? "1 visit marker" : "\(count) visit markers"). Each has its own receipt."
                message = sentence
                validation = nil
                LabAnnouncement(text: sentence).post()
            } catch {
                let sentence = Self.describe(error)
                message = sentence
                LabAnnouncement(failure: sentence).post()
            }
        }
    }

    func cancelReset() { resetRun?.cancel() }

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
