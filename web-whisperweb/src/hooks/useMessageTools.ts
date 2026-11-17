import { useEffect, useState } from "react";
import { toast } from "sonner";
import { supabase } from "@/lib/supabase";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";

interface LocalTools { hidden: string[]; pinned: string | null }
const empty: LocalTools = { hidden: [], pinned: null };
function read(key: string): LocalTools {
  try { const data = JSON.parse(localStorage.getItem(key) ?? "null") as LocalTools | null; return data && Array.isArray(data.hidden) ? data : empty; } catch { return empty; }
}
/** Pins/deletions are explicitly browser-local, like the native device-local tools. */
export function useMessageTools(account: string, thread: string, onUnsent: () => void) {
  const key = `whisper-message-tools-v1:${account}:${thread}`;
  const [stored, setStored] = useState(() => ({ key, data: read(key) }));
  useEffect(() => setStored({ key, data: read(key) }), [key]);
  const data = stored.key === key ? stored.data : empty;
  const begin = useChatOperationGuard(account, thread);
  const update = (next: LocalTools) => {
    try { localStorage.setItem(key, JSON.stringify(next)); setStored({ key, data: next }); }
    catch { toast.error("Couldn't save this change in your browser."); }
  };
  const unsend = async (ids: string[], logicalID?: string | null): Promise<boolean> => {
    const check = begin();
    try {
      const { data: session } = await supabase.auth.getSession();
      check();
      if (session.session?.user.id !== account) throw new Error("Account changed.");
      let request = supabase.from("whisper_messages").delete().eq("from_user_id", account);
      request = logicalID ? request.eq("logical_group_message_id", logicalID) : request.in("id", ids);
      const { data: removed, error } = await request.select("id");
      check();
      onUnsent();
      if (error || !removed?.length || (!logicalID && removed.length !== new Set(ids).size)) throw new Error("Unsend wasn't fully confirmed.");
      toast.success("Message unsent. Previously saved copies can't be removed.");
      return true;
    } catch { try { check(); toast.error("Couldn't fully confirm unsend. Refresh and try again."); } catch { /* Obsolete conversation. */ } return false; }
  };
  return {
    hidden: new Set(data.hidden), pinned: data.pinned,
    hide: (id: string) => update({ ...data, hidden: [...new Set([...data.hidden, id])] }),
    pin: (id: string) => update({ ...data, pinned: data.pinned === id ? null : id }),
    unsend,
  };
}
