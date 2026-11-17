import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Send } from "lucide-react";
import { toast } from "sonner";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Avatar } from "@/components/Avatar";
import { GroupAvatar } from "@/components/GroupAvatar";
import { fetchConversations, sendMessage } from "@/lib/api";
import { fetchMyGroupThreads, quoteLabelFor, sendGroupMessage } from "@/lib/groupChats";
import { isDmBlocked } from "@/lib/brands";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";

export function ForwardMessageDialog({ account, username, thread, body, onClose }: { account: string; username: string; thread: string; body: string | null; onClose: () => void }) {
  const [busy, setBusy] = useState(false);
  const [search, setSearch] = useState("");
  const client = useQueryClient();
  const begin = useChatOperationGuard(account, `${thread}:forward:${body ?? ""}`);
  const conversations = useQuery({ queryKey: ["forward-conversations", account], queryFn: () => fetchConversations(account), enabled: body !== null });
  const groups = useQuery({ queryKey: ["forward-groups", account], queryFn: fetchMyGroupThreads, enabled: body !== null });
  const forward = async (send: (check: () => void) => Promise<void>) => {
    if (busy) return;
    const check = begin();
    setBusy(true);
    try {
      check(); await send(check); check();
      void client.invalidateQueries({ queryKey: ["conversations"] });
      void client.invalidateQueries({ queryKey: ["group-wire", account] });
      toast.success("Forwarded"); onClose();
    } catch { try { check(); toast.error("Couldn't forward this message. Check contact permissions and try again."); } catch { /* Obsolete conversation. */ } }
    finally { try { check(); setBusy(false); } catch { /* Obsolete conversation. */ } }
  };
  const matches = (name: string) => name.toLowerCase().includes(search.toLowerCase());
  return <Dialog open={body !== null} onOpenChange={value => { if (!value && !busy) onClose(); }}><DialogContent className="max-h-[85dvh] overflow-y-auto sm:max-w-md"><DialogHeader><DialogTitle>Forward message</DialogTitle><DialogDescription>Choose who receives this message. Sending still follows contact permissions.</DialogDescription></DialogHeader>
    <p className="line-clamp-3 rounded-xl bg-secondary p-3 text-sm">{quoteLabelFor(body ?? "")}</p>
    <input aria-label="Search conversations" placeholder="Search conversations" value={search} onChange={event => setSearch(event.target.value)} className="min-h-11 rounded-xl border border-border bg-background px-3 text-sm" />
    {conversations.isLoading && <p className="text-sm text-muted-foreground">Loading conversations…</p>}
    {conversations.isError && <button onClick={() => void conversations.refetch()} className="min-h-11 text-sm">Couldn't load conversations · Retry</button>}
    {(conversations.data ?? []).filter(convo => matches(convo.otherUsername)).map(convo => <button key={`${convo.kind}:${convo.otherUserId}`} type="button" disabled={busy} className="flex min-h-14 items-center gap-3 rounded-xl px-2 text-left hover:bg-secondary disabled:opacity-40" onClick={() => void forward(async check => {
      if (await isDmBlocked(account, convo.otherUserId)) throw new Error("Contact unavailable.");
      check(); await sendMessage(account, username, convo.otherUserId, convo.otherUsername, body!, check, convo.kind ?? "direct");
    })}><Avatar url={convo.otherProfile?.profile_image_url} name={convo.otherUsername} size={36} /><span className="flex-1 text-sm">@{convo.otherUsername}{convo.kind === "dating" ? " · Dating" : ""}</span><Send className="h-4 w-4" /></button>)}
    {groups.isError && <button onClick={() => void groups.refetch()} className="min-h-11 text-sm">Couldn't load groups · Retry</button>}
    {(groups.data ?? []).filter(group => matches(group.name)).map(group => <button key={group.id} type="button" disabled={busy} className="flex min-h-14 items-center gap-3 rounded-xl px-2 text-left hover:bg-secondary disabled:opacity-40" onClick={() => void forward(check => sendGroupMessage(group, { id: account, username }, body!, check))}><GroupAvatar group={group} size={36} /><span className="flex-1 text-sm">{group.name}</span><Send className="h-4 w-4" /></button>)}
    {!conversations.isLoading && !groups.isLoading && !conversations.data?.length && !groups.data?.length && <p className="text-sm text-muted-foreground">No conversations available to forward to.</p>}
    {busy && <p role="status" className="text-sm text-muted-foreground">Forwarding…</p>}
  </DialogContent></Dialog>;
}
