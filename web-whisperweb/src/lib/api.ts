import { supabase } from "@/lib/supabase";
import { invalidateFeedSnapshot } from "@/lib/feedPaging";
import type { BadgeFlags } from "@/lib/badges";
import { waveSharedToFeed } from "@/lib/postMeta";
import type {
  WhisperActivity,
  WhisperComment,
  WhisperConversation,
  WhisperCreatorStats,
  WhisperFollowUser,
  WhisperLiarBadge,
  WhisperMessage,
  WhisperPost,
  WhisperProfile,
  WhisperStory,
} from "@/lib/types";

/** Batch-fetch profiles for a set of user ids, returned as a lookup map. */
export async function fetchProfilesByIds(
  ids: string[],
  options?: { signal?: AbortSignal; requireSuccess?: boolean }
): Promise<Record<string, WhisperProfile>> {
  const unique = Array.from(new Set(ids.filter(Boolean)));
  if (unique.length === 0) return {};
  const request = supabase.from("whisper_profiles").select("*").in("user_id", unique);
  const { data, error } = await (options?.signal ? request.abortSignal(options.signal) : request);
  if (error && options?.requireSuccess) throw new Error("People couldn't refresh. Please try again.");
  const map: Record<string, WhisperProfile> = {};
  for (const row of (data as WhisperProfile[] | null) ?? []) {
    map[row.user_id] = row;
  }
  return map;
}

/**
 * Batch-fetch trust/identity badge flags from the `profiles` table for a set of
 * user ids. Returns a lookup keyed by user id. Mirrors the columns the iOS
 * `WhisperSafetyService` reads. Best-effort — if the table or columns aren't
 * available, badges simply don't render rather than crashing the UI.
 */
export async function fetchBadgeFlags(
  userIds: string[]
): Promise<Record<string, BadgeFlags>> {
  const unique = Array.from(new Set(userIds.filter(Boolean)));
  if (unique.length === 0) return {};
  const map: Record<string, BadgeFlags> = {};

  // 1. Safety + reputation flags from the auth `profiles` table.
  //    We intentionally do NOT select `is_director` here — that column may
  //    not exist on `profiles` yet, and a single missing column makes
  //    PostgREST reject the whole query (silently killing every trust
  //    badge, not just director). Director is fetched separately from
  //    `whisper_profiles` below, mirroring iOS `WhisperDirectorService`.
  try {
    const { data } = await supabase
      .from("profiles")
      .select(
        "id,age_band,is_adult_attested,is_dm_restricted,created_at,helpful_report_count,is_trusted_member"
      )
      .in("id", unique);
    type Row = {
      id: string;
      age_band: string | null;
      is_adult_attested: boolean | null;
      is_dm_restricted: boolean | null;
      created_at: string | null;
      helpful_report_count: number | null;
      is_trusted_member: boolean | null;
    };
    for (const r of (data as Row[] | null) ?? []) {
      map[r.id] = {
        ageBand: r.age_band ?? null,
        isAdultAttested: !!r.is_adult_attested,
        isDmRestricted: !!r.is_dm_restricted,
        createdAt: r.created_at ?? null,
        helpfulReportCount: r.helpful_report_count ?? 0,
        isTrustedMember: !!r.is_trusted_member,
        isDirector: false,
        isBlogger: false,
        isAthlete: false,
      };
    }
  } catch {
    // profiles table unavailable — seed empty entries so director/blogger
    // can still resolve from whisper_profiles below.
    for (const id of unique) {
      map[id] = {
        ageBand: null,
        isAdultAttested: false,
        isDmRestricted: false,
        createdAt: null,
        helpfulReportCount: 0,
        isTrustedMember: false,
        isDirector: false,
        isBlogger: false,
        isAthlete: false,
      };
    }
  }

  // 2. Director + blogger flags from `whisper_profiles` — the same table
  //    iOS reads via WhisperDirectorService. Independent of the `profiles`
  //    schema so a missing column there never blocks these badges.
  try {
    const { data: roleRows } = await supabase
      .from("whisper_profiles")
      .select("user_id,is_director,is_blogger,is_athlete")
      .in("user_id", unique)
      .or("is_director.eq.true,is_blogger.eq.true,is_athlete.eq.true");
    type RoleRow = {
      user_id: string;
      is_director: boolean | null;
      is_blogger: boolean | null;
      is_athlete: boolean | null;
    };
    for (const r of (roleRows as RoleRow[] | null) ?? []) {
      const existing = map[r.user_id];
      const isDir = !!r.is_director;
      const isBlog = !!r.is_blogger;
      const isAth = !!r.is_athlete;
      if (existing) {
        if (isDir) existing.isDirector = true;
        if (isBlog) existing.isBlogger = true;
        if (isAth) existing.isAthlete = true;
      } else {
        map[r.user_id] = {
          ageBand: null,
          isAdultAttested: false,
          isDmRestricted: false,
          createdAt: null,
          helpfulReportCount: 0,
          isTrustedMember: false,
          isDirector: isDir,
          isBlogger: isBlog,
          isAthlete: isAth,
        };
      }
    }
  } catch {
    // whisper_profiles flags unavailable — director/blogger/athlete skipped.
  }
  return map;
}

/**
 * The feed's candidate window. A wave (`is_reel`) rides it ONLY when its
 * author flipped "Also share to feed" (the `feed` flag on the caption meta
 * wire) — it then renders as the Instagram reel-in-feed card. Every other
 * wave stays in the Waves format — the player, the profile Waves grid, the
 * Discover mosaic — excluded at the source instead of trusting every caller
 * to filter (the iOS feed applies the same rule).
 */
export async function fetchFeed(limit = 60): Promise<WhisperPost[]> {
  const { data, error } = await supabase
    .from("whisper_posts")
    .select("*")
    // The meta line is JSON at the head of the caption; the ilike is a cheap
    // pre-filter ("feed" … ":true") and the parse below is the real gate.
    .or("is_reel.is.null,is_reel.eq.false,caption.ilike.*feed*:true*")
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return ((data as WhisperPost[] | null) ?? []).filter(
    (p) => !p.is_reel || waveSharedToFeed(p.caption)
  );
}

export async function fetchPostsByUser(userId: string): Promise<WhisperPost[]> {
  const { data, error } = await supabase
    .from("whisper_posts")
    .select("*")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(120);
  if (error) throw error;
  return (data as WhisperPost[] | null) ?? [];
}

/** Batch-fetch posts by id (saved posts, activity deep links). Preserves the input order. */
export async function fetchPostsByIds(ids: string[], options?: { signal?: AbortSignal; requireSuccess?: boolean }): Promise<WhisperPost[]> {
  const unique = Array.from(new Set(ids.filter(Boolean)));
  if (unique.length === 0) return [];
  const request = supabase.from("whisper_posts").select("*").in("id", unique);
  const { data, error } = await (options?.signal ? request.abortSignal(options.signal) : request);
  if (error && options?.requireSuccess) throw new Error("Saved posts couldn’t refresh. Please try again.");
  const rows = (data as WhisperPost[] | null) ?? [];
  const order = new Map(unique.map((id, i) => [id, i]));
  return rows.sort(
    (a, b) => (order.get(a.id) ?? 0) - (order.get(b.id) ?? 0)
  );
}

/** Verified-perk profile banner (cover photo) — mirrors iOS `WhisperVerifiedPerksKit`. */
export interface WhisperProfileBanner {
  banner_url: string | null;
  banner_offset_y: number | null;
  accent_color: string | null;
}

export async function fetchProfileBanner(
  userId: string
): Promise<WhisperProfileBanner | null> {
  try {
    const { data } = await supabase
      .from("whisper_profiles")
      .select("banner_url,banner_offset_y,accent_color")
      .eq("user_id", userId)
      .limit(1)
      .maybeSingle();
    return (data as WhisperProfileBanner | null) ?? null;
  } catch {
    return null;
  }
}

/** Batch-fetch real like counts from the engagement table (source of truth).
 *  Used when whisper_posts.likes_count is NULL or out of sync. */
export async function fetchLikeCounts(
  postIds: string[]
): Promise<Record<string, number>> {
  const unique = Array.from(new Set(postIds.filter(Boolean)));
  if (unique.length === 0) return {};
  try {
    const { data } = await supabase
      .from("whisper_post_likes")
      .select("post_id")
      .in("post_id", unique);
    const counts: Record<string, number> = {};
    for (const row of (data as { post_id: string }[] | null) ?? []) {
      counts[row.post_id] = (counts[row.post_id] ?? 0) + 1;
    }
    return counts;
  } catch {
    return {};
  }
}

/** Batch-fetch real comment counts from the engagement table (source of truth). */
export async function fetchCommentCounts(
  postIds: string[]
): Promise<Record<string, number>> {
  const unique = Array.from(new Set(postIds.filter(Boolean)));
  if (unique.length === 0) return {};
  try {
    const { data } = await supabase
      .from("whisper_post_comments")
      .select("post_id")
      .in("post_id", unique);
    const counts: Record<string, number> = {};
    for (const row of (data as { post_id: string }[] | null) ?? []) {
      counts[row.post_id] = (counts[row.post_id] ?? 0) + 1;
    }
    return counts;
  } catch {
    return {};
  }
}

export async function fetchMyLikedPostIds(userId: string): Promise<string[]> {
  const { data } = await supabase
    .from("whisper_post_likes")
    .select("post_id")
    .eq("user_id", userId);
  return ((data as { post_id: string }[] | null) ?? []).map((r) => r.post_id);
}

export async function toggleLike(
  postId: string,
  userId: string,
  liked: boolean
): Promise<void> {
  if (liked) {
    const { error } = await supabase
      .from("whisper_post_likes")
      .delete()
      .eq("post_id", postId)
      .eq("user_id", userId);
    if (error) throw error;
  } else {
    // Use upsert to avoid errors if a like row already exists (e.g. from a
    // race condition or a previous optimistic update that didn't roll back).
    const { error } = await supabase
      .from("whisper_post_likes")
      .upsert(
        { post_id: postId, user_id: userId },
        { onConflict: "post_id,user_id" }
      );
    if (error) throw error;
  }
}

/** One row in the "Liked by X and others" facepile under grid posts. */
export interface PostLikerPreview {
  userId: string;
  username: string;
  avatarUrl: string | null;
}

/** First few likers of a post (newest first) joined with their profiles —
 *  powers the Instagram "Liked by X and others" line on grid post cards. */
export async function fetchPostLikersPreview(
  postId: string,
  limit = 3
): Promise<PostLikerPreview[]> {
  try {
    const { data } = await supabase
      .from("whisper_post_likes")
      .select("user_id")
      .eq("post_id", postId)
      .order("created_at", { ascending: false })
      .limit(limit);
    const ids = ((data as { user_id: string }[] | null) ?? []).map(
      (r) => r.user_id
    );
    if (ids.length === 0) return [];
    const profiles = await fetchProfilesByIds(ids);
    return ids.map((id) => ({
      userId: id,
      username: profiles[id]?.username ?? "member",
      avatarUrl: profiles[id]?.profile_image_url ?? null,
    }));
  } catch {
    return [];
  }
}

/** Post IDs the user has reposted. */
export async function fetchMyRepostIds(userId: string): Promise<string[]> {
  const { data } = await supabase
    .from("whisper_reposts")
    .select("post_id")
    .eq("user_id", userId);
  return ((data as { post_id: string }[] | null) ?? []).map((r) => r.post_id);
}

/** Posts the given user has reposted, hydrated as full post rows (newest first). */
export async function fetchRepostedPostsByUser(
  userId: string
): Promise<WhisperPost[]> {
  const { data } = await supabase
    .from("whisper_reposts")
    .select("post_id, created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(120);
  const ids = ((data as { post_id: string }[] | null) ?? []).map(
    (r) => r.post_id
  );
  if (ids.length === 0) return [];
  const { data: posts } = await supabase
    .from("whisper_posts")
    .select("*")
    .in("id", ids);
  const rows = (posts as WhisperPost[] | null) ?? [];
  // Preserve repost recency order.
  const order = new Map(ids.map((id, i) => [id, i]));
  return rows.sort(
    (a, b) => (order.get(a.id) ?? 0) - (order.get(b.id) ?? 0)
  );
}

/** Aggregate repost counts for a set of posts, keyed by post id. */
export async function fetchRepostCounts(
  postIds: string[]
): Promise<Record<string, number>> {
  const unique = Array.from(new Set(postIds.filter(Boolean)));
  if (unique.length === 0) return {};
  const { data } = await supabase
    .from("whisper_reposts")
    .select("post_id")
    .in("post_id", unique);
  const counts: Record<string, number> = {};
  for (const row of (data as { post_id: string }[] | null) ?? []) {
    counts[row.post_id] = (counts[row.post_id] ?? 0) + 1;
  }
  return counts;
}

export async function toggleRepost(
  postId: string,
  userId: string,
  reposted: boolean
): Promise<void> {
  if (reposted) {
    const { error } = await supabase
      .from("whisper_reposts")
      .delete()
      .eq("post_id", postId)
      .eq("user_id", userId);
    if (error) throw error;
  } else {
    // The unique constraint is (post_id, user_id); a mismatched conflict
    // target silently failed before, so fall back to a plain insert that
    // tolerates the duplicate-row error code.
    const { error } = await supabase
      .from("whisper_reposts")
      .upsert(
        { user_id: userId, post_id: postId },
        { onConflict: "post_id,user_id" }
      );
    if (error) {
      const { error: insertError } = await supabase
        .from("whisper_reposts")
        .insert({ user_id: userId, post_id: postId });
      if (insertError && insertError.code !== "23505") throw insertError;
    }
  }
}

/** Post IDs the user has bookmarked/saved. */
export async function fetchMyBookmarkIds(userId: string, options?: { signal?: AbortSignal }): Promise<string[]> {
  const request = supabase.from("whisper_bookmarks").select("post_id").eq("user_id", userId);
  const { data, error } = await (options?.signal ? request.abortSignal(options.signal) : request);
  if (error) throw new Error("Your bookmarks couldn’t refresh. Please try again.");
  return ((data as { post_id: string }[] | null) ?? []).map((r) => r.post_id);
}

export async function toggleBookmark(
  postId: string,
  userId: string,
  bookmarked: boolean
): Promise<void> {
  if (bookmarked) {
    await supabase
      .from("whisper_bookmarks")
      .delete()
      .eq("post_id", postId)
      .eq("user_id", userId);
  } else {
    await supabase
      .from("whisper_bookmarks")
      .upsert(
        { user_id: userId, post_id: postId },
        { onConflict: "user_id,post_id" }
      );
  }
}

/** Permanently delete a post the current user authored. */
export async function deletePost(postId: string): Promise<void> {
  const { data, error } = await supabase.from("whisper_posts").delete().eq("id", postId).select("id");
  invalidateFeedSnapshot();
  if (error || !data?.some(row => row.id === postId)) throw new Error("Couldn't confirm deletion. Please refresh and try again.");
}

/** Max posts a user can pin to their profile (matches iOS verified perk). */
export const MAX_PINNED_POSTS = 3;

/** Post IDs the given user has pinned to their profile, in display order. */
export async function fetchPinnedPostIds(userId: string): Promise<string[]> {
  const { data } = await supabase
    .from("whisper_pinned_posts")
    .select("post_id, position")
    .eq("user_id", userId)
    .order("position", { ascending: true });
  return ((data as { post_id: string }[] | null) ?? []).map((r) => r.post_id);
}

/** Pin a post to the current user's profile (no-op past the limit). */
export async function pinPost(
  userId: string,
  postId: string
): Promise<void> {
  const current = await fetchPinnedPostIds(userId);
  if (current.includes(postId)) return;
  if (current.length >= MAX_PINNED_POSTS) {
    throw new Error(`You can pin up to ${MAX_PINNED_POSTS} posts.`);
  }
  const { error } = await supabase.from("whisper_pinned_posts").insert({
    user_id: userId,
    post_id: postId,
    position: current.length,
  });
  if (error) throw error;
}

/** Remove a pinned post from the current user's profile. */
export async function unpinPost(
  userId: string,
  postId: string
): Promise<void> {
  const { error } = await supabase
    .from("whisper_pinned_posts")
    .delete()
    .eq("user_id", userId)
    .eq("post_id", postId);
  if (error) throw error;
}

/** File a moderation report against a post (matches the iOS `whisper_reports`). */
export async function reportPost(input: {
  reporterId: string;
  reporterUsername: string;
  postId: string;
  targetUserId: string;
  targetUsername: string;
  reason: string;
  details?: string;
}): Promise<void> {
  const { data, error } = await supabase.rpc("whisper_submit_report", {
    p_kind: "post", p_target_id: input.postId, p_target_username: input.targetUsername,
    p_reason: input.reason, p_details: input.details ?? null, p_context: { surface: "post" },
  });
  if (error) throw error;
  if (typeof data !== "string" || !/^[0-9a-f-]{36}$/i.test(data)) throw new Error("Report not confirmed. Please try again.");
}

/** File a moderation report against a story (mirrors the iOS story report). */
export async function reportStory(input: {
  reporterId: string;
  reporterUsername: string;
  storyId: string;
  targetUserId: string;
  targetUsername: string;
  reason: string;
  details?: string;
}): Promise<void> {
  const { data, error } = await supabase.rpc("whisper_submit_report", {
    p_kind: "story", p_target_id: input.storyId, p_target_username: input.targetUsername,
    p_reason: input.reason, p_details: input.details ?? null, p_context: { surface: "story" },
  });
  if (error) throw error;
  if (typeof data !== "string" || !/^[0-9a-f-]{36}$/i.test(data)) throw new Error("Report not confirmed. Please try again.");
}

export async function fetchComments(postId: string): Promise<WhisperComment[]> {
  const { data } = await supabase
    .from("whisper_post_comments")
    .select("*")
    .eq("post_id", postId)
    .order("created_at", { ascending: true })
    .limit(200);
  return (data as WhisperComment[] | null) ?? [];
}

export async function addComment(
  postId: string,
  userId: string,
  username: string,
  body: string,
  parentCommentId?: string | null
): Promise<void> {
  const { error } = await supabase.from("whisper_post_comments").insert({
    id: crypto.randomUUID(),
    post_id: postId,
    user_id: userId,
    username,
    body,
    parent_comment_id: parentCommentId ?? null,
  });
  if (error) throw error;
}

/**
 * Persist an Ember AI reply as a comment. Written with the asker's `user_id`
 * (so RLS is satisfied) but `username = "ember"`, so every viewer of the post
 * sees Ember's reply inline — mirrors the iOS `addEmberComment`.
 */
export async function addEmberComment(
  postId: string,
  askerUserId: string,
  body: string,
  parentCommentId?: string | null
): Promise<void> {
  await supabase.from("whisper_post_comments").insert({
    id: crypto.randomUUID(),
    post_id: postId,
    user_id: askerUserId,
    username: "ember",
    body,
    parent_comment_id: parentCommentId ?? null,
  });
}

/**
 * Fetch active "Liar Liar" badges for a set of usernames, keyed by lowercase
 * username. Mirrors the iOS pipeline: reads `whisper_liar_badges` plus manual
 * `profiles.is_liar` / `whisper_profiles.is_liar` overrides. Approved appeals
 * clear the badge unless it was manually re-applied.
 */
export async function fetchLiarBadges(
  usernames: string[]
): Promise<Record<string, WhisperLiarBadge>> {
  // Compatibility for old feed callers: history is private, never public reputation state.
  void usernames;
  return {};
}

/** The signed-in user's un-acknowledged Liar Liar badge, if any (drives popup). */
export async function fetchMyLiarBadge(
  username: string
): Promise<WhisperLiarBadge | null> {
  const map = await fetchLiarBadges([username]);
  const badge = map[username.toLowerCase()];
  if (!badge) return null;
  if (badge.acknowledged_at) return null;
  return badge;
}

/** Mark the current user's Liar Liar badge as acknowledged so the popup stops. */
export async function acknowledgeLiarBadge(username: string): Promise<void> {
  const { error } = await supabase.from("whisper_liar_badges").update({ acknowledged_at: new Date().toISOString() }).eq("username", username.toLowerCase());
  if (error) throw error;
}

/** Submit an appeal against the current user's Liar Liar badge. */
export async function submitLiarAppeal(
  username: string,
  body: string
): Promise<void> {
  const { error } = await supabase.from("whisper_liar_appeals").insert({
    username: username.toLowerCase(),
    body,
    status: "pending",
  });
  if (error) throw error;
}

export async function fetchStories(): Promise<WhisperStory[]> {
  const nowIso = new Date().toISOString();
  const { data } = await supabase
    .from("whisper_stories")
    .select("*")
    .gt("expires_at", nowIso)
    .order("created_at", { ascending: false })
    .limit(100);
  return (data as WhisperStory[] | null) ?? [];
}

import { conversationThreadId, type ConversationKind } from "./conversationIdentity";

export async function fetchConversations(
  userId: string
): Promise<WhisperConversation[]> {
  const [inbound, outbound] = await Promise.all([
    supabase
      .from("whisper_messages")
      .select("*")
      .eq("to_user_id", userId)
      .order("created_at", { ascending: false })
      .limit(1000),
    supabase
      .from("whisper_messages")
      .select("*")
      .eq("from_user_id", userId)
      .order("created_at", { ascending: false })
      .limit(1000),
  ]);

  if (inbound.error || outbound.error) throw new Error("Messages couldn't refresh. Please try again.");
  const all: WhisperMessage[] = [
    ...((inbound.data as WhisperMessage[] | null) ?? []),
    ...((outbound.data as WhisperMessage[] | null) ?? []),
  ];

  const me = userId.toLowerCase();
  const peers = [...new Set(all.map((m) => m.from_user_id.toLowerCase() === me ? m.to_user_id?.toLowerCase() : m.from_user_id.toLowerCase()).filter((id): id is string => !!id && id !== me))];
  const datingIds = new Map(await Promise.all(peers.map(async (peer): Promise<[string, string]> => [peer, await conversationThreadId(me, peer, "dating")])));
  const byOther = new Map<string, WhisperMessage[]>();
  for (const m of all) {
    // Group-chat fan-out rows (shared wire with iOS) never pollute 1:1
    // threads — they surface in the Groups section instead. body can be
    // NULL on media-only rows, so never call startsWith on it directly —
    // one null used to throw here and blank the ENTIRE inbox.
    if (typeof m.body === "string" && m.body.startsWith("::wg-v1::")) continue;
    if (m.body?.startsWith("::whisper-call-")) continue;
    const other = m.from_user_id.toLowerCase() === me ? m.to_user_id?.toLowerCase() : m.from_user_id.toLowerCase();
    if (!other || other === me) continue;
    const key = m.thread_id?.toLowerCase() === datingIds.get(other) ? `dating:${other}` : other;
    const list = byOther.get(key) ?? [];
    if (!list.some((row) => row.id === m.id)) list.push(m);
    byOther.set(key, list);
  }

  const profiles = await fetchProfilesByIds(peers);

  const convos: WhisperConversation[] = [];
  for (const [key, msgs] of byOther.entries()) {
    const kind: ConversationKind = key.startsWith("dating:") ? "dating" : "direct";
    const other = kind === "dating" ? key.slice(7) : key;
    msgs.sort(
      (a, b) =>
        new Date(a.created_at ?? 0).getTime() -
        new Date(b.created_at ?? 0).getTime()
    );
    const last = msgs[msgs.length - 1]!;
    const unread = msgs.filter(
      (m) => m.to_user_id === userId && !m.read_at
    ).length;
    const profile = profiles[other] ?? null;
    const otherUsername =
      profile?.username ??
      (last.from_user_id === other ? last.from_username : last.to_username) ??
      "user";
    convos.push({
      kind,
      threadId: last.thread_id,
      otherUserId: other,
      otherUsername,
      otherProfile: profile,
      lastMessage: last.body,
      lastDate: last.created_at,
      lastFromMe: last.from_user_id === userId,
      unread,
      messages: msgs,
    });
  }

  convos.sort(
    (a, b) =>
      new Date(b.lastDate ?? 0).getTime() - new Date(a.lastDate ?? 0).getTime()
  );
  return convos;
}

/**
 * Deterministic conversation id derived from the two participant ids, matching
 * the iOS `deterministicThreadID` (SHA-256 of the sorted `lo|hi` pair, first 32
 * hex chars formatted 8-4-4-4-12). The deployed `whisper_messages` table has a
 * non-null `thread_id` column, so an insert that omits it is rejected — which is
 * why every web DM send was failing. Both clients must compute the same value so
 * messages land in the same thread.
 */
export async function deterministicThreadId(
  a: string,
  b: string
): Promise<string> {
  return conversationThreadId(a, b);
}

export async function sendMessage(
  fromUserId: string,
  fromUsername: string,
  toUserId: string,
  toUsername: string,
  body: string,
  assertCurrent: () => void = () => {},
  kind: ConversationKind = "direct",
  logicalGroupMessageID?: string
): Promise<void> {
  // Mirror the iOS payload exactly, including the deterministic `thread_id` the
  // deployed table requires (non-null). Without it the insert is rejected and
  // the message vanishes on refresh / surfaces a send error.
  const threadId = await conversationThreadId(fromUserId, toUserId, kind);
  const assertSender = async (): Promise<void> => {
    const { data } = await supabase.auth.getSession();
    assertCurrent();
    if (data.session?.user.id !== fromUserId) throw new Error("Your account changed. Reopen this conversation before sending.");
  };
  await assertSender();
  const row: Record<string, unknown> = {
    id: crypto.randomUUID(),
    from_user_id: fromUserId,
    from_username: fromUsername,
    to_user_id: toUserId,
    to_username: toUsername,
    thread_id: threadId,
    body,
    ...(logicalGroupMessageID ? { logical_group_message_id: logicalGroupMessageID } : {}),
  };
  let { error } = await supabase.from("whisper_messages").insert(row);

  // If the deployed schema is older and has no `thread_id` column, PostgREST
  // reports a schema-cache miss. Retry without it so we stay compatible.
  if (kind === "direct" && error && /thread_id/i.test(error.message) && /column|find/i.test(error.message)) {
    delete row.thread_id;
    await assertSender();
    ({ error } = await supabase.from("whisper_messages").insert(row));
  }

  // Previously this swallowed errors, so a rejected insert (e.g. the body
  // length check) still looked successful — the bubble showed optimistically
  // then disappeared on refresh because nothing was saved. Surface it instead.
  if (error) {
    console.error("sendMessage insert failed:", error.message);
    throw new Error(error.message);
  }
}

export async function markThreadRead(
  userId: string,
  otherUserId: string,
  kind: ConversationKind = "direct"
): Promise<void> {
  const datingId = await conversationThreadId(userId, otherUserId, "dating");
  let request = supabase
    .from("whisper_messages")
    .update({ read_at: new Date().toISOString() })
    .eq("to_user_id", userId)
    .eq("from_user_id", otherUserId)
    .or("body.is.null,body.not.like.::wg-v1::%")
    .is("read_at", null);
  request = kind === "dating" ? request.eq("thread_id", datingId) : request.or(`thread_id.is.null,thread_id.neq.${datingId}`);
  const { error } = await request;
  if (error) throw new Error("Read status couldn't update.");
}

export async function searchProfiles(query: string, signal?: AbortSignal): Promise<WhisperProfile[]> {
  const term = query.trim();
  if (!term) return [];
  const request = supabase
    .from("whisper_profiles")
    .select("*")
    .or(`username.ilike.%${term}%,display_name.ilike.%${term}%`)
    .limit(30);
  const { data, error } = await (signal ? request.abortSignal(signal) : request);
  if (error) throw new Error("Search couldn't refresh. Please try again.");
  return (data as WhisperProfile[] | null) ?? [];
}

/** Batch-fetch profiles for a set of usernames, keyed by lowercased username. */
export async function fetchProfilesByUsernames(
  usernames: string[]
): Promise<Record<string, WhisperProfile>> {
  const unique = Array.from(
    new Set(
      usernames
        .map((u) => u?.toLowerCase().trim())
        .filter((u): u is string => !!u)
    )
  );
  if (unique.length === 0) return {};
  const { data } = await supabase
    .from("whisper_profiles")
    .select("*")
    .in("username", unique);
  const map: Record<string, WhisperProfile> = {};
  for (const row of (data as WhisperProfile[] | null) ?? []) {
    if (row.username) map[row.username.toLowerCase()] = row;
  }
  return map;
}

export async function fetchProfileByUsername(
  username: string
): Promise<WhisperProfile | null> {
  const { data } = await supabase
    .from("whisper_profiles")
    .select("*")
    .ilike("username", username)
    .limit(1)
    .maybeSingle();
  return (data as WhisperProfile | null) ?? null;
}

export async function fetchFollowCounts(
  userId: string
): Promise<{ followers: number; following: number }> {
  const [followers, following] = await Promise.all([
    supabase
      .from("whisper_follows")
      .select("*", { count: "exact", head: true })
      .eq("followee_id", userId),
    supabase
      .from("whisper_follows")
      .select("*", { count: "exact", head: true })
      .eq("follower_id", userId),
  ]);
  return {
    followers: followers.count ?? 0,
    following: following.count ?? 0,
  };
}

export async function isFollowing(
  followerId: string,
  followeeId: string
): Promise<boolean> {
  const { data } = await supabase
    .from("whisper_follows")
    .select("follower_id")
    .eq("follower_id", followerId)
    .eq("followee_id", followeeId)
    .limit(1)
    .maybeSingle();
  return !!data;
}

export async function toggleFollow(
  followerId: string,
  followeeId: string,
  followeeUsername: string,
  following: boolean
): Promise<void> {
  if (following) {
    await supabase
      .from("whisper_follows")
      .delete()
      .eq("follower_id", followerId)
      .eq("followee_id", followeeId);
  } else {
    await supabase.from("whisper_follows").upsert(
      {
        follower_id: followerId,
        followee_id: followeeId,
        followee_username: followeeUsername,
      },
      { onConflict: "follower_id,followee_id" }
    );
  }
}

/** Users who follow `userId`, hydrated with profiles (newest first). */
export async function fetchFollowers(
  userId: string
): Promise<WhisperFollowUser[]> {
  const { data } = await supabase
    .from("whisper_follows")
    .select("follower_id, created_at")
    .eq("followee_id", userId)
    .order("created_at", { ascending: false })
    .limit(500);
  const rows = (data as { follower_id: string }[] | null) ?? [];
  const ids = rows.map((r) => r.follower_id).filter(Boolean);
  const profiles = await fetchProfilesByIds(ids);
  return ids.map((id) => ({
    userId: id,
    username: profiles[id]?.username ?? "user",
    profile: profiles[id] ?? null,
  }));
}

/** User ids currently hosting a live room — powers the LIVE badge on
 * story rings (kit 4.0 grammar). Cheap select; never throws. */
export async function fetchLiveHostIds(): Promise<string[]> {
  try {
    const { data } = await supabase
      .from("whisper_live_rooms")
      .select("host_id")
      .eq("is_live", true)
      .limit(100);
    const rows = (data as { host_id: string | null }[] | null) ?? [];
    return Array.from(
      new Set(rows.map((r) => r.host_id ?? "").filter(Boolean))
    );
  } catch {
    return [];
  }
}

/** Users `userId` follows, hydrated with profiles (newest first). */
export async function fetchFollowing(
  userId: string
): Promise<WhisperFollowUser[]> {
  const { data } = await supabase
    .from("whisper_follows")
    .select("followee_id, followee_username, created_at")
    .eq("follower_id", userId)
    .order("created_at", { ascending: false })
    .limit(500);
  const rows =
    (data as { followee_id: string; followee_username: string | null }[] | null) ??
    [];
  const ids = rows.map((r) => r.followee_id).filter(Boolean);
  const profiles = await fetchProfilesByIds(ids);
  return rows.map((r) => ({
    userId: r.followee_id,
    username: profiles[r.followee_id]?.username ?? r.followee_username ?? "user",
    profile: profiles[r.followee_id] ?? null,
  }));
}

/**
 * People-you-may-know suggestions: recent profiles the user doesn't already
 * follow (and that aren't themselves). Mirrors the iOS suggestions sheet.
 */
export async function fetchSuggestions(
  userId: string,
  limit = 20
): Promise<WhisperFollowUser[]> {
  const { data: followingRows } = await supabase
    .from("whisper_follows")
    .select("followee_id")
    .eq("follower_id", userId);
  const followingSet = new Set(
    ((followingRows as { followee_id: string }[] | null) ?? []).map(
      (r) => r.followee_id
    )
  );
  followingSet.add(userId);

  const { data } = await supabase
    .from("whisper_profiles")
    .select("*")
    .order("updated_at", { ascending: false, nullsFirst: false })
    .limit(limit + followingSet.size + 10);
  const profiles = (data as WhisperProfile[] | null) ?? [];
  return profiles
    .filter((p) => !followingSet.has(p.user_id))
    .slice(0, limit)
    .map((p) => ({ userId: p.user_id, username: p.username, profile: p }));
}

/**
 * Derived activity feed for the Notifications screen: likes, comments and
 * reposts on the user's own posts, plus new followers. We compute this from
 * the same interaction tables the rest of the app already uses, so it works
 * without a dedicated server feed.
 */
export async function fetchActivity(
  userId: string
): Promise<WhisperActivity[]> {
  const myPosts = await fetchPostsByUser(userId);
  const postIds = myPosts.map((p) => p.id);
  const postById = new Map(myPosts.map((p) => [p.id, p]));

  const [likes, comments, reposts, follows] = await Promise.all([
    postIds.length
      ? supabase
          .from("whisper_post_likes")
          .select("post_id, user_id, created_at")
          .in("post_id", postIds)
          .order("created_at", { ascending: false })
          .limit(200)
      : Promise.resolve({ data: [] }),
    postIds.length
      ? supabase
          .from("whisper_post_comments")
          .select("id, post_id, user_id, username, body, created_at")
          .in("post_id", postIds)
          .order("created_at", { ascending: false })
          .limit(200)
      : Promise.resolve({ data: [] }),
    postIds.length
      ? supabase
          .from("whisper_reposts")
          .select("post_id, user_id, created_at")
          .in("post_id", postIds)
          .order("created_at", { ascending: false })
          .limit(200)
      : Promise.resolve({ data: [] }),
    supabase
      .from("whisper_follows")
      .select("follower_id, created_at")
      .eq("followee_id", userId)
      .order("created_at", { ascending: false })
      .limit(200),
  ]);

  type Raw = {
    id: string;
    kind: WhisperActivity["kind"];
    actorUserId: string;
    actorUsername: string;
    postId: string | null;
    preview: string | null;
    createdAt: string | null;
  };
  const raw: Raw[] = [];

  for (const r of (likes.data as { post_id: string; user_id: string; created_at: string | null }[] | null) ?? []) {
    if (r.user_id === userId) continue;
    raw.push({
      id: `like-${r.post_id}-${r.user_id}`,
      kind: "like",
      actorUserId: r.user_id,
      actorUsername: "",
      postId: r.post_id,
      preview: postById.get(r.post_id)?.caption ?? null,
      createdAt: r.created_at,
    });
  }
  for (const r of (comments.data as { id: string; post_id: string; user_id: string; username: string; body: string; created_at: string | null }[] | null) ?? []) {
    if (r.user_id === userId) continue;
    raw.push({
      id: `comment-${r.id}`,
      kind: "comment",
      actorUserId: r.user_id,
      actorUsername: r.username ?? "",
      postId: r.post_id,
      preview: r.body,
      createdAt: r.created_at,
    });
  }
  for (const r of (reposts.data as { post_id: string; user_id: string; created_at: string | null }[] | null) ?? []) {
    if (r.user_id === userId) continue;
    raw.push({
      id: `repost-${r.post_id}-${r.user_id}`,
      kind: "repost",
      actorUserId: r.user_id,
      actorUsername: "",
      postId: r.post_id,
      preview: postById.get(r.post_id)?.caption ?? null,
      createdAt: r.created_at,
    });
  }
  for (const r of (follows.data as { follower_id: string; created_at: string | null }[] | null) ?? []) {
    if (r.follower_id === userId) continue;
    raw.push({
      id: `follow-${r.follower_id}`,
      kind: "follow",
      actorUserId: r.follower_id,
      actorUsername: "",
      postId: null,
      preview: null,
      createdAt: r.created_at,
    });
  }

  const profiles = await fetchProfilesByIds(raw.map((r) => r.actorUserId));
  const events: WhisperActivity[] = raw.map((r) => ({
    id: r.id,
    kind: r.kind,
    actorUserId: r.actorUserId,
    actorUsername:
      profiles[r.actorUserId]?.username ?? (r.actorUsername || "user"),
    actorProfile: profiles[r.actorUserId] ?? null,
    postId: r.postId,
    preview: r.preview,
    createdAt: r.createdAt,
  }));
  events.sort(
    (a, b) =>
      new Date(b.createdAt ?? 0).getTime() - new Date(a.createdAt ?? 0).getTime()
  );
  return events.slice(0, 120);
}

/** Full-screen Reels: posts flagged `is_reel` with media, newest first. */
export async function fetchReels(limit = 60): Promise<WhisperPost[]> {
  const { data } = await supabase
    .from("whisper_posts")
    .select("*")
    .eq("is_reel", true)
    .order("created_at", { ascending: false })
    .limit(limit);
  const rows = (data as WhisperPost[] | null) ?? [];
  return rows.filter((p) => (p.media_urls ?? []).length > 0);
}

/** Aggregate analytics across all of a creator's posts. */
export async function fetchCreatorStats(
  userId: string
): Promise<WhisperCreatorStats> {
  const posts = await fetchPostsByUser(userId);
  const postIds = posts.map((p) => p.id);

  const [likeRows, commentRows, repostCounts, follow] = await Promise.all([
    postIds.length
      ? supabase.from("whisper_post_likes").select("post_id").in("post_id", postIds)
      : Promise.resolve({ data: [] }),
    postIds.length
      ? supabase
          .from("whisper_post_comments")
          .select("post_id")
          .in("post_id", postIds)
      : Promise.resolve({ data: [] }),
    fetchRepostCounts(postIds),
    fetchFollowCounts(userId),
  ]);

  const likesByPost: Record<string, number> = {};
  for (const r of (likeRows.data as { post_id: string }[] | null) ?? []) {
    likesByPost[r.post_id] = (likesByPost[r.post_id] ?? 0) + 1;
  }
  const commentsByPost: Record<string, number> = {};
  for (const r of (commentRows.data as { post_id: string }[] | null) ?? []) {
    commentsByPost[r.post_id] = (commentsByPost[r.post_id] ?? 0) + 1;
  }

  const enriched = posts.map((post) => ({
    post,
    likes: likesByPost[post.id] ?? 0,
    comments: commentsByPost[post.id] ?? 0,
    reposts: repostCounts[post.id] ?? 0,
  }));
  const totals = enriched.reduce(
    (acc, e) => {
      acc.likes += e.likes;
      acc.comments += e.comments;
      acc.reposts += e.reposts;
      return acc;
    },
    { likes: 0, comments: 0, reposts: 0 }
  );
  const topPosts = [...enriched]
    .sort(
      (a, b) =>
        b.likes + b.comments + b.reposts - (a.likes + a.comments + a.reposts)
    )
    .slice(0, 5);

  return {
    posts: posts.length,
    likes: totals.likes,
    comments: totals.comments,
    reposts: totals.reposts,
    followers: follow.followers,
    topPosts,
    entries: enriched,
  };
}

// MARK: Follow requests (private accounts) — mirrors the iOS request queue.

export interface WhisperFollowRequest {
  id: string;
  requester_id: string;
  requester_username: string;
  target_id: string;
  target_username: string;
  status: string;
  created_at: string | null;
}

/** Pending follow requests waiting on `userId` (a private account). */
export async function fetchIncomingFollowRequests(
  userId: string
): Promise<WhisperFollowRequest[]> {
  const { data } = await supabase
    .from("whisper_follow_requests")
    .select("*")
    .eq("target_id", userId)
    .eq("status", "pending")
    .order("created_at", { ascending: false });
  return (data as WhisperFollowRequest[] | null) ?? [];
}

/**
 * Approve or deny a pending follow request. Approving also inserts the
 * `whisper_follows` row from the target's side so the requester actually
 * starts following (matches the iOS approve flow + relaxed RLS policy).
 */
export async function respondToFollowRequest(
  request: WhisperFollowRequest,
  approve: boolean
): Promise<void> {
  await supabase
    .from("whisper_follow_requests")
    .update({
      status: approve ? "approved" : "denied",
      responded_at: new Date().toISOString(),
    })
    .eq("id", request.id);
  if (approve) {
    await supabase.from("whisper_follows").upsert(
      {
        follower_id: request.requester_id,
        followee_id: request.target_id,
        followee_username: request.target_username,
      },
      { onConflict: "follower_id,followee_id" }
    );
  }
}

/** True when `requesterId` has a pending request to follow `targetId`. */
export async function hasPendingFollowRequest(
  requesterId: string,
  targetId: string
): Promise<boolean> {
  const { data } = await supabase
    .from("whisper_follow_requests")
    .select("id")
    .eq("requester_id", requesterId)
    .eq("target_id", targetId)
    .eq("status", "pending")
    .limit(1)
    .maybeSingle();
  return !!data;
}

/** Queue a follow request against a private account. */
export async function createFollowRequest(input: {
  requesterId: string;
  requesterUsername: string;
  targetId: string;
  targetUsername: string;
}): Promise<void> {
  await supabase.from("whisper_follow_requests").upsert(
    {
      requester_id: input.requesterId,
      requester_username: input.requesterUsername,
      target_id: input.targetId,
      target_username: input.targetUsername,
      status: "pending",
    },
    { onConflict: "requester_id,target_id" }
  );
}

/** Cancel an outgoing pending follow request. */
export async function cancelFollowRequest(
  requesterId: string,
  targetId: string
): Promise<void> {
  await supabase
    .from("whisper_follow_requests")
    .delete()
    .eq("requester_id", requesterId)
    .eq("target_id", targetId);
}

/** Toggle the signed-in user's private-account flag. */
export async function setProfilePrivacy(
  userId: string,
  isPrivate: boolean
): Promise<void> {
  await supabase
    .from("whisper_profiles")
    .update({ is_private: isPrivate })
    .eq("user_id", userId);
}

export async function uploadMedia(
  file: File,
  userId: string
): Promise<string> {
  const ext = file.name.split(".").pop() ?? "jpg";
  const path = `${userId}/${crypto.randomUUID()}.${ext}`;
  const { error } = await supabase.storage
    .from("whisper-media")
    .upload(path, file, { cacheControl: "3600", upsert: true });
  if (error) throw error;
  return supabase.storage.from("whisper-media").getPublicUrl(path).data
    .publicUrl;
}

/**
 * Upload a large film file with resumable, chunked transfer and live
 * progress. Supabase's `resumable` upload slices the file into chunks so
 * hundreds of MB stream without hitting the single-request body limit. The
 * optional `onProgress` callback receives a 0–1 fraction for the UI.
 * Falls back to a single-shot upload for very small files.
 */
export async function uploadFilm(
  file: File,
  userId: string,
  onProgress?: (fraction: number) => void
): Promise<string> {
  const ext = file.name.split(".").pop() ?? "mp4";
  const path = `films/${userId}/${crypto.randomUUID()}.${ext}`;
  const bucket = supabase.storage.from("whisper-media");

  // For files under 8 MB a single shot is faster and simpler.
  if (file.size < 8 * 1024 * 1024) {
    const { error } = await bucket.upload(path, file, {
      cacheControl: "3600",
      upsert: false,
      contentType: file.type || "video/mp4",
    });
    if (error) throw error;
    return bucket.getPublicUrl(path).data.publicUrl;
  }

  // Resumable chunked upload for big files.
  const task = bucket.upload(path, file, {
    cacheControl: "3600",
    upsert: false,
    contentType: file.type || "video/mp4",
    // `resumable` streams the file in chunks and survives transient
    // network failures by retrying individual parts.
    // @ts-expect-error — `resumable` is supported at runtime by supabase-js.
    resumable: true,
  });

  // Wire up progress events. supabase-js emits an event with the
  // uploaded-byte count while a resumable upload is in flight.
  if (onProgress && typeof (task as unknown as { on: unknown }).on === "function") {
    (task as unknown as { on: (e: string, cb: (p: { loaded: number; total?: number }) => void) => void }).on(
      "progress",
      (p: { loaded: number; total?: number }) => {
        const total = p.total ?? file.size;
        onProgress(Math.min(1, p.loaded / total));
      }
    );
  }

  const { error } = await task;
  if (error) throw error;
  onProgress?.(1);
  return bucket.getPublicUrl(path).data.publicUrl;
}

/** Pull the offending column name out of a PostgREST schema-cache error. */
function missingColumnName(message: string): string | null {
  // e.g. "Could not find the 'is_reel' column of 'whisper_posts' in the schema cache"
  const m = message.match(/'([^']+)' column/);
  return m?.[1] ?? null;
}

export async function createPost(input: {
  userId: string;
  username: string;
  caption: string;
  mediaUrls: string[];
  /** Optional post kind: "grid" for Instagram-style grid posts, "photo" for
   *  regular thread posts with images, "text" for text-only posts. */
  kind?: string;
  /** Explicit community pick from the composer — stored as data, never as a
   *  hashtag folded into the caption. */
  communityId?: string | null;
  communityName?: string | null;
}): Promise<void> {
  // Build a flexible payload and progressively drop any column the deployed
  // `whisper_posts` table is missing (mirrors the iOS createPost retry loop).
  // Required columns (id, user_id, caption) are never dropped.
  const resolvedKind = input.kind ?? (input.mediaUrls.length > 0 ? "photo" : "text");
  const payload: Record<string, unknown> = {
    id: crypto.randomUUID(),
    user_id: input.userId,
    username: input.username,
    kind: resolvedKind,
    caption: input.caption,
    media_count: input.mediaUrls.length,
    media_urls: input.mediaUrls,
    is_ghost: false,
    is_reel: false,
  };
  if (input.communityId) {
    payload.community_id = input.communityId;
    payload.community_name = input.communityName ?? input.communityId;
  }
  const droppable = new Set([
    "username",
    "kind",
    "media_count",
    "media_urls",
    "is_ghost",
    "is_reel",
    "community_id",
    "community_name",
  ]);

  for (let attempt = 0; attempt < 8; attempt++) {
    const { error } = await supabase.from("whisper_posts").insert(payload);
    if (!error) return;
    const column = missingColumnName(error.message);
    if (column && droppable.has(column) && column in payload) {
      delete payload[column];
      continue;
    }
    throw error;
  }
  throw new Error(
    "Couldn't post — the whisper_posts table is missing required columns."
  );
}

/** Create a reel — a post flagged `is_reel: true` with at least one media URL. */
export async function createReel(input: {
  userId: string;
  username: string;
  caption: string;
  mediaUrls: string[];
}): Promise<void> {
  if (!input.mediaUrls.length || input.mediaUrls.some((url) => !/^https:\/\//i.test(url))) {
    throw new Error("The video hasn't finished uploading. Your reel has not been posted.");
  }
  const payload: Record<string, unknown> = {
    id: crypto.randomUUID(),
    user_id: input.userId,
    username: input.username,
    kind: "reel",
    caption: input.caption,
    media_count: input.mediaUrls.length,
    media_urls: input.mediaUrls,
    is_ghost: false,
    is_reel: true,
  };
  // Never report publication after discarding media identity or reel classification.
  const droppable = new Set(["username", "kind", "media_count"]);
  for (let attempt = 0; attempt < 8; attempt++) {
    const { error } = await supabase.from("whisper_posts").insert(payload);
    if (!error) return;
    const column = missingColumnName(error.message);
    if (column && droppable.has(column) && column in payload) {
      delete payload[column];
      continue;
    }
    throw error;
  }
  throw new Error(
    "Couldn't publish reel — the whisper_posts table is missing required columns."
  );
}

export async function upsertProfile(input: {
  userId: string;
  username: string;
  displayName: string;
  bio: string;
  profileImageUrl: string | null;
  interests?: string[];
  /** Signup's account-type pick rides the first profile save (account-types.sql). */
  accountType?: "personal" | "creator" | "business";
  professionalCategory?: string;
}): Promise<void> {
  const payload: Record<string, unknown> = {
    user_id: input.userId,
    username: input.username,
    display_name: input.displayName,
    bio: input.bio,
    // Preserve existing interests when upserting from the profile editor
    // (which doesn't pass interests); onboarding passes them explicitly so
    // the feed is seeded on day one, matching the iOS flow.
    interests: input.interests ?? [],
    profile_image_url: input.profileImageUrl,
    is_private: false,
    onboarded_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
  if (input.accountType) {
    payload.account_type = input.accountType;
    if (input.accountType !== "personal" && input.professionalCategory?.trim()) {
      payload.professional_category = input.professionalCategory.trim();
    }
  }
  const { error } = await supabase
    .from("whisper_profiles")
    .upsert(payload, { onConflict: "user_id" });
  // Migration not run yet? Retry without the account-type columns so
  // onboarding is NEVER blocked by them.
  if (
    error &&
    (error.code === "42703" ||
      /account_type|professional_category/.test(error.message ?? ""))
  ) {
    delete payload.account_type;
    delete payload.professional_category;
    await supabase.from("whisper_profiles").upsert(payload, { onConflict: "user_id" });
  }
}

/**
 * Joins / leaves a community by toggling its name in the user's `interests`
 * array (mirrors the iOS `WhisperCommunityDetailView.toggleJoin`, which is the
 * same membership signal the sidebar reads). Returns the updated interests.
 */
export async function updateInterests(
  userId: string,
  interests: string[]
): Promise<string[]> {
  const { error } = await supabase
    .from("whisper_profiles")
    .update({ interests, updated_at: new Date().toISOString() })
    .eq("user_id", userId);
  if (error) throw error;
  return interests;
}

/**
 * Tally of poll votes for a post, keyed by option index. Best-effort: if the
 * `whisper_poll_votes` table doesn't exist, returns an empty tally so the UI
 * falls back to the voter's local choice.
 */
export async function fetchPollVotes(
  postId: string
): Promise<Record<number, number>> {
  const tally: Record<number, number> = {};
  try {
    const { data } = await supabase
      .from("whisper_poll_votes")
      .select("option_index")
      .eq("post_id", postId);
    for (const r of (data as { option_index: number }[] | null) ?? []) {
      tally[r.option_index] = (tally[r.option_index] ?? 0) + 1;
    }
  } catch {
    // table unavailable — caller falls back to local state.
  }
  return tally;
}

/** The signed-in user's chosen option index for a poll, or null. */
export async function fetchMyPollVote(
  postId: string,
  userId: string
): Promise<number | null> {
  try {
    const { data } = await supabase
      .from("whisper_poll_votes")
      .select("option_index")
      .eq("post_id", postId)
      .eq("user_id", userId)
      .limit(1)
      .maybeSingle();
    return (data as { option_index: number } | null)?.option_index ?? null;
  } catch {
    return null;
  }
}

/** Cast (or change) the user's vote on a poll. */
export async function castPollVote(
  postId: string,
  userId: string,
  optionIndex: number
): Promise<void> {
  await supabase.from("whisper_poll_votes").upsert(
    { post_id: postId, user_id: userId, option_index: optionIndex },
    { onConflict: "post_id,user_id" }
  );
}

export async function createStory(input: {
  userId: string;
  username: string;
  imageUrl: string;
  caption: string | null;
  metadata?: string | null;
  music?: {
    previewURL: string;
    title: string;
    artist: string;
    artworkURL: string | null;
  } | null;
}): Promise<void> {
  // Build a flexible payload and progressively drop any column the deployed
  // `whisper_stories` table is missing (older deployments may lack the
  // sticker/music columns). Core columns are never dropped.
  const payload: Record<string, unknown> = {
    id: crypto.randomUUID(),
    user_id: input.userId,
    username: input.username,
    image_url: input.imageUrl,
    caption: input.caption,
  };
  if (input.metadata) payload.metadata = input.metadata;
  if (input.music) {
    payload.music_url = input.music.previewURL;
    payload.music_title = input.music.title;
    payload.music_artist = input.music.artist;
    payload.music_artwork = input.music.artworkURL;
  }
  for (let attempt = 0; attempt < 6; attempt++) {
    const { error } = await supabase.from("whisper_stories").insert(payload);
    if (!error) return;
    const missing = missingColumnName(error.message);
    if (
      missing &&
      !(["id", "user_id", "image_url"] as string[]).includes(missing) &&
      missing in payload
    ) {
      delete payload[missing];
      continue;
    }
    console.error("createStory failed:", error.message);
    throw new Error(error.message);
  }
}

/** Permanently delete one of the current user's stories. */
export async function deleteStory(storyId: string): Promise<void> {
  await supabase.from("whisper_stories").delete().eq("id", storyId);
}
