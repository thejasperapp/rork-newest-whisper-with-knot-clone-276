import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Download, Search, Wallet } from "lucide-react";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";
import { backendFetch } from "@/lib/billing";
import { formatCents } from "@/lib/coachPay";

interface AdminReceiptRow {
  id: string;
  receipt_no: string;
  user_id: string | null;
  email: string | null;
  kind: string;
  description: string;
  amount_cents: number;
  status: "paid" | "refunded";
  stripe_subscription_id: string | null;
  refund_note: string | null;
  refunded_at: string | null;
  created_at: string;
}

const KIND_LABELS: Record<string, string> = {
  one: "Whisper One",
  badge: "Badge fee",
  "coach-hire": "Coaching",
  program: "Program",
  sponsorship: "Sponsorship",
};

/** Escape one CSV cell. */
function csvCell(value: string | number | null): string {
  const raw = value === null ? "" : String(value);
  return /[",\n]/.test(raw) ? `"${raw.replace(/"/g, '""')}"` : raw;
}

/**
 * Admin receipts ledger — every charge the webhook recorded, searchable by
 * email / receipt number / description, with one-tap direct refunds (no
 * user request needed) and CSV export for bookkeeping.
 */
export function AdminReceiptsPanel({ token }: { token: string }) {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [search, setSearch] = useState<string>("");
  const [query, setQuery] = useState<string>("");

  const receipts = useQuery({
    queryKey: ["admin-receipts", user?.id, query],
    enabled: !!token && !!user,
    retry: false,
    queryFn: async ({ signal }): Promise<AdminReceiptRow[]> => {
      const path = query
        ? `/admin/receipts?query=${encodeURIComponent(query)}`
        : "/admin/receipts";
      const res = await backendFetch(path, {
        headers: { Authorization: `Bearer ${token}` }, signal,
      });
      if (!res.ok) throw new Error("forbidden");
      const data = (await res.json()) as { receipts?: AdminReceiptRow[] };
      return Array.isArray(data.receipts) ? data.receipts : [];
    },
  });

  const refund = useMutation({
    mutationFn: async (input: { receiptId: string; note: string }) => {
      const res = await backendFetch(`/admin/refunds/direct`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify(input),
      });
      const data = (await res.json().catch(() => ({}))) as {
        error?: string;
        stripeMessage?: string | null;
      };
      if (!res.ok) {
        throw new Error(data.stripeMessage || data.error || "Refund failed.");
      }
      return data;
    },
    onSuccess: () => {
      toast.success("Refund executed — the buyer got an email.");
      queryClient.invalidateQueries({ queryKey: ["admin-receipts"] });
      queryClient.invalidateQueries({ queryKey: ["admin-refunds"] });
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Refund failed."),
  });

  if (receipts.isError || !token) return null;
  const rows = receipts.data ?? [];
  const totalPaid = rows
    .filter((r) => r.status === "paid")
    .reduce((sum, r) => sum + r.amount_cents, 0);

  const exportCsv = (): void => {
    const header =
      "receipt_no,date,kind,description,email,amount_usd,status,refund_note";
    const lines = rows.map((r) =>
      [
        csvCell(r.receipt_no),
        csvCell(new Date(r.created_at).toISOString()),
        csvCell(KIND_LABELS[r.kind] ?? r.kind),
        csvCell(r.description),
        csvCell(r.email),
        csvCell((r.amount_cents / 100).toFixed(2)),
        csvCell(r.status),
        csvCell(r.refund_note),
      ].join(",")
    );
    const blob = new Blob([[header, ...lines].join("\n")], {
      type: "text/csv",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `whisper-receipts-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <section className="mt-12">
      <div className="flex flex-wrap items-center gap-2.5">
        <Wallet className="h-5 w-5" />
        <h2 className="text-[19px] font-extrabold">Receipts</h2>
        {rows.length > 0 && (
          <span className="rounded-full bg-emerald-500/15 px-2.5 py-0.5 text-[11.5px] font-bold text-emerald-600">
            {formatCents(totalPaid)} collected
          </span>
        )}
        <button
          onClick={exportCsv}
          disabled={rows.length === 0}
          className="ml-auto flex h-8 items-center gap-1.5 rounded-full border border-border px-3 text-[12px] font-bold disabled:opacity-40"
        >
          <Download className="h-3.5 w-3.5" />
          CSV
        </button>
      </div>
      <p className="mt-1 text-[13px] text-muted-foreground">
        Every charge the Stripe webhook records lands here. “Refund now”
        refunds the charge, ends the subscription, flips entitlements, and
        emails the buyer — no user request needed.
      </p>

      <form
        className="mt-3 flex items-center gap-2 rounded-full border border-border bg-card px-3.5"
        onSubmit={(e) => {
          e.preventDefault();
          setQuery(search.trim());
        }}
      >
        <Search className="h-4 w-4 text-muted-foreground" />
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search email, receipt #, or description…"
          className="h-10 flex-1 bg-transparent text-[13.5px] outline-none placeholder:text-muted-foreground/60"
        />
        <button
          type="submit"
          className="text-[12.5px] font-bold text-muted-foreground"
        >
          Search
        </button>
      </form>

      {rows.length === 0 ? (
        <p className="mt-4 rounded-2xl border border-border bg-card px-4 py-6 text-center text-[13.5px] text-muted-foreground">
          {query
            ? "No receipts match that search."
            : "No receipts yet — they appear the moment payments land."}
        </p>
      ) : (
        <div className="mt-4 space-y-2.5">
          {rows.map((r) => (
            <div
              key={r.id}
              className={cn(
                "rounded-2xl border border-border bg-card p-4",
                r.status === "refunded" && "opacity-70"
              )}
            >
              <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
                <p className="text-[14.5px] font-bold tabular-nums">
                  {formatCents(r.amount_cents)}
                </p>
                <span className="text-[13px] text-muted-foreground">
                  {KIND_LABELS[r.kind] ?? r.kind} · {r.email ?? "no email"}
                </span>
                <span
                  className={cn(
                    "rounded-full px-2 py-0.5 text-[10.5px] font-bold uppercase tracking-wide",
                    r.status === "paid"
                      ? "bg-emerald-500/10 text-emerald-600"
                      : "bg-secondary text-muted-foreground"
                  )}
                >
                  {r.status}
                </span>
                <span className="ml-auto text-[12px] text-muted-foreground">
                  {r.receipt_no} ·{" "}
                  {new Date(r.created_at).toLocaleDateString()}
                </span>
              </div>
              <p className="mt-1 text-[13px] text-muted-foreground">
                {r.description}
                {r.refund_note ? ` — ${r.refund_note}` : ""}
              </p>
              {r.status === "paid" && (
                <button
                  onClick={() => {
                    const note = window.prompt(
                      "Refund note for the buyer (optional):"
                    );
                    if (note === null) return;
                    if (
                      window.confirm(
                        `Refund ${formatCents(r.amount_cents)} to ${
                          r.email ?? "this buyer"
                        }? This also ends any subscription behind it.`
                      )
                    ) {
                      refund.mutate({ receiptId: r.id, note: note.trim() });
                    }
                  }}
                  disabled={refund.isPending}
                  className="mt-2.5 h-9 rounded-full border border-red-500/40 px-4 text-[13px] font-bold text-red-500 disabled:opacity-50"
                >
                  Refund now
                </button>
              )}
            </div>
          ))}
        </div>
      )}
    </section>
  );
}
