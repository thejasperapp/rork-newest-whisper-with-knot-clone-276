/**
 * Live chat — Instagram/Twitch-style real-time chat for live rooms.
 *
 * Messages are stored in `whisper_live_chat_messages` and delivered via
 * Supabase Realtime postgres_changes. The host can pin messages; all
 * participants see messages stream in live.
 */

import { supabase } from "@/lib/supabase";

export interface LiveChatMessage {
  id: string;
  room_id: string;
  user_id: string;
  username: string;
  body: string;
  is_host: boolean;
  is_pinned: boolean;
  created_at: string;
}

/** Fetch recent chat messages for a room (newest last). */
export async function fetchChatMessages(
  roomId: string,
  limit = 100
): Promise<LiveChatMessage[]> {
  const { data, error } = await supabase
    .from("whisper_live_chat_messages")
    .select("*")
    .eq("room_id", roomId)
    .order("created_at", { ascending: true })
    .limit(limit);
  if (error) {
    console.warn("fetchChatMessages failed:", error.message);
    return [];
  }
  return (data as LiveChatMessage[] | null) ?? [];
}

/** Send a chat message. */
export async function sendChatMessage(input: {
  roomId: string;
  userId: string;
  username: string;
  body: string;
  isHost: boolean;
}): Promise<void> {
  const { error } = await supabase.from("whisper_live_chat_messages").insert({
    room_id: input.roomId,
    user_id: input.userId,
    username: input.username,
    body: input.body,
    is_host: input.isHost,
    is_pinned: false,
  });
  if (error) throw error;
}

/** Pin or unpin a message (host only). */
export async function togglePinMessage(
  messageId: string,
  pinned: boolean
): Promise<void> {
  const { error } = await supabase
    .from("whisper_live_chat_messages")
    .update({ is_pinned: pinned })
    .eq("id", messageId);
  if (error) throw error;
}

/** Delete a chat message (self or host). */
export async function deleteChatMessage(messageId: string): Promise<void> {
  const { error } = await supabase
    .from("whisper_live_chat_messages")
    .delete()
    .eq("id", messageId);
  if (error) throw error;
}

/**
 * Subscribe to realtime chat messages for a room.
 * Returns an unsubscribe function.
 */
export function subscribeToChatMessages(
  roomId: string,
  onMessage: (message: LiveChatMessage) => void,
  onDelete?: (messageId: string) => void
): () => void {
  const channel = supabase
    .channel(`live-chat:${roomId}`, {
      config: { broadcast: { self: false } },
    })
    .on(
      "postgres_changes",
      {
        event: "INSERT",
        schema: "public",
        table: "whisper_live_chat_messages",
        filter: `room_id=eq.${roomId}`,
      },
      (payload) => {
        onMessage(payload.new as LiveChatMessage);
      }
    )
    .on(
      "postgres_changes",
      {
        event: "DELETE",
        schema: "public",
        table: "whisper_live_chat_messages",
        filter: `room_id=eq.${roomId}`,
      },
      (payload) => {
        if (payload.old && onDelete) {
          onDelete((payload.old as { id: string }).id);
        }
      }
    )
    .subscribe();

  return () => {
    void supabase.removeChannel(channel);
  };
}
