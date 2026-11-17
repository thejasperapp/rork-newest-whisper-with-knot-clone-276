import { supabase } from "@/lib/supabase";

/**
 * Web port of the iOS `WhisperStoryResponseService` + `WhisperStoryViewService`.
 * Captures poll votes, slider ratings, and question replies on a story, plus
 * view receipts so the owner can see who watched each story.
 */

export interface StoryViewRow {
  story_id: string;
  viewer_id: string;
  viewer_username: string;
  story_owner_id: string;
  created_at: string | null;
}

/** Record a response (poll/slider/question) to someone else's story. */
export async function recordStoryResponse(input: {
  storyId: string;
  storyOwnerId: string;
  responderId: string;
  responderUsername: string;
  kind: "poll" | "slider" | "question" | "like" | "reaction";
  prompt: string;
  response: string;
}): Promise<void> {
  if (input.storyOwnerId.toLowerCase() === input.responderId.toLowerCase()) return;
  const { error } = await supabase.from("whisper_story_responses").insert({
    story_id: input.storyId,
    story_owner_id: input.storyOwnerId,
    responder_id: input.responderId,
    responder_username: input.responderUsername,
    kind: input.kind,
    prompt: input.prompt,
    response: input.response,
  });
  if (error) {
    console.error("recordStoryResponse failed:", error.message);
    throw new Error(error.message);
  }
}

/** Live vote count per option for a poll, via the SECURITY DEFINER RPC. */
export async function fetchPollTally(
  storyId: string,
  prompt: string
): Promise<Record<string, number>> {
  const { data, error } = await supabase.rpc("whisper_poll_tally", {
    p_story_id: storyId,
    p_prompt: prompt,
  });
  if (error) {
    console.error("fetchPollTally failed:", error.message);
    return {};
  }
  const rows = (data as { option_text: string; vote_count: number }[] | null) ?? [];
  const map: Record<string, number> = {};
  for (const r of rows) map[r.option_text] = r.vote_count;
  return map;
}

/** Record a view receipt. No-op when viewing your own story. */
export async function recordStoryView(input: {
  storyId: string;
  viewerId: string;
  viewerUsername: string;
  storyOwnerId: string;
}): Promise<void> {
  if (input.storyOwnerId.toLowerCase() === input.viewerId.toLowerCase()) return;
  await supabase.from("whisper_story_views").upsert(
    {
      story_id: input.storyId,
      viewer_id: input.viewerId,
      viewer_username: input.viewerUsername,
      story_owner_id: input.storyOwnerId,
    },
    { onConflict: "story_id,viewer_id" }
  );
}

/** Fetch the viewer list for a set of the current user's stories. */
export async function fetchStoryViewers(
  storyIds: string[]
): Promise<Record<string, StoryViewRow[]>> {
  if (storyIds.length === 0) return {};
  const { data } = await supabase
    .from("whisper_story_views")
    .select("*")
    .in("story_id", storyIds)
    .order("created_at", { ascending: false })
    .limit(1000);
  const grouped: Record<string, StoryViewRow[]> = {};
  for (const r of (data as StoryViewRow[] | null) ?? []) {
    (grouped[r.story_id] ??= []).push(r);
  }
  return grouped;
}
