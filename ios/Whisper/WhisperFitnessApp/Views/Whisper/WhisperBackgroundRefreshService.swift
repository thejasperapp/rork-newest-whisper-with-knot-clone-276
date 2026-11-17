import Foundation

/// Background content prefetcher — runs inside the
/// `app.rork.whisper.content.refresh` BGAppRefreshTask so the feed, inbox,
/// and the first screenful of images are already loaded the next time the
/// user opens Whisper.
///
/// Everything is budgeted to finish well inside the ~30s background window:
/// posts + threads fetch concurrently, then the shared `URLCache` is warmed
/// with the images the user will see first (post media + avatars), so the
/// opening feed paints from disk with zero spinners.
@MainActor
final class WhisperBackgroundRefreshService {
    static let shared = WhisperBackgroundRefreshService()

    private init() {}

    private(set) var lastRefreshAt: Date?

    /// Full refresh pass: new posts, new threads, warm image cache.
    /// Safe to call from the background task or opportunistically in
    /// the foreground — every step is idempotent.
    func refreshContent() async {
        let auth = AuthenticationService.shared
        let generation = AccountStorage.generation
        guard auth.isSignedIn, !auth.isRestoringSession,
              auth.currentUser.userID.lowercased() == AccountStorage.currentUserID.lowercased(),
              AccountStorage.currentUserID != "guest", !Task.isCancelled else { return }
        let backend = WhisperBackendService.shared

        async let postsFetch: Void = backend.fetchPosts()
        async let threadsFetch: Void = backend.fetchThreads()
        async let groupsFetch: Void = WhisperGroupChatService.shared.syncRegistry(force: true)
        _ = await (postsFetch, threadsFetch, groupsFetch)

        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        lastRefreshAt = Date()
        await warmImageCache()
    }

    /// Warm cacheable image responses using the foreground loader's shared
    /// transfer budget. Background scheduling and cache hits are best-effort.
    private func warmImageCache() async {
        let backend = WhisperBackendService.shared
        let generation = AccountStorage.generation
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        var seen: Set<String> = []
        var urls: [URL] = []

        func push(_ raw: String?) {
            guard let raw, !raw.isEmpty, !seen.contains(raw), let url = URL(string: raw),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), !WhisperVideo.isVideo(url) else { return }
            seen.insert(raw)
            urls.append(url)
        }

        for post in backend.posts.prefix(14) where post.is_reel != true {
            if let raw = post.media_urls?.first, let url = URL(string: raw), WhisperVideo.isVideo(url) {
                push(WhisperPostMeta.coverURL(from: post.caption)?.absoluteString)
            } else { push(post.media_urls?.first) }
        }
        for profile in backend.postAuthorProfiles.values {
            push(profile.profile_image_url)
        }
        for profile in backend.threadProfiles.values {
            push(profile.profile_image_url)
        }

        let capped = Array(urls.prefix(30))
        guard !capped.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for (index, url) in capped.enumerated() {
                if index >= 2 { await group.next() }
                guard !Task.isCancelled, generation == AccountStorage.generation,
                      !ProcessInfo.processInfo.isLowPowerModeEnabled else { group.cancelAll(); break }
                group.addTask { @MainActor in
                    guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                    await WhisperImageCache.prefetch(url)
                }
            }
        }
    }
}
