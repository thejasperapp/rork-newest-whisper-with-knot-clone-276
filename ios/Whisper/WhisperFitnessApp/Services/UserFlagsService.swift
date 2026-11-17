import Foundation
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.user_flags (
//   user_id uuid not null references auth.users(id) on delete cascade,
//   flag_key text not null,
//   flag_value boolean not null default false,
//   updated_at timestamptz not null default now(),
//   primary key (user_id, flag_key)
// );
// alter table public.user_flags enable row level security;
// create policy "user_flags owner read"   on public.user_flags for select using  (auth.uid() = user_id);
// create policy "user_flags owner insert" on public.user_flags for insert with check (auth.uid() = user_id);
// create policy "user_flags owner update" on public.user_flags for update using  (auth.uid() = user_id);
// create policy "user_flags owner delete" on public.user_flags for delete using  (auth.uid() = user_id);

nonisolated struct UserFlagRow: Codable, Sendable {
    let user_id: String
    let flag_key: String
    let flag_value: Bool
    let updated_at: String?
}

/// Per-user boolean flags that sync across devices via Supabase.
/// Local cache lives in `AccountStorage` so reads are instant; we hydrate from
/// Supabase on sign-in and write through on changes.
@Observable
@MainActor
final class UserFlagsService {
    static let shared = UserFlagsService()

    private let client = SupabaseService.shared.client
    private(set) var hydratedOnce: Bool = false

    private init() {}

    /// Read a flag synchronously from local storage (fast path).
    func bool(_ key: String) -> Bool {
        AccountStorage.bool(forKey: key)
    }

    /// Write through: update local immediately, then sync to Supabase.
    func setBool(_ value: Bool, forKey key: String) {
        AccountStorage.set(value, forKey: key)
        Task { await pushFlag(key: key, value: value) }
    }

    /// Pull all flags for the current user. Newer cloud values overwrite local.
    func hydrate() async {
        let generation = AccountStorage.generation
        let uid = AccountStorage.currentUserID
        guard isRemoteUser(uid) else { return }
        do {
            let rows: [UserFlagRow] = try await client
                .from("user_flags")
                .select("user_id,flag_key,flag_value,updated_at")
                .eq("user_id", value: uid)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            for row in rows {
                AccountStorage.set(row.flag_value, forKey: row.flag_key)
            }
            hydratedOnce = true
        } catch {
            // silent — flags are non-critical
        }
    }

    private func pushFlag(key: String, value: Bool) async {
        let uid = AccountStorage.currentUserID
        guard isRemoteUser(uid) else { return }
        let row = UserFlagRow(
            user_id: uid,
            flag_key: key,
            flag_value: value,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await client
                .from("user_flags")
                .upsert(row, onConflict: "user_id,flag_key")
                .execute()
        } catch {
            // silent
        }
    }

    private func isRemoteUser(_ userID: String) -> Bool {
        userID != "guest" && !userID.hasPrefix("local_")
    }
}

extension UserFlagsService {
    // Centralized flag keys for discoverability.
    static let firstDelightResearch = "firstdelight_research_v1"
    static let firstDelightMeal     = "firstdelight_meal_v1"
    static let firstDelightWorkout  = "firstdelight_workout_v1"
    static let firstDelightSeen     = "hasSeenFirstDelight"

    // Beach Bonanza event flags — mirrored across devices so the join /
    // popup-dismissal state follows the user.
    static let beachBonanzaJoined           = "summerEvent_joined"
    static let beachBonanzaPopupDismissed   = "summerEvent_dismissedPopup"

    static func emberBriefingDismissed(version: String) -> String {
        "ember_briefingDismissed_\(version)"
    }
}
