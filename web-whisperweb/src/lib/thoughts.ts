import { supabase } from "@/lib/supabase";

/**
 * Web port of the iOS `WhisperThoughtService`. Reads/writes the shared
 * `whisper_thoughts` table so a user's IG-Notes "What's on your mind?"
 * bubble follows them across iOS and web. The text column on the wire is
 * named `body` (the iOS service maps `text` → `body`).
 */

export type ThoughtStyle = "plain" | "location" | "music";

export interface WhisperThought {
  user_id: string;
  text: string;
  posted_at: string | null;
  style: ThoughtStyle;
  accent: string;
  emoji: string;
  color_hex: string;
}

interface ThoughtRow {
  user_id: string;
  body: string | null;
  posted_at: string | null;
  style: string | null;
  accent: string | null;
  emoji: string | null;
  color_hex: string | null;
}

/** A thought is "active" for 24h after it was posted. */
export function isThoughtActive(t: WhisperThought | null): boolean {
  if (!t) return false;
  if (!t.text.trim()) return false;
  if (!t.posted_at) return false;
  const age = Date.now() - new Date(t.posted_at).getTime();
  return age < 24 * 3600 * 1000;
}

function rowToThought(r: ThoughtRow): WhisperThought {
  const style = (r.style ?? "plain") as ThoughtStyle;
  return {
    user_id: r.user_id,
    text: r.body ?? "",
    posted_at: r.posted_at,
    style: style === "location" || style === "music" ? style : "plain",
    accent: r.accent ?? "",
    emoji: r.emoji ?? "",
    color_hex: r.color_hex ?? "",
  };
}

/** Fetch active thoughts for a set of user ids, keyed by user id. */
export async function fetchThoughts(
  userIds: string[]
): Promise<Record<string, WhisperThought>> {
  const unique = Array.from(new Set(userIds.filter(Boolean)));
  if (unique.length === 0) return {};
  const { data } = await supabase
    .from("whisper_thoughts")
    .select("user_id, body, posted_at, style, accent, emoji, color_hex")
    .in("user_id", unique);
  const map: Record<string, WhisperThought> = {};
  for (const r of (data as ThoughtRow[] | null) ?? []) {
    const t = rowToThought(r);
    if (isThoughtActive(t)) map[t.user_id] = t;
  }
  return map;
}

/** Fetch a single user's current thought (active or not). */
export async function fetchMyThought(
  userId: string
): Promise<WhisperThought | null> {
  if (!userId) return null;
  const { data } = await supabase
    .from("whisper_thoughts")
    .select("user_id, body, posted_at, style, accent, emoji, color_hex")
    .eq("user_id", userId)
    .limit(1)
    .maybeSingle();
  const row = data as ThoughtRow | null;
  return row ? rowToThought(row) : null;
}

const MAX_LENGTH = 60;

/** Post / update the current user's thought. Matches the iOS upsert shape. */
export async function postThought(input: {
  userId: string;
  text: string;
  style?: ThoughtStyle;
  accent?: string;
  emoji?: string;
  colorHex?: string;
}): Promise<void> {
  const body = input.text.trim().slice(0, MAX_LENGTH);
  const { error } = await supabase.from("whisper_thoughts").upsert(
    {
      user_id: input.userId,
      body,
      posted_at: new Date().toISOString(),
      style: input.style ?? "plain",
      accent: (input.accent ?? "").slice(0, 80),
      emoji: input.emoji ?? "",
      color_hex: input.colorHex ?? "",
    },
    { onConflict: "user_id" }
  );
  if (error) throw error;
}

/** Clear the current user's thought. */
export async function clearThought(userId: string): Promise<void> {
  await supabase.from("whisper_thoughts").delete().eq("user_id", userId);
}
