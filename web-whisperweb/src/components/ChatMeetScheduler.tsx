import { useEffect, useRef, useState } from "react";
import { Video } from "lucide-react";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { scheduleChatMeet, type ChatMeetInvitation, type ChatMeetScheduleRequest } from "@/lib/chatMeet";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { ChatMeetCard } from "@/components/ChatMeetCard";

export function ChatMeetScheduler({ owner, thread, kind, peerID, groupID, name, onClose, onScheduled }: {
  owner: string; thread: string; kind: "direct" | "dating" | "group"; peerID?: string; groupID?: string; name: string; onClose: () => void; onScheduled: () => void;
}) {
  const [title, setTitle] = useState(`Meet with ${name}`.slice(0, 120));
  const [when, setWhen] = useState(() => { const date = new Date(Date.now() + 3600000); return new Date(date.getTime() - date.getTimezoneOffset() * 60000).toISOString().slice(0, 16); });
  const [minutes, setMinutes] = useState(30);
  const [request, setRequest] = useState<ChatMeetScheduleRequest | null>(null);
  const [confirmed, setConfirmed] = useState<ChatMeetInvitation | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const controller = useRef<AbortController | null>(null);
  const begin = useChatOperationGuard(owner, thread);
  useEffect(() => {
    const inactive = (): void => { if (document.visibilityState !== "visible") controller.current?.abort(); };
    document.addEventListener("visibilitychange", inactive);
    return () => { controller.current?.abort(); document.removeEventListener("visibilitychange", inactive); };
  }, []);
  const close = (): void => {
    if (busy) return;
    if (request && !confirmed?.deliveryComplete && !window.confirm("Leave this meeting request? It may already have been saved. Check Meet before creating another; leaving does not cancel it.")) return;
    onClose();
  };
  const schedule = async (): Promise<void> => {
    if (busy || document.visibilityState !== "visible") return;
    const check = begin();
    const start = new Date(when);
    if (!request && (!title.trim() || !Number.isFinite(start.getTime()) || start.getTime() <= Date.now())) { setError("Choose a title and a future start time."); return; }
    const frozen: ChatMeetScheduleRequest = request ?? {
      operation_id: crypto.randomUUID(), conversation_kind: kind,
      ...(kind === "group" ? { group_id: groupID } : { peer_id: peerID }),
      title: title.trim(), starts_at: start.toISOString(), ends_at: new Date(start.getTime() + minutes * 60000).toISOString(), timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    };
    setRequest(frozen); setBusy(true); setError(null);
    const work = new AbortController(); controller.current = work;
    try {
      const result = await scheduleChatMeet(owner, frozen, work.signal, confirmed?.eventID); check();
      if (work.signal.aborted) throw new Error("Request interrupted. Keep this form and check the same meeting again.");
      if (confirmed && confirmed.meetingID !== result.meetingID) throw new Error("Meet’s response changed. Check the saved meeting in Meet.");
      setConfirmed(result);
      if (result.deliveryComplete && !result.cancelled) onScheduled();
    } catch (reason) { try { check(); setError(reason instanceof Error ? reason.message : "Couldn’t confirm this meeting."); } catch { /* Old account/thread. */ } }
    finally { try { check(); setBusy(false); controller.current = null; } catch { /* Closed. */ } }
  };
  return <Dialog open onOpenChange={open => { if (!open) close(); }}><DialogContent className="max-h-[88dvh] overflow-y-auto sm:max-w-lg" onEscapeKeyDown={event => { event.preventDefault(); close(); }} onPointerDownOutside={event => { event.preventDefault(); close(); }}>
    <DialogHeader><DialogTitle><span className="flex items-center gap-2"><Video className="h-5 w-5" />Schedule a Meet</span></DialogTitle><DialogDescription>Meet verifies this chat’s invitation permissions. Each recipient chooses Going or Not going; scheduling never joins a call.</DialogDescription></DialogHeader>
    <fieldset disabled={busy || !!request} className="space-y-3 disabled:opacity-60">
      <label className="block text-sm">Meeting title<input value={title} maxLength={120} onChange={event => setTitle(event.target.value)} className="mt-1 min-h-11 w-full rounded-xl border border-border bg-background px-3" /></label>
      <label className="block text-sm">Starts<input type="datetime-local" value={when} onChange={event => setWhen(event.target.value)} className="mt-1 min-h-11 w-full rounded-xl border border-border bg-background px-3" /></label>
      <label className="block text-sm">Duration<select value={minutes} onChange={event => setMinutes(Number(event.target.value))} className="mt-1 min-h-11 w-full rounded-xl border border-border bg-background px-3">{[15, 30, 45, 60, 90, 120].map(duration => <option key={duration} value={duration}>{duration} minutes</option>)}</select></label>
    </fieldset>
    <p className="text-xs leading-relaxed text-muted-foreground">{kind === "group" ? "Meet freezes the eligible server roster (2–20 people); no selected subset. Membership changes can revoke invitations." : kind === "dating" ? "Both eligible adults must currently choose Again for the same latest recorded date. Previous messages or a match alone do not qualify." : "The recipient must approve your one-way Meet invitation permission. A previous message does not grant it. Manage permission in Meet or the iPhone chat."}</p>
    {request && <p className="text-xs text-muted-foreground">This form keeps the same request for retries. Meet delivers the invitation cards; Whisper won’t send extra copies.</p>}
    {confirmed && <><p role="status" className="text-sm">{confirmed.cancelled ? "Meeting cancelled" : confirmed.deliveryComplete ? "Meeting scheduled and delivery confirmed" : "Meeting saved; invitation delivery is still pending."}</p><ChatMeetCard eventID={confirmed.eventID} /></>}
    {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    {!confirmed?.deliveryComplete && !confirmed?.cancelled && <button type="button" disabled={busy} onClick={() => void schedule()} className="min-h-11 rounded-full bg-foreground px-4 text-sm font-semibold text-background disabled:opacity-50">{busy ? "Confirming…" : confirmed ? "Retry invitation delivery" : request ? "Retry same meeting" : "Schedule invitation"}</button>}
    <button type="button" disabled={busy} onClick={close} className="min-h-11 rounded-full bg-secondary text-sm">{confirmed?.deliveryComplete ? "Done" : "Close"}</button>
    <a href="/meetings" target="_blank" rel="noopener noreferrer" className="min-h-11 py-3 text-center text-sm underline">Open Meetings</a>
  </DialogContent></Dialog>;
}
