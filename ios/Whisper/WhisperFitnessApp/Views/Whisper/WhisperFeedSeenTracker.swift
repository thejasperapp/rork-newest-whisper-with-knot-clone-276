import Foundation

/// Session-scoped tracker for "have I already shown the viewer this post?".
/// Used by `WhisperAlgorithmService.score` to apply a 0.7× decay after the
/// first impression so Discover / personalized rails feel alive on refresh
/// instead of showing the same handful of viral posts in the same order.
///
/// State is intentionally in-memory only — we *want* the decay to reset when
/// the app cold-starts so the user always lands on the strongest content
/// the next morning.
@MainActor
final class WhisperFeedSeenTracker {
    static let shared = WhisperFeedSeenTracker()

    private var seen: Set<UUID> = []

    /// Cap the in-memory set so the tracker can't grow unbounded across a
    /// long-running foreground session.
    private let maxEntries: Int = 2_000

    private init() {}

    func hasSeen(_ id: UUID) -> Bool { seen.contains(id) }

    /// Mark a post as having been rendered to the viewer. Idempotent.
    func markSeen(_ id: UUID) {
        if seen.count >= maxEntries {
            // Drop ~10% to keep the set bounded. Order isn't important —
            // anything we drop simply becomes "fresh" again next pass.
            for victim in seen.prefix(maxEntries / 10) {
                seen.remove(victim)
            }
        }
        seen.insert(id)
    }

    /// Mark a batch of posts as seen — call from `onAppear` when a card
    /// scrolls into view so the next ranking pass demotes them.
    func markSeen(_ ids: [UUID]) {
        for id in ids { markSeen(id) }
    }

    func reset() { seen.removeAll() }
}
