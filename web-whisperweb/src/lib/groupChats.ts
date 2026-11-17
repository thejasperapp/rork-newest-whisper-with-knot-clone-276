import { supabase } from "@/lib/supabase";
import { changeGroupRoster, freshGroupForSend } from "@/lib/groupRoster";
import { meetEventID } from "@/lib/meetMessageIdentity";
import { chatVideoUrl } from "@/lib/chatMedia";
import { sendMessage } from "@/lib/api";
import type { WhisperMessage } from "@/lib/types";
import { isBareImageUrl } from "@/lib/linkPreview";
import { jasperStickerName } from "@/lib/storyStickers";
import { stripPostMeta } from "@/lib/postMeta";
import { decodeSharedPost } from "@/lib/postShare";
import { decodeSharedCommunity, SHARED_COMMUNITY_PREFIX } from "@/lib/communityShare";
import { decodeSharedProfile } from "@/lib/profileShare";

/**
 * Group chats in DMs — cross-platform with iOS on the SAME wire.
 *
 * iOS ships groups today by fanning each group message out as N individual
 * whisper_messages rows (one per recipient) with the body prefixed:
 *
 *   ::wg-v1::{groupID}::{name}::{actual body}
 *
 * Web speaks that exact format, so a group message sent here lands in every
 * member's iOS group thread and vice versa. On top of the wire, web adds a
 * durable REGISTRY (whisper_group_threads — run supabase/business-plus.sql)
 * so rosters survive across devices; groups created on iOS (no registry row)
 * are still discovered from their wire messages.
 */

export const GROUP_WIRE_PREFIX = "::wg-v1::";

export interface GroupThread {
  id: string;
  name: string;
  owner_id: string;
  member_ids: string[];
  member_usernames: string[];
  avatar_path?: string | null;
  business_id: string | null;
  created_at: string | null;
}

export interface ParsedGroupWire {
  groupId: string;
  groupName: string;
  body: string;
}

/** A member handed to group create/send calls. */
export interface GroupPerson {
  id: string;
  username: string;
}

/** Parses an iOS-format group message body; null for normal DMs.
 *  Accepts null/undefined — media-only rows carry a NULL body. */
export function parseGroupWire(raw: string | null | undefined): ParsedGroupWire | null {
  if (typeof raw !== "string" || !raw.startsWith(GROUP_WIRE_PREFIX)) return null;
  const rest = raw.slice(GROUP_WIRE_PREFIX.length);
  const parts = rest.split("::");
  if (parts.length < 3 || !parts[0]) return null;
  return {
    groupId: parts[0].toLowerCase(),
    groupName: parts[1] || "Group",
    body: parts.slice(2).join("::"),
  };
}

export function buildGroupWire(groupId: string, name: string, body: string): string {
  // iOS parses with UUID(uuidString:) which is case-insensitive; uppercase
  // matches what Swift's uuidString emits so both sides read identically.
  return `${GROUP_WIRE_PREFIX}${groupId.toUpperCase()}::${name}::${body}`;
}

/** My registry rows (owner or member) — RLS scopes the select. */
export async function fetchMyGroupThreads(): Promise<GroupThread[]> {
  const { data, error } = await supabase
    .from("whisper_group_threads")
    .select("*")
    .order("created_at", { ascending: false });
  if (error) throw new Error("Couldn't refresh your groups. Please try again.");
  return (data as GroupThread[] | null) ?? [];
}

/** Creates a registry row + says hello on the wire so iOS members see it. */
export async function createGroupThread(input: {
  name: string;
  owner: GroupPerson;
  members: GroupPerson[];
  businessId?: string | null;
}): Promise<GroupThread> {
  const members = input.members.filter((m) => m.id !== input.owner.id);
  if (members.length === 0) throw new Error("Add at least one person.");
  const name = input.name.trim() || `Group · ${members.slice(0, 3).map((m) => m.username).join(", ")}`;
  const row: GroupThread = {
    id: crypto.randomUUID(),
    name,
    owner_id: input.owner.id,
    member_ids: members.map((m) => m.id),
    member_usernames: members.map((m) => m.username),
    business_id: input.businessId ?? null,
    created_at: new Date().toISOString(),
  };
  const { error } = await supabase.from("whisper_group_threads").insert(row);
  if (error) {
    if (error.code === "42P01") {
      throw new Error("Group chats need a one-time update — run supabase/business-plus.sql.");
    }
    throw new Error("Couldn't create the group. Try again.");
  }
  await sendGroupMessage(row, input.owner, `created the group "${name}" 👋`).catch(() => undefined);
  return row;
}

/** Everyone who should receive a message from `sender` in this group. */
function recipientsFor(group: GroupThread, senderId: string): GroupPerson[] {
  const everyone: GroupPerson[] = group.member_ids.map((id, i) => ({
    id,
    username: group.member_usernames[i] ?? "member",
  }));
  // The owner isn't stored in member_ids — members' sends must reach them.
  if (!everyone.some((p) => p.id === group.owner_id)) {
    everyone.push({ id: group.owner_id, username: "owner" });
  }
  return everyone.filter((p) => p.id !== senderId);
}

/** Fan-out send — one whisper_messages row per recipient (the iOS wire). */
export async function sendGroupMessage(
  group: GroupThread,
  from: GroupPerson,
  body: string,
  assertCurrent: () => void = () => {}
): Promise<void> {
  assertCurrent();
  const latest = await freshGroupForSend(group.id, from.id);
  assertCurrent();
  const wire = buildGroupWire(latest.id, latest.name, body);
  const targets = recipientsFor(latest, from.id);
  if (targets.length === 0) throw new Error("This group has no other members yet.");
  const logicalID = crypto.randomUUID();
  const results = await Promise.allSettled(
    targets.map((t) => sendMessage(from.id, from.username, t.id, t.username, wire, assertCurrent, "direct", logicalID))
  );
  if (!results.some((r) => r.status === "fulfilled")) {
    throw new Error("Couldn't send to the group. Try again.");
  }
}

/** Owner-only rename (RLS enforces it) — announces on the wire so iOS
 *  members see the new name immediately. */
export async function renameGroupThread(
  group: GroupThread,
  me: GroupPerson,
  name: string
): Promise<GroupThread> {
  const trimmed = name.trim();
  if (!trimmed) throw new Error("Give the group a name.");
  const { data, error } = await supabase
    .from("whisper_group_threads")
    .update({ name: trimmed })
    .eq("id", group.id)
    .select("id");
  if (error || !data || data.length === 0) {
    throw new Error("Only the group's creator can rename it.");
  }
  const next = { ...group, name: trimmed };
  await sendGroupMessage(next, me, `renamed the group to “${trimmed}”`).catch(
    () => undefined
  );
  return next;
}

/** Owner-only, fresh CAS roster update. No duplicate client announcement on retry. */
export async function addGroupMembers(
  group: GroupThread,
  me: GroupPerson,
  people: GroupPerson[]
): Promise<GroupThread> {
  return changeGroupRoster(group.id, me.id, { add: people });
}

/** Owner-only: removes one member from the roster (they stop receiving new
 *  messages — the wire history in their DMs stays theirs). */
export async function removeGroupMember(
  group: GroupThread,
  me: GroupPerson,
  person: GroupPerson
): Promise<GroupThread> {
  return changeGroupRoster(group.id, me.id, { remove: person.id });
}

/** Owner-only delete — the registry row goes away; everyone's DM history
 *  keeps the messages they already received. */
export async function deleteGroupThread(groupId: string): Promise<void> {
  const { error } = await supabase
    .from("whisper_group_threads")
    .delete()
    .eq("id", groupId);
  if (error) throw new Error("Couldn't delete the group.");
}

/**
 * "Leave group" for non-owners. The registry is owner-controlled (RLS), so a
 * member leaves by saying goodbye on the wire and hiding the group locally —
 * honest and instant; the owner can remove them from the roster for good.
 */
const LEFT_GROUPS_KEY = "whisper_left_groups";

export function loadLeftGroupIds(): Set<string> {
  try {
    const raw = localStorage.getItem(LEFT_GROUPS_KEY);
    const arr = raw ? (JSON.parse(raw) as string[]) : [];
    return new Set(arr.map((s) => s.toLowerCase()));
  } catch {
    return new Set();
  }
}

function markGroupLeft(groupId: string): void {
  const next = loadLeftGroupIds();
  next.add(groupId.toLowerCase());
  try {
    localStorage.setItem(LEFT_GROUPS_KEY, JSON.stringify(Array.from(next)));
  } catch {
    // Storage full/blocked — leaving still announced on the wire.
  }
}

export async function leaveGroup(
  group: GroupThread,
  me: GroupPerson
): Promise<void> {
  await sendGroupMessage(group, me, "left the group").catch(() => undefined);
  markGroupLeft(group.id);
}

// ─── Thread grammar shared with iOS ───────────────────────────────────────────

/** Roster events both platforms announce on the wire — rendered as quiet
 *  system lines instead of bubbles. */
export function isGroupSystemLine(body: string): boolean {
  const b = body.trim();
  return (
    b.startsWith("created the group") ||
    b.startsWith("renamed the group to") ||
    b.startsWith("added @") ||
    b.startsWith("removed @") ||
    b === "left the group"
  );
}

export interface GroupReplyQuote {
  username: string;
  text: string;
}

/** What kind of thing a quote line points at — drives the MINI CARD a reply
 *  shows instead of the full card (mirrors iOS `WhisperChatQuotePreview`). */
export type QuoteCardKind =
  | "wave"
  | "post"
  | "photo"
  | "gif"
  | "sticker"
  | "profile"
  | "chart"
  | "map"
  | "recipe"
  | "film"
  | "article"
  | "meeting"
  | "jasper"
  | "card";

/** The friendly ONE-LINE label a message reads as inside a quote — media and
 *  every card collapse to a label ("Shared a wave · caption", "Photo", …);
 *  plain text stays plain text. Deterministic and identical to iOS
 *  `WhisperChatReply.quoteText`, so a quote written on one platform reads
 *  the same on the other and never carries raw card wire. */
export function quoteLabelFor(body: string | null | undefined): string {
  const t = (body ?? "").trim();
  if (!t) return "";
  if (t.startsWith("↩ @")) {
    const inner = splitGroupReply(t);
    if (inner.quote) return quoteLabelFor(inner.text);
  }
  if (chatVideoUrl(t)) return "Video";
  if (isBareImageUrl(t)) {
    const lower = t.toLowerCase();
    return lower.includes(".gif") || lower.includes("giphy.com") ? "GIF" : "Photo";
  }
  if (jasperStickerName(t)) return "Sticker";
  if (t.startsWith(SHARED_COMMUNITY_PREFIX)) {
    const community = decodeSharedCommunity(t);
    return community ? `Shared a community · ${community.name}` : "Shared a community";
  }
  const post = decodeSharedPost(t);
  if (post) {
    const isWave = post.isReel === true || post.isVideo;
    const caption = stripPostMeta(post.caption).replace(/\n/g, " ").trim();
    const head = isWave ? "Shared a wave" : "Shared a post";
    return caption ? `${head} · ${caption.slice(0, 60)}` : head;
  }
  const profile = decodeSharedProfile(t);
  if (profile) return `Shared a profile · @${profile.username}`;
  if (t.startsWith("::") || t.startsWith("{")) {
    if (t.startsWith("::whisper-chart")) return "Sent a chart";
    if (t.startsWith("::whisper-map")) return "Sent a map";
    if (t.startsWith("::whisper-recipe")) return "Shared a recipe";
    if (t.startsWith("::whisper-film")) return "Shared a film";
    if (t.startsWith("::whisper-article")) return "Shared an article";
    if (t.startsWith("::whisper-ember-answer") || t.startsWith("::whisper-jasper")) return "Knot answered";
    if (t.startsWith("::whisper-factcheck")) return "Fact check";
    if (t.startsWith("::whisper-meeting-notes")) return "Meeting notes";
    if (t.startsWith("::whisper-grocery")) return "Shared a grocery list";
    if (t.startsWith("::whisper-checkin")) return "Check-in";
    if (t.startsWith("::whisper-workout")) return "Shared a workout";
    if (t.startsWith("::whisper-program")) return "Sent a training program";
    if (t.startsWith("::whisper-healthshare")) return "Shared health stats";
    return "Shared a card";
  }
  if (/\/meet\/[0-9a-f-]{36}|wsp-[a-z0-9]{4}-[a-z0-9]{4}/i.test(t)) return "Meeting link";
  return t;
}

/** The card kind behind a quote LINE (as written by `quoteLabelFor` on either
 *  platform), or null when the quote is plain text. */
export function quoteCardKind(quoteText: string): QuoteCardKind | null {
  const q = quoteText.trim();
  if (!q) return null;
  if (q.startsWith("::") || q.startsWith("{")) return "card";
  if (q === "Video" || chatVideoUrl(q)) return "film";
  if (q.startsWith("Shared a wave")) return "wave";
  if (q.startsWith("Shared a post")) return "post";
  if (q === "Photo" || q.startsWith("Sent a photo")) return "photo";
  if (q === "GIF") return "gif";
  if (q === "Sticker" || q.startsWith("Sent a sticker")) return "sticker";
  if (q.startsWith("Shared a profile")) return "profile";
  if (q.startsWith("Sent a chart")) return "chart";
  if (q.startsWith("Sent a map")) return "map";
  if (q.startsWith("Shared a recipe") || q.startsWith("Shared recipe")) return "recipe";
  if (q.startsWith("Shared a film")) return "film";
  if (q.startsWith("Shared an article")) return "article";
  if (q === "Meeting link" || q.startsWith("Meeting notes")) return "meeting";
  if (q.startsWith("Jasper answered") || q.startsWith("Fact check")) return "jasper";
  if (
    q.startsWith("Shared a card") ||
    q.startsWith("Shared an attachment") ||
    q.startsWith("Shared a grocery") ||
    q.startsWith("Shared a workout") ||
    q.startsWith("Shared health") ||
    q.startsWith("Sent a training") ||
    q === "Check-in" ||
    q.startsWith("Program ·") ||
    q.startsWith("Workout ·") ||
    q.startsWith("Diet plan ·") ||
    q.startsWith("Coach questionnaire") ||
    q.startsWith("Questionnaire answers")
  ) {
    return "card";
  }
  return null;
}

/** Builds the plain-text reply-quote prefix every client can read:
 *  `↩ @name: "quoted…"\n\nreply` (iOS `WhisperGroupChatService.replyBody`).
 *  The quoted line is the message's FRIENDLY label — never raw card wire, so
 *  a reply to a card can't decode as the card — and inner quotes become
 *  apostrophes so the `"…"` framing parses on every client. */
export function buildGroupReplyBody(quoted: GroupChatMessage, text: string): string {
  const snippet = quoteLabelFor(quoted.body).replace(/\n/g, " ").replace(/"/g, "'").trim();
  const clipped = snippet.length > 90 ? `${snippet.slice(0, 90)}…` : snippet;
  return `↩ @${quoted.fromUsername}: "${clipped}"\n\n${text}`;
}

/** Splits a `↩ @name: "quote"\n\nreply` body into its quote and text. */
export function splitGroupReply(body: string): { quote: GroupReplyQuote | null; text: string } {
  if (!body.startsWith("↩ @")) return { quote: null, text: body };
  const m = body.match(/^↩ @([^:]+): "([^"]*)"\s*([\s\S]*)$/);
  if (!m) return { quote: null, text: body };
  return { quote: { username: m[1], text: m[2] }, text: m[3].trim() };
}

/** Device-local per-message reactions (message key → emoji), like DMs. */
const REACTIONS_KEY = "whisper_group_reactions";
export function loadGroupReactions(): Record<string, string> {
  try {
    const raw = localStorage.getItem(REACTIONS_KEY);
    const parsed = raw ? (JSON.parse(raw) as Record<string, string>) : {};
    return typeof parsed === "object" && parsed ? parsed : {};
  } catch {
    return {};
  }
}
export function saveGroupReactions(map: Record<string, string>): void {
  try {
    localStorage.setItem(REACTIONS_KEY, JSON.stringify(map));
  } catch {
    /* storage blocked */
  }
}

/** Device-local pinned message per group. */
const PINS_KEY = "whisper_group_pins";
export function loadPinnedMessageKey(groupId: string): string | null {
  try {
    const raw = localStorage.getItem(PINS_KEY);
    const map = raw ? (JSON.parse(raw) as Record<string, string>) : {};
    return map[groupId.toLowerCase()] ?? null;
  } catch {
    return null;
  }
}
export function savePinnedMessageKey(groupId: string, key: string | null): void {
  try {
    const raw = localStorage.getItem(PINS_KEY);
    const map = raw ? (JSON.parse(raw) as Record<string, string>) : {};
    if (key) map[groupId.toLowerCase()] = key;
    else delete map[groupId.toLowerCase()];
    localStorage.setItem(PINS_KEY, JSON.stringify(map));
  } catch {
    /* storage blocked */
  }
}

/** Device-local muted groups. */
const MUTED_KEY = "whisper_group_muted";
export function isGroupMuted(groupId: string): boolean {
  try {
    const raw = localStorage.getItem(MUTED_KEY);
    const arr = raw ? (JSON.parse(raw) as string[]) : [];
    return arr.map((s) => s.toLowerCase()).includes(groupId.toLowerCase());
  } catch {
    return false;
  }
}
export function toggleGroupMute(groupId: string): boolean {
  try {
    const raw = localStorage.getItem(MUTED_KEY);
    const set = new Set((raw ? (JSON.parse(raw) as string[]) : []).map((s) => s.toLowerCase()));
    const id = groupId.toLowerCase();
    const next = !set.has(id);
    if (next) set.add(id);
    else set.delete(id);
    localStorage.setItem(MUTED_KEY, JSON.stringify(Array.from(set)));
    return next;
  } catch {
    return false;
  }
}

/** Every group-wire row I can see (sent or received), newest last. */
export async function fetchGroupWireRows(userId: string): Promise<WhisperMessage[]> {
  const [inbound, outbound] = await Promise.all([
    supabase
      .from("whisper_messages")
      .select("*")
      .eq("to_user_id", userId)
      .like("body", `${GROUP_WIRE_PREFIX}%`)
      .order("created_at", { ascending: false })
      .limit(600),
    supabase
      .from("whisper_messages")
      .select("*")
      .eq("from_user_id", userId)
      .like("body", `${GROUP_WIRE_PREFIX}%`)
      .order("created_at", { ascending: false })
      .limit(600),
  ]);
  if (inbound.error || outbound.error) throw new Error("Couldn't load group messages. Please try again.");
  return [
    ...((inbound.data as WhisperMessage[] | null) ?? []),
    ...((outbound.data as WhisperMessage[] | null) ?? []),
  ];
}

/** A group visible to me — registry-backed or discovered from the wire. */
export interface GroupInbox {
  thread: GroupThread;
  /** True when there's no registry row (an iOS-created group) — replies
   *  fan out to the senders we've seen so far. */
  discovered: boolean;
  lastBody: string | null;
  lastFrom: string | null;
  lastDate: string | null;
  unread?: number;
}

/** One clean message per group event — the sender's N fan-out copies of the
 *  same message collapse into one bubble. */
export interface GroupChatMessage {
  key: string;
  fromUserId: string;
  fromUsername: string;
  body: string;
  createdAt: string | null;
  receipts?: { userID: string; username: string; readAt: string }[];
  deliveryIDs?: string[];
  reactionMessageID?: string;
  logicalGroupMessageID?: string | null;
}

export function collectGroupMessages(
  rows: WhisperMessage[],
  groupId: string
): GroupChatMessage[] {
  const byKey = new Map<string, GroupChatMessage>();
  const seenIDs = new Set<string>();
  const out: GroupChatMessage[] = [];
  const ordered = [...rows].sort((a, b) => (a.created_at ?? "").localeCompare(b.created_at ?? "") || a.id.localeCompare(b.id));
  for (const row of ordered) {
    const parsed = parseGroupWire(row.body);
    if (!parsed || parsed.groupId !== groupId.toLowerCase()) continue;
    if (typeof row.id !== "string" || typeof row.from_user_id !== "string" || typeof row.to_user_id !== "string") continue;
    if (seenIDs.has(row.id.toLowerCase())) continue;
    seenIDs.add(row.id.toLowerCase());
    const event = meetEventID(parsed.body);
    const bucket = row.created_at ? row.created_at.slice(0, 18) : row.id;
    const key = row.logical_group_message_id
      ? `${row.from_user_id.toLowerCase()}|message:${row.logical_group_message_id.toLowerCase()}`
      : `${row.from_user_id.toLowerCase()}|${event ? `meet:${event}` : `${parsed.body}|${bucket}`}`;
    let message = byKey.get(key);
    if (!message) {
      message = { key, fromUserId: row.from_user_id, fromUsername: row.from_username ?? "member", body: parsed.body, createdAt: row.created_at, receipts: [], deliveryIDs: [], reactionMessageID: row.id, logicalGroupMessageID: row.logical_group_message_id };
      byKey.set(key, message);
      out.push(message);
    }
    message.deliveryIDs?.push(row.id);
    if (row.read_at && Number.isFinite(Date.parse(row.read_at)) && !message.receipts?.some(r => r.userID === row.to_user_id.toLowerCase())) {
      message.receipts?.push({ userID: row.to_user_id.toLowerCase(), username: row.to_username ?? "Member", readAt: row.read_at });
    }
  }
  out.sort(
    (a, b) => new Date(a.createdAt ?? 0).getTime() - new Date(b.createdAt ?? 0).getTime()
  );
  return out;
}

/**
 * Merge registry threads with wire-discovered groups into the Groups inbox.
 * Discovered rosters grow as more members speak (their sends reach us).
 */
export function buildGroupInbox(
  userId: string,
  threads: GroupThread[],
  rows: WhisperMessage[]
): GroupInbox[] {
  const byId = new Map<string, GroupInbox>();
  for (const t of threads) {
    byId.set(t.id.toLowerCase(), {
      thread: { ...t, id: t.id.toLowerCase() },
      discovered: false,
      lastBody: null,
      lastFrom: null,
      lastDate: null,
    });
  }
  const unreadIDs = new Set<string>();
  for (const row of rows) {
    const parsed = parseGroupWire(row.body);
    if (!parsed) continue;
    let entry = byId.get(parsed.groupId);
    if (!entry) {
      entry = {
        thread: {
          id: parsed.groupId,
          name: parsed.groupName,
          owner_id: row.from_user_id,
          member_ids: [],
          member_usernames: [],
          business_id: null,
          created_at: row.created_at,
        },
        discovered: true,
        lastBody: null,
        lastFrom: null,
        lastDate: null,
      };
      byId.set(parsed.groupId, entry);
    }
    if (row.to_user_id?.toLowerCase() === userId.toLowerCase() && row.from_user_id?.toLowerCase() !== userId.toLowerCase() && !row.read_at && !unreadIDs.has(row.id)) {
      unreadIDs.add(row.id);
      entry.unread = (entry.unread ?? 0) + 1;
    }
    // Grow discovered rosters from every participant we can see.
    if (entry.discovered) {
      for (const [pid, pname] of [
        [row.from_user_id, row.from_username ?? "member"],
        [row.to_user_id, row.to_username ?? "member"],
      ] as const) {
        if (!pid || pid === userId) continue;
        if (!entry.thread.member_ids.includes(pid)) {
          entry.thread.member_ids.push(pid);
          entry.thread.member_usernames.push(pname);
        }
      }
      entry.thread.name = parsed.groupName || entry.thread.name;
    }
    const t = new Date(row.created_at ?? 0).getTime();
    if (t >= new Date(entry.lastDate ?? 0).getTime()) {
      entry.lastBody = parsed.body;
      entry.lastFrom = row.from_username ?? "member";
      entry.lastDate = row.created_at;
    }
  }
  return Array.from(byId.values()).sort(
    (a, b) =>
      new Date(b.lastDate ?? b.thread.created_at ?? 0).getTime() -
      new Date(a.lastDate ?? a.thread.created_at ?? 0).getTime()
  );
}
