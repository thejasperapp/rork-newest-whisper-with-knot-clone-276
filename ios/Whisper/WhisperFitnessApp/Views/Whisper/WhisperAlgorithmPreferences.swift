import SwiftUI

// MARK: - Signals

/// One thing the Waves algorithm has learned you're into — a community, a
/// hashtag, or a creator — with the weight your likes / saves / watch time /
/// follows gave it. Computed on-device from the loaded pool; nothing leaves
/// the phone.
struct WhisperAlgorithmSignal: Identifiable, Hashable {
    enum Kind: Hashable {
        case community
        case hashtag
        case creator
    }

    let kind: Kind
    /// Display label — "Workouts", "#legday", "@dyl".
    let label: String
    /// Lowercased match term without the # / @ prefix.
    let term: String
    let weight: Double

    var id: String { "\(kind).\(term)" }
}

/// The counts behind the "Based on your activity" line.
struct WhisperAlgorithmActivity: Equatable {
    var likes: Int = 0
    var saves: Int = 0
    var watched: Int = 0
    var following: Int = 0

    var isEmpty: Bool { likes + saves + watched + following == 0 }
}

// MARK: - Preferences

/// "Your algorithm" — the on-device ledger behind the Waves feed. Keeps the
/// user's explicit steering (see MORE of · see LESS of), the wave watch log,
/// dismissed suggestions, and the cached AI summary. Persisted in
/// UserDefaults; the ranker reads `multiplier(for:)` on every sort.
@MainActor
@Observable
final class WhisperAlgorithmPreferences {
    static let shared = WhisperAlgorithmPreferences()

    private struct Watch: Codable {
        let at: Date
        var seconds: Double
    }

    private struct Persisted: Codable {
        var strength: Double? = nil
        var moreOf: [String] = []
        var lessOf: [String] = []
        var dismissed: [String] = []
        var watches: [String: Watch] = [:]
        var summary: String? = nil
        var summaryAt: Date? = nil
        var summarySignature: String? = nil
    }

    private let key = "whisper.algorithm.prefs.v2"
    private(set) var strength: Double = 1

    func setStrength(_ value: Double) {
        strength = min(1, max(0, value))
        persist()
    }

    /// Terms the user wants MORE of — display labels ("Workouts", "#legday", "@dyl").
    private(set) var moreOf: [String] = []
    /// Terms the user wants LESS of.
    private(set) var lessOf: [String] = []
    private(set) var dismissed: Set<String> = []
    private var watches: [String: Watch] = [:]
    /// The AI one-liner ("Lately you've been into …"), cached 24h per signature.
    private(set) var summary: String?
    private(set) var summaryAt: Date?
    private(set) var summarySignature: String?

    init() { reloadForCurrentAccount() }

    func reloadForCurrentAccount() {
        moreOf = []; lessOf = []; dismissed = []; watches = [:]
        summary = nil; summaryAt = nil; summarySignature = nil; strength = 1
        guard let data = AccountStorage.data(forKey: key),
              let p = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        strength = min(1, max(0, p.strength ?? 1))
        moreOf = p.moreOf
        lessOf = p.lessOf
        dismissed = Set(p.dismissed)
        watches = p.watches
        summary = p.summary
        summaryAt = p.summaryAt
        summarySignature = p.summarySignature
    }

    // MARK: Steering

    func addMore(_ label: String) {
        let clean = Self.clean(label)
        guard !clean.isEmpty else { return }
        lessOf.removeAll { Self.norm($0) == Self.norm(clean) }
        if !moreOf.contains(where: { Self.norm($0) == Self.norm(clean) }) {
            moreOf.append(clean)
        }
        dismissed.remove(Self.norm(clean))
        persist()
    }

    func removeMore(_ label: String) {
        moreOf.removeAll { Self.norm($0) == Self.norm(label) }
        persist()
    }

    func addLess(_ label: String) {
        let clean = Self.clean(label)
        guard !clean.isEmpty else { return }
        moreOf.removeAll { Self.norm($0) == Self.norm(clean) }
        if !lessOf.contains(where: { Self.norm($0) == Self.norm(clean) }) {
            lessOf.append(clean)
        }
        persist()
    }

    func removeLess(_ label: String) {
        lessOf.removeAll { Self.norm($0) == Self.norm(label) }
        persist()
    }

    /// Hides a suggested chip without steering either way.
    func dismissSuggestion(_ label: String) {
        dismissed.insert(Self.norm(label))
        persist()
    }

    func isMore(_ label: String) -> Bool { moreOf.contains { Self.norm($0) == Self.norm(label) } }
    func isLess(_ label: String) -> Bool { lessOf.contains { Self.norm($0) == Self.norm(label) } }

    /// Wipes every steer, the watch log, and the cached summary.
    func reset() {
        strength = 1
        moreOf = []
        lessOf = []
        dismissed = []
        watches = [:]
        summary = nil
        summaryAt = nil
        summarySignature = nil
        persist()
    }

    // MARK: Watch log

    /// Records that a wave was actually watched (called once it has been on
    /// screen ~2.5s). Accumulates seconds per wave; the log keeps 400 waves.
    func recordWatch(postID: String, seconds: Double) {
        let id = postID.lowercased()
        if var w = watches[id] {
            w.seconds += seconds
            watches[id] = w
        } else {
            watches[id] = Watch(at: Date(), seconds: seconds)
        }
        if watches.count > 400 {
            let oldest = watches.sorted { $0.value.at < $1.value.at }.prefix(watches.count - 400)
            for (k, _) in oldest { watches.removeValue(forKey: k) }
        }
        persist()
    }

    func hasWatched(_ id: UUID) -> Bool {
        watches[id.uuidString.lowercased()] != nil
    }

    func watchSeconds(_ id: UUID) -> Double {
        watches[id.uuidString.lowercased()]?.seconds ?? 0
    }

    var watchedCount: Int { watches.count }

    // MARK: Summary cache

    func cacheSummary(_ text: String, signature: String) {
        summary = text
        summaryAt = Date()
        summarySignature = signature
        persist()
    }

    /// The cached summary if it's under 24h old and still describes the same
    /// top signals.
    func cachedSummary(for signature: String) -> String? {
        guard let summary, let at = summaryAt, summarySignature == signature,
              Date().timeIntervalSince(at) < 60 * 60 * 24 else { return nil }
        return summary
    }

    // MARK: Ranking hooks

    /// Multiplier the Waves ranker applies per wave: ×1.5 per matched
    /// "more of" term (capped at ×2.25), ×0.3 when any "less of" term matches.
    func multiplier(for post: WhisperPost) -> Double {
        var m: Double = 1
        for term in moreOf where Self.matches(term, post: post) {
            m *= 1.5
            if m >= 2.25 { m = 2.25; break }
        }
        if lessOf.contains(where: { Self.matches($0, post: post) }) {
            m *= 0.3
        }
        return pow(m, strength)
    }

    /// Whether a steer term describes a wave — its community, a hashtag or
    /// word in the caption, or its creator.
    static func matches(_ term: String, post: WhisperPost) -> Bool {
        let t = norm(term)
        guard !t.isEmpty else { return false }
        if term.hasPrefix("@") {
            return post.username.lowercased() == t
        }
        if let c = post.communityName?.lowercased(), c == t || c.contains(t) { return true }
        if post.username.lowercased() == t { return true }
        let caption = post.displayCaption.lowercased()
        if term.hasPrefix("#") {
            return caption.contains("#" + t)
        }
        return caption.contains(t)
    }

    // MARK: Helpers

    private static func clean(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(40))
    }

    /// Lowercased, prefix-stripped comparison key.
    static func norm(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while t.hasPrefix("#") || t.hasPrefix("@") { t.removeFirst() }
        return t
    }

    private func persist() {
        let p = Persisted(
            strength: strength,
            moreOf: moreOf,
            lessOf: lessOf,
            dismissed: Array(dismissed),
            watches: watches,
            summary: summary,
            summaryAt: summaryAt,
            summarySignature: summarySignature
        )
        if let data = try? JSONEncoder().encode(p) {
            AccountStorage.set(data, forKey: key)
        }
    }
}

// MARK: - The signal engine

/// Turns what you actually did — likes, saves, watch time, follows — into
/// ranked interest signals, and writes the one-line "Lately you've been
/// into …" summary (one AI call, cached a day; a templated line offline).
@MainActor
enum WhisperAlgorithmSignals {

    /// Ranked signals + the activity counts they came from.
    static func compute(pool: [WhisperPost]) -> (signals: [WhisperAlgorithmSignal], activity: WhisperAlgorithmActivity) {
        let prefs = WhisperAlgorithmPreferences.shared
        let bookmarks = WhisperBookmarkService.shared
        let following = Set(WhisperFollowService.shared.followingUsernames.values.map { $0.lowercased() })

        var buckets: [String: (WhisperAlgorithmSignal.Kind, String, Double)] = [:]
        var activity = WhisperAlgorithmActivity()
        activity.following = following.count

        func add(_ kind: WhisperAlgorithmSignal.Kind, label: String, weight: Double) {
            let term = WhisperAlgorithmPreferences.norm(label)
            guard !term.isEmpty, weight > 0 else { return }
            let key = "\(kind).\(term)"
            if let existing = buckets[key] {
                buckets[key] = (existing.0, existing.1, existing.2 + weight)
            } else {
                buckets[key] = (kind, label, weight)
            }
        }

        var seenIDs = Set<UUID>()
        for post in pool where !seenIDs.contains(post.id) {
            seenIDs.insert(post.id)
            let id = post.id.uuidString.lowercased()
            var weight: Double = 0
            if post.liked { weight += 3; activity.likes += 1 }
            if bookmarks.isBookmarked(id) { weight += 4; activity.saves += 1 }
            let watched = prefs.watchSeconds(post.id)
            if watched > 0 {
                weight += 1 + min(2, watched / 8)
                activity.watched += 1
            }
            if following.contains(post.username.lowercased()) { weight += 0.75 }
            guard weight > 0 else { continue }

            if let community = post.communityName?.trimmingCharacters(in: .whitespacesAndNewlines), !community.isEmpty {
                add(.community, label: community, weight: weight * 1.2)
            }
            for token in WhisperMentionParser.tokens(in: post.displayCaption) where token.kind == .hashtag {
                add(.hashtag, label: "#" + token.value.lowercased(), weight: weight)
            }
            add(.creator, label: "@" + post.username.lowercased(), weight: weight * 0.6)
        }

        let signals = buckets.values
            .map { WhisperAlgorithmSignal(kind: $0.0, label: $0.1, term: WhisperAlgorithmPreferences.norm($0.1), weight: $0.2) }
            .sorted { lhs, rhs in
                if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
                return lhs.label < rhs.label
            }
        return (signals, activity)
    }

    /// Suggested "more of" chips — the strongest signals you haven't steered
    /// or dismissed yet.
    static func suggestions(from signals: [WhisperAlgorithmSignal], limit: Int = 6) -> [WhisperAlgorithmSignal] {
        let prefs = WhisperAlgorithmPreferences.shared
        return signals
            .filter { !prefs.isMore($0.label) && !prefs.isLess($0.label) && !prefs.dismissed.contains($0.term) }
            .prefix(limit)
            .map { $0 }
    }

    /// Cache key for the summary — the top five labels plus the explicit steers.
    static func signature(signals: [WhisperAlgorithmSignal]) -> String {
        let prefs = WhisperAlgorithmPreferences.shared
        let top = signals.prefix(5).map(\.label)
        return (top + ["|"] + prefs.moreOf + ["|"] + prefs.lessOf).joined(separator: ",").lowercased()
    }

    /// The offline / fallback line — humanizes the labels without AI.
    static func templatedSummary(signals: [WhisperAlgorithmSignal]) -> String {
        let prefs = WhisperAlgorithmPreferences.shared
        var labels: [String] = prefs.moreOf
        for s in signals where labels.count < 4 && !labels.contains(where: { WhisperAlgorithmPreferences.norm($0) == s.term }) {
            labels.append(s.label)
        }
        let human = labels.prefix(4).map { humanize($0) }
        guard !human.isEmpty else {
            return "Lately you've been quiet — like, save, and watch a few waves and I'll learn what you're into."
        }
        return "Lately you've been into " + joined(human) + "."
    }

    /// One AI call → "Lately you've been into fitness fashion, mixology and
    /// logging miles." Cached 24h per signature; templated line on failure.
    static func summarize(signals: [WhisperAlgorithmSignal]) async -> String {
        let prefs = WhisperAlgorithmPreferences.shared
        let sig = signature(signals: signals)
        if let cached = prefs.cachedSummary(for: sig) { return cached }
        let fallback = templatedSummary(signals: signals)
        guard !signals.isEmpty || !prefs.moreOf.isEmpty else { return fallback }

        let top = signals.prefix(8).map { "\($0.label) (\(Int($0.weight.rounded())))" }.joined(separator: ", ")
        let steers = prefs.moreOf.isEmpty ? "none" : prefs.moreOf.joined(separator: ", ")
        let avoid = prefs.lessOf.isEmpty ? "none" : prefs.lessOf.joined(separator: ", ")
        let system = """
        You summarize what someone has been into on Whisper's short-video feed. Reply with ONE sentence, plain and human, that starts exactly with "Lately you've been into" and names two to four interests in everyday words (e.g. "fitness fashion, mixology and logging miles"). Turn hashtags and @handles into natural phrases ("@dyl" → "dyl's waves", "#legday" → "leg day"). No hashtags, no @ signs, no quotes, no emojis, under 95 characters, end with a period.
        """
        let user = "Signals by weight: \(top). They asked to see more of: \(steers). Less of: \(avoid)."
        if let reply = await WhisperMeetingCompanion.completion(system: system, user: user, maxTokens: 60) {
            var line = reply.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let firstLine = line.split(separator: "\n").first { line = String(firstLine) }
            if line.lowercased().hasPrefix("lately you've been into"), line.count <= 140 {
                prefs.cacheSummary(line, signature: sig)
                return line
            }
        }
        prefs.cacheSummary(fallback, signature: sig)
        return fallback
    }

    // MARK: Text helpers

    private static func humanize(_ label: String) -> String {
        if label.hasPrefix("@") { return String(label.dropFirst()) + "'s waves" }
        if label.hasPrefix("#") {
            let raw = String(label.dropFirst())
            // Split camelCase / joined words lightly: "legday" stays "legday", "LegDay" → "leg day".
            var out = ""
            for (i, ch) in raw.enumerated() {
                if ch.isUppercase, i > 0 { out.append(" ") }
                out.append(ch)
            }
            return out.lowercased()
        }
        return label.lowercased()
    }

    private static func joined(_ parts: [String]) -> String {
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        case 2: return "\(parts[0]) and \(parts[1])"
        default: return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
    }
}
