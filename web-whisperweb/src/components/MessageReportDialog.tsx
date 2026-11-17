import { useState } from "react";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { supabase } from "@/lib/supabase";

export interface ReportMessageTarget { id: string; username: string; senderID: string; body: string }
export function MessageReportDialog({ account, thread, target, onClose }: { account: string; thread: string; target: ReportMessageTarget; onClose: () => void }) {
  const [reason, setReason] = useState("harassment");
  const [details, setDetails] = useState("");
  const [status, setStatus] = useState<"idle" | "busy" | "error" | "sent">("idle");
  const begin = useChatOperationGuard(account, `${thread}:report:${target.id}`);
  const submit = async () => {
    if (status !== "idle") return;
    const check = begin(); setStatus("busy");
    try {
      const { data: session } = await supabase.auth.getSession(); check();
      if (session.session?.user.id !== account) throw new Error("Account changed.");
      const { data, error } = await supabase.rpc("whisper_submit_report", { p_kind: "dm", p_target_id: target.id, p_target_username: target.username, p_reason: reason, p_details: details.trim() || null, p_context: { surface: "message", thread_id: thread, sender_id: target.senderID, message_body: target.body.slice(0, 8000) } });
      check();
      if (error || typeof data !== "string" || !/^[0-9a-f-]{36}$/i.test(data)) throw new Error("Report not confirmed.");
      setStatus("sent");
    } catch { try { check(); setStatus("error"); } catch { /* Obsolete conversation. */ } }
  };
  return <Dialog open onOpenChange={value => { if (!value && status !== "busy") onClose(); }}><DialogContent className="sm:max-w-md"><DialogHeader><DialogTitle>Report message</DialogTitle><DialogDescription>This message and the context you provide will be sent privately to reviewers. Reports do not automatically penalize someone.</DialogDescription></DialogHeader>
    {status === "sent" ? <><p role="status" className="text-sm">Your report was confirmed. Thank you for helping keep Whisper safe.</p><button type="button" className="min-h-11 rounded-xl bg-primary text-primary-foreground" onClick={onClose}>Done</button></> : <>
      <label className="space-y-2 text-sm">Reason<select aria-label="Report reason" disabled={status !== "idle"} value={reason} onChange={event => setReason(event.target.value)} className="block min-h-11 w-full rounded-xl border border-border bg-background px-3"><option value="harassment">Harassment or bullying</option><option value="spam">Spam or misleading</option><option value="hate">Hate speech</option><option value="scam">Scam or fraud</option><option value="other">Something else</option></select></label>
      <textarea aria-label="Additional report context" placeholder="Additional context (optional)" maxLength={4000} rows={3} value={details} disabled={status !== "idle"} onChange={event => setDetails(event.target.value)} className="rounded-xl border border-border bg-background p-3 text-sm" />
      {status === "error" && <p role="alert" className="text-sm text-destructive">The report couldn't be confirmed. No automatic retry was sent. <button className="underline" onClick={() => setStatus("idle")}>Try again</button></p>}
      <button type="button" disabled={status !== "idle"} className="min-h-11 rounded-xl bg-primary text-sm font-semibold text-primary-foreground disabled:opacity-40" onClick={() => void submit()}>{status === "busy" ? "Submitting…" : "Submit report"}</button>
    </>}
  </DialogContent></Dialog>;
}
