import { useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Loader2, ReceiptText } from "lucide-react";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import {
  fetchMyReceipts,
  fetchMyRefunds,
  requestRefund,
  type ReceiptRow,
  type RefundKind,
} from "@/lib/billing";
import { fetchMyCoachSubscriptions, formatCents } from "@/lib/coachPay";
import { fetchMyBusinessPlus } from "@/lib/businessPlus";
import { useAuth } from "@/hooks/useAuth";

const KIND_LABELS: Record<RefundKind, string> = {
  one: "Whisper One",
  badge: "Verified badge",
  "coach-hire": "Coaching",
  program: "Program",
  "business-plus": "Business+",
};

const STATUS_STYLES: Record<string, string> = {
  pending: "bg-amber-500/10 text-amber-600",
  processed: "bg-emerald-500/10 text-emerald-600",
  denied: "bg-red-500/10 text-red-500",
  failed: "bg-secondary text-muted-foreground",
};

interface RefundOption {
  key: string;
  kind: RefundKind;
  subscriptionId?: string;
  label: string;
}

/**
 * Settings → Billing & refunds. Users file refund requests here (reviewed by
 * a human within ~2 business days) and track their status. Windows: One and
 * badges 14 days, coaching 7 days — published at /policies#billing.
 */
export function BillingRefundsSection() {
  const queryClient = useQueryClient();
  const { user } = useAuth();
  const [open, setOpen] = useState<boolean>(false);
  const [choice, setChoice] = useState<string>("one");
  const [reason, setReason] = useState<string>("");

  const refunds = useQuery({
    queryKey: ["my-refunds"],
    queryFn: fetchMyRefunds,
    retry: false,
  });
  const receipts = useQuery({
    queryKey: ["my-receipts"],
    queryFn: fetchMyReceipts,
    retry: false,
  });
  const subs = useQuery({
    queryKey: ["my-coach-subscriptions-refunds"],
    queryFn: fetchMyCoachSubscriptions,
    enabled: open,
    retry: false,
  });
  // Business+ owners can refund the company plan (14-day window).
  const bizPlus = useQuery({
    queryKey: ["my-business-plus-refund", user?.id ?? ""],
    queryFn: () => fetchMyBusinessPlus(user!.id),
    enabled: open && !!user,
    retry: false,
  });

  const options: RefundOption[] = [
    { key: "one", kind: "one", label: "Whisper One membership" },
    { key: "badge", kind: "badge", label: "Verified badge (annual fee)" },
    ...(bizPlus.data?.isOwner
      ? [
          {
            key: "business-plus",
            kind: "business-plus" as RefundKind,
            label: `Business+ — ${bizPlus.data.business.company_name?.trim() || "your company plan"}`,
          },
        ]
      : []),
    ...(subs.data ?? []).map((s) => ({
      key: `sub-${s.id}`,
      kind: "coach-hire" as RefundKind,
      subscriptionId: s.id,
      label: `Coaching — @${s.coachUsername ?? "coach"}${
        s.priceCents ? ` (${formatCents(s.priceCents)}/mo)` : ""
      }`,
    })),
  ];
  const selected = options.find((o) => o.key === choice) ?? options[0];

  const submit = useMutation({
    mutationFn: () =>
      requestRefund({
        kind: selected.kind,
        subscriptionId: selected.subscriptionId,
        reason: reason.trim(),
      }),
    onSuccess: (res) => {
      if (res.duplicate) {
        toast("That purchase already has a request in review.");
      } else {
        toast.success(
          "Refund request filed — most decisions land within 2 business days."
        );
      }
      setOpen(false);
      setReason("");
      queryClient.invalidateQueries({ queryKey: ["my-refunds"] });
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Couldn't file that."),
  });

  const rows = refunds.data ?? [];
  const receiptRows = receipts.data ?? [];

  /** Preselect the matching refund option straight from a receipt row. */
  const startRefundFromReceipt = (r: ReceiptRow): void => {
    if (r.kind === "coach-hire" && r.subscriptionId) {
      setChoice(`sub-${r.subscriptionId}`);
    } else if (r.kind === "badge") {
      setChoice("badge");
    } else if (r.kind === "business-plus") {
      setChoice("business-plus");
    } else {
      setChoice("one");
    }
    setOpen(true);
  };

  return (
    <section className="mt-6 overflow-hidden rounded-[24px] border border-border bg-card">
      <div className="flex items-center gap-2.5 px-4 pt-4">
        <ReceiptText className="h-4.5 w-4.5 text-muted-foreground" />
        <p className="text-[15px] font-bold">Billing &amp; refunds</p>
      </div>
      <p className="px-4 pt-1.5 text-[13px] leading-snug text-muted-foreground">
        Whisper One, badges &amp; Business+: 14-day window · coaching: 7 days.
        Every request is reviewed by a human —{" "}
        <Link to="/policies#billing" className="underline">
          read the refund policy
        </Link>
        .
      </p>

      <div className="px-4 py-3.5">
        {!open ? (
          <button
            onClick={() => setOpen(true)}
            className="flex h-10 items-center justify-center rounded-full border border-border px-5 text-[13.5px] font-bold transition-colors hover:bg-secondary/50"
          >
            Request a refund
          </button>
        ) : (
          <div className="rounded-2xl border border-border bg-background p-3.5">
            <p className="text-[13px] font-bold">What should we refund?</p>
            <div className="mt-2 space-y-1.5">
              {options.map((o) => (
                <button
                  key={o.key}
                  onClick={() => setChoice(o.key)}
                  className={cn(
                    "flex w-full items-center gap-2 rounded-xl border px-3 py-2 text-left text-[13.5px]",
                    o.key === selected.key
                      ? "border-foreground font-semibold"
                      : "border-border text-muted-foreground"
                  )}
                >
                  <span
                    className={cn(
                      "h-3.5 w-3.5 rounded-full border-2",
                      o.key === selected.key
                        ? "border-foreground bg-foreground"
                        : "border-muted-foreground/40"
                    )}
                  />
                  {o.label}
                </button>
              ))}
              {subs.isPending && open && (
                <p className="px-1 text-[12px] text-muted-foreground">
                  Checking for coaching subscriptions…
                </p>
              )}
            </div>
            <textarea
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Briefly, why? (required)"
              rows={2}
              className="mt-3 w-full resize-none rounded-xl border border-border bg-card px-3 py-2 text-[13.5px] outline-none placeholder:text-muted-foreground/60"
            />
            <div className="mt-2.5 flex gap-2">
              <button
                onClick={() => submit.mutate()}
                disabled={submit.isPending || reason.trim().length < 5}
                className="flex h-10 flex-1 items-center justify-center gap-2 rounded-full bg-foreground text-[13.5px] font-bold text-background disabled:opacity-40"
              >
                {submit.isPending && (
                  <Loader2 className="h-4 w-4 animate-spin" />
                )}
                Submit request
              </button>
              <button
                onClick={() => setOpen(false)}
                className="h-10 rounded-full border border-border px-4 text-[13.5px] font-bold"
              >
                Cancel
              </button>
            </div>
          </div>
        )}

        {receiptRows.length > 0 && (
          <div className="mt-1 rounded-2xl border border-border bg-background p-3">
            <p className="px-1 text-[11px] font-black uppercase tracking-[0.16em] text-muted-foreground">
              Purchase history
            </p>
            <div className="mt-1 divide-y divide-border">
              {receiptRows.slice(0, 8).map((r) => (
                <div key={r.id} className="flex items-center gap-3 py-2.5">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[13.5px] font-semibold">
                      {r.description || r.kind}
                    </p>
                    <p className="truncate text-[12px] text-muted-foreground">
                      {formatCents(r.amountCents)} ·{" "}
                      {new Date(r.createdAt).toLocaleDateString("en-US", {
                        month: "short",
                        day: "numeric",
                      })}{" "}
                      · {r.receiptNo}
                    </p>
                  </div>
                  {r.status === "refunded" ? (
                    <span className="rounded-full bg-secondary px-2.5 py-1 text-[10.5px] font-bold uppercase tracking-wide text-muted-foreground">
                      refunded
                    </span>
                  ) : r.kind === "one" ||
                    r.kind === "badge" ||
                    r.kind === "coach-hire" ||
                    r.kind === "business-plus" ? (
                    <button
                      onClick={() => startRefundFromReceipt(r)}
                      className="rounded-full border border-border px-2.5 py-1 text-[11px] font-bold text-muted-foreground transition-colors hover:text-foreground"
                    >
                      Refund
                    </button>
                  ) : (
                    <span className="rounded-full bg-emerald-500/10 px-2.5 py-1 text-[10.5px] font-bold uppercase tracking-wide text-emerald-600">
                      paid
                    </span>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {rows.length > 0 && (
          <div className="mt-3 divide-y divide-border">
            {rows.map((r) => (
              <div key={r.id} className="flex items-center gap-3 py-2.5">
                <div className="min-w-0 flex-1">
                  <p className="truncate text-[13.5px] font-semibold">
                    {KIND_LABELS[r.kind] ?? r.kind}
                    {r.amountCents ? ` · ${formatCents(r.amountCents)}` : ""}
                  </p>
                  <p className="truncate text-[12px] text-muted-foreground">
                    {new Date(r.createdAt).toLocaleDateString("en-US", {
                      month: "short",
                      day: "numeric",
                    })}
                    {r.adminNote ? ` · ${r.adminNote}` : ""}
                  </p>
                </div>
                <span
                  className={cn(
                    "rounded-full px-2.5 py-1 text-[10.5px] font-bold uppercase tracking-wide",
                    STATUS_STYLES[r.status] ?? STATUS_STYLES.failed
                  )}
                >
                  {r.status === "processed" ? "refunded" : r.status}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}
