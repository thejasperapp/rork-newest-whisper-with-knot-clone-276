import Foundation

/// Suspends work rather than blocking threads, removing cancelled queue entries.
actor WhisperImageWorkGate {
    private let limit: Int
    private var active: Int = 0
    private var waiters: [(id: UUID, priority: TaskPriority, continuation: CheckedContinuation<Bool, Never>)] = []

    init(limit: Int) { self.limit = max(1, limit) }

    func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }
        if active < limit { active += 1; return true }
        let id = UUID()
        let priority = Task.currentPriority
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: false); return }
                waiters.append((id, priority, continuation))
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    private func cancel(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }

    func release() {
        guard !waiters.isEmpty else { active -= 1; return }
        var index = 0
        for candidate in waiters.indices where waiters[candidate].priority.rawValue > waiters[index].priority.rawValue {
            index = candidate
        }
        waiters.remove(at: index).continuation.resume(returning: true)
    }
}
