import type { WhisperConversation } from "./types";

export type ConversationKind = "direct" | "dating";

/** Same namespaced SHA-256 identity as the native client. Legacy history stays direct. */
export async function conversationThreadId(a: string, b: string, kind: ConversationKind = "direct"): Promise<string> {
  const prefix = kind === "dating" ? "dating-v1:" : "";
  const ids = [prefix + a.toLowerCase(), prefix + b.toLowerCase()].sort();
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(ids.join("|")));
  const h = Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("").slice(0, 32);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
}

/** UI/recovery identity; never use this key as a database UUID. */
export function conversationKey(conversation: Pick<WhisperConversation, "otherUserId" | "kind">): string {
  return (conversation.kind === "dating" ? "dating:" : "") + conversation.otherUserId.toLowerCase();
}
