import Foundation
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// -- 1) Add is_private to whisper_profiles (column is nullable; treated as false when null).
// alter table public.whisper_profiles
//   add column if not exists is_private boolean not null default false;
//
// -- 2) Follow-request queue.
// create table if not exists public.whisper_follow_requests (
//   id uuid primary key default gen_random_uuid(),
//   requester_id   uuid not null references auth.users(id) on delete cascade,
//   requester_username text not null,
//   target_id      uuid not null references auth.users(id) on delete cascade,
//   target_username text not null,
//   status text not null default 'pending'
//     check (status in ('pending','approved','denied','cancelled')),
//   created_at timestamptz not null default now(),
//   responded_at timestamptz,
//   unique (requester_id, target_id)
// );
// create index if not exists wfr_target_idx
//   on public.whisper_follow_requests (target_id, status);
// create index if not exists wfr_requester_idx
//   on public.whisper_follow_requests (requester_id, status);
// alter table public.whisper_follow_requests enable row level security;
// drop policy if exists "wfr read involved" on public.whisper_follow_requests;
// create policy "wfr read involved" on public.whisper_follow_requests
//   for select using (auth.uid() = requester_id or auth.uid() = target_id);
// drop policy if exists "wfr insert requester" on public.whisper_follow_requests;
// create policy "wfr insert requester" on public.whisper_follow_requests
//   for insert with check (auth.uid() = requester_id);
// drop policy if exists "wfr update involved" on public.whisper_follow_requests;
// create policy "wfr update involved" on public.whisper_follow_requests
//   for update using (auth.uid() = requester_id or auth.uid() = target_id);
// drop policy if exists "wfr delete involved" on public.whisper_follow_requests;
// create policy "wfr delete involved" on public.whisper_follow_requests
//   for delete using (auth.uid() = requester_id or auth.uid() = target_id);
//
// -- 3) Relax whisper_follows insert policy so a private-account holder can
// --    create the follow row on approval (target inserts on behalf of the
// --    requester). Without this, approve would no-op.
// drop policy if exists "wf insert self" on public.whisper_follows;
// create policy "wf insert self or followee" on public.whisper_follows
//   for insert with check (auth.uid() = follower_id or auth.uid() = followee_id);
//
// notify pgrst, 'reload schema';

nonisolated struct WhisperFollowRequestRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let requester_id: String
    let requester_username: String
    let target_id: String
    let target_username: String
    let status: String
    let created_at: String?
    let responded_at: String?
}

nonisolated struct WhisperFollowRequestInsert: Codable, Sendable {
    let requester_id: String
    let requester_username: String
    let target_id: String
    let target_username: String
    let status: String
}

nonisolated struct WhisperFollowRequestStatusUpdate: Encodable, Sendable {
    let status: String
    let responded_at: String
}

/// Tracks pending / resolved follow requests when the target is a private
/// Whisper account. Mirrors Instagram's request queue.
@MainActor
@Observable
final class WhisperFollowRequestService {
    static let shared = WhisperFollowRequestService()

    private let client = SupabaseService.shared.client

    /// Requests waiting for the local user to approve / deny.
    var incoming: [WhisperFollowRequestRow] = []
    /// Requests the local user has sent that haven't been resolved.
    var outgoing: [WhisperFollowRequestRow] = []
    var lastError: String?

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    private init() {}

    var pendingIncomingCount: Int {
        incoming.filter { $0.status == "pending" }.count
    }

    func hasPendingOutgoing(targetID: String) -> Bool {
        outgoing.contains { $0.target_id == targetID && $0.status == "pending" }
    }

    /// Pull the latest state for both directions.
    func refresh() async {
        let owner = currentUID
        let epoch = AccountStorage.generation
        guard isRemote else {
            incoming = []
            outgoing = []
            return
        }
        async let incomingTask: [WhisperFollowRequestRow]? = {
            do {
                return try await client
                    .from("whisper_follow_requests")
                    .select()
                    .eq("target_id", value: owner)
                    .eq("status", value: "pending")
                    .order("created_at", ascending: false)
                    .execute()
                    .value
            } catch {
                print("[Whisper] follow-requests incoming error: \(error)")
                return nil
            }
        }()
        async let outgoingTask: [WhisperFollowRequestRow]? = {
            do {
                return try await client
                    .from("whisper_follow_requests")
                    .select()
                    .eq("requester_id", value: owner)
                    .eq("status", value: "pending")
                    .order("created_at", ascending: false)
                    .execute()
                    .value
            } catch {
                print("[Whisper] follow-requests outgoing error: \(error)")
                return nil
            }
        }()
        let (i, o) = await (incomingTask, outgoingTask)
        guard !Task.isCancelled, epoch == AccountStorage.generation, owner == currentUID else { return }
        if let i { incoming = i }
        if let o { outgoing = o }
    }

    /// Create a pending follow request. Used when the target is a private
    /// account.
    @discardableResult
    func request(targetID: String, targetUsername: String) async -> Bool {
        let account = currentUID; let epoch = AccountStorage.generation
        guard !Task.isCancelled else { return false }
        guard isRemote, targetID != currentUID else { return false }
        let myUsername = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "user"
        let payload = WhisperFollowRequestInsert(
            requester_id: currentUID,
            requester_username: myUsername,
            target_id: targetID,
            target_username: targetUsername,
            status: "pending"
        )
        do {
            try await client
                .from("whisper_follow_requests")
                .upsert(payload, onConflict: "requester_id,target_id")
                .execute()
            guard !Task.isCancelled, epoch == AccountStorage.generation, account == currentUID else { return false }
            // Reflect the optimistic state locally so the profile button
            // can flip to "Requested" without an extra refresh.
            if !outgoing.contains(where: { $0.target_id == targetID }) {
                outgoing.insert(
                    WhisperFollowRequestRow(
                        id: UUID().uuidString,
                        requester_id: currentUID,
                        requester_username: myUsername,
                        target_id: targetID,
                        target_username: targetUsername,
                        status: "pending",
                        created_at: nil,
                        responded_at: nil
                    ),
                    at: 0
                )
            }
            return true
        } catch {
            guard epoch == AccountStorage.generation, account == currentUID else { return false }
            lastError = "Couldn't send the follow request. Try again."
            print("[Whisper] follow-request insert failed")
            return false
        }
    }

    /// Cancel an outgoing pending request (requester taps "Requested" again).
    @discardableResult
    func cancelRequest(targetID: String) async -> Bool {
        guard isRemote else { return false }
        do {
            try await client
                .from("whisper_follow_requests")
                .delete()
                .eq("requester_id", value: currentUID)
                .eq("target_id", value: targetID)
                .execute()
            outgoing.removeAll { $0.target_id == targetID }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Approve an incoming request: mark it approved, then insert the
    /// `whisper_follows` row so the requester actually starts following.
    /// Requires the relaxed RLS policy described at the top of this file.
    @discardableResult
    func approve(_ request: WhisperFollowRequestRow) async -> Bool {
        guard isRemote else { return false }
        let iso = ISO8601DateFormatter().string(from: Date())
        let upd = WhisperFollowRequestStatusUpdate(status: "approved", responded_at: iso)
        do {
            try await client
                .from("whisper_follow_requests")
                .update(upd)
                .eq("id", value: request.id)
                .execute()
            // Insert the follow row from the *target* side (this account).
            // The relaxed policy in this file allows that.
            let row = WhisperFollowInsert(
                follower_id: request.requester_id,
                followee_id: request.target_id,
                followee_username: request.target_username
            )
            try await client
                .from("whisper_follows")
                .upsert(row, onConflict: "follower_id,followee_id")
                .execute()
            incoming.removeAll { $0.id == request.id }
            // Update local follow service so the counts stay in sync.
            WhisperFollowService.shared.followers.insert(request.requester_id.lowercased())
            WhisperFollowService.shared.followerCount += 1
            return true
        } catch {
            lastError = error.localizedDescription
            print("[Whisper] follow-request approve error: \(error)")
            return false
        }
    }

    /// Deny an incoming request — leaves a row marked `denied` so the
    /// requester sees their button revert to "Follow" (and the queue stays
    /// auditable).
    @discardableResult
    func deny(_ request: WhisperFollowRequestRow) async -> Bool {
        guard isRemote else { return false }
        let iso = ISO8601DateFormatter().string(from: Date())
        let upd = WhisperFollowRequestStatusUpdate(status: "denied", responded_at: iso)
        do {
            try await client
                .from("whisper_follow_requests")
                .update(upd)
                .eq("id", value: request.id)
                .execute()
            incoming.removeAll { $0.id == request.id }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
