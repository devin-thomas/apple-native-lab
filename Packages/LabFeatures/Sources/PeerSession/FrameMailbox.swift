import Foundation

/// Buffers a connection's incoming frames so a reader can stop waiting without losing any.
///
/// A task that iterates an `AsyncThrowingStream` and is cancelled ends the stream. The handshake
/// needs to race a person's answer against the next frame, and the session needs timeouts, so one
/// pump task drains the connection into this mailbox and readers wait here instead. A cancelled
/// or timed-out wait leaves every frame in the buffer.
actor FrameMailbox {
    private enum End {
        case finished
        case failed(any Error)
    }

    private var buffer: [Data] = []
    private var end: End?
    private var waiter: (id: UInt64, continuation: CheckedContinuation<Data?, any Error>)?
    private var nextWaiterID: UInt64 = 0
    private var pump: Task<Void, Never>?
    private var timer: Task<Void, Never>?

    init() {}

    /// Starts draining `connection`. Call once.
    func start(_ connection: any PeerConnection) {
        guard pump == nil else { return }
        pump = Task { [weak self] in
            do {
                for try await frame in connection.incoming {
                    await self?.deliver(frame)
                }
                await self?.finish(.finished)
            } catch {
                await self?.finish(.failed(error))
            }
        }
    }

    /// The next frame, or `nil` once the connection has closed and every frame was read.
    ///
    /// With a `timeout`, throws `MailboxTimeout` if nothing arrives in time. Delivery, timeout, and
    /// cancellation are all decided on this actor, so a frame is either returned or kept.
    func receive(within timeout: Duration? = nil) async throws -> Data? {
        if !buffer.isEmpty { return buffer.removeFirst() }
        switch end {
        case .finished: return nil
        case .failed(let error): throw error
        case nil: break
        }
        nextWaiterID += 1
        let id = nextWaiterID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiter = (id, continuation)
                if let timeout {
                    timer = Task { [weak self] in
                        try? await Task.sleep(for: timeout)
                        await self?.resumeWaiter(id, throwing: MailboxTimeout())
                    }
                }
            }
        } onCancel: {
            Task { await self.resumeWaiter(id, throwing: CancellationError()) }
        }
    }

    func stop() {
        pump?.cancel()
        finish(.finished)
    }

    private func deliver(_ frame: Data) {
        if let waiter {
            self.waiter = nil
            timer?.cancel()
            waiter.continuation.resume(returning: frame)
        } else {
            buffer.append(frame)
        }
    }

    private func finish(_ reason: End) {
        guard end == nil else { return }
        end = reason
        guard let waiter else { return }
        self.waiter = nil
        timer?.cancel()
        switch reason {
        case .finished: waiter.continuation.resume(returning: nil)
        case .failed(let error): waiter.continuation.resume(throwing: error)
        }
    }

    private func resumeWaiter(_ id: UInt64, throwing error: any Error) {
        guard let waiter, waiter.id == id else { return }
        self.waiter = nil
        timer?.cancel()
        waiter.continuation.resume(throwing: error)
    }
}

struct MailboxTimeout: Error {}
