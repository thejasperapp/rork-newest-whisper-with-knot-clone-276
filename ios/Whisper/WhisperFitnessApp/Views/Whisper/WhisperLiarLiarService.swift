import Foundation
import SwiftUI
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.whisper_liar_strikes (
//     id uuid primary key default gen_random_uuid(),
//     target_username text not null,
//     claim text,
//     verdict text not null,
//     reported_by_username text,
//     created_at timestamptz not null default now()
// );
// create index if not exists whisper_liar_strikes_target_idx
//     on public.whisper_liar_strikes (lower(target_username), created_at desc);
// alter table public.whisper_liar_strikes enable row level security;
// drop policy if exists "liar strikes read" on public.whisper_liar_strikes;
// create policy "liar strikes read" on public.whisper_liar_strikes
//     for select using (true);
// drop policy if exists "liar strikes write" on public.whisper_liar_strikes;
// create policy "liar strikes write" on public.whisper_liar_strikes
//     for insert with check (auth.uid() is not null);
//
// create table if not exists public.whisper_liar_badges (
//     username text primary key,
//     reason text,
//     strike_count int not null default 3,
//     acknowledged_at timestamptz,
//     appeal_status text,
//     created_at timestamptz not null default now()
// );
// alter table public.whisper_liar_badges enable row level security;
// drop policy if exists "liar badges read" on public.whisper_liar_badges;
// create policy "liar badges read" on public.whisper_liar_badges
//     for select using (true);
// drop policy if exists "liar badges write" on public.whisper_liar_badges;
// create policy "liar badges write" on public.whisper_liar_badges
//     for insert with check (auth.uid() is not null);
// drop policy if exists "liar badges update" on public.whisper_liar_badges;
// create policy "liar badges update" on public.whisper_liar_badges
//     for update using (auth.uid() is not null);
//
// create table if not exists public.whisper_liar_appeals (
//     id uuid primary key default gen_random_uuid(),
//     username text not null,
//     body text not null,
//     status text not null default 'pending',
//     created_at timestamptz not null default now()
// );
// alter table public.whisper_liar_appeals enable row level security;
// drop policy if exists "liar appeals write" on public.whisper_liar_appeals;
// create policy "liar appeals write" on public.whisper_liar_appeals
//     for insert with check (auth.uid() is not null);
// drop policy if exists "liar appeals read" on public.whisper_liar_appeals;
// create policy "liar appeals read" on public.whisper_liar_appeals
//     for select using (true);
//
// -- Mirror into public.profiles so the badge can be assigned / removed
// -- manually from the Supabase table editor without touching whisper_liar_badges.
// alter table public.profiles
//     add column if not exists is_liar boolean not null default false;
// alter table public.profiles
//     add column if not exists liar_reason text;
// -- (optional) same column on whisper_profiles for symmetry with is_coach
// alter table public.whisper_profiles
//     add column if not exists is_liar boolean not null default false;
// alter table public.whisper_profiles
//     add column if not exists liar_reason text;

/// Active "Liar Liar" badge state for a single username. Stored in
/// `whisper_liar_badges` so all clients can render the chip and so the
/// owner sees the explainer popup exactly once per badge issuance.
nonisolated struct WhisperLiarLiarBadgeRow: Codable, Sendable, Identifiable {
    let username: String
    let reason: String?
    let strike_count: Int?
    let acknowledged_at: Date?
    let appeal_status: String?
    let created_at: Date?
    /// Set when the badge was sourced from `profiles.is_liar` (manual
    /// assignment via Supabase) rather than the automated strike pipeline.
    /// Not persisted — synthesized on the client.
    var manualOverride: Bool? = nil

    var id: String { username }
    var hasAppealedPending: Bool { (appeal_status ?? "") == "pending" }
    var wasApproved: Bool { (appeal_status ?? "") == "approved" }

    enum CodingKeys: String, CodingKey {
        case username, reason, strike_count, acknowledged_at, appeal_status, created_at
    }
}

/// Tracks "Liar Liar" badges across Whisper. A user earns the badge after
/// 3 false / misleading fact-checks are logged against them within a
/// rolling 30-day window. Badge is rendered next to their username, the
/// owner gets a one-time explainer popup, and they can submit an appeal.
@Observable
@MainActor
final class WhisperLiarLiarService {
    static let shared = WhisperLiarLiarService()

    /// Strikes required before the badge is auto-applied.
    static let strikeThreshold: Int = 3
    /// Rolling window strikes are counted in.
    static let strikeWindow: TimeInterval = 60 * 60 * 24 * 30

    private let client = SupabaseService.shared.client

    /// Lowercased username -> badge row.
    private(set) var badgesByUsername: [String: WhisperLiarLiarBadgeRow] = [:]
    private var inFlight: Set<String> = []

    /// Set when the current viewer has an un-acknowledged Liar Liar badge —
    /// drives the explainer popup in `WhisperRootView`.
    var pendingPopup: WhisperLiarLiarBadgeRow?

    private init() {}

    // Compatibility shell for older callers. Historical review records stay on the server.
    private let legacyLabelsRetired = true

    // MARK: - Lookup

    func badge(forUsername raw: String) -> WhisperLiarLiarBadgeRow? {
        guard !legacyLabelsRetired else { return nil }
        let key = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let row = badgesByUsername[key] else { return nil }
        // Approved appeals clear the badge for everyone, UNLESS the badge
        // was manually re-applied via profiles.is_liar (manualOverride).
        if row.wasApproved && row.manualOverride != true { return nil }
        return row
    }

    /// Returns true if `username` currently wears the Liar Liar chip.
    func isLiar(_ raw: String) -> Bool { badge(forUsername: raw) != nil }

    /// Prefetches Liar Liar badges for a batch of usernames so feed rows /
    /// inbox can render the chip in the first frame.
    func preload(usernames: [String]) async {
        guard !legacyLabelsRetired else { return }
        let normalized = Set(usernames
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && badgesByUsername[$0] == nil && !inFlight.contains($0) })
        guard !normalized.isEmpty else { return }
        inFlight.formUnion(normalized)
        defer { inFlight.subtract(normalized) }

        var updated = badgesByUsername
        do {
            let rows: [WhisperLiarLiarBadgeRow] = try await client
                .from("whisper_liar_badges")
                .select("username,reason,strike_count,acknowledged_at,appeal_status,created_at")
                .in("username", values: Array(normalized))
                .execute()
                .value
            for r in rows {
                updated[r.username.lowercased()] = r
            }
        } catch {
            // Silent — badges are non-critical.
        }

        // Also pull manual assignments from public.profiles.is_liar — any
        // user flipped to true there earns the chip even without strikes.
        let manualRows = await fetchManualFlags(usernames: Array(normalized))
        for row in manualRows {
            let key = row.username.lowercased()
            if var existing = updated[key] {
                existing.manualOverride = true
                updated[key] = existing
            } else {
                updated[key] = WhisperLiarLiarBadgeRow(
                    username: row.username,
                    reason: row.liar_reason ?? "Manually assigned by a moderator.",
                    strike_count: Self.strikeThreshold,
                    acknowledged_at: nil,
                    appeal_status: nil,
                    created_at: nil,
                    manualOverride: true
                )
            }
        }
        badgesByUsername = updated
    }

    // MARK: - Manual flag (profiles.is_liar)

    nonisolated struct ManualLiarRow: Decodable, Sendable {
        let username: String
        let is_liar: Bool?
        let liar_reason: String?
    }

    private func fetchManualFlags(usernames: [String]) async -> [ManualLiarRow] {
        guard !usernames.isEmpty else { return [] }
        var hits: [String: ManualLiarRow] = [:]
        // public.profiles
        do {
            let rows: [ManualLiarRow] = try await client
                .from("profiles")
                .select("username,is_liar,liar_reason")
                .in("username", values: usernames)
                .eq("is_liar", value: true)
                .execute()
                .value
            for r in rows { hits[r.username.lowercased()] = r }
        } catch {
            // column / table missing — ignore
        }
        // whisper_profiles (mirror)
        do {
            let rows: [ManualLiarRow] = try await client
                .from("whisper_profiles")
                .select("username,is_liar,liar_reason")
                .in("username", values: usernames)
                .eq("is_liar", value: true)
                .execute()
                .value
            for r in rows where hits[r.username.lowercased()] == nil {
                hits[r.username.lowercased()] = r
            }
        } catch {
            // ignore
        }
        return Array(hits.values)
    }

    private func fetchManualFlag(username: String) async -> ManualLiarRow? {
        let rows = await fetchManualFlags(usernames: [username])
        return rows.first
    }

    // MARK: - Strikes

    nonisolated struct StrikeInsert: Codable, Sendable {
        let target_username: String
        let claim: String?
        let verdict: String
        let reported_by_username: String?
    }

    /// Heuristic that detects whether a piece of text looks like a factual
    /// claim worth holding someone accountable for. Filters out short text,
    /// questions, jokes, casual chatter, and anything that isn't an
    /// assertion with a verifiable number or domain keyword. Public so the
    /// Liar Liar pipeline can be gated from any caller (e.g. the post
    /// fact-check button) without duplicating the rule.
    nonisolated static func looksLikeFactualClaim(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 14, trimmed.count <= 800 else { return false }
        let lower = trimmed.lowercased()
        if lower.hasSuffix("?") { return false }
        if looksLikeSatire(body) { return false }
        let hasDigit = trimmed.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
        let keywords = [
            "calor", "protein", "carb", "fat", "sugar", "fiber",
            "bmi", "kg", "lbs", "pound", "gram", "oz",
            "mile", "km ", "kilometer", "step",
            "heart rate", "bpm", "vo2", "hrv",
            "creatine", "caffeine", "vitamin", "supplement", "steroid",
            "keto", "vegan", "carnivore", "fasting", "intermittent",
            "cardio", "strength", "hypertrophy", "deload",
            "sleep", "recover", "injury", "tendon", "ligament",
            "hormone", "testosteron", "insulin", "cortisol",
            "percent", "%",
            // Broader health / science / claim-shaped vocab so common
            "diet", "weight", "muscle", "fitness", "workout", "exercise",
            "metabolism", "deficit", "surplus", "macro", "micronutrient",
            "squat", "deadlift", "bench", "press", "rep ", "reps ", "set ", "sets ",
            "vaccine", "covid", "medicine", "doctor", "study", "research",
            "science", "prove", "proven", "fact", "truth"
        ]
        let hasKeyword = keywords.contains { lower.contains($0) }
        let hasAssertion = lower.contains(" is ") || lower.contains(" are ") ||
            lower.contains(" causes ") || lower.contains(" cause ") ||
            lower.contains(" prevent") || lower.contains(" reduce") ||
            lower.contains(" burns ") || lower.contains(" builds ") ||
            lower.contains(" needs ") || lower.contains(" makes ") ||
            lower.contains(" increases") || lower.contains(" decreases") ||
            lower.contains(" always") || lower.contains(" never") ||
            lower.contains(" everyone") || lower.contains(" nobody") ||
            lower.contains("% of") || lower.contains(" per day") ||
            lower.contains(" per week")
        return (hasDigit && hasKeyword) || (hasKeyword && hasAssertion) || (hasDigit && hasAssertion)
    }

    /// Heuristic that flags obviously satirical, sarcastic, or joke posts
    /// so the fact-checker never lights them up. Catches the standard
    /// humor tells (lol, /s, crying-laughing emoji) plus shitpost-shaped
    /// captions ("breaking:", "scientists discover", "local man"), absurd
    /// numeric claims (10000% etc.), and clear self-deprecation. Public so
    /// any caller (post card, DM auto-check, prewarm) can short-circuit
    /// without duplicating the rule.
    nonisolated static func looksLikeSatire(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        // Direct humor / sarcasm markers.
        let humorMarkers = [
            " lol", "lol ", "lmao", "rofl", " jk", "jk ", "/s", "/sarc",
            " haha", "hehe", "\u{1F602}", "\u{1F923}", "\u{1F606}",
            "\u{1F605}", "\u{1F643}", "\u{1F921}", "\u{1F92A}", "\u{1F928}",
            // explicit satire signals
            "satire", "shitpost", "shit post", "the onion", "/joke", "jk lol",
            "this is a joke", "obviously joking", "clearly joking", "kidding",
            "just kidding", "i'm joking", "im joking", "obviously fake"
        ]
        if humorMarkers.contains(where: { lower.contains($0) }) { return true }
        // Catch "lol" / "jk" / "haha" as standalone words at start/end too.
        let words = lower.split { !$0.isLetter }.map(String.init)
        let standalone: Set<String> = ["lol", "lmao", "jk", "haha", "hehe", "rofl"]
        if let first = words.first, standalone.contains(first) { return true }
        if let last = words.last, standalone.contains(last) { return true }
        // Shitpost / faux-headline shapes.
        let satireShapes = [
            "breaking:", "local man", "local woman", "area man", "scientists discover",
            "new study reveals that", "experts hate this", "doctors hate",
            "my doctor told me i\u{2019}d die", "i was today years old"
        ]
        if satireShapes.contains(where: { lower.contains($0) }) { return true }
        // Absurd numeric claims — "10000%", "i lost 500 pounds", etc.
        // These are almost always jokes; real fitness numbers stay sane.
        if lower.range(of: #"\b(\d{4,})\s*%"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"\b(\d{3,})\s*(lbs|pounds|kg|kilos)\b"#, options: .regularExpression) != nil {
            // 100lb is plausible; 300+ lbs lost / gained in a caption is shitpost territory.
            // Only flag when paired with a transformation verb.
            if lower.contains("lost ") || lower.contains("gained ") || lower.contains("dropped ") {
                return true
            }
        }
        // Lots of trailing exclamation / 😂 / multi-emoji = vibe post, not a claim.
        let exclamationRun = trimmed.suffix(6).filter { $0 == "!" }.count
        if exclamationRun >= 3 { return true }
        return false
    }

    /// Records a single false / misleading fact-check strike against
    /// `username`. If the rolling-window count crosses the threshold, the
    /// badge is auto-applied. Strikes are ONLY recorded for public posts
    /// whose caption text looks like a factual claim — never DMs, workouts,
    /// jokes, or anything else. Duplicate calls are throttled per
    /// (username, claim).
    func recordStrike(againstUsername raw: String, claim: String, verdict: WhisperFactCheckEmbed.Verdict) async {
        guard !legacyLabelsRetired else { return }
        guard verdict == .falseClaim || verdict == .misleading else { return }
        // Hard gate — only factual-looking post text earns a strike.
        guard Self.looksLikeFactualClaim(claim) else { return }
        let username = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else { return }
        // Don't strike the current viewer based on their OWN fact-check tap;
        // strikes should be for the AUTHOR of the claim. Caller is expected
        // to pass the claim author's username, so we only block obviously
        // self-reported strikes when the viewer fact-checks their own post.
        let me = (LeaderboardService.shared.savedUsername
                  ?? AuthenticationService.shared.currentUser.username
                  ?? "").lowercased()

        let throttleKey = "liarStrike:\(username):\(claim.hashValue):\(verdict.rawValue)"
        if inFlight.contains(throttleKey) { return }
        inFlight.insert(throttleKey)
        defer { inFlight.remove(throttleKey) }

        let row = StrikeInsert(
            target_username: username,
            claim: String(claim.prefix(500)),
            verdict: verdict.rawValue,
            reported_by_username: me.isEmpty ? nil : me
        )
        do {
            try await client.from("whisper_liar_strikes").insert(row).execute()
        } catch {
            return
        }

        // Count rolling-window strikes for this user; if the target is the
        // signed-in viewer, fire a local notification so they always know a
        // strike just landed (and how close they are to the badge). Auto-
        // applies the badge once the threshold is hit.
        await evaluateBadge(
            forUsername: username,
            latestClaim: claim,
            verdict: verdict,
            isSelf: !me.isEmpty && me == username
        )
    }

    nonisolated struct StrikeCountRow: Codable, Sendable {
        let id: String
        let verdict: String
        let claim: String?
        let created_at: Date
    }

    private func evaluateBadge(forUsername username: String, latestClaim: String, verdict: WhisperFactCheckEmbed.Verdict, isSelf: Bool) async {
        let since = Date().addingTimeInterval(-Self.strikeWindow)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let sinceISO = isoFormatter.string(from: since)

        do {
            let rows: [StrikeCountRow] = try await client
                .from("whisper_liar_strikes")
                .select("id,verdict,claim,created_at")
                .eq("target_username", value: username)
                .gte("created_at", value: sinceISO)
                .execute()
                .value
            let bad = rows.filter { $0.verdict == "false" || $0.verdict == "misleading" }
            let count = bad.count

            // Always let the viewer know when one of their own posts just
            // earned a strike — runs even if the badge is already applied
            // so users see every accumulation, not just the first three.
            if isSelf {
                let latestID = bad
                    .sorted { $0.created_at > $1.created_at }
                    .first?.id ?? UUID().uuidString
                WhisperNotificationService.shared.notifyLiarStrike(
                    strikeID: latestID,
                    count: count,
                    threshold: Self.strikeThreshold,
                    verdictLabel: verdict.label,
                    claimPreview: latestClaim
                )
            }

            // Already badged (and not pardoned via approved appeal) — no
            // need to re-apply, but the notification above still fires.
            if let existing = badgesByUsername[username], !existing.wasApproved { return }
            guard count >= Self.strikeThreshold else { return }
            await applyBadge(username: username, strikeCount: count, latestClaim: latestClaim, verdict: verdict)
        } catch {
            // Silent — strikes are non-critical.
        }
    }

    // MARK: - Badge application

    nonisolated struct BadgeUpsert: Codable, Sendable {
        let username: String
        let reason: String
        let strike_count: Int
    }

    private func applyBadge(username: String, strikeCount: Int, latestClaim: String, verdict: WhisperFactCheckEmbed.Verdict) async {
        let reason = "Auto-issued after \(strikeCount) false or misleading fact-checks in the last 30 days. Most recent: \"\(String(latestClaim.prefix(140)))\" — verdict: \(verdict.label)."
        let row = BadgeUpsert(username: username, reason: reason, strike_count: strikeCount)
        do {
            try await client
                .from("whisper_liar_badges")
                .upsert(row, onConflict: "username")
                .execute()
            // Refresh the local cache + trigger the popup if it's us.
            await refresh(username: username, showPopupIfMine: true)
        } catch {
            // Silent.
        }
    }

    // MARK: - Refresh / popup gating

    /// Re-fetches one user's badge row. When `showPopupIfMine` is true and the
    /// row belongs to the signed-in viewer and hasn't been acknowledged yet,
    /// `pendingPopup` is set so `WhisperRootView` can present the explainer.
    func refresh(username raw: String, showPopupIfMine: Bool) async {
        guard !legacyLabelsRetired else { pendingPopup = nil; return }
        let key = raw.lowercased()
        guard !key.isEmpty else { return }
        do {
            let rows: [WhisperLiarLiarBadgeRow] = try await client
                .from("whisper_liar_badges")
                .select("username,reason,strike_count,acknowledged_at,appeal_status,created_at")
                .eq("username", value: key)
                .limit(1)
                .execute()
                .value
            var updated = badgesByUsername
            // Layer in manual profiles.is_liar override.
            let manual = await fetchManualFlag(username: key)
            if var row = rows.first {
                if manual != nil { row.manualOverride = true }
                updated[key] = row
                badgesByUsername = updated

                if showPopupIfMine {
                    let me = (LeaderboardService.shared.savedUsername
                              ?? AuthenticationService.shared.currentUser.username
                              ?? "").lowercased()
                    if me == key, row.acknowledged_at == nil, !row.wasApproved {
                        pendingPopup = row
                    }
                }
            } else if let manual = manual {
                // No auto-issued row, but a moderator flipped is_liar=true.
                let row = WhisperLiarLiarBadgeRow(
                    username: manual.username,
                    reason: manual.liar_reason ?? "Manually assigned by a moderator.",
                    strike_count: Self.strikeThreshold,
                    acknowledged_at: nil,
                    appeal_status: nil,
                    created_at: nil,
                    manualOverride: true
                )
                updated[key] = row
                badgesByUsername = updated
                if showPopupIfMine {
                    let me = (LeaderboardService.shared.savedUsername
                              ?? AuthenticationService.shared.currentUser.username
                              ?? "").lowercased()
                    // Even for manual overrides, check whisper_liar_badges
                    // for a prior acknowledgement so the popup doesn't fire
                    // again after the user has already dismissed it.
                    if me == key {
                        let alreadyAcked = await hasAcknowledgedBadge(username: key)
                        if !alreadyAcked { pendingPopup = row }
                    }
                }
            } else {
                updated.removeValue(forKey: key)
                badgesByUsername = updated
            }
        } catch {
            // Silent.
        }
    }

    nonisolated struct AckRow: Decodable, Sendable { let acknowledged_at: Date? }

    private func hasAcknowledgedBadge(username: String) async -> Bool {
        do {
            let rows: [AckRow] = try await client
                .from("whisper_liar_badges")
                .select("acknowledged_at")
                .eq("username", value: username)
                .limit(1)
                .execute()
                .value
            return rows.first?.acknowledged_at != nil
        } catch {
            return false
        }
    }

    /// Called from `WhisperRootView.task` so the popup also fires on cold
    /// launch if a strike accumulated while the user was away.
    func checkPopupForCurrentUser() async {
        let me = (LeaderboardService.shared.savedUsername
                  ?? AuthenticationService.shared.currentUser.username
                  ?? "").lowercased()
        guard !me.isEmpty else { return }
        await refresh(username: me, showPopupIfMine: true)
    }

    // MARK: - Acknowledge

    nonisolated struct AckUpdate: Codable, Sendable {
        let acknowledged_at: Date
    }

    nonisolated struct AckUpsert: Codable, Sendable {
        let username: String
        let reason: String
        let strike_count: Int
        let acknowledged_at: Date
    }

    /// Marks the popup as seen so it doesn't fire again on next launch.
    /// Uses upsert so manually-assigned badges (which may not have a row in
    /// `whisper_liar_badges` yet) still persist the acknowledgement.
    func acknowledgePopup() async {
        guard let row = pendingPopup else { return }
        pendingPopup = nil
        let now = Date()
        let payload = AckUpsert(
            username: row.username.lowercased(),
            reason: row.reason ?? "Manually assigned by a moderator.",
            strike_count: row.strike_count ?? Self.strikeThreshold,
            acknowledged_at: now
        )
        do {
            try await client
                .from("whisper_liar_badges")
                .upsert(payload, onConflict: "username")
                .execute()
            var updated = badgesByUsername
            if var current = updated[row.username.lowercased()] {
                let override = current.manualOverride
                current = WhisperLiarLiarBadgeRow(
                    username: current.username,
                    reason: current.reason,
                    strike_count: current.strike_count,
                    acknowledged_at: Date(),
                    appeal_status: current.appeal_status,
                    created_at: current.created_at,
                    manualOverride: override
                )
                updated[row.username.lowercased()] = current
                badgesByUsername = updated
            }
        } catch {
            // Silent.
        }
    }

    // MARK: - Appeals

    nonisolated struct AppealInsert: Codable, Sendable {
        let username: String
        let body: String
    }

    nonisolated struct AppealStatusUpdate: Codable, Sendable {
        let appeal_status: String
    }

    /// Submits a removal appeal. Marks the badge as `appeal_status = 'pending'`
    /// so the chip in the UI can render a subdued "appeal pending" state.
    func submitAppeal(body: String) async -> Bool {
        let me = (LeaderboardService.shared.savedUsername
                  ?? AuthenticationService.shared.currentUser.username
                  ?? "").lowercased()
        guard !me.isEmpty else { return false }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let payload = AppealInsert(username: me, body: trimmed)
        do {
            try await client.from("whisper_liar_appeals").insert(payload).execute()
            try await client
                .from("whisper_liar_badges")
                .update(AppealStatusUpdate(appeal_status: "pending"))
                .eq("username", value: me)
                .execute()
            await refresh(username: me, showPopupIfMine: false)
            return true
        } catch {
            return false
        }
    }
}
