import { supabase } from "./supabase";
import { conversationThreadId, type ConversationKind } from "./conversationIdentity";
import { beforeMessage, messagePage, OLDER_MESSAGE_LIMIT, RECENT_MESSAGE_LIMIT, type MessageCursor, type MessagePage } from "./messageHistory";
import type { WhisperMessage } from "./types";
import { currentMessageCacheRevision, invalidateMessageSnapshots, saveMessageSnapshot } from "./messageCache";

// This stores no content or identities. A mutation invalidates SELECT snapshots
// already in flight, including an older row not loaded when it was unsent.
let historyRevision = 0;
export function invalidateHistorySnapshot(): void { historyRevision++; invalidateMessageSnapshots(); }
export function currentHistoryRevision(): number { return historyRevision; }

export async function fetchConversationHistory(owner: string, peer: string, kind: ConversationKind,
  cursor: MessageCursor | null, signal?: AbortSignal): Promise<MessagePage> {
  const revision = historyRevision;
  const cacheRevision = currentMessageCacheRevision();
  const assertOwner = async () => {
    const { data } = await supabase.auth.getSession();
    if (signal?.aborted || data.session?.user.id.toLowerCase() !== owner.toLowerCase()) {
      throw new Error("Your account changed. Reopen this conversation.");
    }
  };
  await assertOwner();
  if (![owner, peer].every(id => /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(id))) throw new Error("Invalid conversation.");
  const datingID = await conversationThreadId(owner, peer, "dating");
  // PostgREST stores `or` in a single URL parameter: chained .or() calls
  // overwrite earlier restrictions. Compose all alternatives under one AND.
  const clauses = [
    `or(and(from_user_id.eq.${owner},to_user_id.eq.${peer}),and(from_user_id.eq.${peer},to_user_id.eq.${owner}))`,
    "or(body.is.null,body.not.like.::wg-v1::%)",
    "or(body.is.null,body.not.like.::whisper-call-%)",
    kind === "dating" ? `thread_id.eq.${datingID}` : `or(thread_id.is.null,thread_id.neq.${datingID})`,
  ];
  if (cursor) clauses.push(`or(${beforeMessage(cursor)})`);
  const request = supabase.from("whisper_messages").select("*").or(`and(${clauses.join(",")})`);
  const limit = cursor ? OLDER_MESSAGE_LIMIT : RECENT_MESSAGE_LIMIT;
  const ordered = request.order("created_at", { ascending: false, nullsFirst: false }).order("id", { ascending: false }).limit(limit + 1);
  const { data, error } = await (signal ? ordered.abortSignal(signal) : ordered);
  await assertOwner();
  if (error || revision !== historyRevision) throw new Error("Messages couldn't refresh. Please try again.");
  const page = messagePage((data as WhisperMessage[] | null) ?? [], limit);
  if (!cursor) void saveMessageSnapshot(owner, `${kind}:${peer.toLowerCase()}`, page.messages, cacheRevision, signal);
  return page;
}
