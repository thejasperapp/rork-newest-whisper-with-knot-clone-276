import { z } from "zod";
import type { WhisperStory } from "./types";
import { groupThemeSession } from "./groupThemeSession";
import { supabaseUrl, supabaseAnonKey } from "./supabase";
const nullableText = z.string().nullable();
const storySchema = z.object({ id: z.string().uuid(), user_id: z.string().uuid(), username: z.string(), image_url: z.string().url(), caption: nullableText, created_at: nullableText, expires_at: z.string(), metadata: nullableText, video_url: nullableText.optional(), music_url: nullableText, music_title: nullableText, music_artist: nullableText, music_artwork: nullableText });
/** Compatible with native ID-only shares; neither text nor JSON can supply preview media. */
export function sharedStoryID(body: unknown): string | null {
  if (typeof body !== "string") return null;
  return /^::whisper-story(?:tag)?-v1::([a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12})$/i.exec(body.trim())?.[1].toLowerCase() ?? null;
}
/** The authenticated resolver rechecks expiry, profiles, follows and bilateral blocks. */
export async function loadSharedStory(accountID: string, storyID: string, signal: AbortSignal): Promise<WhisperStory> {
  const session = await groupThemeSession(accountID);
  try {
    const result = await fetch(`${supabaseUrl}/rest/v1/rpc/whisper_story_card`, { method: "POST", redirect: "error", cache: "no-store", signal: AbortSignal.any([signal, session.signal, AbortSignal.timeout(15_000)]), headers: { apikey: supabaseAnonKey, Authorization: `Bearer ${session.token}`, "Content-Type": "application/json" }, body: JSON.stringify({ p_story_id: storyID }) });
    session.check();
    if (!result.ok) throw new Error("This story is unavailable or access has changed.");
    const parsed = storySchema.safeParse(await result.json()); session.check();
    if (!parsed.success || parsed.data.id.toLowerCase() !== storyID.toLowerCase() || !(Date.parse(parsed.data.expires_at) > Date.now())) throw new Error("This story is unavailable or expired.");
    return parsed.data as WhisperStory;
  } finally { session.dispose(); }
}
