import Foundation
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.whisper_story_responses (
//   id uuid primary key default gen_random_uuid(),
//   story_id uuid not null references public.whisper_stories(id) on delete cascade,
//   story_owner_id uuid not null,
//   responder_id uuid not null references auth.users(id) on delete cascade,
//   responder_username text not null,
//   kind text not null,                   -- 'poll' | 'slider' | 'question'
//   prompt text not null,                 -- the sticker question/title
//   response text not null,               -- chosen option / "73%" / free-text answer
//   created_at timestamptz not null default now(),
//   read_at timestamptz
// );
// create index if not exists whisper_story_responses_owner_idx
//   on public.whisper_story_responses (story_owner_id, created_at desc);
// alter table public.whisper_story_responses enable row level security;
// -- Anyone signed-in can drop a response.
// create policy "wsr insert own" on public.whisper_story_responses
//   for insert with check (auth.uid() = responder_id);
// -- Owner can read their inbox; responders can read what they sent.
// create policy "wsr read owner" on public.whisper_story_responses
//   for select using (auth.uid() = story_owner_id or auth.uid() = responder_id);
// create policy "wsr update read" on public.whisper_story_responses
//   for update using (auth.uid() = story_owner_id);
//
// -- Poll tally RPC. SECURITY DEFINER lets non-owner voters read aggregate
// -- counts without exposing individual rows (RLS still hides those).
// create or replace function public.whisper_poll_tally(
//   p_story_id uuid,
//   p_prompt text
// ) returns table(option_text text, vote_count integer)
// language sql security definer set search_path = public as $
//   select response as option_text, count(*)::int as vote_count
//   from public.whisper_story_responses
//   where story_id = p_story_id
//     and kind = 'poll'
//     and prompt = p_prompt
//   group by response;
// $;
// grant execute on function public.whisper_poll_tally(uuid, text) to authenticated, anon;

nonisolated struct WhisperStoryResponseRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let story_id: String
    let story_owner_id: String
    let responder_id: String
    let responder_username: String
    let kind: String
    let prompt: String
    let response: String
    let created_at: String?
    let read_at: String?

    var actionDescription: String {
        switch kind {
        case "poll": return "voted on your poll"
        case "slider": return "rated your slider"
        case "question": return "answered your question with"
        case "like": return "liked your story"
        case "reaction": return "reacted to your story with"
        default: return "responded to your story with"
        }
    }
}

nonisolated struct WhisperStoryResponseInsert: Codable, Sendable {
    let story_id: String
    let story_owner_id: String
    let responder_id: String
    let responder_username: String
    let kind: String
    let prompt: String
    let response: String
}

/// Story interaction inbox — captures poll votes, slider ratings, and
/// question replies on the current user's stories so they show up under a
/// dedicated "Story responses" section in Activity instead of being
/// scattered across DMs.
@MainActor
@Observable
final class WhisperStoryResponseService {
    static let shared = WhisperStoryResponseService()

    private let client = SupabaseService.shared.client

    /// Newest-first list of responses to the current user's stories.
    var inbox: [WhisperStoryResponseRow] = []
    var lastError: String?
    /// Cached poll tallies keyed by "<storyID>|<prompt>". Maps each option
    /// label to its current vote count. Populated by `fetchPollTally`.
    var pollTallies: [String: [String: Int]] = [:]

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    /// Unread count drives the badge on the Activity tab.
    var unreadCount: Int { inbox.reduce(0) { $0 + ($1.read_at == nil ? 1 : 0) } }

    private init() {
        NotificationCenter.default.addObserver(forName: Notification.Name("WhisperMeetingAccountWillChange"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.inbox = []
                self?.pollTallies = [:]
                self?.lastError = nil
            }
        }
    }

    /// Record a response to someone else's story. No-op for guest sessions
    /// and for responses to your own story (which can't happen via the UI
    /// but we guard anyway).
    func record(
        story: WhisperStoryRow,
        kind: String,
        prompt: String,
        response: String
    ) async {
        guard isRemote else { return }
        guard story.user_id.lowercased() != currentUID.lowercased() else { return }
        let username = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
        let payload = WhisperStoryResponseInsert(
            story_id: story.id,
            story_owner_id: story.user_id,
            responder_id: currentUID,
            responder_username: username,
            kind: kind,
            prompt: prompt,
            response: response
        )
        do {
            try await client.from("whisper_story_responses")
                .insert(payload)
                .execute()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Fetch the inbox of responses to the current user's stories.
    @ObservationIgnored private let inboxRefresh = WhisperAccountRefresh()

    func fetch() async {
        await inboxRefresh.run { [self] generation in await loadInbox(generation: generation) }
    }

    private func loadInbox(generation: UUID) async {
        guard isRemote, !Task.isCancelled, generation == AccountStorage.generation else { return }
        let owner = currentUID
        do {
            let rows: [WhisperStoryResponseRow] = try await client
                .from("whisper_story_responses")
                .select()
                .eq("story_owner_id", value: owner)
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID else { return }
            inbox = rows
            WhisperNotificationService.shared.refreshAppIconBadge()
        } catch {
            guard generation == AccountStorage.generation, owner == currentUID else { return }
            lastError = "Story responses couldn't load. Try again."
        }
    }

    /// Fetch the live vote count per option for a given poll (story + prompt).
    /// Uses a SECURITY DEFINER RPC so non-owner voters can see results too.
    /// Updates `pollTallies["<storyID>|<prompt>"]` and returns the map.
    @discardableResult
    func fetchPollTally(storyID: String, prompt: String) async -> [String: Int] {
        let key = "\(storyID)|\(prompt)"
        guard isRemote else { return pollTallies[key] ?? [:] }
        struct TallyRow: Decodable { let option_text: String; let vote_count: Int }
        struct Params: Encodable { let p_story_id: String; let p_prompt: String }
        do {
            let rows: [TallyRow] = try await client.rpc(
                "whisper_poll_tally",
                params: Params(p_story_id: storyID, p_prompt: prompt)
            )
            .execute()
            .value
            var map: [String: Int] = [:]
            for row in rows { map[row.option_text] = row.vote_count }
            pollTallies[key] = map
            return map
        } catch {
            lastError = error.localizedDescription
            return pollTallies[key] ?? [:]
        }
    }

    /// Synchronous lookup used by views — returns the cached tally or nil.
    func cachedPollTally(storyID: String, prompt: String) -> [String: Int]? {
        pollTallies["\(storyID)|\(prompt)"]
    }

    /// Prune any cached responses for a story that was just deleted so the
    /// Activity tab updates immediately, before the next `fetch()` round-trip.
    func removeResponses(forStoryID storyID: String) {
        let before = inbox.count
        inbox.removeAll { $0.story_id == storyID }
        if inbox.count != before {
            WhisperNotificationService.shared.refreshAppIconBadge()
        }
    }

    /// Mark every unread response as read. Called when the user opens the
    /// Activity tab.
    func markAllRead() async {
        guard isRemote else { return }
        let unread = inbox.filter { $0.read_at == nil }.map { $0.id }
        guard !unread.isEmpty else { return }
        // Optimistically clear local state so the badge disappears right away.
        let nowIso = ISO8601DateFormatter().string(from: Date())
        inbox = inbox.map { row in
            guard row.read_at == nil else { return row }
            return WhisperStoryResponseRow(
                id: row.id,
                story_id: row.story_id,
                story_owner_id: row.story_owner_id,
                responder_id: row.responder_id,
                responder_username: row.responder_username,
                kind: row.kind,
                prompt: row.prompt,
                response: row.response,
                created_at: row.created_at,
                read_at: nowIso
            )
        }
        WhisperNotificationService.shared.refreshAppIconBadge()
        do {
            try await client.from("whisper_story_responses")
                .update(["read_at": nowIso])
                .in("id", values: unread)
                .execute()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
