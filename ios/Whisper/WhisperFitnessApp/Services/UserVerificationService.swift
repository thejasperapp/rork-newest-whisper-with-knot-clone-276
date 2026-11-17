import Foundation
import SwiftUI
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// -- Extend the existing usernames reservation table so the badge data lives
// -- right next to the username it belongs to. All columns default to false
// -- and are flipped manually from the Supabase dashboard.
// alter table public.usernames
//   add column if not exists is_verified  boolean not null default false,
//   add column if not exists is_moderator boolean not null default false,
//   add column if not exists is_admin     boolean not null default false,
//   add column if not exists is_owner     boolean not null default false;
// alter table public.profiles
//   add column if not exists is_admin     boolean not null default false,
//   add column if not exists is_owner     boolean not null default false;
//
// -- Anyone can read badges so the leaderboard / friends list can show them.
// drop policy if exists "usernames read all" on public.usernames;
// create policy "usernames read all" on public.usernames
//   for select using (true);
//
// -- Quick lookup index for badge fetches by username.
// create index if not exists usernames_lower_idx
//   on public.usernames (lower(username));

nonisolated enum UserBadge: String, Sendable, Codable {
    case none
    case verified   // blue checkmark — handed out by you to trusted users
    case moderator  // silver checkmark — community moderators (mute powers)
    case admin      // gold checkmark — admins (mute + ban powers)
    case owner      // gradient checkmark — app owner / founder

    var color: Color {
        switch self {
        case .none:      return .clear
        case .verified:  return Color(red: 0.13, green: 0.55, blue: 0.96) // Twitter-style blue
        case .moderator: return Color(red: 0.78, green: 0.80, blue: 0.84) // brushed silver
        case .admin:     return Color(red: 1.00, green: 0.78, blue: 0.13) // rich gold
        case .owner:     return Color(red: 0.953, green: 0.565, blue: 0.341) // fallback ember orange
        }
    }

    /// Linear gradient used by the owner badge. Other badges return a flat
    /// gradient of `color` so callers can render uniformly.
    var gradient: LinearGradient {
        switch self {
        case .owner:
            return LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.78, blue: 0.30), // gold
                    Color(red: 0.97, green: 0.45, blue: 0.30), // ember
                    Color(red: 0.85, green: 0.25, blue: 0.55), // magenta
                    Color(red: 0.45, green: 0.35, blue: 0.95)  // indigo
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(colors: [color, color], startPoint: .top, endPoint: .bottom)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .none:      return ""
        case .verified:  return "Verified user"
        case .moderator: return "Moderator"
        case .admin:     return "Admin"
        case .owner:     return "Owner"
        }
    }

    /// Higher = more prestigious. Used to break ties when a user has multiple
    /// flags set on the same row.
    var rank: Int {
        switch self {
        case .none: return 0
        case .verified: return 1
        case .moderator: return 2
        case .admin: return 3
        case .owner: return 4
        }
    }

    /// Can mute users (silence comments/posts for a duration).
    var canMute: Bool {
        switch self {
        case .moderator, .admin, .owner: return true
        default: return false
        }
    }

    /// Can permanently ban users.
    var canBan: Bool {
        switch self {
        case .admin, .owner: return true
        default: return false
        }
    }

    /// Algorithm boost — verified, moderator, admin and owner profiles get
    /// surfaced more often in Discover and the main feed.
    var algorithmBoost: Double {
        switch self {
        case .none:      return 1.0
        case .verified:  return 1.6
        case .moderator: return 1.8
        case .admin:     return 2.0
        case .owner:     return 2.4
        }
    }
}

nonisolated struct UserBadgeRow: Codable, Sendable {
    let username: String
    let user_id: String?
    let is_verified: Bool?
    let is_moderator: Bool?
    let is_admin: Bool?
    let is_owner: Bool?

    var badge: UserBadge {
        if is_owner     == true { return .owner     }
        if is_admin     == true { return .admin     }
        if is_moderator == true { return .moderator }
        if is_verified  == true { return .verified  }
        return .none
    }
}

/// Caches verified / moderator badges so leaderboard + friends rows can show
/// the blue / gold checkmark next to a username without hammering Supabase.
@Observable
@MainActor
final class UserVerificationService {
    static let shared = UserVerificationService()

    private let client = SupabaseService.shared.client

    /// Lowercased username -> badge.
    private(set) var badgesByUsername: [String: UserBadge] = [:]
    private var inFlight: Set<String> = []

    private init() {}

    func badge(forUsername raw: String) -> UserBadge {
        badgesByUsername[raw.lowercased()] ?? .none
    }

    /// Seeds the cache with an authoritative badge (e.g. from the unified
    /// account-status read) so gates depending on `badge(forUsername:)`
    /// resolve instantly without a per-username round trip.
    func seed(username: String, badge: UserBadge) {
        let key = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        badgesByUsername[key] = badge
    }

    /// Prefetches badges for a batch of usernames. Safe to call repeatedly —
    /// already-cached usernames are skipped.
    func preload(usernames: [String]) async {
        let normalized = Set(usernames
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && badgesByUsername[$0] == nil && !inFlight.contains($0) })
        guard !normalized.isEmpty else { return }
        inFlight.formUnion(normalized)
        defer { inFlight.subtract(normalized) }

        let list = Array(normalized)
        var updated = badgesByUsername
        // Primary source: `profiles` row (now carries username + badge flags).
        do {
            nonisolated struct ProfileBadgeRow: Codable, Sendable {
                let username: String?
                let is_verified: Bool?
                let is_moderator: Bool?
                let is_admin: Bool?
                let is_owner: Bool?
                var badge: UserBadge {
                    if is_owner     == true { return .owner     }
                    if is_admin     == true { return .admin     }
                    if is_moderator == true { return .moderator }
                    if is_verified  == true { return .verified  }
                    return .none
                }
            }
            let profileRows: [ProfileBadgeRow] = try await client
                .from("whisper_profiles")
                .select("username,is_verified,is_moderator,is_admin,is_owner")
                .in("username", values: list)
                .execute()
                .value
            for row in profileRows {
                guard let name = row.username?.lowercased(), !name.isEmpty else { continue }
                updated[name] = row.badge
            }
        } catch {
            // Silent — fall through to the legacy `usernames` table.
        }
        // Secondary: legacy badges still on the `usernames` reservation table.
        do {
            let rows: [UserBadgeRow] = try await client
                .from("usernames")
                .select("username,user_id,is_verified,is_moderator,is_admin,is_owner")
                .in("username", values: list)
                .execute()
                .value
            for row in rows {
                let key = row.username.lowercased()
                let existing = updated[key] ?? .none
                // Take whichever badge has the higher rank so a profile row
                // can't accidentally downgrade an owner mark stored on the
                // usernames table (or vice-versa).
                if row.badge.rank > existing.rank {
                    updated[key] = row.badge
                }
            }
        } catch {
            // Silent — badges are non-critical.
        }
        for name in normalized where updated[name] == nil {
            updated[name] = .none
        }
        badgesByUsername = updated
    }

    /// Re-fetch the badge for a single username (e.g. after granting verification
    /// from the Supabase dashboard and pulling-to-refresh).
    func refresh(username: String) async {
        let key = username.lowercased()
        badgesByUsername.removeValue(forKey: key)
        await preload(usernames: [key])
    }
}
