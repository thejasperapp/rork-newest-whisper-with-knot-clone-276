import Foundation
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.friend_requests (
//   id uuid primary key default gen_random_uuid(),
//   from_user_id uuid not null references auth.users(id) on delete cascade,
//   from_username text not null,
//   to_user_id   uuid not null references auth.users(id) on delete cascade,
//   to_username  text not null,
//   status text not null default 'pending'
//     check (status in ('pending','accepted','denied','cancelled')),
//   created_at   timestamptz not null default now(),
//   responded_at timestamptz,
//   unique (from_user_id, to_user_id)
// );
// create index if not exists friend_requests_to_idx
//   on public.friend_requests (to_user_id, status);
// create index if not exists friend_requests_from_idx
//   on public.friend_requests (from_user_id, status);
// alter table public.friend_requests enable row level security;
// create policy "fr read involved" on public.friend_requests
//   for select using (auth.uid() = from_user_id or auth.uid() = to_user_id);
// create policy "fr insert sender" on public.friend_requests
//   for insert with check (auth.uid() = from_user_id);
// create policy "fr update recipient" on public.friend_requests
//   for update using (auth.uid() = to_user_id or auth.uid() = from_user_id);
// create policy "fr delete involved" on public.friend_requests
//   for delete using (auth.uid() = from_user_id or auth.uid() = to_user_id);
//
// create table if not exists public.friendships (
//   user_id        uuid not null references auth.users(id) on delete cascade,
//   friend_user_id uuid not null references auth.users(id) on delete cascade,
//   friend_username text not null,
//   created_at     timestamptz not null default now(),
//   primary key (user_id, friend_user_id)
// );
// alter table public.friendships enable row level security;
// create policy "fs read owner"   on public.friendships for select using (auth.uid() = user_id);
// create policy "fs insert owner" on public.friendships for insert with check (auth.uid() = user_id);
// create policy "fs delete owner" on public.friendships for delete using (auth.uid() = user_id);

nonisolated struct FriendRequestRow: Codable, Sendable, Identifiable {
    let id: String
    let from_user_id: String
    let from_username: String
    let to_user_id: String
    let to_username: String
    let status: String
    let created_at: String?
    let responded_at: String?
}

nonisolated struct FriendshipRow: Codable, Sendable, Identifiable {
    let user_id: String
    let friend_user_id: String
    let friend_username: String
    let created_at: String?

    nonisolated var id: String { "\(user_id)_\(friend_user_id)" }
}

nonisolated struct FriendRequestInsert: Codable, Sendable {
    let from_user_id: String
    let from_username: String
    let to_user_id: String
    let to_username: String
    let status: String
}

nonisolated struct FriendshipInsert: Codable, Sendable {
    let user_id: String
    let friend_user_id: String
    let friend_username: String
}

nonisolated struct FriendRequestStatusUpdate: Encodable, Sendable {
    let status: String
    let responded_at: String
}

enum FriendRequestResult: Equatable {
    case sent
    case alreadyFriends
    case alreadyPending
    case userNotFound
    case cannotFriendSelf
    case notSignedIn
    case error(String)
}

/// Supabase-backed friend requests + accepted friendships.
/// Friend additions now require a confirm/deny step rather than a free-for-all.
@Observable
@MainActor
final class FriendRequestsService {
    static let shared = FriendRequestsService()

    private let client = SupabaseService.shared.client

    var incoming: [FriendRequestRow] = []
    var outgoing: [FriendRequestRow] = []
    var friendships: [FriendshipRow] = []
    var isLoading: Bool = false
    var lastError: String?

    private init() {}

    private var currentUID: String { AccountStorage.currentUserID }

    private var isRemote: Bool {
        currentUID != "guest" && !currentUID.hasPrefix("local_")
    }

    // MARK: - Username lookup

    /// Resolves `username` -> user_id via the `usernames` reservation table.
    /// Returns nil if no one owns that username.
    func resolveUsername(_ rawUsername: String) async -> UsernameReservationRow? {
        let normalized = rawUsername
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }
        do {
            let rows: [UsernameReservationRow] = try await client
                .from("usernames")
                .select("username,user_id")
                .ilike("username", pattern: normalized)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            return nil
        }
    }

    // MARK: - Sending requests

    func sendRequest(toUsername rawUsername: String) async -> FriendRequestResult {
        guard isRemote else { return .notSignedIn }
        let mineUsername = LeaderboardService.shared.savedUsername?.lowercased() ?? ""
        let typed = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !typed.isEmpty else { return .userNotFound }
        if typed == mineUsername { return .cannotFriendSelf }

        // 1. Verify the username actually exists.
        guard let target = await resolveUsername(typed) else {
            return .userNotFound
        }
        if target.user_id == currentUID { return .cannotFriendSelf }

        // 2. Already friends?
        if friendships.contains(where: { $0.friend_user_id == target.user_id }) {
            return .alreadyFriends
        }

        // 3. Already a pending request?
        if outgoing.contains(where: { $0.to_user_id == target.user_id && $0.status == "pending" }) {
            return .alreadyPending
        }

        // 4. If THEY already requested US, auto-accept their request.
        if let incomingMatch = incoming.first(where: { $0.from_user_id == target.user_id && $0.status == "pending" }) {
            await accept(incomingMatch)
            return .sent
        }

        let payload = FriendRequestInsert(
            from_user_id: currentUID,
            from_username: mineUsername,
            to_user_id: target.user_id,
            to_username: target.username,
            status: "pending"
        )
        do {
            try await client
                .from("friend_requests")
                .upsert(payload, onConflict: "from_user_id,to_user_id")
                .execute()
            await refresh()
            return .sent
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Responding to requests

    func accept(_ request: FriendRequestRow) async {
        guard isRemote, request.to_user_id == currentUID else { return }

        // Optimistically remove from the incoming list so the row disappears
        // immediately even if Supabase is slow / momentarily offline.
        incoming.removeAll { $0.id == request.id }

        let update = FriendRequestStatusUpdate(
            status: "accepted",
            responded_at: ISO8601DateFormatter().string(from: Date())
        )
        do {
            // Mark request accepted. RLS allows the recipient (to_user_id) to
            // update their own incoming request.
            try await client
                .from("friend_requests")
                .update(update)
                .eq("id", value: request.id)
                .execute()
        } catch {
            lastError = "Couldn't accept that request: \(error.localizedDescription)"
            // Roll back the optimistic UI on hard failure.
            await refresh()
            return
        }

        // Write OUR friendship row. The sender's matching row is created the
        // next time their client refreshes via `reconcileAcceptedSenderSide()`.
        let mine = FriendshipInsert(
            user_id: currentUID,
            friend_user_id: request.from_user_id,
            friend_username: request.from_username
        )
        do {
            try await client
                .from("friendships")
                .upsert(mine, onConflict: "user_id,friend_user_id")
                .execute()
        } catch {
            lastError = "Friendship saved partially: \(error.localizedDescription)"
        }

        // Best-effort: also write the sender's mirror row. RLS may reject this
        // depending on the policy setup — that's fine, the sender's own client
        // will reconcile it on their next refresh.
        let theirs = FriendshipInsert(
            user_id: request.from_user_id,
            friend_user_id: currentUID,
            friend_username: request.to_username
        )
        try? await client
            .from("friendships")
            .upsert(theirs, onConflict: "user_id,friend_user_id")
            .execute()

        await refresh()
    }

    func deny(_ request: FriendRequestRow) async {
        guard isRemote, request.to_user_id == currentUID else { return }
        incoming.removeAll { $0.id == request.id }
        let update = FriendRequestStatusUpdate(
            status: "denied",
            responded_at: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await client
                .from("friend_requests")
                .update(update)
                .eq("id", value: request.id)
                .execute()
            await refresh()
        } catch {
            lastError = error.localizedDescription
            await refresh()
        }
    }

    func cancelOutgoing(_ request: FriendRequestRow) async {
        guard isRemote, request.from_user_id == currentUID else { return }
        do {
            try await client
                .from("friend_requests")
                .delete()
                .eq("id", value: request.id)
                .execute()
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func removeFriend(_ friend: FriendshipRow) async {
        guard isRemote else { return }
        do {
            try await client
                .from("friendships")
                .delete()
                .eq("user_id", value: currentUID)
                .eq("friend_user_id", value: friend.friend_user_id)
                .execute()
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Refresh

    func refresh() async {
        guard isRemote else {
            incoming = []
            outgoing = []
            friendships = []
            return
        }
        isLoading = true
        defer { isLoading = false }

        async let inc: [FriendRequestRow] = (try? await client
            .from("friend_requests")
            .select()
            .eq("to_user_id", value: currentUID)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value) ?? []

        async let out: [FriendRequestRow] = (try? await client
            .from("friend_requests")
            .select()
            .eq("from_user_id", value: currentUID)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value) ?? []

        async let fr: [FriendshipRow] = (try? await client
            .from("friendships")
            .select()
            .eq("user_id", value: currentUID)
            .order("created_at", ascending: false)
            .execute()
            .value) ?? []

        let (i, o, f) = await (inc, out, fr)
        incoming = i
        outgoing = o
        friendships = f

        // When somebody else accepted a request we sent, RLS prevented them
        // from inserting our friendship row. Reconcile here so the friendship
        // shows up on our side too.
        await reconcileAcceptedSenderSide(existing: f)

        // Preload verification badges for everyone we just pulled in.
        let names = incoming.map { $0.from_username }
            + outgoing.map { $0.to_username }
            + friendships.map { $0.friend_username }
        if !names.isEmpty {
            await UserVerificationService.shared.preload(usernames: names)
        }
    }

    /// Look for accepted friend_requests where we are the SENDER and ensure
    /// the corresponding friendship row exists under our user_id. This unblocks
    /// the scenario where the recipient accepted but RLS prevented them from
    /// writing the mirror row for us.
    private func reconcileAcceptedSenderSide(existing: [FriendshipRow]) async {
        guard isRemote else { return }
        let acceptedOutgoing: [FriendRequestRow] = (try? await client
            .from("friend_requests")
            .select()
            .eq("from_user_id", value: currentUID)
            .eq("status", value: "accepted")
            .execute()
            .value) ?? []
        guard !acceptedOutgoing.isEmpty else { return }

        let existingIDs = Set(existing.map { $0.friend_user_id })
        var didInsert = false
        for req in acceptedOutgoing where !existingIDs.contains(req.to_user_id) {
            let row = FriendshipInsert(
                user_id: currentUID,
                friend_user_id: req.to_user_id,
                friend_username: req.to_username
            )
            do {
                try await client
                    .from("friendships")
                    .upsert(row, onConflict: "user_id,friend_user_id")
                    .execute()
                didInsert = true
            } catch {
                // Ignore — we'll try again on the next refresh.
            }
        }
        if didInsert {
            let fr: [FriendshipRow] = (try? await client
                .from("friendships")
                .select()
                .eq("user_id", value: currentUID)
                .order("created_at", ascending: false)
                .execute()
                .value) ?? []
            friendships = fr
        }
    }
}
