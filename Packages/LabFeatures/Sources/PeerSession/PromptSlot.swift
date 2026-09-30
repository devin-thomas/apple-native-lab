import Foundation

/// One question for a person that a handshake waits on, such as "Allow this device?" or "Enter the
/// code", held by the actor that owns the session.
///
/// The actor publishes `question` in its state; a view shows it and the actor calls `answer`.
/// Only one question is open at a time: opening another answers the last with `nil`, and so do
/// `dismiss` and cancellation of the waiting task.
struct PromptSlot<Question: Sendable, Answer: Sendable>: Sendable {
    private var open: (id: UInt64, question: Question, continuation: CheckedContinuation<Answer?, Never>)?
    private var nextID: UInt64 = 0

    var question: Question? { open?.question }

    /// Reserves an ID for the next question.
    mutating func reserve() -> UInt64 {
        nextID += 1
        return nextID
    }

    /// Opens `question`, answering any earlier one with `nil`.
    mutating func open(_ id: UInt64, _ question: Question, _ continuation: CheckedContinuation<Answer?, Never>) {
        close(with: nil)
        open = (id, question, continuation)
    }

    /// Answers the open question, if it is still `id` (or any question when `id` is `nil`).
    /// Returns whether one was open.
    @discardableResult
    mutating func close(with answer: Answer?, id: UInt64? = nil) -> Bool {
        guard let current = open, id == nil || current.id == id else { return false }
        open = nil
        current.continuation.resume(returning: answer)
        return true
    }
}
