import SwiftUI

/// Knot feed-curation request. The user types
/// `@knot <wish>` in the composer (or anywhere we plug it in) and
/// instead of publishing a normal post we capture the wish, extract a few
/// interest keywords from it, persist them, and bump the feed ranker so the
/// next refresh reorders around what the user asked for.
///
/// The overlay animation that runs in `WhisperFeedView` reads `isRunning`
/// and `etaSeconds` to render the progress bar / countdown copy.
@MainActor
@Observable
final class WhisperDearEmberService {
    static let shared = WhisperDearEmberService()

    /// True while the curating animation is on screen. Feed view binds an
    /// overlay to this flag.
    var isRunning: Bool = false
    /// Free-form copy from the user — surfaced in the overlay so they see
    /// exactly what Jasper is acting on.
    var wish: String = ""
    /// Countdown displayed while the curation runs.
    var etaSeconds: Int = 12
    /// Active boost keywords parsed from the most recent wish. Ranker
    /// reads these and gives matching posts a small bump for the rest of
    /// the session (cleared on next sign-in).
    var boostKeywords: [String] = []
    /// Lower-bound timestamp — anything older than this gets pushed down
    /// once Jasper "freshens" the feed (set when the user asks for fresher
    /// content explicitly).
    var freshenFromBoot: Bool = false

    private var curationTask: Task<Void, Never>?
    private var runID = UUID()

    private init() { reloadForCurrentAccount() }

    func reloadForCurrentAccount() {
        curationTask?.cancel()
        curationTask = nil
        runID = UUID()
        isRunning = false
        wish = ""
        etaSeconds = 0
        freshenFromBoot = false
        boostKeywords = (AccountStorage.string(forKey: keywordsKey) ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private let keywordsKey = "whisper.dearember.keywords"
    private let wishKey = "whisper.dearember.wish"

    /// Composer-only command. Keep old directives working without hijacking
    /// longer handles such as @knotty, or mentions in ordinary captions.
    static let trigger = "@knot"
    private static let prefixes = ["@dear ember", "dear ember", "@dear knot", "dear knot", trigger]

    private static func matchedPrefix(in text: String) -> String? {
        let lower = text.lowercased()
        return prefixes.first { prefix in
            guard lower.hasPrefix(prefix) else { return false }
            let tail = lower.dropFirst(prefix.count)
            guard let next = tail.first else { return true }
            return next.isWhitespace || ",:;.!?".contains(next)
        }
    }

    static func matches(_ caption: String) -> Bool {
        matchedPrefix(in: caption.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    /// Strip only a complete leading directive, never an ordinary user mention.
    static func wishBody(_ caption: String) -> String {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prefix = matchedPrefix(in: trimmed) else { return trimmed }
        return String(trimmed.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",:;.!?")))
    }

    /// Kick off the curation. The feed view listens on `isRunning` and
    /// surfaces the animated overlay. We also extract keywords + write
    /// them to `boostKeywords` so the ranker picks them up immediately.
    func curate(wish: String) {
        let body = WhisperDearEmberService.wishBody(wish)
        guard !body.isEmpty else { return }
        curationTask?.cancel()
        runID = UUID()
        let currentRun = runID
        let generation = AccountStorage.generation
        self.wish = body
        boostKeywords = Self.extractKeywords(from: body)
        AccountStorage.set(boostKeywords.joined(separator: ","), forKey: keywordsKey)
        AccountStorage.set(body, forKey: wishKey)
        // Heuristic: any request mentioning "new", "fresh", "today" pins
        // the recency bias higher for this session.
        let lower = body.lowercased()
        freshenFromBoot = lower.contains("fresh")
            || lower.contains("today")
            || lower.contains("new ")
            || lower.contains("recent")
        let seconds = max(8, min(20, 6 + boostKeywords.count * 2))
        etaSeconds = seconds
        isRunning = true
        Haptics.success()
        curationTask = Task { @MainActor in
            do {
                for _ in 0..<seconds {
                    try await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled, generation == AccountStorage.generation, currentRun == runID else { return }
                    if etaSeconds > 0 { etaSeconds -= 1 }
                }
                await WhisperBackendService.shared.fetchPosts()
                guard !Task.isCancelled, generation == AccountStorage.generation, currentRun == runID else { return }
                await WhisperStoryService.shared.fetch()
                guard !Task.isCancelled, generation == AccountStorage.generation, currentRun == runID else { return }
                isRunning = false
                curationTask = nil
            } catch { /* Account changes and replacement requests cancel this run. */ }
        }
    }

    /// Cancel the running animation early — used by the overlay's tap.
    func dismissOverlay() {
        isRunning = false
    }

    /// Tiny stopword-aware keyword extractor — splits on whitespace, drops
    /// stopwords + tokens under 3 chars, returns the first 6 unique tokens.
    /// Good enough to bias the ranker without a server round-trip.
    static func extractKeywords(from text: String) -> [String] {
        let stop: Set<String> = [
            "the","a","an","of","to","in","on","for","and","or","but",
            "is","are","was","were","be","been","being","i","you","me",
            "my","mine","your","yours","want","need","please","more","less",
            "see","show","feed","posts","post","ember","knot","dear","with","without",
            "about","this","that","these","those","up","down","kind","of"
        ]
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "#", with: "")
        let tokens = cleaned
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 && !stop.contains($0) }
        var seen: Set<String> = []
        var out: [String] = []
        for t in tokens {
            if seen.insert(t).inserted { out.append(t) }
            if out.count >= 6 { break }
        }
        return out
    }

    /// Multiplicative bump applied per matching keyword found in the post
    /// caption — small enough that organic engagement still wins, large
    /// enough that two matches noticeably reorder the feed.
    func boost(for post: WhisperPost) -> Double {
        guard !boostKeywords.isEmpty else { return 1.0 }
        let cap = post.caption.lowercased()
        var mult = 1.0
        for kw in boostKeywords where cap.contains(kw) {
            mult *= 1.18
        }
        return mult
    }
}
