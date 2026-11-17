import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

/** Only trusted database senders may submit webhook records. Never accept an anon/user JWT. */
export async function authenticWebhook(header: string | null, serviceKey: string): Promise<boolean> {
  const token = /^Bearer ([^\s]+)$/i.exec(header ?? "")?.[1];
  if (!token || !serviceKey) return false;
  const hash = async (value: string) => new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  const [actual, expected] = await Promise.all([hash(token), hash(serviceKey)]);
  let difference = 0;
  for (let i = 0; i < actual.length; i++) difference |= actual[i] ^ expected[i];
  return difference === 0;
}

export const eventKeys: Record<string, readonly string[]> = {
  whisper_posts: ["id"], whisper_messages: ["id"], whisper_follows: ["follower_id", "followee_id"],
  whisper_post_likes: ["post_id", "user_id"], whisper_post_comments: ["id"],
  whisper_mentions: ["id"], whisper_story_responses: ["id"],
  whisper_thought_replies: ["id"], whisper_coach_proposals: ["id"],
  whisper_message_reaction_events: ["id"],
};

// Public catalog IDs used by native/web; custom communities always take database precedence.
const publicCatalog = new Set("jasper-circle dating workouts running yoga mobility lifting hiit recovery sleep nutrition hydration mindset mindfulness outdoors hiking climbing cycling swimming stretching progress food cooking coffee books music movies tv gaming anime sports basketball football soccer travel photography art design fashion beauty tech ai coding startups finance business productivity study languages mentalhealth parenting pets plants diy cars motorcycles comedy news science philosophy history home writing geo-law geo-med geo-business geo-code".split(" "));

export function isUUID(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(value);
}

/** Stable identity includes creation time for composite-key follow/like reinserts. */
export function eventIdentity(table: string, row: Record<string, unknown>): string | null {
  const keys = Object.hasOwn(eventKeys, table) ? eventKeys[table] : undefined;
  if (!keys || !keys.every(key => isUUID(row[key]))) return null;
  return JSON.stringify([table, ...keys.map(key => (row[key] as string).toLowerCase()), typeof row.created_at === "string" && Number.isFinite(Date.parse(row.created_at)) ? new Date(row.created_at).toISOString() : ""]);
}

export function preferenceAllows(prefs: Record<string, unknown> | null, category: string): boolean {
  if (prefs?.master_enabled === false || prefs?.quiet_mode === true) return false;
  const key: Record<string, string> = {
    WHISPER_DM: "dms", WHISPER_FOLLOW: "follows", WHISPER_LIKE: "likes",
    WHISPER_COMMENT: "comments", WHISPER_MENTION: "mentions",
    WHISPER_STORY_RESPONSE: "story_responses", WHISPER_CALL_MISSED: "missed_calls",
    WHISPER_THOUGHT_REPLY: "comments", WHISPER_NEW_POST: "new_posts",
  };
  return prefs?.[key[category]] !== false;
}

export function storyResponseAction(kind: unknown): string {
  switch (kind) {
    case "poll": return "voted on your poll";
    case "slider": return "rated your slider";
    case "question": return "answered your question";
    case "like": return "liked your story";
    case "reaction": return "reacted to your story";
    default: return "responded to your story";
  }
}

/** Database read failures stop delivery rather than bypassing privacy/preferences. */
export function createPushPolicy(db: SupabaseClient) {
  async function one(table: string, filters: Record<string, string>) {
    let query = db.from(table).select("*");
    for (const [key, value] of Object.entries(filters)) query = query.eq(key, value);
    const { data, error } = await query.maybeSingle();
    if (error) throw new Error(`push lookup failed: ${table}`);
    return data;
  }
  async function blocked(a: string, b: string): Promise<boolean> {
    if (!isUUID(a) || !isUUID(b)) return true;
    const { data, error } = await db.from("whisper_blocks").select("id")
      .or(`and(blocker_id.eq.${a},blocked_user_id.eq.${b}),and(blocker_id.eq.${b},blocked_user_id.eq.${a})`).limit(1);
    if (error) throw new Error("push block lookup failed");
    return !!data?.length;
  }
  async function contactAllowed(sender: string, recipient: string): Promise<boolean> {
    if (!isUUID(sender) || !isUUID(recipient)) return false;
    const { data, error } = await db.rpc("whisper_can_contact", { p_sender: sender, p_recipient: recipient });
    if (error) throw new Error("push contact authorization unavailable");
    return data === true;
  }
  async function profileVisible(owner: string, viewer: string): Promise<boolean> {
    if (owner === viewer) return true;
    if (await blocked(owner, viewer)) return false;
    const profile = await one("whisper_profiles", { user_id: owner });
    if (!profile || profile.ghost_enabled) return false;
    if (!profile.is_private) return true;
    return !!await one("whisper_follow_requests", { requester_id: viewer, target_id: owner, status: "approved" });
  }
  async function postVisible(post: Record<string, any>, viewer: string): Promise<boolean> {
    if (!isUUID(post.user_id) || post.is_ghost || !await profileVisible(post.user_id, viewer)) return false;
    if (!post.community_id) return true;
    const community = await one("whisper_communities", { slug: post.community_id });
    if (!community) return publicCatalog.has(post.community_id)
      || /^geo-(campus|gym)-[a-z0-9-]{1,120}$/.test(post.community_id);
    if (community.visibility === "public" || community.creator_id === viewer) return true;
    const member = await one("whisper_community_members", { community_slug: post.community_id, user_id: viewer });
    return member?.status === "member";
  }
  async function canonicalRecord(table: string, incoming: Record<string, unknown>) {
    const identity = eventIdentity(table, incoming);
    if (!identity) return null;
    const filters = Object.fromEntries(eventKeys[table].map(key => [key, incoming[key] as string]));
    const row = await one(table, filters);
    if (!row || eventIdentity(table, row) !== identity) return null;
    const age = Date.now() - Date.parse(row.created_at);
    if (!Number.isFinite(age) || age < -60_000 || age > 86_400_000) return null;
    return row;
  }
  async function canNotify(recipient: string, actor: string, category: string): Promise<boolean> {
    if (recipient === actor || await blocked(recipient, actor)) return false;
    if ((category === "WHISPER_DM" || category === "WHISPER_CALL_MISSED") && !await contactAllowed(actor, recipient)) return false;
    const prefs = await one("whisper_notification_prefs", { user_id: recipient });
    return preferenceAllows(prefs, category);
  }
  async function groupFor(id: string, sender: string, recipient: string) {
    if (!isUUID(id)) return null;
    const group = await one("whisper_group_threads", { id });
    const members: string[] = group ? [group.owner_id, ...group.member_ids] : [];
    return members.includes(sender) && members.includes(recipient) ? group : null;
  }
  return { one, blocked, contactAllowed, profileVisible, postVisible, canonicalRecord, canNotify, groupFor };
}
