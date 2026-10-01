import Foundation
import LabDomain
import Synchronization

/// Turns a chosen image into a reviewable record, then commits only an approved one.
///
/// The read stops at a time limit or when cancelled, and a late result is discarded. Barcode
/// payloads never become operations other than the item the person applies.
public struct PointInspectFlow: Sendable {
    private let backend: any PointInspectBackend
    private let timeLimit: Duration

    public init(backend: any PointInspectBackend, timeLimit: Duration = PointInspect.defaultTimeLimit) {
        self.backend = backend
        self.timeLimit = timeLimit
    }

    public enum Route: Sendable {
        case opticalRecognition
        case onDeviceModel(any ImageInterpreting)
        case manual(title: String, body: String)
    }

    /// Reads the image and builds a suggestion. Writes nothing.
    public func inspect(
        _ image: SelectedImage,
        route: Route,
        inspector: any ImageInspecting,
        consent: CaptureConsent
    ) async -> Result<Observation, InspectFailure> {
        await InspectTimeLimit.run(limit: timeLimit) { () async throws(InspectFailure) -> Observation in
            if Task.isCancelled { throw .cancelled }
            let reading = try await inspector.inspect(image)
            if Task.isCancelled { throw .cancelled }
            let draft = try await self.draft(route, image: image, reading: reading)
            return self.observation(image: image, reading: reading, draft: draft, consent: consent)
        }
    }

    /// Checks the record with the operation service as the proposer. Writes nothing.
    public func review(_ observation: Observation) async -> Result<ReviewableInspection, InspectFailure> {
        let operation: DomainOperation
        do {
            operation = try observation.operation()
        } catch {
            return .failure(error)
        }
        do {
            let proposal = try await backend.propose(operation)
            return .success(ReviewableInspection(observation: observation, operation: operation, serviceCheck: .accepted(proposal)))
        } catch {
            if case .refused(let refused) = error {
                return .success(ReviewableInspection(observation: observation, operation: operation, serviceCheck: .refused(refused)))
            }
            return .failure(error)
        }
    }

    /// The Apply button: creates the Inspections collection if needed, checks the record, and commits it.
    ///
    /// An invalid title fails before any write. A retry of one approval uses `apply(_:)`, which commits once.
    public func commit(_ observation: Observation) async -> Result<ActionReceipt, InspectFailure> {
        let operation: DomainOperation
        do {
            operation = try observation.operation()
        } catch {
            return .failure(error)
        }
        do {
            try await ensureCollection()
            let proposal = try await backend.propose(operation)
            let inspection = ReviewableInspection(
                observation: observation,
                operation: operation,
                serviceCheck: .accepted(proposal)
            )
            let receipt = try await backend.commit(try inspection.approve())
            return .success(receipt)
        } catch {
            return .failure(error)
        }
    }

    /// Commits an approval the person already gave. A retry of the same approval commits once.
    public func apply(_ inspection: ApprovedInspection) async -> Result<ActionReceipt, InspectFailure> {
        do {
            try await ensureCollection()
            let receipt = try await backend.commit(inspection)
            return .success(receipt)
        } catch {
            return .failure(error)
        }
    }

    private func draft(_ route: Route, image: SelectedImage, reading: OpticalReading) async throws(InspectFailure) -> InterpretationDraft {
        switch route {
        case .opticalRecognition:
            return OpticalRecognition.draft(from: reading)
        case .onDeviceModel(let interpreter):
            return try await interpreter.interpret(image, reading: reading)
        case .manual(let title, let body):
            return try await ManualInterpretation(title: title, body: body).interpret(image, reading: reading)
        }
    }

    private func observation(
        image: SelectedImage,
        reading: OpticalReading,
        draft: InterpretationDraft,
        consent: CaptureConsent
    ) -> Observation {
        let suggestion = InterpretationSuggestion(
            title: Self.clipped(draft.title),
            body: Self.clippedBody(draft.body),
            confidence: draft.confidence,
            source: draft.source,
            imageDigest: image.evidence.digest,
            isUncertain: draft.uncertain || draft.confidence < InspectLimits.certainConfidence
        )
        return Observation(
            evidence: image.evidence,
            consent: consent,
            lines: reading.lines,
            barcodes: reading.barcodes,
            suggestion: suggestion
        )
    }

    private func ensureCollection() async throws(InspectFailure) {
        if try await backend.collection(PointInspect.collectionID) != nil { return }
        let title: EntityTitle
        do {
            title = try EntityTitle(PointInspect.collectionTitle)
        } catch {
            throw .invalidText("The Inspections collection could not be named.")
        }
        do {
            _ = try await backend.createCollection(
                CollectionDraft(id: PointInspect.collectionID, title: title),
                requestID: RequestID()
            )
        } catch .refused(.ruleViolation(.alreadyExists(_))) {
            return
        }
    }

    private static func clipped(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let single = trimmed.replacingOccurrences(of: "\n", with: " ")
        if single.count <= InspectLimits.title { return single }
        return String(single.prefix(InspectLimits.title))
    }

    private static func clippedBody(_ body: String) -> String {
        body.count <= InspectLimits.body ? body : String(body.prefix(InspectLimits.body))
    }
}

/// Runs a read with a time limit and prompt cancellation, and discards a late result.
enum InspectTimeLimit {
    static func run(
        limit: Duration,
        _ work: @escaping @Sendable () async throws(InspectFailure) -> Observation
    ) async -> Result<Observation, InspectFailure> {
        let outcome = FirstInspection<Result<Observation, InspectFailure>>()
        let worker = Task {
            let result: Result<Observation, InspectFailure>
            do throws(InspectFailure) {
                result = .success(try await work())
            } catch {
                result = .failure(error)
            }
            outcome.deliver(result)
        }
        let timer = Task {
            do { try await Task.sleep(for: limit) } catch { return }
            outcome.deliver(.failure(.timedOut))
        }
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { outcome.install($0) }
        } onCancel: {
            outcome.deliver(.failure(.cancelled))
        }
        worker.cancel()
        timer.cancel()
        return result
    }
}

private final class FirstInspection<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, Never>?
        var pending: Value?
        var delivered = false
    }

    private let state = Mutex(State())

    func install(_ continuation: CheckedContinuation<Value, Never>) {
        let ready: Value? = state.withLock { state in
            if let pending = state.pending {
                state.pending = nil
                return pending
            }
            state.continuation = continuation
            return nil
        }
        if let ready { continuation.resume(returning: ready) }
    }

    func deliver(_ value: Value) {
        let waiting: CheckedContinuation<Value, Never>? = state.withLock { state in
            guard !state.delivered else { return nil }
            state.delivered = true
            if let continuation = state.continuation {
                state.continuation = nil
                return continuation
            }
            state.pending = value
            return nil
        }
        waiting?.resume(returning: value)
    }
}
