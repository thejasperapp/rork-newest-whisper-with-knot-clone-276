import { useEffect, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { groupThemeSession } from "@/lib/groupThemeSession";
import { supabaseUrl, supabaseAnonKey } from "@/lib/supabase";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { useDocumentVisible } from "@/hooks/useDocumentVisible";

/** Existing native moderation tables, with explicit intent and no automatic mutation retry. */
export function ConversationSafety({ accountID, peerID, username, onBlocked }: { accountID: string; peerID: string; username: string; onBlocked: () => void }) {
  const client = useQueryClient();
  const capture = useChatOperationGuard(accountID, peerID);
  const visible = useDocumentVisible();
  const [confirm, setConfirm] = useState<boolean>(false);
  const [reason, setReason] = useState<string>("spam");
  const lifetime = useRef<AbortController>(new AbortController());
  useEffect(() => { const controller = new AbortController(); lifetime.current = controller; return () => controller.abort(); }, [accountID, peerID, visible]);
  const key = ["conversation-block", accountID, peerID];
  const request = async (path: string, init: RequestInit = {}, signal?: AbortSignal, assertCurrent: () => void = capture()): Promise<unknown> => {
    const lifecycleSignal = lifetime.current.signal;
    const session = await groupThemeSession(accountID);
    try {
      session.check(); assertCurrent();
      if (lifecycleSignal.aborted || document.hidden) throw new Error("Reopen safety to continue.");
      const response = await fetch(`${supabaseUrl}/rest/v1/${path}`, { ...init, redirect: "error", signal: AbortSignal.any([session.signal, lifecycleSignal, AbortSignal.timeout(12000), ...(signal ? [signal] : [])]), headers: { apikey: supabaseAnonKey, Authorization: `Bearer ${session.token}`, "Content-Type": "application/json", Prefer: "return=representation", ...init.headers } });
      session.check(); assertCurrent();
      if (!response.ok) throw new Error("Couldn't confirm the change. Refresh the status before trying again.");
      const data: unknown = await response.json(); session.check(); assertCurrent(); return data;
    } finally { session.dispose(); }
  };
  const filter = `blocker_id=eq.${encodeURIComponent(accountID)}&blocked_user_id=eq.${encodeURIComponent(peerID)}`;
  const status = useQuery({ queryKey: key, enabled: visible, gcTime: 0, queryFn: async ({ signal }) => {
    const rows = await request(`whisper_blocks?select=blocked_user_id&${filter}`, {}, signal);
    if (!Array.isArray(rows) || rows.some(row => row?.blocked_user_id !== peerID)) throw new Error("Block status unavailable");
    return rows.length > 0;
  }, retry: false });
  const change = useMutation({ retry: false, mutationFn: async () => {
    const check = capture(); check();
    if (typeof status.data !== "boolean" || status.isError) throw new Error("Refresh the block status first.");
    const blocking = !status.data;
    const rows = await request(blocking ? "whisper_blocks?select=blocked_user_id" : `whisper_blocks?select=blocked_user_id&${filter}`, blocking ? { method: "POST", body: JSON.stringify({ blocker_id: accountID, blocked_user_id: peerID, blocked_username: username }) } : { method: "DELETE" }, undefined, check);
    check();
    if (!Array.isArray(rows) || rows.length !== 1 || rows[0]?.blocked_user_id !== peerID) throw new Error("Couldn't confirm the change. Refresh the status.");
    client.setQueryData(key, blocking); setConfirm(false);
    void client.invalidateQueries({ queryKey: ["conversations", accountID] });
    if (blocking) onBlocked();
  } });
  const permissionKey = ["contact-permission", accountID, peerID];
  const permission = useQuery({ queryKey: permissionKey, enabled: visible, gcTime: 0, retry: false, queryFn: async ({ signal }) => {
    const rows = await request(`whisper_contact_permissions?select=allowed&recipient_id=eq.${accountID}&sender_id=eq.${peerID}`, {}, signal);
    if (!Array.isArray(rows)) throw new Error("Contact permission unavailable");
    return rows[0]?.allowed === true;
  } });
  const permit = useMutation({ retry: false, mutationFn: async () => {
    const check = capture(); check();
    if (permission.isError || typeof permission.data !== "boolean") throw new Error("Refresh contact permission first");
    const allowed = !permission.data;
    const rows = await request("whisper_contact_permissions?on_conflict=recipient_id,sender_id", { method: "POST", headers: { Prefer: "resolution=merge-duplicates,return=representation" }, body: JSON.stringify({ recipient_id: accountID, sender_id: peerID, allowed, updated_at: new Date().toISOString() }) }, undefined, check);
    check(); if (!Array.isArray(rows) || rows.length !== 1 || rows[0]?.allowed !== allowed) throw new Error("Permission not confirmed");
    client.setQueryData(permissionKey, allowed);
  } });
  const report = useMutation({ retry: false, mutationFn: async () => {
    const check = capture(); check();
    const receipt = await request("rpc/whisper_submit_report", { method: "POST", body: JSON.stringify({ p_kind: "safety", p_target_id: peerID, p_target_username: username, p_reason: reason, p_context: { surface: "conversation" } }) }, undefined, check);
    check(); if (typeof receipt !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(receipt)) throw new Error("Report not confirmed. Please try again later.");
  } });
  return <div className="space-y-4 text-sm">
    <p>Blocks stop new direct-message delivery in either direction, including message attachments. They do not erase past messages or revoke downloaded media. Muted words are a local filter, not an access restriction.</p>
    <p>Adult-to-teen first contact requires the teen’s explicit permission. Unknown age does not bypass contact checks. Age is self-declared, not verified. A prior message alone is not permission.</p>
    <button className="min-h-11 font-medium disabled:opacity-50" disabled={!visible || permission.isFetching || permission.isError || permit.isPending || permit.isError || permission.data == null} onClick={() => permit.mutate()}>{permit.isPending ? "Saving permission…" : permission.data ? "Revoke explicit message permission" : "Explicitly allow this person to message me"}</button>
    <p className="text-xs text-muted-foreground">Allowing contact does not override a block or an active messaging restriction.</p>
    {(permission.isError || permit.isError) && <p role="alert">Contact permission not confirmed. <button className="min-h-11 underline" onClick={() => { permit.reset(); void permission.refetch(); }}>Refresh permission</button></p>}
    {(status.isError || change.isError) && <p role="alert" className="text-destructive">Block status or change could not be confirmed. <button className="min-h-11 underline" onClick={() => { change.reset(); setConfirm(false); void status.refetch(); }}>Refresh status</button></p>}
    <button disabled={!visible || status.isFetching || status.isError || change.isError || change.isPending || status.data == null} className="min-h-11 text-destructive disabled:opacity-50" onClick={() => setConfirm(true)}>{status.isFetching ? "Checking block status…" : status.data ? "Unblock this person" : "Block this person"}</button>
    {confirm && <div className="rounded-xl border border-border p-3"><p>{status.data ? "Unblock" : "Block"} @{username}?</p><div className="flex gap-5"><button className="min-h-11 font-semibold text-destructive" disabled={change.isPending || !visible} onClick={() => change.mutate()}>Confirm</button><button className="min-h-11" disabled={change.isPending} onClick={() => setConfirm(false)}>Cancel</button></div></div>}
    <label className="block space-y-2"><span>Report conversation</span><select aria-label="Report reason" value={reason} onChange={e => setReason(e.target.value)} disabled={report.isPending || report.isSuccess || report.isError} className="block min-h-11 w-full rounded-xl border border-border bg-background px-3"><option value="spam">Spam or misleading</option><option value="harassment">Harassment or bullying</option><option value="hate">Hate speech</option><option value="scam">Scam or fraud</option><option value="other">Something else</option></select></label>
    <button disabled={report.isPending || report.isSuccess || report.isError || !visible} className="min-h-11 font-medium disabled:opacity-50" onClick={() => report.mutate()}>{report.isSuccess ? "Report submitted" : report.isPending ? "Submitting…" : "Submit report"}</button>
    {report.isError && <p role="alert" className="text-destructive">Report could not be confirmed. No automatic retry was sent. <button className="min-h-11 underline" onClick={() => report.reset()}>Try again</button></p>}
  </div>;
}
