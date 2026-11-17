import { supabase } from "@/lib/supabase";
import type { ThoughtStyle, WhisperThought } from "@/lib/thoughts";

/**
 * Web port of the iOS `WhisperThoughtRepliesService`. Replies to a user's
 * "What's on your mind?" thought live in their own community room (the
 * `whisper_thought_replies` table) instead of cluttering DMs — exactly like
 * the iOS app. The owner and every replier share one chat keyed by the
 * thought owner's user id.
 */

export interface ThoughtReplyRow {
  id: string;
  thought_user_id: string;
  replier_user_id: string;
  replier_username: string;
  replier_avatar_url: string | null;
  body: string;
  thought_text: string | null;
  thought_style: string | null;
  thought_accent: string | null;
  thought_emoji: string | null;
  thought_color_hex: string | null;
  thought_owner_username: string | null;
  created_at: string | null;
  read_at: string | null;
}

const SELECT =
  "id, thought_user_id, replier_user_id, replier_username, replier_avatar_url, body, thought_text, thought_style, thought_accent, thought_emoji, thought_color_hex, thought_owner_username, created_at, read_at";

/** Snapshot of a thought captured when a reply is sent. */
export interface ThoughtSnapshot {
  text: string;
  style: ThoughtStyle;
  accent: string;
  emoji: string;
  colorHex: string;
}

export function snapshotFromThought(
  t: WhisperThought | null | undefined
): ThoughtSnapshot {
  return {
    text: t?.text ?? "",
    style: t?.style ?? "plain",
    accent: t?.accent ?? "",
    emoji: t?.emoji ?? "",
    colorHex: t?.color_hex ?? "",
  };
}

/** Derive a pinned-thought snapshot from the newest row in a chat. */
export function snapshotFromRow(
  row: ThoughtReplyRow | undefined
): ThoughtSnapshot | null {
  if (!row || !row.thought_text) return null;
  const style = (row.thought_style ?? "plain") as ThoughtStyle;
  return {
    text: row.thought_text,
    style: style === "location" || style === "music" ? style : "plain",
    accent: row.thought_accent ?? "",
    emoji: row.thought_emoji ?? "",
    colorHex: row.thought_color_hex ?? "",
  };
}

/** Fetch the chat for a given thought owner, oldest → newest (chat order). */
export async function fetchThoughtChat(
  ownerUserId: string
): Promise<ThoughtReplyRow[]> {
  if (!ownerUserId) return [];
  const { data, error } = await supabase
    .from("whisper_thought_replies")
    .select(SELECT)
    .eq("thought_user_id", ownerUserId)
    .order("created_at", { ascending: true })
    .limit(200);
  if (error) throw error;
  return (data as ThoughtReplyRow[] | null) ?? [];
}

/** Count of unread replies addressed to me (drives the unread dot). */
export async function fetchMyReplyMeta(
  userId: string
): Promise<{ rows: ThoughtReplyRow[]; unread: number }> {
  if (!userId) return { rows: [], unread: 0 };
  const { data } = await supabase
    .from("whisper_thought_replies")
    .select(SELECT)
    .eq("thought_user_id", userId)
    .order("created_at", { ascending: false })
    .limit(100);
  const rows = (data as ThoughtReplyRow[] | null) ?? [];
  const unread = rows.filter((r) => !r.read_at).length;
  return { rows, unread };
}

interface SendReplyInput {
  ownerUserId: string;
  ownerUsername: string;
  meUserId: string;
  meUsername: string;
  meAvatarUrl: string | null;
  thought: ThoughtSnapshot | null;
  body: string;
}

/** Send a reply into a thought owner's community room. */
export async function sendThoughtReply(
  input: SendReplyInput
): Promise<ThoughtReplyRow | null> {
  const trimmed = input.body.trim();
  if (!trimmed) return null;
  const t = input.thought;
  const payload = {
    thought_user_id: input.ownerUserId.toLowerCase(),
    replier_user_id: input.meUserId.toLowerCase(),
    replier_username: input.meUsername,
    replier_avatar_url: input.meAvatarUrl,
    body: trimmed.slice(0, 280),
    thought_text: t?.text ?? "",
    thought_style: t?.style || null,
    thought_accent: t?.accent || null,
    thought_emoji: t?.emoji || null,
    thought_color_hex: t?.colorHex || null,
    thought_owner_username: input.ownerUsername,
  };
  const { data, error } = await supabase
    .from("whisper_thought_replies")
    .insert(payload)
    .select(SELECT)
    .maybeSingle();
  if (error) throw error;
  return (data as ThoughtReplyRow | null) ?? null;
}

/** Mark a set of replies as read. */
export async function markRepliesRead(ids: string[]): Promise<void> {
  const real = ids.filter((id) => !id.startsWith("local-"));
  if (real.length === 0) return;
  await supabase
    .from("whisper_thought_replies")
    .update({ read_at: new Date().toISOString() })
    .in("id", real);
}
