import Foundation
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.whisper_story_views (
//   story_id uuid not null references public.whisper_stories(id) on delete cascade,
//   viewer_id uuid not null references auth.users(id) on delete cascade,
//   viewer_username text not null,
//   story_owner_id uuid not null,
//   created_at timestamptz not null default now(),
//   primary key (story_id, viewer_id)
// );
// create index if not exists whisper_story_views_story_idx
//   on public.whisper_story_views (story_id);
// create index if not exists whisper_story_views_owner_idx
//   on public.whisper_story_views (story_owner_id);
// alter table public.whisper_story_views enable row level security;
// -- A viewer can record their own view.
// create policy "wsv insert own" on public.whisper_story_views
//   for insert with check (auth.uid() = viewer_id);
// -- Story owner can see who viewed their stories; everyone can read counts.
// create policy "wsv read all" on public.whisper_story_views
//   for select using (true);

nonisolated struct WhisperStoryViewRow: Codable, Sendable, Hashable {
    let story_id: String
    let viewer_id: String
    let viewer_username: String
    let story_owner_id: String
    let created_at: String?
}

nonisolated struct WhisperStoryViewInsert: Codable, Sendable {
    let story_id: String
    let viewer_id: String
    let viewer_username: String
    let story_owner_id: String
}

/// Records and reads story view receipts so the story owner can see who
/// watched each of their stories (Instagram-style swipe-up viewer list).
@MainActor
@Observable
final class WhisperStoryViewService {
    static let shared = WhisperStoryViewService()

    private let client = SupabaseService.shared.client

    /// Total view count per story_id. Used to render "123 views" at the
    /// bottom-left of a user's own story.
    var counts: [String: Int] = [:]
    /// Full viewer list per story_id, newest first.
    var viewersByStory: [String: [WhisperStoryViewRow]] = [:]
    var lastError: String?

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }
    /// Story IDs we've already submitted a view for in this session, so
    /// repeated taps don't hammer Supabase.
    private var submitted: Set<String> = []

    private init() {}

    /// Record that the current user viewed a story. No-op when the story
    /// belongs to the current user (you don't view your own stories) or
    /// when running in a guest/local session.
    func recordView(story: WhisperStoryRow) async {
        guard isRemote else { return }
        guard story.user_id.lowercased() != currentUID.lowercased() else { return }
        if submitted.contains(story.id) { return }
        submitted.insert(story.id)
        let username = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
        let payload = WhisperStoryViewInsert(
            story_id: story.id,
            viewer_id: currentUID,
            viewer_username: username,
            story_owner_id: story.user_id
        )
        do {
            try await client.from("whisper_story_views")
                .upsert(payload, onConflict: "story_id,viewer_id")
                .execute()
            Analytics.record("story_view", ["story_id": story.id])
            // Bump the local count optimistically so the owner sees it
            // immediately if they re-open the viewer.
            counts[story.id, default: 0] += 1
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Load viewers + counts for every story belonging to the current user.
    /// Cheap one-shot query — called when the owner opens their own story
    /// viewer or pulls down on the viewer list sheet.
    func loadViewersForMyStories(storyIDs: [String]) async {
        guard isRemote, !storyIDs.isEmpty else { return }
        do {
            let rows: [WhisperStoryViewRow] = try await client
                .from("whisper_story_views")
                .select()
                .in("story_id", values: storyIDs)
                .order("created_at", ascending: false)
                .limit(1000)
                .execute()
                .value
            var grouped: [String: [WhisperStoryViewRow]] = [:]
            for r in rows { grouped[r.story_id, default: []].append(r) }
            viewersByStory = grouped
            var c: [String: Int] = [:]
            for (id, list) in grouped { c[id] = list.count }
            counts = c
        } catch {
            lastError = error.localizedDescription
        }
    }
}
