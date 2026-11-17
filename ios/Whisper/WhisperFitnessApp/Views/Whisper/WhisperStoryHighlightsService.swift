import Foundation
import SwiftUI
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.whisper_story_highlights (
//   id uuid primary key default gen_random_uuid(),
//   user_id uuid not null references auth.users(id) on delete cascade,
//   title text not null,
//   cover_url text,
//   created_at timestamptz not null default now(),
//   updated_at timestamptz not null default now()
// );
// create index if not exists whisper_story_highlights_user_idx
//   on public.whisper_story_highlights (user_id, updated_at desc);
// alter table public.whisper_story_highlights enable row level security;
// drop policy if exists "wsh read all" on public.whisper_story_highlights;
// create policy "wsh read all" on public.whisper_story_highlights for select using (true);
// drop policy if exists "wsh write own" on public.whisper_story_highlights;
// create policy "wsh write own" on public.whisper_story_highlights
//   for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
//
// create table if not exists public.whisper_story_highlight_items (
//   id uuid primary key default gen_random_uuid(),
//   highlight_id uuid not null references public.whisper_story_highlights(id) on delete cascade,
//   user_id uuid not null references auth.users(id) on delete cascade,
//   image_url text not null,
//   caption text,
//   music_title text,
//   music_artist text,
//   position int not null default 0,
//   created_at timestamptz not null default now()
// );
// create index if not exists whisper_story_highlight_items_idx
//   on public.whisper_story_highlight_items (highlight_id, position asc, created_at asc);
// alter table public.whisper_story_highlight_items enable row level security;
// drop policy if exists "wshi read all" on public.whisper_story_highlight_items;
// create policy "wshi read all" on public.whisper_story_highlight_items for select using (true);
// drop policy if exists "wshi write own" on public.whisper_story_highlight_items;
// create policy "wshi write own" on public.whisper_story_highlight_items
//   for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

nonisolated struct WhisperStoryHighlightRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let title: String
    let cover_url: String?
    let created_at: String?
    let updated_at: String?
}

nonisolated struct WhisperStoryHighlightItemRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let highlight_id: String
    let user_id: String
    let image_url: String
    let caption: String?
    let music_title: String?
    let music_artist: String?
    let position: Int?
    let created_at: String?
    /// Full sticker JSON copied from the source story so saved highlights
    /// keep their text/poll/question/gif layers (nil on pre-upgrade rows).
    let metadata: String?
    /// 30s music preview URL so highlights keep playing their track.
    let music_url: String?
    let music_artwork: String?
}

nonisolated struct WhisperStoryHighlightInsert: Codable, Sendable {
    let user_id: String
    let title: String
    let cover_url: String?
}

/// Full-fidelity insert — carries stickers + playable music. Requires the
/// `story-highlights-upgrade.sql` columns; `addStory` falls back to the
/// legacy payload when they don't exist yet.
nonisolated struct WhisperStoryHighlightItemInsert: Codable, Sendable {
    let highlight_id: String
    let user_id: String
    let image_url: String
    let caption: String?
    let music_title: String?
    let music_artist: String?
    let position: Int
    let metadata: String?
    let music_url: String?
    let music_artwork: String?
}

nonisolated struct WhisperStoryHighlightItemLegacyInsert: Codable, Sendable {
    let highlight_id: String
    let user_id: String
    let image_url: String
    let caption: String?
    let music_title: String?
    let music_artist: String?
    let position: Int
}

nonisolated struct WhisperStoryHighlightRename: Codable, Sendable {
    let title: String
    let updated_at: String
}

nonisolated struct WhisperStoryHighlightCoverUpdate: Codable, Sendable {
    let cover_url: String
    let updated_at: String
}

nonisolated struct WhisperStoryHighlightTouch: Codable, Sendable {
    let updated_at: String
}

/// Instagram-style saved Story Highlights — named collections of stories
/// that persist past the normal 24h expiry. Items are denormalized copies
/// of the original story media so deleting / expiring the source story
/// doesn't break the highlight.
@MainActor
@Observable
final class WhisperStoryHighlightsService {
    static let shared = WhisperStoryHighlightsService()

    private let client = SupabaseService.shared.client

    /// Highlight albums keyed by owner user_id.
    var albumsByUser: [String: [WhisperStoryHighlightRow]] = [:]
    /// Items keyed by highlight_id, in display order.
    var itemsByAlbum: [String: [WhisperStoryHighlightItemRow]] = [:]
    var lastError: String?

    /// Every image_url the CURRENT user has saved into any highlight —
    /// powers the story viewer's bookmark state without walking albums.
    var mySavedImageURLs: Set<String> = []

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    private init() {}

    // MARK: - Reads

    /// Returns this user's highlight albums, newest update first.
    func albums(forUserID userID: String) -> [WhisperStoryHighlightRow] {
        albumsByUser[userID] ?? []
    }

    func items(forAlbumID id: String) -> [WhisperStoryHighlightItemRow] {
        itemsByAlbum[id] ?? []
    }

    func refresh(forUserID userID: String) async {
        guard isRemote else { return }
        do {
            let rows: [WhisperStoryHighlightRow] = try await client
                .from("whisper_story_highlights")
                .select()
                .eq("user_id", value: userID)
                .order("updated_at", ascending: false)
                .limit(60)
                .execute()
                .value
            albumsByUser[userID] = rows
            for row in rows {
                await refreshItems(highlightID: row.id)
            }
            if userID == currentUID { rebuildSavedIndex() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// True when the current user already saved this story image into ANY
    /// of their highlight albums.
    func isSaved(imageURL: String) -> Bool {
        mySavedImageURLs.contains(imageURL)
    }

    private func rebuildSavedIndex() {
        var urls = Set<String>()
        for album in albumsByUser[currentUID] ?? [] {
            for item in itemsByAlbum[album.id] ?? [] {
                urls.insert(item.image_url)
            }
        }
        mySavedImageURLs = urls
    }

    func refreshItems(highlightID: String) async {
        guard isRemote else { return }
        do {
            let rows: [WhisperStoryHighlightItemRow] = try await client
                .from("whisper_story_highlight_items")
                .select()
                .eq("highlight_id", value: highlightID)
                .order("position", ascending: true)
                .order("created_at", ascending: true)
                .limit(200)
                .execute()
                .value
            itemsByAlbum[highlightID] = rows
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Writes

    /// Create a new highlight album seeded with the given stories. The first
    /// story's image is used as the cover unless `coverURL` overrides it.
    @discardableResult
    func createAlbum(
        title: String,
        coverURL: String?,
        stories: [WhisperStoryRow]
    ) async -> WhisperStoryHighlightRow? {
        guard isRemote else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cover = coverURL ?? stories.first?.image_url
        let payload = WhisperStoryHighlightInsert(
            user_id: currentUID,
            title: trimmed,
            cover_url: cover
        )
        do {
            let inserted: [WhisperStoryHighlightRow] = try await client
                .from("whisper_story_highlights")
                .insert(payload)
                .select()
                .execute()
                .value
            guard let album = inserted.first else { return nil }
            albumsByUser[currentUID, default: []].insert(album, at: 0)
            // Seed items
            for (idx, s) in stories.enumerated() {
                await addStory(s, toAlbumID: album.id, position: idx)
            }
            Analytics.record("highlight_created", [
                "count": "\(stories.count)"
            ])
            return album
        } catch {
            lastError = "Couldn't create highlight: \(error.localizedDescription)"
            WhisperErrorService.shared.report("Couldn't create highlight. Try again.")
            Analytics.record("highlight_failed", ["reason": String(error.localizedDescription.prefix(80))])
            return nil
        }
    }

    @discardableResult
    func addStory(
        _ story: WhisperStoryRow,
        toAlbumID albumID: String,
        position: Int? = nil
    ) async -> WhisperStoryHighlightItemRow? {
        guard isRemote else { return nil }
        let existing = itemsByAlbum[albumID] ?? []
        let pos = position ?? existing.count
        // Full-fidelity copy first (stickers + playable music); fall back to
        // the legacy flat payload when the upgrade columns don't exist yet.
        let payload = WhisperStoryHighlightItemInsert(
            highlight_id: albumID,
            user_id: currentUID,
            image_url: story.image_url,
            caption: story.caption,
            music_title: story.music_title,
            music_artist: story.music_artist,
            position: pos,
            metadata: story.metadata,
            music_url: story.music_url,
            music_artwork: story.music_artwork
        )
        do {
            let inserted: [WhisperStoryHighlightItemRow] = try await client
                .from("whisper_story_highlight_items")
                .insert(payload)
                .select()
                .execute()
                .value
            if let item = inserted.first {
                itemsByAlbum[albumID, default: []].append(item)
                mySavedImageURLs.insert(item.image_url)
                await touchAlbum(albumID)
                return item
            }
        } catch {
            // Legacy retry — pre-upgrade schema without the new columns.
            let legacy = WhisperStoryHighlightItemLegacyInsert(
                highlight_id: albumID,
                user_id: currentUID,
                image_url: story.image_url,
                caption: story.caption,
                music_title: story.music_title,
                music_artist: story.music_artist,
                position: pos
            )
            do {
                let inserted: [WhisperStoryHighlightItemRow] = try await client
                    .from("whisper_story_highlight_items")
                    .insert(legacy)
                    .select()
                    .execute()
                    .value
                if let item = inserted.first {
                    itemsByAlbum[albumID, default: []].append(item)
                    mySavedImageURLs.insert(item.image_url)
                    await touchAlbum(albumID)
                    return item
                }
            } catch {
                lastError = "Couldn't save to highlight: \(error.localizedDescription)"
                WhisperErrorService.shared.report("Couldn't save to highlight. Try again.")
            }
        }
        return nil
    }

    func deleteAlbum(_ id: String) async {
        guard isRemote else { return }
        do {
            try await client.from("whisper_story_highlights")
                .delete()
                .eq("id", value: id)
                .eq("user_id", value: currentUID)
                .execute()
            albumsByUser[currentUID]?.removeAll { $0.id == id }
            itemsByAlbum.removeValue(forKey: id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteItem(_ itemID: String, fromAlbum albumID: String) async {
        guard isRemote else { return }
        do {
            try await client.from("whisper_story_highlight_items")
                .delete()
                .eq("id", value: itemID)
                .eq("user_id", value: currentUID)
                .execute()
            itemsByAlbum[albumID]?.removeAll { $0.id == itemID }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func rename(albumID: String, title: String) async {
        guard isRemote else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let iso = ISO8601DateFormatter().string(from: Date())
            try await client.from("whisper_story_highlights")
                .update(WhisperStoryHighlightRename(title: trimmed, updated_at: iso))
                .eq("id", value: albumID)
                .eq("user_id", value: currentUID)
                .execute()
            if var list = albumsByUser[currentUID],
               let idx = list.firstIndex(where: { $0.id == albumID }) {
                let old = list[idx]
                list[idx] = WhisperStoryHighlightRow(
                    id: old.id,
                    user_id: old.user_id,
                    title: trimmed,
                    cover_url: old.cover_url,
                    created_at: old.created_at,
                    updated_at: iso
                )
                albumsByUser[currentUID] = list
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setCover(albumID: String, coverURL: String) async {
        guard isRemote else { return }
        do {
            let iso = ISO8601DateFormatter().string(from: Date())
            try await client.from("whisper_story_highlights")
                .update(WhisperStoryHighlightCoverUpdate(cover_url: coverURL, updated_at: iso))
                .eq("id", value: albumID)
                .eq("user_id", value: currentUID)
                .execute()
            if var list = albumsByUser[currentUID],
               let idx = list.firstIndex(where: { $0.id == albumID }) {
                let old = list[idx]
                list[idx] = WhisperStoryHighlightRow(
                    id: old.id,
                    user_id: old.user_id,
                    title: old.title,
                    cover_url: coverURL,
                    created_at: old.created_at,
                    updated_at: iso
                )
                albumsByUser[currentUID] = list
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func touchAlbum(_ albumID: String) async {
        do {
            let iso = ISO8601DateFormatter().string(from: Date())
            try await client.from("whisper_story_highlights")
                .update(WhisperStoryHighlightTouch(updated_at: iso))
                .eq("id", value: albumID)
                .eq("user_id", value: currentUID)
                .execute()
        } catch {
            // Best-effort; ordering will catch up on next refresh.
        }
    }
}
