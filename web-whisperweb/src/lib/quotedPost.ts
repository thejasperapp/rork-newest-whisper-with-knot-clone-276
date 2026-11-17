import { supabaseAnonKey, supabaseUrl } from "@/lib/supabase";
import { groupThemeSession } from "@/lib/groupThemeSession";
import type { WhisperPost, WhisperProfile } from "@/lib/types";

/** Read the current original with captured-account credentials; never trust embedded snapshots. */
export async function loadQuotedPost(postID: string, accountID: string, signal: AbortSignal): Promise<{ post: WhisperPost; author: WhisperProfile; liked: boolean } | null> {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(postID)) return null;
  const session = await groupThemeSession(accountID);
  const read = async <T>(table: string, params: Record<string, string>): Promise<T[]> => {
    session.check();
    const response = await fetch(`${supabaseUrl}/rest/v1/${table}?${new URLSearchParams(params)}`, {
      headers: { apikey: supabaseAnonKey, Authorization: `Bearer ${session.token}` },
      signal: AbortSignal.any([signal, session.signal]),
    });
    if (!response.ok) throw new Error("Couldn't load the original post.");
    const rows: unknown = await response.json();
    session.check();
    signal.throwIfAborted();
    if (!Array.isArray(rows)) throw new Error("Couldn't load the original post.");
    return rows as T[];
  };
  try {
    const [post] = await read<WhisperPost>("whisper_posts", { select: "*", id: `eq.${postID}`, limit: "1" });
    if (!post) return null;
    const [author] = await read<WhisperProfile>("whisper_profiles", { select: "*", user_id: `eq.${post.user_id}`, limit: "1" });
    if (!author) return null;
    const blocks = await read<{ blocked_user_id: string }>("whisper_blocks", { select: "blocked_user_id", blocker_id: `eq.${accountID}`, blocked_user_id: `eq.${post.user_id}`, limit: "1" });
    if (blocks.length) return null;
    if (author.is_private && post.user_id !== accountID) {
      const follows = await read<{ follower_id: string }>("whisper_follows", { select: "follower_id", follower_id: `eq.${accountID}`, followee_id: `eq.${post.user_id}`, limit: "1" });
      if (!follows.length) return null;
    }
    const likes = await read<{ post_id: string }>("whisper_post_likes", { select: "post_id", post_id: `eq.${postID}`, user_id: `eq.${accountID}`, limit: "1" });
    return { post, author, liked: likes.length > 0 };
  } finally { session.dispose(); }
}
