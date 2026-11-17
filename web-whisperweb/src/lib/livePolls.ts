/**
 * Live chat polls — create, vote, close, and subscribe to realtime updates.
 */

import { supabase } from "@/lib/supabase";

export interface LivePoll {
  id: string;
  room_id: string;
  question: string;
  options: string[];
  creator_id: string;
  creator_username: string;
  created_at: string;
  closed_at: string | null;
}

export interface LivePollVote {
  id: string;
  poll_id: string;
  user_id: string;
  option_index: number;
  voted_at: string;
}

/** Create a poll in a live room. */
export async function createPoll(input: {
  roomId: string;
  question: string;
  options: string[];
  creatorId: string;
  creatorUsername: string;
}): Promise<string | null> {
  const { data, error } = await supabase
    .from("whisper_live_chat_polls")
    .insert({
      room_id: input.roomId,
      question: input.question.trim(),
      options: input.options.filter((o) => o.trim()),
      creator_id: input.creatorId,
      creator_username: input.creatorUsername,
    })
    .select("id")
    .single();
  if (error) {
    console.warn("createPoll failed:", error.message);
    return null;
  }
  return data?.id ?? null;
}

/** Close a poll (creator only). */
export async function closePoll(pollId: string): Promise<void> {
  const { error } = await supabase
    .from("whisper_live_chat_polls")
    .update({ closed_at: new Date().toISOString() })
    .eq("id", pollId);
  if (error) throw error;
}

/** Vote on a poll. */
export async function votePoll(pollId: string, optionIndex: number): Promise<void> {
  const { data: userData } = await supabase.auth.getUser();
  const userId = userData.user?.id;
  if (!userId) throw new Error("Sign in to vote");

  const { error } = await supabase
    .from("whisper_live_chat_poll_votes")
    .upsert(
      { poll_id: pollId, user_id: userId, option_index: optionIndex },
      { onConflict: "poll_id,user_id" }
    );
  if (error) throw error;
}

/** Fetch all polls for a room. */
export async function fetchPolls(roomId: string): Promise<LivePoll[]> {
  const { data, error } = await supabase
    .from("whisper_live_chat_polls")
    .select("*")
    .eq("room_id", roomId)
    .order("created_at", { ascending: false });
  if (error) {
    console.warn("fetchPolls failed:", error.message);
    return [];
  }
  return (data as LivePoll[]) ?? [];
}

/** Fetch vote counts per option for a poll. Returns array of counts indexed by option_index. */
export async function fetchPollVoteCounts(
  pollIds: string[]
): Promise<Record<string, number[]>> {
  if (pollIds.length === 0) return {};
  const { data, error } = await supabase
    .from("whisper_live_chat_poll_votes")
    .select("poll_id, option_index")
    .in("poll_id", pollIds);
  if (error) {
    console.warn("fetchPollVoteCounts failed:", error.message);
    return {};
  }
  const result: Record<string, number[]> = {};
  for (const vote of (data as { poll_id: string; option_index: number }[]) ?? []) {
    if (!result[vote.poll_id]) result[vote.poll_id] = [];
    result[vote.poll_id][vote.option_index] =
      (result[vote.poll_id][vote.option_index] ?? 0) + 1;
  }
  // Fill sparse holes with 0 — unvoted options used to be `undefined`,
  // which made downstream Math.max return NaN.
  for (const key of Object.keys(result)) {
    result[key] = Array.from(result[key], (v) => v ?? 0);
  }
  return result;
}

/** Fetch the current user's votes for a set of polls. Returns poll_id → option_index. */
export async function fetchMyVotes(
  pollIds: string[]
): Promise<Record<string, number>> {
  if (pollIds.length === 0) return {};
  const { data: userData } = await supabase.auth.getUser();
  const userId = userData.user?.id;
  if (!userId) return {};
  const { data, error } = await supabase
    .from("whisper_live_chat_poll_votes")
    .select("poll_id, option_index")
    .eq("user_id", userId)
    .in("poll_id", pollIds);
  if (error) return {};
  const result: Record<string, number> = {};
  for (const vote of (data as { poll_id: string; option_index: number }[]) ?? []) {
    result[vote.poll_id] = vote.option_index;
  }
  return result;
}

/** Subscribe to realtime poll + vote changes for a room. Returns unsubscribe. */
export function subscribeToPolls(
  roomId: string,
  onPollChange: () => void,
  onVoteChange: () => void
): () => void {
  const channel = supabase
    .channel(`live-polls:${roomId}`)
    .on(
      "postgres_changes",
      { event: "*", schema: "public", table: "whisper_live_chat_polls", filter: `room_id=eq.${roomId}` },
      () => onPollChange()
    )
    .on(
      "postgres_changes",
      { event: "*", schema: "public", table: "whisper_live_chat_poll_votes" },
      () => onVoteChange()
    )
    .subscribe();
  return () => { void supabase.removeChannel(channel); };
}
