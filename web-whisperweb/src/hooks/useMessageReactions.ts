import { useRef } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { supabase } from "@/lib/supabase";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";

export interface MessageReaction { message_id: string; emoji: string; reaction_count: number; mine: boolean }
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Uses the native client's RPCs, never local-only reaction selections. */
export function useMessageReactions(account: string, thread: string, messageIDs: string[]) {
  const client = useQueryClient();
  const begin = useChatOperationGuard(account, thread);
  const busy = useRef(new Set<string>());
  const ids = [...new Set(messageIDs.filter(id => uuid.test(id)).map(id => id.toLowerCase()))].sort();
  const prefix = ["shared-message-reactions", account, thread];
  const query = useQuery({
    queryKey: [...prefix, ids.join(",")],
    enabled: !!account && ids.length > 0,
    staleTime: 2_000,
    refetchInterval: () => document.visibilityState === "visible" && busy.current.size === 0 ? 3_000 : false,
    queryFn: async ({ signal }): Promise<Record<string, MessageReaction[]>> => {
      const check = begin();
      const { data: session } = await supabase.auth.getSession();
      check();
      if (session.session?.user.id !== account) throw new Error("Account changed.");
      const result: Record<string, MessageReaction[]> = {};
      for (let start = 0; start < ids.length; start += 200) {
        const { data, error } = await supabase.rpc("whisper_get_message_reactions", { p_message_ids: ids.slice(start, start + 200) }).abortSignal(signal);
        check();
        if (error) throw error;
        for (const row of (data ?? []) as MessageReaction[]) (result[row.message_id.toLowerCase()] ??= []).push(row);
      }
      return result;
    },
  });
  const toggle = async (id: string | undefined, emoji: string, legacy = false): Promise<void> => {
    if (legacy) { toast.error("This older group message has no shared identity. React to a new message instead."); return; }
    if (!id || !uuid.test(id)) { toast.error("Wait for this message to finish sending, then try again."); return; }
    if (busy.current.has(id)) return;
    const check = begin();
    busy.current.add(id);
    try {
      const { data } = await supabase.auth.getSession();
      check();
      if (data.session?.user.id !== account) throw new Error("Account changed.");
      await client.cancelQueries({ queryKey: prefix });
      check();
      const { error } = await supabase.rpc("whisper_toggle_message_reaction", { p_message_id: id, p_emoji: emoji, p_operation_id: crypto.randomUUID() });
      check();
      if (error) throw error;
      await client.cancelQueries({ queryKey: prefix });
      check();
      await client.invalidateQueries({ queryKey: prefix });
    } catch {
      try { check(); toast.error("Couldn't confirm your reaction. Check your connection and try again."); } catch { /* Obsolete conversation. */ }
    } finally { busy.current.delete(id); }
  };
  return { rows: query.data ?? {}, toggle };
}
