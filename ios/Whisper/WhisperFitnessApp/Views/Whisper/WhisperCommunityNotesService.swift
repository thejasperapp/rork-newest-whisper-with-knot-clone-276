import Foundation
import SwiftUI
import Supabase

// MARK: - Supabase schema (run once)
//
// create table if not exists public.whisper_community_notes (
//     id uuid primary key default gen_random_uuid(),
//     post_id text not null,
//     author_user_id uuid,
//     author_username text not null,
//     body text not null,
//     helpful_count int not null default 0,
//     not_helpful_count int not null default 0,
//     status text not null default 'visible',
//     created_at timestamptz not null default now()
// );
// create index if not exists whisper_community_notes_post_idx
//     on public.whisper_community_notes (post_id, created_at desc);
// alter table public.whisper_community_notes enable row level security;
// drop policy if exists "notes read" on public.whisper_community_notes;
// create policy "notes read" on public.whisper_community_notes for select using (true);
// drop policy if exists "notes write" on public.whisper_community_notes;
// create policy "notes write" on public.whisper_community_notes
//     for insert with check (auth.uid() is not null);
// drop policy if exists "notes update" on public.whisper_community_notes;
// create policy "notes update" on public.whisper_community_notes
//     for update using (auth.uid() is not null);
//
// create table if not exists public.whisper_community_note_votes (
//     note_id uuid not null references public.whisper_community_notes(id) on delete cascade,
//     voter_user_id uuid not null,
//     vote int not null check (vote in (-1, 1)),
//     created_at timestamptz not null default now(),
//     primary key (note_id, voter_user_id)
// );
// alter table public.whisper_community_note_votes enable row level security;
// drop policy if exists "note votes rw" on public.whisper_community_note_votes;
// create policy "note votes rw" on public.whisper_community_note_votes
//     for all using (auth.uid() is not null) with check (auth.uid() is not null);

/// A single community-authored context note attached to a post.
/// "Community notes" let readers add verified context, citations, or
/// corrections to a post the author may have gotten wrong.
nonisolated struct WhisperCommunityNote: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let post_id: String
    let author_user_id: String?
    let author_username: String
    let body: String
    let helpful_count: Int
    let not_helpful_count: Int
    let status: String?
    let created_at: Date

    /// Net helpfulness score used to rank notes. Notes need both helpful
    /// votes AND a positive net score to surface inline on the post.
    var score: Int { helpful_count - not_helpful_count }
    var isHidden: Bool { (status ?? "visible") == "hidden" }
}

@Observable
@MainActor
final class WhisperCommunityNotesService {
    static let shared = WhisperCommunityNotesService()

    private let client = SupabaseService.shared.client

    /// Cached notes per post id.
    private(set) var notesByPost: [String: [WhisperCommunityNote]] = [:]
    /// Post IDs already fetched this session — lets feed cards skip
    /// re-fetching notes every time they remount while scrolling.
    private var fetchedPostIDs: Set<String> = []
    /// Note IDs the local viewer has voted on, mapped to their vote (+1 / -1).
    private(set) var myVotes: [String: Int] = [:]

    private init() {}

    /// Visible notes for `postID` ranked by score then recency.
    func notes(forPostID postID: String) -> [WhisperCommunityNote] {
        (notesByPost[postID] ?? [])
            .filter { !$0.isHidden }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.created_at > rhs.created_at
            }
    }

    /// Top community note for `postID` — only returned when it's clearly
    /// surfaced as helpful (score >= 2 and at least 2 helpful votes) so the
    /// inline card never shows brand-new or contested notes.
    func topNote(forPostID postID: String) -> WhisperCommunityNote? {
        notes(forPostID: postID).first { $0.score >= 2 && $0.helpful_count >= 2 }
    }

    nonisolated struct NoteInsert: Codable, Sendable {
        let post_id: String
        let author_user_id: String?
        let author_username: String
        let body: String
    }

    @discardableResult
    func addNote(postID: String, body: String) async -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return false }
        let me = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "anonymous"
        let uid = AccountStorage.currentUserID.isEmpty
            ? nil
            : AccountStorage.currentUserID
        let row = NoteInsert(
            post_id: postID,
            author_user_id: uid,
            author_username: me,
            body: String(trimmed.prefix(500))
        )
        do {
            try await client.from("whisper_community_notes").insert(row).execute()
            await refresh(postID: postID)
            return true
        } catch {
            return false
        }
    }

    /// Session-cached variant of `refresh` — only hits the network the
    /// first time a post's notes are requested. Feed cards use this;
    /// detail views and the notes sheet keep calling `refresh` directly.
    func refreshIfNeeded(postID: String) async {
        guard !fetchedPostIDs.contains(postID) else { return }
        await refresh(postID: postID)
    }

    func refresh(postID: String) async {
        do {
            let rows: [WhisperCommunityNote] = try await client
                .from("whisper_community_notes")
                .select("id,post_id,author_user_id,author_username,body,helpful_count,not_helpful_count,status,created_at")
                .eq("post_id", value: postID)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
            notesByPost[postID] = rows
            fetchedPostIDs.insert(postID)
            await refreshMyVotes(noteIDs: rows.map { $0.id })
        } catch {
            // Silent — notes are non-critical.
        }
    }

    nonisolated struct VoteRow: Codable, Sendable {
        let note_id: String
        let voter_user_id: String
        let vote: Int
    }

    private func refreshMyVotes(noteIDs: [String]) async {
        guard !noteIDs.isEmpty else { return }
        let uid = AccountStorage.currentUserID
        guard !uid.isEmpty else { return }
        do {
            let rows: [VoteRow] = try await client
                .from("whisper_community_note_votes")
                .select("note_id,voter_user_id,vote")
                .in("note_id", values: noteIDs)
                .eq("voter_user_id", value: uid)
                .execute()
                .value
            for r in rows { myVotes[r.note_id] = r.vote }
        } catch {
            // Silent.
        }
    }

    /// Cast (or un-cast) a vote on `note`. Votes are upserted on the
    /// `(note_id, voter_user_id)` composite key and the running totals on
    /// the note row are recomputed from `whisper_community_note_votes`.
    func vote(on note: WhisperCommunityNote, value: Int) async {
        let uid = AccountStorage.currentUserID
        guard !uid.isEmpty else { return }
        let normalized = max(-1, min(1, value))
        let previous = myVotes[note.id] ?? 0
        if previous == normalized {
            // Toggle off — delete the vote row.
            do {
                try await client.from("whisper_community_note_votes")
                    .delete()
                    .eq("note_id", value: note.id)
                    .eq("voter_user_id", value: uid)
                    .execute()
                myVotes.removeValue(forKey: note.id)
            } catch {
                return
            }
        } else {
            let row = VoteRow(note_id: note.id, voter_user_id: uid, vote: normalized)
            do {
                try await client.from("whisper_community_note_votes")
                    .upsert(row, onConflict: "note_id,voter_user_id")
                    .execute()
                myVotes[note.id] = normalized
            } catch {
                return
            }
        }
        // Recompute totals on the parent note row.
        await recomputeTotals(noteID: note.id, postID: note.post_id)
    }

    nonisolated struct TallyRow: Decodable, Sendable { let vote: Int }
    nonisolated struct TotalsUpdate: Encodable, Sendable {
        let helpful_count: Int
        let not_helpful_count: Int
    }

    private func recomputeTotals(noteID: String, postID: String) async {
        do {
            let rows: [TallyRow] = try await client
                .from("whisper_community_note_votes")
                .select("vote")
                .eq("note_id", value: noteID)
                .execute()
                .value
            let helpful = rows.filter { $0.vote == 1 }.count
            let notHelpful = rows.filter { $0.vote == -1 }.count
            try await client.from("whisper_community_notes")
                .update(TotalsUpdate(helpful_count: helpful, not_helpful_count: notHelpful))
                .eq("id", value: noteID)
                .execute()
            await refresh(postID: postID)
        } catch {
            // Silent.
        }
    }
}
