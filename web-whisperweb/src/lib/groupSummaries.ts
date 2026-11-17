import { supabase } from "./supabase";
import { currentHistoryRevision } from "./conversationHistory";
import { buildGroupInbox, parseGroupWire, type GroupInbox, type GroupThread } from "./groupChats";
import type { MessageCursor } from "./messageHistory";
import type { WhisperMessage } from "./types";

export interface GroupSummary {
  group_id: string;
  last_created_at: string;
  last_message_id: string;
  unread_count: number | string;
  last_message: WhisperMessage;
  participants: { user_id: string; username: string | null }[];
}
export interface GroupSummaryPage { groups: GroupSummary[]; next: MessageCursor | null }
export function groupSummaryPage(rows: GroupSummary[]): GroupSummaryPage {
  const groups = rows.slice(0, 50);
  const last = groups[groups.length - 1];
  return { groups, next: rows.length > 50 && last ? { id: last.last_message_id, createdAt: last.last_created_at } : null };
}
export function uniqueGroupSummaries(pages: GroupSummaryPage[]): GroupSummary[] {
  const groups = new Map<string, GroupSummary>();
  for (const page of pages) for (const row of page.groups) {
    const id = row.group_id.toLowerCase();
    if (!groups.has(id)) groups.set(id, row);
  }
  return [...groups.values()];
}
async function assertOwner(owner: string, signal?: AbortSignal) {
  const { data } = await supabase.auth.getSession();
  if (signal?.aborted || data.session?.user.id.toLowerCase() !== owner.toLowerCase()) throw new Error("Your account changed. Reopen messages.");
}
export async function fetchGroupSummaries(owner: string, cursor: MessageCursor | null, signal?: AbortSignal): Promise<GroupSummaryPage> {
  const revision = currentHistoryRevision();
  await assertOwner(owner, signal);
  const request = supabase.rpc("whisper_group_summaries_v1", {
    p_limit: 50, p_before_at: cursor?.createdAt ?? undefined, p_before_id: cursor?.id ?? undefined,
  });
  const { data, error } = await (signal ? request.abortSignal(signal) : request);
  await assertOwner(owner, signal);
  if (error || revision !== currentHistoryRevision()) throw new Error("Groups couldn't refresh. Please try again.");
  return groupSummaryPage((data ?? []) as unknown as GroupSummary[]);
}
export async function fetchGroupRegistry(owner: string, signal?: AbortSignal): Promise<GroupThread[]> {
  await assertOwner(owner, signal);
  const request = supabase.from("whisper_group_threads").select("*").order("created_at", { ascending: false });
  const { data, error } = await (signal ? request.abortSignal(signal) : request);
  await assertOwner(owner, signal);
  if (error) throw new Error("Groups couldn't refresh. Please try again.");
  return (data ?? []) as GroupThread[];
}
/** Registry rosters remain authoritative. Observed historical endpoints only
 * enrich legacy discovery and never confer current permission to send. */
export function groupSummaryInbox(owner: string, registry: GroupThread[], summaries: GroupSummary[]): GroupInbox[] {
  const inbox = buildGroupInbox(owner, registry, summaries.map(row => row.last_message));
  const lookup = new Map(summaries.map(row => [row.group_id.toLowerCase(), row]));
  return inbox.map(entry => {
    const summary = lookup.get(entry.thread.id.toLowerCase());
    if (!summary || !parseGroupWire(summary.last_message.body)) return entry;
    const result = { ...entry, unread: Number(summary.unread_count), lastDate: summary.last_created_at };
    if (entry.discovered) {
      const members = new Map<string, string>();
      for (const member of summary.participants) {
        const id = member.user_id.toLowerCase();
        if (id !== owner.toLowerCase()) members.set(id, member.username ?? "member");
      }
      result.thread = { ...entry.thread, member_ids: [...members.keys()], member_usernames: [...members.values()] };
    }
    return result;
  });
}
