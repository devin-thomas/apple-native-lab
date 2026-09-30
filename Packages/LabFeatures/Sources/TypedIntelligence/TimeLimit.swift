import Synchronization

/// Runs extraction work with a time limit and prompt cancellation.
///
/// The caller gets an answer as soon as the first of three things happens: the work finishes, the
/// limit passes, or the caller's task is cancelled. It does not wait for work that ignores
/// cancellation: the work is cancelled and any late result is discarded, so a stalled or hostile
/// extractor can hold neither the interface nor a proposal. This function owns both tasks it
/// starts and cancels both before it returns.
enum TimeLimit {
    static func run<Value: Sendable>(
        limit: Duration,
        _ work: @escaping @Sendable () async throws(ExtractionFailure) -> Value
    ) async -> Result<Value, ExtractionFailure> {
        let outcome = FirstOutcome<Result<Value, ExtractionFailure>>()
        let worker = Task {
            let result: Result<Value, ExtractionFailure>
            do throws(ExtractionFailure) {
                result = .success(try await work())
            } catch {
                result = .failure(error)
            }
            outcome.deliver(result)
        }
        let timer = Task {
            do { try await Task.sleep(for: limit) } catch { return }
            outcome.deliver(.failure(.timedOut(limit: limit)))
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

/// Resumes one continuation with the first value delivered, whether it arrives before or after
/// the continuation is installed. Later values are dropped.
private final class FirstOutcome<Value: Sendable>: Sendable {
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
