import Foundation
import SwiftUI
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.whisper_blocks (
//     id uuid primary key default gen_random_uuid(),
//     blocker_id uuid not null references auth.users(id) on delete cascade,
//     blocked_user_id uuid not null,
//     blocked_username text not null,
//     created_at timestamptz not null default now(),
//     unique (blocker_id, blocked_user_id)
// );
// create index if not exists whisper_blocks_blocker_idx
//     on public.whisper_blocks (blocker_id);
// alter table public.whisper_blocks enable row level security;
// drop policy if exists "blocks read own" on public.whisper_blocks;
// create policy "blocks read own" on public.whisper_blocks
//     for select using (auth.uid() = blocker_id);
// drop policy if exists "blocks write own" on public.whisper_blocks;
// create policy "blocks write own" on public.whisper_blocks
//     for insert with check (auth.uid() = blocker_id);
// drop policy if exists "blocks delete own" on public.whisper_blocks;
// create policy "blocks delete own" on public.whisper_blocks
//     for delete using (auth.uid() = blocker_id);
//
// create table if not exists public.whisper_reports (
//     id uuid primary key default gen_random_uuid(),
//     reporter_id uuid not null references auth.users(id) on delete cascade,
//     reporter_username text,
//     target_kind text not null check (target_kind in ('user','story','post','dm','comment','reel')),
//     target_id text,
//     target_user_id uuid,
//     target_username text,
//     reason text not null,
//     details text,
//     created_at timestamptz not null default now(),
//     status text not null default 'open'
// );
// create index if not exists whisper_reports_target_idx
//     on public.whisper_reports (target_user_id, created_at desc);
// alter table public.whisper_reports enable row level security;
// drop policy if exists "reports insert own" on public.whisper_reports;
// create policy "reports insert own" on public.whisper_reports
//     for insert with check (auth.uid() = reporter_id);
// drop policy if exists "reports read own" on public.whisper_reports;
// create policy "reports read own" on public.whisper_reports
//     for select using (auth.uid() = reporter_id);

nonisolated struct WhisperBlockRow: Codable, Sendable, Identifiable {
    let id: String?
    let blocker_id: String
    let blocked_user_id: String
    let blocked_username: String
    let created_at: Date?
}

nonisolated struct WhisperBlockInsert: Codable, Sendable {
    let blocker_id: String
    let blocked_user_id: String
    let blocked_username: String
}

nonisolated enum WhisperReportTargetKind: String, Codable, Sendable, CaseIterable {
    case user, story, post, dm, comment, reel

    var label: String {
        switch self {
        case .user:    return "account"
        case .story:   return "story"
        case .post:    return "post"
        case .dm:      return "message"
        case .comment: return "comment"
        case .reel:    return "reel"
        }
    }
}

nonisolated enum WhisperReportReason: String, CaseIterable, Sendable, Identifiable {
    case spam
    case harassment
    case hate
    case sexual
    case violence
    case selfHarm
    case minorSafety
    case impersonation
    case scam
    case misinformation
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spam:           return "Spam or misleading"
        case .harassment:     return "Harassment or bullying"
        case .hate:           return "Hate speech or symbols"
        case .sexual:         return "Nudity or sexual content"
        case .violence:       return "Violence or threats"
        case .selfHarm:       return "Self-harm or suicide"
        case .minorSafety:    return "Endangering a minor"
        case .impersonation:  return "Impersonation"
        case .scam:           return "Scam or fraud"
        case .misinformation: return "False information"
        case .other:          return "Something else"
        }
    }

    var icon: String {
        switch self {
        case .spam:           return "exclamationmark.bubble"
        case .harassment:     return "hand.raised.slash"
        case .hate:           return "nosign"
        case .sexual:         return "eye.slash"
        case .violence:       return "exclamationmark.triangle"
        case .selfHarm:       return "heart.slash"
        case .minorSafety:    return "shield.lefthalf.filled"
        case .impersonation:  return "person.crop.circle.badge.questionmark"
        case .scam:           return "creditcard.trianglebadge.exclamationmark"
        case .misinformation: return "questionmark.bubble"
        case .other:          return "ellipsis.circle"
        }
    }
}

nonisolated struct WhisperReportInsert: Codable, Sendable {
    let reporter_id: String
    let reporter_username: String?
    let target_kind: String
    let target_id: String?
    let target_user_id: String?
    let target_username: String?
    let reason: String
    let details: String?
}

/// Per-user blocks, abuse reports, and muted-word filters. Blocks are
/// authoritative through Supabase RLS; muted words are local-only on purpose
/// (private preference, not a moderation signal).
@Observable
@MainActor
final class WhisperBlockService {
    static let shared = WhisperBlockService()

    private let client = SupabaseService.shared.client

    /// Lowercased user_id -> block row.
    private(set) var blockedUserIDs: Set<String> = []
    /// Lowercased username -> block row (mirror, used when only the handle is known).
    private(set) var blockedUsernames: Set<String> = []
    /// Raw block rows so we can render the "Blocked accounts" list.
    private(set) var blocks: [WhisperBlockRow] = []
    /// Words / phrases the viewer chose to mute. Lowercased.
    var mutedWords: [String] = [] {
        didSet { persistMutedWords() }
    }

    private static let mutedWordsKey = "whisperBlock_mutedWords"
    private static let eulaKey = "whisperBlock_eulaAcceptedAt"
    private static let blocksCacheKey = "whisperBlock_blocksCache"

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    private init() {
        if let data = AccountStorage.data(forKey: Self.mutedWordsKey),
           let words = try? JSONDecoder().decode([String].self, from: data) {
            mutedWords = words
        }
        if let data = AccountStorage.data(forKey: Self.blocksCacheKey),
           let cached = try? JSONDecoder().decode([WhisperBlockRow].self, from: data) {
            apply(rows: cached)
        }
    }

    // MARK: - Blocks

    func isBlocked(userID: String) -> Bool {
        blockedUserIDs.contains(userID.lowercased())
    }

    func isBlockedUsername(_ username: String) -> Bool {
        blockedUsernames.contains(username.lowercased())
    }

    /// Convenience: hide anything authored by a blocked account in feeds, stories, DMs.
    func shouldHide(userID: String?, username: String?) -> Bool {
        if let uid = userID?.lowercased(), !uid.isEmpty, blockedUserIDs.contains(uid) {
            return true
        }
        if let name = username?.lowercased(), !name.isEmpty, blockedUsernames.contains(name) {
            return true
        }
        return false
    }

    func refresh() async {
        guard isRemote else { return }
        do {
            let rows: [WhisperBlockRow] = try await client
                .from("whisper_blocks")
                .select()
                .eq("blocker_id", value: currentUID)
                .order("created_at", ascending: false)
                .limit(500)
                .execute()
                .value
            apply(rows: rows)
            persistCache(rows)
        } catch {
            // Silent — keep cache.
        }
    }

    private func apply(rows: [WhisperBlockRow]) {
        blocks = rows
        blockedUserIDs = Set(rows.map { $0.blocked_user_id.lowercased() })
        blockedUsernames = Set(rows.map { $0.blocked_username.lowercased() })
    }

    private func persistCache(_ rows: [WhisperBlockRow]) {
        if let data = try? JSONEncoder().encode(rows) {
            AccountStorage.set(data, forKey: Self.blocksCacheKey)
        }
    }

    @discardableResult
    func block(userID: String, username: String) async -> Bool {
        guard isRemote, !userID.isEmpty else { return false }
        // Optimistic update for instant feedback.
        blockedUserIDs.insert(userID.lowercased())
        blockedUsernames.insert(username.lowercased())
        let payload = WhisperBlockInsert(
            blocker_id: currentUID,
            blocked_user_id: userID,
            blocked_username: username.lowercased()
        )
        do {
            try await client
                .from("whisper_blocks")
                .upsert(payload, onConflict: "blocker_id,blocked_user_id")
                .execute()
            await refresh()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func unblock(userID: String, username: String) async -> Bool {
        guard isRemote else { return false }
        blockedUserIDs.remove(userID.lowercased())
        blockedUsernames.remove(username.lowercased())
        blocks.removeAll { $0.blocked_user_id.lowercased() == userID.lowercased() }
        do {
            try await client
                .from("whisper_blocks")
                .delete()
                .eq("blocker_id", value: currentUID)
                .eq("blocked_user_id", value: userID)
                .execute()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Reports

    @discardableResult
    func report(
        kind: WhisperReportTargetKind,
        targetID: String?,
        targetUserID: String?,
        targetUsername: String?,
        reason: WhisperReportReason,
        details: String?
    ) async -> Bool {
        guard isRemote else { return false }
        let generation = AccountStorage.generation
        nonisolated struct ReportParams: Encodable, Sendable {
            let p_kind: String
            let p_target_id: String?
            let p_target_username: String?
            let p_reason: String
            let p_details: String?
        }
        let payload = ReportParams(p_kind: kind.rawValue, p_target_id: targetID ?? targetUserID, p_target_username: targetUsername, p_reason: reason.rawValue, p_details: details)
        do {
            let receipt: UUID = try await client.rpc("whisper_submit_report", params: payload).execute().value
            guard generation == AccountStorage.generation else { return false }
            _ = receipt
            return true
        } catch {
            return false
        }
    }

    // MARK: - Muted words

    func addMutedWord(_ raw: String) {
        let cleaned = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !mutedWords.contains(cleaned) else { return }
        mutedWords.append(cleaned)
    }

    func removeMutedWord(_ raw: String) {
        let cleaned = raw.lowercased()
        mutedWords.removeAll { $0 == cleaned }
    }

    /// Returns true if the supplied text contains any of the viewer's muted
    /// words (word-level match, case-insensitive). Empty text → false.
    func textIsMuted(_ text: String?) -> Bool {
        guard let raw = text, !raw.isEmpty, !mutedWords.isEmpty else { return false }
        let haystack = raw.lowercased()
        return mutedWords.contains { !$0.isEmpty && haystack.contains($0) }
    }

    private func persistMutedWords() {
        if let data = try? JSONEncoder().encode(mutedWords) {
            AccountStorage.set(data, forKey: Self.mutedWordsKey)
        }
    }

    // MARK: - EULA acknowledgment

    /// True once the user has accepted the EULA + objectionable-content ack.
    /// Persisted per-account so a fresh sign-in re-prompts.
    var hasAcceptedEULA: Bool {
        AccountStorage.object(forKey: Self.eulaKey) as? Double ?? 0 > 0
    }

    func acceptEULA() {
        AccountStorage.set(Date().timeIntervalSince1970, forKey: Self.eulaKey)
    }
}
