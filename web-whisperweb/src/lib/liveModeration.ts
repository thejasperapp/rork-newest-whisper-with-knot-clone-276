/**
 * Live moderation — the Twitch-style trust layer for Whisper Live:
 *
 *   • Channel-level MODS and BANS (per host — a mod moderates every live
 *     that host runs, a ban keeps someone out of the whole channel).
 *   • Per-room TIMEOUTS (short cool-downs).
 *   • Per-room BANNED WORDS (host-set list checked before every send).
 *   • GO-LIVE ALERTS fanned out to followers when a host starts a live.
 *
 * Tables come from supabase/live-v2.sql; every call degrades gracefully
 * (`missing: true`) until the migration runs.
 */
import { supabase } from "@/lib/supabase";

export interface LiveModerator {
  host_id: string;
  mod_user_id: string;
  mod_username: string;
  created_at: string;
}

export interface LiveBan {
  host_id: string;
  banned_user_id: string;
  banned_username: string;
  created_at: string;
}

export interface LiveTimeoutRow {
  room_id: string;
  user_id: string;
  username: string;
  until: string;
  created_at: string;
}

export interface LiveModerationState {
  mods: LiveModerator[];
  bans: LiveBan[];
  timeouts: LiveTimeoutRow[];
  bannedWords: string[];
  /** True when supabase/live-v2.sql hasn't been applied yet. */
  missing: boolean;
}

export const EMPTY_MODERATION: LiveModerationState = {
  mods: [],
  bans: [],
  timeouts: [],
  bannedWords: [],
  missing: false,
};

function isMissingTable(error: { code?: string } | null): boolean {
  return error?.code === "42P01";
}

/** Everything the room needs to enforce + render moderation, in one call. */
export async function fetchLiveModeration(
  hostId: string,
  roomId: string
): Promise<LiveModerationState> {
  const [mods, bans, timeouts, words] = await Promise.all([
    supabase
      .from("whisper_live_moderators")
      .select("*")
      .eq("host_id", hostId),
    supabase.from("whisper_live_bans").select("*").eq("host_id", hostId),
    supabase
      .from("whisper_live_timeouts")
      .select("*")
      .eq("room_id", roomId)
      .gt("until", new Date().toISOString()),
    supabase
      .from("whisper_live_rooms")
      .select("banned_words")
      .eq("id", roomId)
      .maybeSingle(),
  ]);
  const missing =
    isMissingTable(mods.error) ||
    isMissingTable(bans.error) ||
    isMissingTable(timeouts.error);
  const bannedWords = Array.isArray(
    (words.data as { banned_words?: unknown } | null)?.banned_words
  )
    ? ((words.data as { banned_words: string[] }).banned_words ?? [])
    : [];
  return {
    mods: (mods.data as LiveModerator[] | null) ?? [],
    bans: (bans.data as LiveBan[] | null) ?? [],
    timeouts: (timeouts.data as LiveTimeoutRow[] | null) ?? [],
    bannedWords,
    missing,
  };
}

/** @username → their account (case-insensitive). */
export async function resolveUserByUsername(
  username: string
): Promise<{ userId: string; username: string } | null> {
  const uname = username.trim().replace(/^@/, "");
  if (!uname) return null;
  const { data } = await supabase
    .from("whisper_profiles")
    .select("user_id, username")
    .ilike("username", uname)
    .limit(1);
  const row = ((data as { user_id: string; username: string }[] | null) ?? [])[0];
  return row ? { userId: row.user_id, username: row.username } : null;
}

/** Host adds a channel mod by @username. Returns an error string or null. */
export async function addModerator(
  hostId: string,
  username: string
): Promise<string | null> {
  const target = await resolveUserByUsername(username);
  if (!target) return "No Whisper account with that username.";
  if (target.userId === hostId) return "You're the host — already all-powerful.";
  const { error } = await supabase.from("whisper_live_moderators").upsert(
    {
      host_id: hostId,
      mod_user_id: target.userId,
      mod_username: target.username,
    },
    { onConflict: "host_id,mod_user_id" }
  );
  if (error) {
    return isMissingTable(error)
      ? "Run supabase/live-v2.sql to unlock moderation."
      : "Couldn't add that mod. Try again.";
  }
  return null;
}

export async function removeModerator(
  hostId: string,
  modUserId: string
): Promise<void> {
  await supabase
    .from("whisper_live_moderators")
    .delete()
    .eq("host_id", hostId)
    .eq("mod_user_id", modUserId);
}

/** Channel ban (host or mods). Returns an error string or null. */
export async function banUser(
  hostId: string,
  userId: string,
  username: string
): Promise<string | null> {
  const { error } = await supabase.from("whisper_live_bans").upsert(
    {
      host_id: hostId,
      banned_user_id: userId,
      banned_username: username,
    },
    { onConflict: "host_id,banned_user_id" }
  );
  if (error) {
    return isMissingTable(error)
      ? "Run supabase/live-v2.sql to unlock moderation."
      : "Couldn't ban that viewer. Try again.";
  }
  return null;
}

export async function unbanUser(
  hostId: string,
  userId: string
): Promise<void> {
  await supabase
    .from("whisper_live_bans")
    .delete()
    .eq("host_id", hostId)
    .eq("banned_user_id", userId);
}

/** Room timeout (host or mods). Returns an error string or null. */
export async function timeoutUser(
  roomId: string,
  userId: string,
  username: string,
  minutes: number
): Promise<string | null> {
  const until = new Date(Date.now() + minutes * 60_000).toISOString();
  const { error } = await supabase.from("whisper_live_timeouts").upsert(
    { room_id: roomId, user_id: userId, username, until },
    { onConflict: "room_id,user_id" }
  );
  if (error) {
    return isMissingTable(error)
      ? "Run supabase/live-v2.sql to unlock moderation."
      : "Couldn't time that viewer out. Try again.";
  }
  return null;
}

/** Host saves the room's banned-words list. Returns an error string or null. */
export async function setBannedWords(
  roomId: string,
  words: string[]
): Promise<string | null> {
  const clean = Array.from(
    new Set(
      words
        .map((w) => w.trim().toLowerCase())
        .filter((w) => w.length > 1 && w.length <= 40)
    )
  ).slice(0, 50);
  const { error } = await supabase
    .from("whisper_live_rooms")
    .update({ banned_words: clean })
    .eq("id", roomId);
  if (error) {
    return "Banned words need supabase/live-v2.sql — run it once and retry.";
  }
  return null;
}

/** The first banned word a message trips, or null when it's clean. */
export function findBannedWord(
  text: string,
  words: string[]
): string | null {
  if (words.length === 0) return null;
  const lower = text.toLowerCase();
  for (const word of words) {
    if (word && lower.includes(word)) return word;
  }
  return null;
}

/**
 * Fan out a "went live" alert to the host's followers (capped, chunked,
 * best-effort — a failure never blocks going live).
 */
export async function notifyFollowersLive(input: {
  hostId: string;
  hostUsername: string;
  roomId: string;
  roomName: string;
}): Promise<void> {
  try {
    const { data } = await supabase
      .from("whisper_follows")
      .select("follower_id")
      .eq("followee_id", input.hostId)
      .limit(400);
    const followers = ((data as { follower_id: string }[] | null) ?? [])
      .map((r) => r.follower_id)
      .filter((fid) => fid && fid !== input.hostId);
    if (followers.length === 0) return;
    const rows = followers.map((fid) => ({
      host_id: input.hostId,
      host_username: input.hostUsername,
      room_id: input.roomId,
      room_name: input.roomName,
      follower_id: fid,
    }));
    for (let i = 0; i < rows.length; i += 100) {
      const chunk = rows.slice(i, i + 100);
      const { error } = await supabase
        .from("whisper_live_alerts")
        .insert(chunk);
      if (error) return; // table missing or RLS — quietly skip the rest
    }
  } catch {
    /* never block going live */
  }
}
