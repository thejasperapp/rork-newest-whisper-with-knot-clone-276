import Foundation

/// Cancels the owned request, not its session. A cancellation that arrives before
/// Foundation creates the task is remembered and applied at task registration.
/// The lock protects both mutable fields across notification/delegate callbacks;
/// URLSessionTask.cancel() is thread-safe and is called outside the lock.
nonisolated final class WhisperKnotRequestCancellation: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private weak var task: URLSessionTask?

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let shouldCancel = lock.withLock {
            self.task = task
            return cancelled
        }
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        let ownedTask = lock.withLock {
            cancelled = true
            return task
        }
        ownedTask?.cancel()
    }

    func check() throws {
        if lock.withLock({ cancelled }) { throw CancellationError() }
    }
}
