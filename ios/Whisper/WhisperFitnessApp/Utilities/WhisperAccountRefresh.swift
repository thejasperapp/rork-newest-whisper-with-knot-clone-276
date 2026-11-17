import Foundation

/// Shares an overlapping read without letting an outgoing account own the next
/// account's request. The read itself must guard publication after every await.
@MainActor
final class WhisperAccountRefresh {
    private var task: Task<Void, Never>?
    private var generation: UUID?

    func run(_ read: @escaping @MainActor (UUID) async -> Void) async {
        guard !Task.isCancelled else { return }
        let ownerGeneration = AccountStorage.generation
        if let task, generation == ownerGeneration {
            await task.value
            return
        }
        task?.cancel()
        generation = ownerGeneration
        let request = Task { await read(ownerGeneration) }
        task = request
        await request.value
        if task == request { task = nil }
    }
}
