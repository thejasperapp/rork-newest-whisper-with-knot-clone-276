import Foundation
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.whisper_moderation_actions (
//     id uuid primary key default gen_random_uuid(),
//     target_username text not null,
//     target_user_id uuid,
//     action text not null check (action in ('mute','ban','unmute','unban')),
//     scope text not null default 'all' check (scope in ('post','comment','all')),
//     reason text,
//     duration_minutes integer,
//     expires_at timestamptz,
//     issued_by_username text not null,
//     issued_by_role text not null,
//     created_at timestamptz not null default now()
// );
// create index if not exists whisper_mod_target_idx
//     on public.whisper_moderation_actions (lower(target_username), created_at desc);
//
// alter table public.whisper_moderation_actions enable row level security;
// drop policy if exists "moderation read" on public.whisper_moderation_actions;
// create policy "moderation read" on public.whisper_moderation_actions
//     for select using (true);
// drop policy if exists "moderation write" on public.whisper_moderation_actions;
// create policy "moderation write" on public.whisper_moderation_actions
//     for insert with check (auth.uid() is not null);

nonisolated enum WhisperModerationScope: String, Codable, Sendable, CaseIterable {
    case post, comment, all

    var label: String {
        switch self {
        case .post:    return "Posting"
        case .comment: return "Commenting"
        case .all:     return "All activity"
        }
    }
}

nonisolated enum WhisperModerationAction: String, Codable, Sendable {
    case mute, ban, unmute, unban
}

nonisolated struct WhisperModerationRecord: Identifiable, Sendable, Codable {
    let id: UUID
    let target_username: String
    let action: WhisperModerationAction
    let scope: WhisperModerationScope
    let reason: String?
    let duration_minutes: Int?
    let expires_at: Date?
    let issued_by_username: String
    let issued_by_role: String
    let created_at: Date
}

/// Tracks active mutes / bans for Whisper. Decisions are cached in-memory and
/// also persisted to Supabase so other devices can enforce them.
@Observable
@MainActor
final class WhisperModerationService {
    static let shared = WhisperModerationService()

    private let client = SupabaseService.shared.client

    /// Lowercased username -> earliest expiry (nil = permanent ban).
    private(set) var activeMutes: [String: Date] = [:]
    private(set) var bannedUsers: Set<String> = []

    private init() {}

    // MARK: - Capability checks

    /// Returns the current viewer's badge (used to decide whether to show
    /// moderation menus on a post / profile).
    func viewerBadge() -> UserBadge {
        let me = (LeaderboardService.shared.savedUsername
                  ?? AuthenticationService.shared.currentUser.username
                  ?? "").lowercased()
        guard !me.isEmpty else { return .none }
        return UserVerificationService.shared.badge(forUsername: me)
    }

    var canMuteAsViewer: Bool { viewerBadge().canMute }
    var canBanAsViewer: Bool  { viewerBadge().canBan  }

    // MARK: - State queries

    func isMuted(_ username: String) -> Bool {
        let key = username.lowercased()
        if let until = activeMutes[key], until > Date() { return true }
        return false
    }

    func isBanned(_ username: String) -> Bool {
        bannedUsers.contains(username.lowercased())
    }

    // MARK: - Actions

    func mute(username: String, duration: WhisperMuteDuration, scope: WhisperModerationScope, reason: String?) async {
        guard canMuteAsViewer else { return }
        let key = username.lowercased()
        let expires = Date().addingTimeInterval(duration.seconds)
        activeMutes[key] = expires
        await record(action: .mute, target: key, scope: scope, reason: reason,
                     durationMinutes: duration.minutes, expiresAt: expires)
    }

    func unmute(username: String) async {
        guard canMuteAsViewer else { return }
        let key = username.lowercased()
        activeMutes.removeValue(forKey: key)
        await record(action: .unmute, target: key, scope: .all, reason: nil,
                     durationMinutes: nil, expiresAt: nil)
    }

    func ban(username: String, reason: String?) async {
        guard canBanAsViewer else { return }
        let key = username.lowercased()
        bannedUsers.insert(key)
        await record(action: .ban, target: key, scope: .all, reason: reason,
                     durationMinutes: nil, expiresAt: nil)
    }

    func unban(username: String) async {
        guard canBanAsViewer else { return }
        let key = username.lowercased()
        bannedUsers.remove(key)
        await record(action: .unban, target: key, scope: .all, reason: nil,
                     durationMinutes: nil, expiresAt: nil)
    }

    // MARK: - Persistence

    nonisolated struct ModerationInsert: Codable, Sendable {
        let target_username: String
        let action: String
        let scope: String
        let reason: String?
        let duration_minutes: Int?
        let expires_at: Date?
        let issued_by_username: String
        let issued_by_role: String
    }

    private func record(action: WhisperModerationAction, target: String, scope: WhisperModerationScope,
                        reason: String?, durationMinutes: Int?, expiresAt: Date?) async {
        let viewer = (LeaderboardService.shared.savedUsername
                      ?? AuthenticationService.shared.currentUser.username
                      ?? "system").lowercased()
        let role = viewerBadge().rawValue
        let row = ModerationInsert(
            target_username: target,
            action: action.rawValue,
            scope: scope.rawValue,
            reason: reason,
            duration_minutes: durationMinutes,
            expires_at: expiresAt,
            issued_by_username: viewer,
            issued_by_role: role
        )
        do {
            try await client.from("whisper_moderation_actions").insert(row).execute()
        } catch {
            // Silent — local enforcement still applies.
        }
    }

    /// Pulls the most recent moderation actions from Supabase and rebuilds
    /// the local mute / ban caches.
    func refresh() async {
        do {
            let rows: [WhisperModerationRecord] = try await client
                .from("whisper_moderation_actions")
                .select()
                .order("created_at", ascending: false)
                .limit(500)
                .execute()
                .value
            var mutes: [String: Date] = [:]
            var bans: Set<String> = []
            // Walk newest-first; first action wins per user.
            var seen: Set<String> = []
            let now = Date()
            for r in rows {
                let key = r.target_username.lowercased()
                if seen.contains(key) { continue }
                seen.insert(key)
                switch r.action {
                case .ban:
                    bans.insert(key)
                case .mute:
                    if let until = r.expires_at, until > now {
                        mutes[key] = until
                    }
                case .unban, .unmute:
                    break
                }
            }
            self.activeMutes = mutes
            self.bannedUsers = bans
        } catch {
            // Silent — moderation is non-critical.
        }
    }
}

nonisolated enum WhisperMuteDuration: String, CaseIterable, Sendable {
    case oneHour, oneDay, threeDays, oneWeek, thirtyDays

    var label: String {
        switch self {
        case .oneHour:   return "1 hour"
        case .oneDay:    return "24 hours"
        case .threeDays: return "3 days"
        case .oneWeek:   return "1 week"
        case .thirtyDays: return "30 days"
        }
    }

    var minutes: Int {
        switch self {
        case .oneHour: return 60
        case .oneDay: return 60 * 24
        case .threeDays: return 60 * 24 * 3
        case .oneWeek: return 60 * 24 * 7
        case .thirtyDays: return 60 * 24 * 30
        }
    }

    var seconds: TimeInterval { TimeInterval(minutes * 60) }
}
