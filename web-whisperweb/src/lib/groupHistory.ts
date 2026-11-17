import { supabase } from "./supabase";
import { currentHistoryRevision } from "./conversationHistory";
import { OLDER_MESSAGE_LIMIT, RECENT_MESSAGE_LIMIT, type MessageCursor, type MessagePage } from "./messageHistory";
import type { WhisperMessage } from "./types";
import { currentMessageCacheRevision, saveMessageSnapshot } from "./messageCache";

export interface GroupHistoryEnvelope { cursor_at: string; cursor_id: string; messages: WhisperMessage[] }
export function groupHistoryPage(envelopes: GroupHistoryEnvelope[], limit: number): MessagePage {
  const selected = envelopes.slice(0, limit);
  const last = selected[selected.length - 1];
  const seen = new Set<string>();
  return {
    messages: selected.reverse().flatMap(envelope => envelope.messages).filter(row => {
      const key = row.id.toLowerCase();
      if (seen.has(key)) return false;
      seen.add(key); return true;
    }),
    next: envelopes.length > limit && last ? { createdAt: last.cursor_at, id: last.cursor_id } : null,
  };
}

/** The server pages logical messages before expanding RLS-authorized deliveries.
 * Never truncate the expanded rows: a sender needs every copy for receipts/unsend. */
export async function fetchGroupHistory(owner: string, group: string, cursor: MessageCursor | null, signal?: AbortSignal): Promise<MessagePage> {
  const revision = currentHistoryRevision();
  const cacheRevision = currentMessageCacheRevision();
  const assertOwner = async () => {
    const { data } = await supabase.auth.getSession();
    if (signal?.aborted || data.session?.user.id.toLowerCase() !== owner.toLowerCase()) throw new Error("Your account changed. Reopen this conversation.");
  };
  await assertOwner();
  if (![owner, group].every(id => /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(id))) throw new Error("Invalid conversation.");
  const limit = cursor ? OLDER_MESSAGE_LIMIT : RECENT_MESSAGE_LIMIT;
  const request = supabase.rpc("whisper_group_history_v1", {
    p_group_id: group, p_limit: limit,
    p_before_at: cursor?.createdAt ?? undefined, p_before_id: cursor?.id ?? undefined,
  });
  const { data, error } = await (signal ? request.abortSignal(signal) : request);
  await assertOwner();
  if (error || revision !== currentHistoryRevision()) throw new Error("Messages couldn't refresh. Please try again.");
  const envelopes = (data ?? []) as unknown as GroupHistoryEnvelope[];
  const page = groupHistoryPage(envelopes, limit);
  if (!cursor) void saveMessageSnapshot(owner, `group:${group.toLowerCase()}`, page.messages, cacheRevision, signal);
  return page;
}
