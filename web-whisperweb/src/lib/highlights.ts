import { supabase } from "./supabase";

/**
 * Story Highlights — Instagram-style saved story albums. Mirrors the iOS
 * `whisper_story_highlights` / `whisper_story_highlight_items` tables so the
 * highlight covers a user curates on the app show up on their web profile too.
 */
export interface StoryHighlight {
  id: string;
  user_id: string;
  title: string;
  cover_url: string | null;
  updated_at: string | null;
}

export interface StoryHighlightItem {
  id: string;
  highlight_id: string;
  image_url: string;
  caption: string | null;
  music_title: string | null;
  music_artist: string | null;
  position: number;
}

/** All highlight albums for a user, newest first. */
export async function fetchHighlights(
  userId: string
): Promise<StoryHighlight[]> {
  const { data, error } = await supabase
    .from("whisper_story_highlights")
    .select("id, user_id, title, cover_url, updated_at")
    .eq("user_id", userId)
    .order("updated_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as StoryHighlight[];
}

/** The stories inside one highlight album, in display order. */
export async function fetchHighlightItems(
  highlightId: string
): Promise<StoryHighlightItem[]> {
  const { data, error } = await supabase
    .from("whisper_story_highlight_items")
    .select("id, highlight_id, image_url, caption, music_title, music_artist, position")
    .eq("highlight_id", highlightId)
    .order("position", { ascending: true });
  if (error) throw error;
  return (data ?? []) as StoryHighlightItem[];
}

/** Every image_url the signed-in user already saved into ANY highlight —
 *  powers the story viewer's bookmark saved-state. */
export async function fetchMyHighlightCoverage(
  userId: string
): Promise<Set<string>> {
  const { data } = await supabase
    .from("whisper_story_highlight_items")
    .select("image_url")
    .eq("user_id", userId)
    .limit(500);
  return new Set(
    (((data as { image_url: string }[] | null) ?? []).map((r) => r.image_url))
  );
}

/** Minimal story payload the quick-save flow copies into a highlight. */
export interface HighlightSaveStory {
  image_url: string;
  caption?: string | null;
  music_title?: string | null;
  music_artist?: string | null;
  /** Sticker JSON — kept so saved highlights stay interactive-looking. */
  metadata?: string | null;
  music_url?: string | null;
  music_artwork?: string | null;
}

/** Adds one story to a highlight. Tries the full-fidelity payload first
 *  (stickers + playable music — requires story-highlights-upgrade.sql) and
 *  falls back to the legacy flat columns when the upgrade hasn't run. */
export async function addStoryToHighlight(
  highlightId: string,
  userId: string,
  story: HighlightSaveStory
): Promise<void> {
  const { count } = await supabase
    .from("whisper_story_highlight_items")
    .select("id", { count: "exact", head: true })
    .eq("highlight_id", highlightId);
  const position = count ?? 0;
  const base = {
    highlight_id: highlightId,
    user_id: userId,
    image_url: story.image_url,
    caption: story.caption ?? null,
    music_title: story.music_title ?? null,
    music_artist: story.music_artist ?? null,
    position,
  };
  const { error } = await supabase
    .from("whisper_story_highlight_items")
    .insert({
      ...base,
      metadata: story.metadata ?? null,
      music_url: story.music_url ?? null,
      music_artwork: story.music_artwork ?? null,
    });
  if (error) {
    const retry = await supabase
      .from("whisper_story_highlight_items")
      .insert(base);
    if (retry.error) throw new Error("Couldn't save to highlight.");
  }
  await supabase
    .from("whisper_story_highlights")
    .update({ updated_at: new Date().toISOString() })
    .eq("id", highlightId);
}

/** Creates a brand-new highlight album seeded with the given story — the
 *  inline "name it, done" path in the story viewer. */
export async function createHighlightWithStory(
  userId: string,
  title: string,
  story: HighlightSaveStory
): Promise<StoryHighlight> {
  const trimmed = title.trim();
  if (!trimmed) throw new Error("Name the highlight first.");
  const { data, error } = await supabase
    .from("whisper_story_highlights")
    .insert({ user_id: userId, title: trimmed, cover_url: story.image_url })
    .select("id, user_id, title, cover_url, updated_at")
    .limit(1);
  if (error || !data?.[0]) throw new Error("Couldn't create that highlight.");
  const album = data[0] as StoryHighlight;
  await addStoryToHighlight(album.id, userId, story);
  return album;
}
