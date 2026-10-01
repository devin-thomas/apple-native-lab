import LabDomain
import ModelRouting
import Observation
import SwiftUI

/// LAB-011's shared names.
enum ModelRoutingExperiment {
    static let id = ModelRouting.experimentID
    static let title = ModelRouting.title
    static let symbol = ModelRouting.symbol
}

/// One observatory session: policy, live or fixture gates, the outgoing preview, and usage.
@MainActor
@Observable
final class ModelRoutingSession {
    private(set) var policy: RoutingPolicy = .localOnly
    private(set) var observation: RouteObservation?
    private(set) var prompt = ""
    private(set) var localSummary: String?
    var manualAnswer = ""
    private(set) var message: String?
    private(set) var usage: [UsageReceipt] = []
    private(set) var lastStoreReceipt: ReceiptRecord?
    private(set) var pendingAnnotation: OperationProposal?
    private(set) var annotationTarget: String?
    @ObservationIgnored private var annotationRequest: RequestID?
    private(set) var isBusy = false

    @ObservationIgnored private var flow: ModelRoutingFlow?
    @ObservationIgnored private var library: LabLibrary?
    @ObservationIgnored private var backend: LibraryRoutingBackend?

    func start(with library: LabLibrary) async {
        guard flow == nil else { return }
        self.library = library
        backend = LibraryRoutingBackend(library: library)
        let reading = RoutingProbe.live(carriesPCCEntitlement: false)
        let resolver = RouteResolver(
            policy: .localOnly,
            onDevice: reading.onDevice,
            pcc: RoutingProbe.eligibility(from: reading)
        )
        flow = ModelRoutingFlow(resolver: resolver, transport: RefusingCloudTransport(), diagnostics: RoutingDiagnostics.log)
        do {
            prompt = try await Self.loadFixture()
        } catch {
            message = (error as? ModelRoutingError)?.message ?? "The fixture could not be loaded."
            return
        }
        await refresh()
    }

    @concurrent
    nonisolated private static func loadFixture() async throws -> String {
        try RoutingFixture.samplePrompt.load(from: .main)
    }

    func setPolicy(_ policy: RoutingPolicy) async {
        guard let flow else { return }
        self.policy = policy
        await flow.setPolicy(policy)
        await refresh()
    }

    func refresh() async {
        guard let flow else { return }
        do {
            observation = try await flow.observe(prompt: prompt)
            usage = await flow.receipts
            message = nil
        } catch {
            message = error.message
        }
    }

    func runLocal() async {
        guard let flow, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let (summary, _) = try await flow.runLocalFallback(prompt: prompt)
            localSummary = summary
            usage = await flow.receipts
            message = nil
            pendingAnnotation = nil
            annotationTarget = nil
            annotationRequest = nil
            lastStoreReceipt = nil
        } catch {
            message = error.message
        }
    }

    func runManual() async {
        guard let flow, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await flow.runManual(prompt: prompt, answer: manualAnswer)
            usage = await flow.receipts
            message = nil
        } catch {
            message = error.message
        }
    }

    func grantConsent() async {
        guard let flow, let preview = observation?.preview else { return }
        do {
            _ = try await flow.grantConsent(for: preview)
            usage = await flow.receipts
            message = "Consent recorded for the previewed fields. Nothing has left this device."
        } catch {
            message = error.message
        }
    }

    func attemptCloud() async {
        guard let flow, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let (_, receipt) = try await flow.runCloud(prompt: prompt)
            usage = await flow.receipts
            message = receipt.summary
        } catch {
            usage = await flow.receipts
            message = error.message
        }
    }

    func resetDemo() async {
        guard let flow, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        await flow.resetDemo()
        localSummary = nil
        manualAnswer = ""
        lastStoreReceipt = nil
        pendingAnnotation = nil
        annotationTarget = nil
        annotationRequest = nil
        policy = .localOnly
        await flow.setPolicy(.localOnly)
        usage = []
        message = "Observatory demo state cleared. The lab store was not changed."
        await refresh()
    }

    func prepareAnnotation() async {
        guard let backend, let summary = localSummary, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let items = try await backend.demoItems()
            guard let target = items.first(where: { $0.title.value == "Tracing vellum" }) ?? items.first else { return }
            let operation = try LocalFallbackCommit.operation(for: target, summary: summary)
            pendingAnnotation = try await backend.propose(operation)
            annotationTarget = target.title.value
            annotationRequest = nil
        } catch {
            message = "The demo annotation could not be prepared. Nothing was changed."
        }
    }

    func approveAnnotation() async {
        guard let backend, let library, let proposal = pendingAnnotation, proposal.isReady, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let request = annotationRequest ?? RequestID()
            annotationRequest = request
            let receipt = try await backend.commit(proposal.operation, requestID: request)
            lastStoreReceipt = library.receipt(id: receipt.operationID)
            pendingAnnotation = nil
            annotationRequest = nil
            message = receipt.conflict == nil ? "Demo annotation saved." : "The sample changed. Review a new annotation."
        } catch {
            message = "The annotation was refused. Nothing was changed."
        }
    }

}

/// Host backend: proposes as the model tool, commits as the app UI.
struct LibraryRoutingBackend: ModelRoutingBackend {
    let library: LabLibrary

    func demoItems() async throws(ModelRoutingError) -> [LabItem] {
        let service: LabDataService
        do { service = try await library.openedService() } catch {
            throw .unavailable("The lab is unavailable.")
        }
        do {
            let filter = try ItemFilter(includeArchived: true, limit: 200)
            return try await service.items(filter, as: ModelRouting.proposer).filter { $0.namespace == .demo }
        } catch {
            throw .unavailable("Demo samples could not be read.")
        }
    }

    func propose(_ operation: DomainOperation) async throws(ModelRoutingError) -> OperationProposal {
        let service: LabDataService
        do { service = try await library.openedService() } catch {
            throw .unavailable("The lab is unavailable.")
        }
        do {
            return try await service.propose(operation, as: ModelRouting.proposer)
        } catch {
            throw .unavailable("The proposal was refused.")
        }
    }

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID
    ) async throws(ModelRoutingError) -> ActionReceipt {
        do {
            return try await library.submit(
                operation, requestID: requestID, authority: .userAction, names: [:]
            ).receipt
        } catch {
            throw .unavailable("The commit was refused.")
        }
    }
}

enum RoutingDiagnostics {
    static let log = DiagnosticsLog(sinks: [OSLogDiagnosticSink()])
}
