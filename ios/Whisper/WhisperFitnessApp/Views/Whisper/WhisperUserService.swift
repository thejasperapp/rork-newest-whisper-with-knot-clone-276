import Foundation
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.whisper_profiles (
//   user_id uuid primary key references auth.users(id) on delete cascade,
//   username text not null,
//   display_name text,
//   bio text not null default '',
//   interests text[] not null default '{}',
//   profile_image_url text,
//   onboarded_at timestamptz not null default now(),
//   updated_at timestamptz not null default now()
// );
// create index if not exists whisper_profiles_username_idx
//   on public.whisper_profiles (lower(username));
// alter table public.whisper_profiles enable row level security;
// create policy "wprof read all" on public.whisper_profiles for select using (true);
// create policy "wprof upsert own" on public.whisper_profiles
//   for insert with check (auth.uid() = user_id);
// create policy "wprof update own" on public.whisper_profiles
//   for update using (auth.uid() = user_id);
// create policy "wprof delete own" on public.whisper_profiles
//   for delete using (auth.uid() = user_id);

nonisolated struct WhisperUserRow: Codable, Sendable, Identifiable, Hashable {
    let user_id: String
    let username: String
    let display_name: String?
    let bio: String?
    let interests: [String]?
    let profile_image_url: String?
    let onboarded_at: String?
    /// `true` if this user has flipped the Private Account toggle in
    /// settings. Nullable so we can decode rows that predate the column.
    let is_private: Bool?
    /// The creator niche / professional category (account-types.sql) — the
    /// light-gray line under the name on the profile. Defaulted so every
    /// existing memberwise call site keeps compiling; decodes nil when the
    /// column predates the migration.
    var professional_category: String? = nil
    /// The self-selected account type (account-types.sql): "personal" ·
    /// "creator" · "business". Professional (creator/business) accounts get
    /// ANALYTICS — never the verified-only Creator Studio (see
    /// `WhisperAccountAccess`). Defaulted so existing memberwise call sites
    /// keep compiling; decodes nil when the column predates the migration.
    var account_type: String? = nil
    /// Whisper Plus — the Jasper Intelligence pro pack (supabase/whisper-plus.sql).
    /// Decodes nil when the column predates the migration.
    var is_plus: Bool? = nil
    nonisolated var id: String { user_id }

    /// True for self-selected professional accounts (creator or business).
    nonisolated var isProfessionalAccount: Bool {
        let t = (account_type ?? "").lowercased()
        return t == "creator" || t == "business"
    }
}

nonisolated struct WhisperUserUpsert: Codable, Sendable {
    let user_id: String
    let username: String
    let display_name: String?
    let bio: String
    let interests: [String]
    let profile_image_url: String?
    let is_private: Bool?
}

nonisolated struct WhisperPrivacyUpdate: Encodable, Sendable {
    let is_private: Bool
    let updated_at: String
}

/// Tracks which Whisper users have actually signed up for Whisper. Powers
/// the Explore search (so we only surface real Whisper accounts, not every
/// Whisper user) and the follow graph.
@MainActor
@Observable
final class WhisperUserService {
    static let shared = WhisperUserService()

    private let client = SupabaseService.shared.client
    /// Per-account key so signing into a different user on the same device
    /// can never inherit a previous account's onboarded=true value.
    private var onboardedKey: String { "whisper.onboarded.v1.\(AccountStorage.currentUserID)" }

    /// True once the local user has completed Whisper onboarding (bio, etc.).
    var hasOnboarded: Bool
    var me: WhisperUserRow?
    private var cachedDisplayProfile: WhisperProfileDisplay?
    /// Display fallback only; all access checks continue to use the live `me` row.
    var displayProfile: WhisperProfileDisplay? { me.map(WhisperProfileDisplay.init) ?? cachedDisplayProfile }
    var lastError: String?
    /// Becomes true only after `refreshMe()` has resolved against the
    /// remote profile table at least once for the current account. The
    /// root gate uses this to avoid flashing the onboarding sheet while
    /// the profile row is still being fetched right after sign-in.
    var didLoadFromServer: Bool = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration: UUID?
    private var lastIdentityRefresh: Date?

    /// In-memory cache of recent search results, keyed by lowercased query.
    var lastResults: [WhisperUserRow] = []
    var isSearching: Bool = false
    var searchError: String?
    @ObservationIgnored private var searchOperation: UUID = UUID()

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    private init() {
        hasOnboarded = UserDefaults.standard.bool(forKey: "whisper.onboarded.v1.\(AccountStorage.currentUserID)")
    }

    /// Re-reads `hasOnboarded` from UserDefaults using the currently-active
    /// AccountStorage UID. Call after `activateAccount(_:)` switches users so
    /// the gate reflects the new account's flag instead of the previous one.
    func rehydrateForCurrentAccount() {
        hasOnboarded = UserDefaults.standard.bool(forKey: onboardedKey)
        me = nil; cachedDisplayProfile = nil
        didLoadFromServer = false
        lastError = nil; lastResults = []; isSearching = false
        refreshTask?.cancel(); refreshTask = nil; refreshGeneration = nil; lastIdentityRefresh = nil
    }

    // MARK: - Self

    /// Fetches the local user's whisper profile (if any). Updates
    /// `hasOnboarded` so the gate stays in sync across devices.
    func refreshMeIfStale(maxAge: TimeInterval = 30) async {
        if refreshGeneration == AccountStorage.generation, didLoadFromServer,
           let lastIdentityRefresh, Date().timeIntervalSince(lastIdentityRefresh) < maxAge { return }
        await refreshMe()
    }

    func refreshMe() async {
        let generation = AccountStorage.generation
        if let refreshTask, refreshGeneration == generation { await refreshTask.value; return }
        let task = Task { await self.loadMe(generation: generation) }
        refreshTask = task; refreshGeneration = generation
        await task.value
        if refreshTask == task { refreshTask = nil }
    }

    private func loadMe(generation: UUID) async {
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        guard isRemote else {
            me = nil
            didLoadFromServer = true
            return
        }
        let owner = currentUID
        if me == nil {
            let cached = await WhisperDisplayCache.load(WhisperProfileDisplay.self, key: WhisperDisplayCache.profileKey)
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            if cached?.user_id.lowercased() == owner.lowercased() { cachedDisplayProfile = cached }
        }
        do {
            let rows: [WhisperUserRow] = try await client
                .from("whisper_profiles")
                .select()
                .eq("user_id", value: owner)
                .limit(1)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            lastError = nil
            lastIdentityRefresh = Date()
            didLoadFromServer = true
            if let row = rows.first {
                me = row
                cachedDisplayProfile = nil
                if !hasOnboarded {
                    hasOnboarded = true
                    UserDefaults.standard.set(true, forKey: onboardedKey)
                }
                await WhisperDisplayCache.save(WhisperProfileDisplay(row), key: WhisperDisplayCache.profileKey,
                    owner: owner, generation: generation)
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                // Self-heal: if this account's row was previously upserted
                // with the literal "you" / "user" placeholder (legacy race
                // during onboarding), or with an empty handle, repair it
                // once a real handle is available.
                let stored = row.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if stored.isEmpty || stored == "you" || stored == "user" {
                    await repairLegacyYouUsername()
                }
            } else {
                // No whisper_profiles row for this account — they have not
                // completed Whisper onboarding (e.g. brand-new sign-up). Force
                // the gate to surface the walkthrough regardless of whatever
                // value the in-memory flag held from a previous account.
                me = nil; cachedDisplayProfile = nil
                WhisperDisplayCache.invalidate(key: WhisperDisplayCache.profileKey)
                if hasOnboarded {
                    hasOnboarded = false
                    UserDefaults.standard.removeObject(forKey: onboardedKey)
                }
            }
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            lastError = "Your profile couldn't load. Check your connection and try again."
        }
    }

    @discardableResult
    func completeOnboarding(
        bio: String,
        interests: [String]
    ) async -> Bool {
        guard isRemote else { return false }
        // Make sure the user's chosen handle is in hand BEFORE we upsert
        // the whisper_profiles row. Without this the row would persist
        // "you" as the username and the profile would show @you forever.
        let hydrated = await LeaderboardService.shared.hydrateUsernameFromSupabase()
        // Refuse to persist the literal "you" placeholder — once written,
        // it would shadow the real handle forever in posts/comments/feeds.
        let resolved: String? = [
            LeaderboardService.shared.savedUsername,
            hydrated,
            AuthenticationService.shared.currentUser.username
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty && $0.lowercased() != "you" })
        guard let username = resolved else {
            print("[Whisper] completeOnboarding: no real username yet, aborting upsert")
            lastError = "Pick a username before continuing."
            return false
        }
        let displayName = AuthenticationService.shared.currentUser.displayName
        let avatar = AuthenticationService.shared.currentUser.profileImageURL

        let payload = WhisperUserUpsert(
            user_id: currentUID,
            username: username,
            display_name: displayName,
            bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
            interests: interests,
            profile_image_url: avatar,
            is_private: me?.is_private
        )
        do {
            try await client
                .from("whisper_profiles")
                .upsert(payload, onConflict: "user_id")
                .execute()
            hasOnboarded = true
            UserDefaults.standard.set(true, forKey: onboardedKey)
            Analytics.record("onboarding_completed", ["interests": String(interests.count)])
            await refreshMe()
            // Whisper signup IS a Whisper signup — mirror any existing local
            // Whisper blobs (workouts, nutrition, achievements, programs…) up
            // to public.user_data so this user is fully bootstrapped on the
            // Whisper backend too. Safe no-op if there's nothing local yet.
            await SupabaseSyncService.shared.pushAll(userID: currentUID)
            await SupabaseSyncService.shared.pullAll(userID: currentUID)
            return true
        } catch {
            lastError = error.localizedDescription
            // Still mark locally so the user isn't blocked if RLS or table
            // is missing — they can re-run onboarding from settings later.
            hasOnboarded = true
            UserDefaults.standard.set(true, forKey: onboardedKey)
            return false
        }
    }

    /// Updates this user's `whisper_profiles` row in place. Only the bio is
    /// strictly required — display name / avatar fall through to the existing
    /// `AuthenticationService.currentUser` values if not provided. Returns
    /// `true` on success.
    @discardableResult
    func updateProfile(
        bio: String,
        displayName: String? = nil,
        avatarURL: String? = nil
    ) async -> Bool {
        guard isRemote else { return false }
        let owner = currentUID; let epoch = AccountStorage.generation
        if me == nil { await refreshMe() }
        guard epoch == AccountStorage.generation, owner == currentUID, !Task.isCancelled, me?.user_id.lowercased() == owner.lowercased() else { return false }
        // Patch only the edited fields; username, interests and privacy have independent save paths.
        nonisolated struct ProfilePatch: Encodable {
            let display_name: String?
            let bio: String
            let profile_image_url: String?
        }
        nonisolated struct SavedProfile: Decodable { let user_id: String }
        let resolvedAvatar = avatarURL ?? AuthenticationService.shared.currentUser.profileImageURL
        let resolvedName = displayName ?? AuthenticationService.shared.currentUser.displayName
        let payload = ProfilePatch(
            display_name: resolvedName,
            bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
            profile_image_url: resolvedAvatar
        )
        do {
            try WhisperChatMediaService.checkAccount(owner, generation: epoch)
            let saved: [SavedProfile] = try await client
                .from("whisper_profiles")
                .update(payload)
                .eq("user_id", value: owner)
                .select("user_id")
                .execute().value
            guard epoch == AccountStorage.generation, owner == currentUID, !Task.isCancelled,
                  saved.contains(where: { $0.user_id.lowercased() == owner.lowercased() }) else { return false }
            await refreshMe()
            return epoch == AccountStorage.generation && owner == currentUID && !Task.isCancelled
        } catch {
            guard epoch == AccountStorage.generation, owner == currentUID else { return false }
            lastError = "Couldn't save your profile. Please try again."
            return false
        }
    }

    /// Updates the user's `interests` array in-place. Used by the
    /// Communities Join/Leave button so toggling a community persists
    /// across launches and feeds into the personalized feed score.
    /// Returns `true` on success.
    @discardableResult
    func updateInterests(_ interests: [String]) async -> Bool {
        guard isRemote else { return false }
        let owner = currentUID; let epoch = AccountStorage.generation
        // Local optimistic update so the UI reflects the change immediately.
        let current = me
        if let cur = current {
            me = WhisperUserRow(
                user_id: cur.user_id,
                username: cur.username,
                display_name: cur.display_name,
                bio: cur.bio,
                interests: interests,
                profile_image_url: cur.profile_image_url,
                onboarded_at: cur.onboarded_at,
                is_private: cur.is_private,
                professional_category: cur.professional_category,
                account_type: cur.account_type,
                is_plus: cur.is_plus
            )
        }
        do {
            struct InterestsPatch: Encodable { let interests: [String] }
            try await client
                .from("whisper_profiles")
                .update(InterestsPatch(interests: interests))
                .eq("user_id", value: owner)
                .execute()
            guard epoch == AccountStorage.generation, owner == currentUID, !Task.isCancelled else { return false }
            await refreshMe()
            return epoch == AccountStorage.generation && owner == currentUID && !Task.isCancelled
        } catch {
            guard epoch == AccountStorage.generation, owner == currentUID else { return false }
            // Roll back the optimistic edit on failure.
            me = current
            lastError = error.localizedDescription
            return false
        }
    }

    /// Detects the legacy "@you" username on the current user's row and
    /// rewrites it with the real handle (from Leaderboard / Auth) so the
    /// rest of the app stops showing them as @you. Silent no-op when no
    /// better handle is available yet.
    private func repairLegacyYouUsername() async {
        let hydrated = await LeaderboardService.shared.hydrateUsernameFromSupabase()
        let candidates: [String?] = [
            LeaderboardService.shared.savedUsername,
            hydrated,
            AuthenticationService.shared.currentUser.username
        ]
        let realUsername = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && $0.lowercased() != "you" })
        guard let realUsername else { return }
        do {
            struct UsernamePatch: Encodable { let username: String }
            try await client
                .from("whisper_profiles")
                .update(UsernamePatch(username: realUsername))
                .eq("user_id", value: currentUID)
                .execute()
            print("[Whisper] repaired legacy @you username -> @\(realUsername)")
            // Re-fetch so the local cache reflects the rewrite.
            await refreshMe()
        } catch {
            print("[Whisper] repairLegacyYouUsername failed: \(error)")
        }
    }

    /// Persist the Private Account flag to the user's `whisper_profiles`
    /// row so other clients see the same value. Updates the cached `me`
    /// row on success.
    @discardableResult
    func setIsPrivate(_ value: Bool) async -> Bool {
        guard isRemote else { return false }
        let iso = ISO8601DateFormatter().string(from: Date())
        let payload = WhisperPrivacyUpdate(is_private: value, updated_at: iso)
        let account = currentUID
        let generation = AccountStorage.generation
        do {
            try Task.checkCancellation()
            try await client
                .from("whisper_profiles")
                .update(payload)
                .eq("user_id", value: account)
                .execute()
            guard generation == AccountStorage.generation, account == currentUID, !Task.isCancelled else { return false }
            await refreshMe()
            return generation == AccountStorage.generation && account == currentUID
        } catch {
            guard generation == AccountStorage.generation, account == currentUID else { return false }
            lastError = "Privacy wasn’t updated. Please try again."
            print("[Whisper] privacy update failed")
            return false
        }
    }

    /// Fetch a target user's privacy state without mutating local cache.
    /// Used by the follow flow to decide whether to insert directly or to
    /// route through `WhisperFollowRequestService`.
    func isPrivate(userID: String) async -> Bool {
        guard isRemote else { return false }
        do {
            let rows: [WhisperUserRow] = try await client
                .from("whisper_profiles")
                .select()
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value
            return rows.first?.is_private ?? false
        } catch {
            return false
        }
    }

    func resetOnboardingLocally() {
        hasOnboarded = false
        UserDefaults.standard.removeObject(forKey: onboardedKey)
        me = nil; cachedDisplayProfile = nil
        didLoadFromServer = false
    }

    // MARK: - Search & suggestions

    /// Looks up a single Whisper profile by username (case-insensitive).
    /// Returns nil if the user hasn't completed Whisper onboarding.
    func fetchByUsername(_ username: String) async -> WhisperUserRow? {
        let q = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty, isRemote else { return nil }
        do {
            let rows: [WhisperUserRow] = try await client
                .from("whisper_profiles")
                .select()
                .ilike("username", pattern: q)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            return nil
        }
    }

    /// Stable-ID hydration keeps old mentions and shared profiles valid after a rename.
    func fetchByUserID(_ userID: String) async -> WhisperUserRow? {
        guard isRemote, UUID(uuidString: userID) != nil else { return nil }
        let generation = AccountStorage.generation
        do {
            let rows: [WhisperUserRow] = try await client.from("whisper_profiles").select()
                .eq("user_id", value: userID).limit(1).execute().value
            guard !Task.isCancelled, generation == AccountStorage.generation else { return nil }
            return rows.first
        } catch { return nil }
    }

    /// Searches Whisper users by username (case-insensitive prefix +
    /// substring). Excludes the current user.
    func search(_ query: String, limit: Int = 30) async -> [WhisperUserRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isRemote else { return [] }
        let generation = AccountStorage.generation
        let operation = UUID(); searchOperation = operation
        isSearching = true; searchError = nil
        defer { if operation == searchOperation { isSearching = false } }
        do {
            // Match usernames AND display names (web parity). Inside a
            // PostgREST `or=` group the wildcard is `*`; strip separator
            // characters that would break the filter syntax.
            let safe = q
                .replacingOccurrences(of: ",", with: " ")
                .replacingOccurrences(of: "(", with: " ")
                .replacingOccurrences(of: ")", with: " ")
                .trimmingCharacters(in: .whitespaces)
            let pattern = safe.isEmpty ? "*" : "*\(safe)*"
            let rows: [WhisperUserRow] = try await client
                .from("whisper_profiles")
                .select()
                .or("username.ilike.\(pattern),display_name.ilike.\(pattern)")
                .neq("user_id", value: currentUID)
                .order("onboarded_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation else { return [] }
            if operation == searchOperation { lastResults = rows }
            return rows
        } catch {
            if !Task.isCancelled, generation == AccountStorage.generation, operation == searchOperation {
                searchError = "Check your connection, then change your search to try again."
            }
            return []
        }
    }

    /// Independent composer search; never changes Explore's results or loading state.
    func mentionSuggestions(_ query: String, limit: Int = 12, matchingNames: Bool = false) async throws -> [WhisperUserRow] {
        guard isRemote else { return [] }
        let generation = AccountStorage.generation
        let safe = String(query.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || (matchingNames && ($0 == " " || $0 == "-" || $0 == "'")) }.prefix(60))
        guard !safe.isEmpty else { return [] }
        let rows: [WhisperUserRow] = try await client.from("whisper_profiles").select()
            .or("username.ilike.*\(safe)*,display_name.ilike.*\(safe)*")
            .neq("user_id", value: currentUID).limit(limit).execute().value
        try Task.checkCancellation()
        guard generation == AccountStorage.generation else { throw CancellationError() }
        return rows
    }

    /// Suggested whisper users for onboarding / discover. Picks the most
    /// recently-onboarded users (excluding self), then re-ranks the pool by
    /// shared interests with the local user so the list feels personal
    /// instead of just chronological.
    func suggestions(limit: Int = 12) async -> [WhisperUserRow] {
        guard isRemote else { return [] }
        do {
            // Pull a wider pool so we have enough headroom to re-rank.
            let rows: [WhisperUserRow] = try await client
                .from("whisper_profiles")
                .select()
                .neq("user_id", value: currentUID)
                .order("onboarded_at", ascending: false)
                .limit(max(limit, 40))
                .execute()
                .value
            let mine = Set((me?.interests ?? []).map { $0.lowercased() })
            if mine.isEmpty { return Array(rows.prefix(limit)) }
            // Score = shared interests; stable tiebreak by onboarded_at desc.
            let scored = rows.enumerated().map { idx, row -> (WhisperUserRow, Int, Int) in
                let theirs = Set((row.interests ?? []).map { $0.lowercased() })
                return (row, mine.intersection(theirs).count, idx)
            }
            let ranked = scored.sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.2 < $1.2
            }
            return Array(ranked.prefix(limit).map { $0.0 })
        } catch {
            return []
        }
    }
}

// MARK: - SQL block to paste in Supabase
/*
create table if not exists public.whisper_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  display_name text,
  bio text not null default '',
  interests text[] not null default '{}',
  profile_image_url text,
  onboarded_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists whisper_profiles_username_idx
  on public.whisper_profiles (lower(username));
alter table public.whisper_profiles enable row level security;
drop policy if exists "wprof read all" on public.whisper_profiles;
create policy "wprof read all" on public.whisper_profiles for select using (true);
drop policy if exists "wprof upsert own" on public.whisper_profiles;
create policy "wprof upsert own" on public.whisper_profiles
  for insert with check (auth.uid() = user_id);
drop policy if exists "wprof update own" on public.whisper_profiles;
create policy "wprof update own" on public.whisper_profiles
  for update using (auth.uid() = user_id);
drop policy if exists "wprof delete own" on public.whisper_profiles;
create policy "wprof delete own" on public.whisper_profiles
  for delete using (auth.uid() = user_id);
notify pgrst, 'reload schema';
*/
