import { useEffect, useState } from "react";
import { Bug, Check, Loader2, Mail } from "lucide-react";
import { toast } from "sonner";

import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";
import { WHISPER_BRAND_GRADIENT_DIAGONAL } from "@/lib/brand";
import {
  BUG_CATEGORIES,
  bugReportMailto,
  submitBugReport,
  type BugCategory,
  type BugReportContext,
} from "@/lib/reports";

interface ReportBugDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Where the report was filed from — surface + optional meeting id. */
  context: BugReportContext;
  /** Preselect an area (e.g. "meetings" from the Meet landing). */
  defaultCategory?: BugCategory;
}

/**
 * Whisper's in-app bug report — the same rail the iOS "Report a problem"
 * sheet writes to (`whisper_submit_report`). Category tiles, what happened,
 * an optional page/browser snapshot, one ink Send. When the rail isn't
 * reachable (signed out, migration pending) the report opens as a prepared
 * support email instead, so it's never lost.
 */
export function ReportBugDialog({
  open,
  onOpenChange,
  context,
  defaultCategory = "other",
}: ReportBugDialogProps): JSX.Element {
  const [category, setCategory] = useState<BugCategory>(defaultCategory);
  const [details, setDetails] = useState<string>("");
  const [includeEnvironment, setIncludeEnvironment] = useState<boolean>(true);
  const [sending, setSending] = useState<boolean>(false);
  const [sent, setSent] = useState<boolean>(false);

  useEffect(() => {
    if (!open) return;
    setCategory(defaultCategory);
    setDetails("");
    setSending(false);
    setSent(false);
  }, [open, defaultCategory]);

  const canSend = details.trim().length >= 8 && !sending;

  const send = async (): Promise<void> => {
    if (!canSend) return;
    setSending(true);
    const payload = { category, details, includeEnvironment, context };
    try {
      const result = await submitBugReport(payload);
      if (result === "filed") {
        setSent(true);
        toast.success("Thanks — the report is in.");
        window.setTimeout(() => onOpenChange(false), 900);
        return;
      }
      window.location.href = bugReportMailto(payload);
      toast.message("Opening your email with the report ready to send.");
      onOpenChange(false);
    } catch {
      toast.error("Couldn't send the report. Try again in a moment.");
    } finally {
      setSending(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-[460px] rounded-[26px] border-border p-0 sm:rounded-[26px]">
        <DialogHeader className="px-6 pt-6">
          <div className="flex items-center gap-2.5">
            <span
              className="grid h-9 w-9 place-items-center rounded-full text-white"
              style={{ backgroundImage: WHISPER_BRAND_GRADIENT_DIAGONAL }}
            >
              <Bug className="h-4 w-4" />
            </span>
            <div>
              <DialogTitle className="text-[17px] font-bold tracking-tight">Report a bug</DialogTitle>
              <p className="text-[12.5px] text-muted-foreground">Tell us what broke — a real person reads every one.</p>
            </div>
          </div>
        </DialogHeader>

        <div className="px-6 pb-6 pt-4">
          <p className="text-[10.5px] font-bold uppercase tracking-[0.16em] text-muted-foreground">Where</p>
          <div className="mt-2 grid grid-cols-2 gap-1.5 sm:grid-cols-3">
            {BUG_CATEGORIES.map((c) => {
              const active = c.id === category;
              return (
                <button
                  key={c.id}
                  type="button"
                  onClick={() => setCategory(c.id)}
                  aria-pressed={active}
                  className={cn(
                    "rounded-2xl border px-3 py-2.5 text-left transition-colors",
                    active
                      ? "border-foreground bg-foreground text-background"
                      : "border-border bg-background hover:bg-secondary",
                  )}
                >
                  <span className="block text-[13px] font-semibold leading-tight">{c.label}</span>
                  <span className={cn("mt-0.5 block text-[11px] leading-tight", active ? "text-background/70" : "text-muted-foreground")}>
                    {c.hint}
                  </span>
                </button>
              );
            })}
          </div>

          <p className="mt-4 text-[10.5px] font-bold uppercase tracking-[0.16em] text-muted-foreground">What happened</p>
          <textarea
            value={details}
            onChange={(e) => setDetails(e.target.value)}
            rows={4}
            placeholder="What did you do, what did you expect, what happened instead?"
            className="mt-2 w-full resize-none rounded-2xl border border-border bg-background px-3.5 py-3 text-[14px] leading-relaxed outline-none transition-colors placeholder:text-muted-foreground/70 focus:border-foreground"
          />

          <label className="mt-3 flex cursor-pointer items-start gap-2.5 text-[12.5px] text-muted-foreground">
            <input
              type="checkbox"
              checked={includeEnvironment}
              onChange={(e) => setIncludeEnvironment(e.target.checked)}
              className="mt-0.5 h-4 w-4 rounded border-border accent-foreground"
            />
            <span>Include page & browser info (URL, browser, screen size — never your messages or personal data)</span>
          </label>

          <div className="mt-5 flex items-center justify-between gap-3">
            <a
              href={bugReportMailto({ category, details, includeEnvironment, context })}
              className="flex items-center gap-1.5 text-[12.5px] font-semibold text-muted-foreground transition-colors hover:text-foreground"
            >
              <Mail className="h-3.5 w-3.5" /> Email support instead
            </a>
            <button
              type="button"
              onClick={() => void send()}
              disabled={!canSend}
              className="flex h-11 items-center gap-2 rounded-full bg-foreground px-5 text-[14px] font-bold text-background transition-all hover:opacity-90 active:scale-[0.98] disabled:opacity-40"
            >
              {sent ? <Check className="h-4 w-4" /> : sending ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
              {sent ? "Sent" : "Send report"}
            </button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
