import Foundation
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// -- Coaching requests + active coach/client relationships.
// create table if not exists public.whisper_coach_requests (
//   id uuid primary key default gen_random_uuid(),
//   client_user_id uuid not null references auth.users(id) on delete cascade,
//   client_username text not null,
//   coach_user_id uuid not null references auth.users(id) on delete cascade,
//   coach_username text not null,
//   message text not null default '',
//   status text not null default 'pending'
//     check (status in ('pending','accepted','declined','cancelled')),
//   created_at timestamptz not null default now(),
//   updated_at timestamptz not null default now(),
//   unique (client_user_id, coach_user_id)
// );
// alter table public.whisper_coach_requests enable row level security;
// create policy "wcr read own" on public.whisper_coach_requests for select
//   using (auth.uid() = client_user_id or auth.uid() = coach_user_id);
// create policy "wcr insert as client" on public.whisper_coach_requests
//   for insert with check (auth.uid() = client_user_id);
// create policy "wcr update by either" on public.whisper_coach_requests
//   for update using (auth.uid() = client_user_id or auth.uid() = coach_user_id);
// create policy "wcr delete by either" on public.whisper_coach_requests
//   for delete using (auth.uid() = client_user_id or auth.uid() = coach_user_id);
//
// -- Snapshots of a client's health data, kept fresh by the client app.
// -- Coaches with an 'accepted' request row can read the matching snapshot.
// create table if not exists public.whisper_client_snapshots (
//   user_id uuid primary key references auth.users(id) on delete cascade,
//   username text not null,
//   payload jsonb not null default '{}'::jsonb,
//   photo_front_url text,
//   photo_side_url text,
//   photo_back_url text,
//   updated_at timestamptz not null default now()
//);
// alter table public.whisper_client_snapshots enable row level security;
// create policy "wcs read own or coach" on public.whisper_client_snapshots
//   for select using (
//     auth.uid() = user_id
//     or exists (
//       select 1 from public.whisper_coach_requests r
//       where r.client_user_id = whisper_client_snapshots.user_id
//         and r.coach_user_id = auth.uid()
//         and r.status = 'accepted'
//     )
//   );
// create policy "wcs upsert own" on public.whisper_client_snapshots
//   for insert with check (auth.uid() = user_id);
// create policy "wcs update own" on public.whisper_client_snapshots
//   for update using (auth.uid() = user_id);

nonisolated struct WhisperCoachRequestRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let client_user_id: String
    let client_username: String
    let coach_user_id: String
    let coach_username: String
    let message: String?
    let status: String
    let created_at: String?
    let updated_at: String?
}

nonisolated struct WhisperCoachRequestInsert: Codable, Sendable {
    let client_user_id: String
    let client_username: String
    let coach_user_id: String
    let coach_username: String
    let message: String
    let status: String
    let updated_at: String
}

nonisolated struct WhisperCoachRequestStatusUpdate: Codable, Sendable {
    let status: String
    let updated_at: String
}

/// Tracks coach <-> client requests and the resulting active relationships.
/// - Clients call `requestCoach(...)` to ask another user to coach them.
/// - Coaches accept/decline pending requests from `WhisperCoachClientsView`.
/// - Both sides observe `incoming` / `outgoing` / `myCoaches` / `myClients`.
@MainActor
@Observable
final class WhisperCoachRequestService {
    static let shared = WhisperCoachRequestService()

    private let client = SupabaseService.shared.client

    /// Requests the local user has SENT (they want someone to be their coach).
    var outgoing: [WhisperCoachRequestRow] = []
    /// Requests the local user has RECEIVED (people who want them as coach).
    var incoming: [WhisperCoachRequestRow] = []
    /// Accepted requests where the local user is the client → coaches they
    /// have hired.
    var myCoaches: [WhisperCoachRequestRow] = []
    /// Accepted requests where the local user is the coach → active clients.
    var myClients: [WhisperCoachRequestRow] = []

    var isLoading: Bool = false
    var lastError: String?

    private var currentUID: String { AccountStorage.currentUserID.lowercased() }
    private var isRemote: Bool {
        WhisperIdentityService.isValidSupabaseUID(AccountStorage.currentUserID)
    }

    private init() {}

    // MARK: - Refresh

    func refresh() async {
        guard isRemote else { return }
        let generation = AccountStorage.generation
        isLoading = true
        defer { if generation == AccountStorage.generation { isLoading = false } }
        async let outTask = fetch(role: .client)
        async let inTask = fetch(role: .coach)
        let (out, inc) = await (outTask, inTask)
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        self.outgoing = out
        self.incoming = inc
        self.myCoaches = out.filter { $0.status == "accepted" }
        self.myClients = inc.filter { $0.status == "accepted" }
        mirrorClientsToWidgets()
    }

    /// Mirrors the active client roster into the App Group so the Coach
    /// Clients widget + the Apple Watch stay current.
    private func mirrorClientsToWidgets() {
        let compact: [WhisperWidgetSync.CompactClient] = myClients.prefix(6).map { row in
            WhisperWidgetSync.CompactClient(
                name: row.client_username,
                userID: row.client_user_id,
                avatar: nil,
                since: row.updated_at.flatMap { WhisperBackendService.parseISO($0) }?.timeIntervalSince1970
            )
        }
        WhisperWidgetSync.writeCoachClients(compact, isCoach: !myClients.isEmpty || !incoming.isEmpty)
    }

    private enum Role { case client, coach }

    private func fetch(role: Role) async -> [WhisperCoachRequestRow] {
        let column = role == .client ? "client_user_id" : "coach_user_id"
        do {
            let rows: [WhisperCoachRequestRow] = try await client
                .from("whisper_coach_requests")
                .select()
                .eq(column, value: AccountStorage.currentUserID)
                .order("updated_at", ascending: false)
                .execute()
                .value
            return rows
        } catch {
            let msg = error.localizedDescription.lowercased()
            if msg.contains("relation") && msg.contains("does not exist") {
                lastError = "Coach requests table missing. Owner: run the WhisperCoachRequestService SQL block once."
            }
            print("[Whisper] coach requests fetch error: \(error)")
            return []
        }
    }

    // MARK: - Mutations

    /// Client → coach: "please coach me".
    @discardableResult
    func requestCoach(coachUserID: String, coachUsername: String, message: String) async -> Bool {
        let clientUID: String
        do {
            clientUID = try WhisperIdentityService.requireValidUID()
        } catch {
            lastError = error.localizedDescription
            print("[Whisper] coach request blocked — invalid local UID: \(AccountStorage.currentUserID)")
            return false
        }
        let myUsername = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "client"
        let payload = WhisperCoachRequestInsert(
            client_user_id: clientUID,
            client_username: myUsername,
            coach_user_id: coachUserID,
            coach_username: coachUsername,
            message: message,
            status: "pending",
            // Postgres has no auto-update trigger on this table — a re-request
            // upsert must bump updated_at itself or the row keeps its stale
            // ordering in the coach's request list.
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await client
                .from("whisper_coach_requests")
                .upsert(payload, onConflict: "client_user_id,coach_user_id")
                .execute()
            await refresh()
            return true
        } catch {
            lastError = "Couldn't send request: \(error.localizedDescription)"
            print("[Whisper] coach request insert error: \(error)")
            return false
        }
    }

    @discardableResult
    func updateStatus(requestID: String, status: String) async -> Bool {
        guard isRemote else { return false }
        do {
            try await client
                .from("whisper_coach_requests")
                .update(WhisperCoachRequestStatusUpdate(
                    status: status,
                    // No DB trigger — stamp it here so `order("updated_at")`
                    // reflects the actual latest activity.
                    updated_at: ISO8601DateFormatter().string(from: Date())
                ))
                .eq("id", value: requestID)
                .execute()
            await refresh()
            return true
        } catch {
            lastError = "Couldn't update request: \(error.localizedDescription)"
            return false
        }
    }

    func accept(_ row: WhisperCoachRequestRow) async {
        let ok = await updateStatus(requestID: row.id, status: "accepted")
        guard ok else { return }
        // `whisper_coach_requests` has no push webhook, so without this the
        // client never learns they were accepted until they manually check
        // My Coaches. A DM rides the existing push pipeline — banner with
        // the coach's avatar, inbox thread, the works.
        _ = await WhisperBackendService.shared.sendMessage(
            toUserID: row.client_user_id,
            toUsername: row.client_username,
            body: "I've accepted your coaching request \u{2014} welcome aboard! \u{1F4AA} Your health snapshot is syncing to my Coach Studio now, so tell me about your goals."
        )
    }

    func decline(_ row: WhisperCoachRequestRow) async {
        _ = await updateStatus(requestID: row.id, status: "declined")
    }

    func cancel(_ row: WhisperCoachRequestRow) async {
        _ = await updateStatus(requestID: row.id, status: "cancelled")
    }

    func end(_ row: WhisperCoachRequestRow) async {
        guard isRemote else { return }
        do {
            try await client
                .from("whisper_coach_requests")
                .delete()
                .eq("id", value: row.id)
                .execute()
            await refresh()
        } catch {
            lastError = "Couldn't end coaching: \(error.localizedDescription)"
        }
    }

    // MARK: - Lookups

    /// Returns the live status of any prior request the local user sent to
    /// `coachUserID`, or nil if none exists.
    func outgoingStatus(coachUserID: String) -> String? {
        outgoing.first { $0.coach_user_id.lowercased() == coachUserID.lowercased() }?.status
    }

    /// True iff the local user has at least one *accepted* coach.
    var hasAnyCoach: Bool { !myCoaches.isEmpty }

    /// True iff the local user has at least one *accepted* client (they
    /// actively coach someone).
    var hasAnyClient: Bool { !myClients.isEmpty }
}
