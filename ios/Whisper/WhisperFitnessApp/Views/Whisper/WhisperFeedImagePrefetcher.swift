import Foundation

/// A replaceable look-ahead window, not an ever-growing download queue.
@MainActor
final class WhisperFeedImagePrefetcher {
    // Visibility bookkeeping is not render state: crossing a viewport threshold
    // should not rebuild Home's entire lazy stack.
    var visiblePostIDs: Set<UUID> = []
    private var pending: [URL] = []
    private var pixelSize: CGSize?
    private var recent: [URL: Date] = [:]
    private var task: Task<Void, Never>?
    private var operation: UUID = UUID()
    private var generation: UUID = AccountStorage.generation

    nonisolated static func imageURLs(in posts: [WhisperPost]) -> [URL] {
        var seen: Set<URL> = []
        return posts.prefix(3).compactMap { post in
            let first = post.mediaURLs.first
            let url = first.flatMap { WhisperVideo.isVideo($0) ? WhisperPostMeta.coverURL(from: post.caption) : $0 }
            guard let url, !WhisperVideo.isVideo(url),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""), seen.insert(url).inserted else { return nil }
            return url
        }
    }

    func update(posts: [WhisperPost], pixelSize: CGSize? = nil) {
        if self.pixelSize != pixelSize { recent = [:]; self.pixelSize = pixelSize }
        if generation != AccountStorage.generation { stop(); generation = AccountStorage.generation; recent = [:] }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { stop(); return }
        let now = Date()
        recent = recent.filter { now.timeIntervalSince($0.value) < 60 }
        pending = Self.imageURLs(in: posts).filter { recent[$0] == nil }
        guard task == nil, !pending.isEmpty else { return }
        let epoch = generation
        let token = UUID(); operation = token
        task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { if self.operation == token { self.task = nil } }
            while !Task.isCancelled, epoch == AccountStorage.generation, !self.pending.isEmpty,
                  !ProcessInfo.processInfo.isLowPowerModeEnabled {
                let url = self.pending.removeFirst()
                if self.recent.count >= 128 { self.recent = [:] }
                self.recent[url] = Date()
                await WhisperImageCache.prefetch(url, fillPixelSize: self.pixelSize)
            }
        }
    }

    func stop() {
        pending = []
        operation = UUID()
        task?.cancel(); task = nil
        // A URL transfer already shared with an on-screen image may finish;
        // stopping speculation must not cancel that visible consumer.
    }
}
