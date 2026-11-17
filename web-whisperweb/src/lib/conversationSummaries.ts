import { supabase } from "./supabase";
import { fetchProfilesByIds } from "./api";
import { conversationKey, type ConversationKind } from "./conversationIdentity";
import { currentHistoryRevision } from "./conversationHistory";
import type { MessageCursor } from "./messageHistory";
import type { WhisperConversation, WhisperMessage } from "./types";

export const INBOX_PAGE_LIMIT = 50;
export interface ThreadSummaryRow {
  peer_id: string;
  conversation_kind: ConversationKind;
  last_message_id: string;
  last_body: string;
  last_created_at: string | null;
  last_from_me: boolean;
  peer_username: string | null;
  unread_count: number | string;
  last_message: WhisperMessage;
}
export interface ConversationSummaryPage {
  conversations: WhisperConversation[];
  next: MessageCursor | null;
}

/** Continuation is derived before hiding/search/ranking/profile enrichment. */
export function summaryWindow(rows: ThreadSummaryRow[]) {
  const visible = rows.slice(0, INBOX_PAGE_LIMIT);
  const last = visible[visible.length - 1];
  return { rows: visible, next: rows.length > INBOX_PAGE_LIMIT && last
    ? { id: last.last_message_id, createdAt: last.last_created_at } : null };
}

export async function fetchConversationSummaries(owner: string, cursor: MessageCursor | null,
  signal?: AbortSignal): Promise<ConversationSummaryPage> {
  const revision = currentHistoryRevision();
  const assertCurrent = async () => {
    const { data } = await supabase.auth.getSession();
    if (signal?.aborted || data.session?.user.id.toLowerCase() !== owner.toLowerCase()) {
      throw new Error("Your account changed. Reopen messages.");
    }
    if (revision !== currentHistoryRevision()) throw new Error("Messages couldn't refresh. Please try again.");
  };
  await assertCurrent();
  const request = supabase.rpc("whisper_thread_summaries_v1", {
    p_limit: INBOX_PAGE_LIMIT,
    p_before_at: cursor?.createdAt ?? null,
    p_before_id: cursor?.id ?? null,
  });
  const { data, error } = await (signal ? request.abortSignal(signal) : request);
  await assertCurrent();
  if (error) throw new Error("Messages couldn't refresh. Please try again.");
  const page = summaryWindow((data ?? []) as ThreadSummaryRow[]);
  const profiles = await fetchProfilesByIds(page.rows.map(row => row.peer_id), { signal, requireSuccess: true });
  await assertCurrent();
  return {
    next: page.next,
    conversations: page.rows.map(row => {
      const profile = profiles[row.peer_id] ?? null;
      return {
        kind: row.conversation_kind, threadId: row.last_message.thread_id,
        otherUserId: row.peer_id,
        otherUsername: profile?.username ?? row.peer_username ?? "user",
        otherProfile: profile, lastMessage: row.last_body ?? "",
        lastDate: row.last_created_at, lastFromMe: row.last_from_me,
        unread: Number(row.unread_count), messages: [row.last_message],
      };
    }),
  };
}

/** A refreshed earlier page wins any overlap caused by inbox activity. */
export function uniqueConversations(pages: ConversationSummaryPage[]): WhisperConversation[] {
  const rows = new Map<string, WhisperConversation>();
  for (const page of pages) for (const row of page.conversations) {
    const key = conversationKey(row);
    if (!rows.has(key)) rows.set(key, row);
  }
  return [...rows.values()];
}
