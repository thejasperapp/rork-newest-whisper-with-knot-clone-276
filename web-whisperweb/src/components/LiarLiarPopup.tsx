import { useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { MessageSquareWarning } from "lucide-react";
import { toast } from "sonner";

import {
  acknowledgeLiarBadge,
  fetchMyLiarBadge,
  submitLiarAppeal,
} from "@/lib/api";
import { useAuth } from "@/hooks/useAuth";

/**
 * One-time explainer shown to the signed-in user when they earn the Liar Liar
 * badge, mirroring the iOS popup: reason card, appeal CTA, and a dismiss that
 * records `acknowledged_at` so it never re-appears for the same badge.
 */
export function LiarLiarPopup() {
  const { profile } = useAuth();
  const queryClient = useQueryClient();
  const username = profile?.username ?? "";
  const [open, setOpen] = useState<boolean>(true);
  const [appealing, setAppealing] = useState<boolean>(false);
  const [appealText, setAppealText] = useState<string>("");

  const badgeQuery = useQuery({
    queryKey: ["my-liar-badge", username],
    queryFn: () => fetchMyLiarBadge(username),
    enabled: !!username,
  });

  const badge = badgeQuery.data;

  const ack = useMutation({
    mutationFn: () => acknowledgeLiarBadge(username),
    onSuccess: () => {
      setOpen(false);
      queryClient.invalidateQueries({ queryKey: ["my-liar-badge", username] });
    },
  });

  const appeal = useMutation({
    mutationFn: () => submitLiarAppeal(username, appealText.trim()),
    onSuccess: () => {
      toast("Appeal submitted — we're reviewing it.");
      setAppealing(false);
      setOpen(false);
      queryClient.invalidateQueries({ queryKey: ["my-liar-badge", username] });
    },
    onError: () => toast("Couldn't submit appeal"),
  });

  if (!badge) return null;

  const strikeCount = badge.strike_count ?? 3;
  const appealPending = (badge.appeal_status ?? "") === "pending";

  return (
    <Dialog.Root open={open} onOpenChange={(o) => !o && ack.mutate()}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-[60] bg-black/70 backdrop-blur-sm data-[state=open]:animate-in data-[state=open]:fade-in-0" />
        <Dialog.Content className="fixed left-1/2 top-1/2 z-[60] w-[calc(100%-2rem)] max-w-[420px] -translate-x-1/2 -translate-y-1/2 overflow-hidden rounded-[26px] bg-background p-6 shadow-2xl outline-none data-[state=open]:animate-in data-[state=open]:zoom-in-95">
          {/* Floating clown crest */}
          <div className="mx-auto flex h-28 w-28 items-center justify-center rounded-full bg-[radial-gradient(circle,rgba(239,68,68,0.32),transparent_70%)]">
            <span className="text-[64px] drop-shadow-[0_3px_8px_rgba(239,68,68,0.45)]">
              🤡
            </span>
          </div>

          <Dialog.Title className="mt-1 text-center font-display text-2xl font-extrabold">
            You got the Liar Liar badge
          </Dialog.Title>
          <p className="mt-2 text-center text-sm text-muted-foreground">
            Ember flagged {strikeCount} of your recent posts as false or
            misleading.
          </p>

          {/* Reason card */}
          <div className="mt-4 rounded-2xl border border-red-500/25 bg-card p-3.5">
            <div className="flex items-center gap-1.5 text-[11px] font-extrabold uppercase tracking-wide text-muted-foreground">
              <MessageSquareWarning className="h-3.5 w-3.5 text-red-500" />
              Why you got this
            </div>
            <p className="mt-1.5 text-sm text-foreground/90">
              {badge.reason ??
                `You received ${strikeCount} false or misleading fact-checks in the last 30 days.`}
            </p>
          </div>

          <ul className="mt-4 space-y-2 text-sm text-foreground/90">
            <li className="flex gap-2">
              <span className="text-muted-foreground">•</span>
              This chip appears next to your name across Whisper.
            </li>
            <li className="flex gap-2">
              <span className="text-muted-foreground">•</span>
              Ember keeps auto-checking your claims — accurate posts won't add
              strikes.
            </li>
            <li className="flex gap-2">
              <span className="text-muted-foreground">•</span>
              You can appeal below if you think this was a mistake.
            </li>
          </ul>

          {appealing ? (
            <div className="mt-5">
              <textarea
                value={appealText}
                onChange={(e) => setAppealText(e.target.value)}
                rows={3}
                autoFocus
                placeholder="Tell us why this badge is a mistake…"
                className="w-full resize-none rounded-2xl border border-border bg-card px-4 py-3 text-sm outline-none focus:border-foreground/40"
              />
              <button
                onClick={() => appealText.trim() && appeal.mutate()}
                disabled={!appealText.trim() || appeal.isPending}
                className="mt-2 w-full rounded-2xl bg-foreground py-3.5 text-[15px] font-bold text-background disabled:opacity-50"
              >
                {appeal.isPending ? "Submitting…" : "Submit appeal"}
              </button>
            </div>
          ) : (
            <div className="mt-5 space-y-2">
              <button
                onClick={() => setAppealing(true)}
                disabled={appealPending}
                className="w-full rounded-2xl bg-foreground py-3.5 text-[15px] font-bold text-background disabled:opacity-50"
              >
                Apply to remove
              </button>
              {appealPending && (
                <p className="text-center text-xs text-muted-foreground">
                  Appeal already submitted — we're reviewing it.
                </p>
              )}
              <button
                onClick={() => ack.mutate()}
                disabled={ack.isPending}
                className="w-full py-2.5 text-sm font-semibold text-muted-foreground"
              >
                I understand
              </button>
            </div>
          )}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
