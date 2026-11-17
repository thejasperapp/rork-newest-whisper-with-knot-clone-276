import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ReceiptText } from "lucide-react";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";
import { backendFetch } from "@/lib/billing";
import { formatCents } from "@/lib/coachPay";

interface AdminRefundRow {
  id: string;
  username: string | null;
  email: string | null;
  kind: string;
  amountCents: number | null;
  reason: string | null;
  status: string;
  eligibleAuto: boolean;
  adminNote: string | null;
  createdAt: string;
}

const KIND_LABELS: Record<string, string> = {
  one: "Whisper One",
  badge: "Badge fee",
  "coach-hire": "Coaching",
  program: "Program",
};

/**
 * Admin refunds queue — approving executes the Stripe refund server-side
 * (reversing coach transfers + the platform fee on destination charges) and
 * ends the underlying subscription immediately.
 */
export function AdminRefundsPanel({ token }: { token: string }) {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  const queue = useQuery({
    queryKey: ["admin-refunds", user?.id],
    enabled: !!token && !!user,
    retry: false,
    queryFn: async ({ signal }): Promise<AdminRefundRow[]> => {
      const res = await backendFetch(`/admin/refunds`, {
        headers: { Authorization: `Bearer ${token}` }, signal,
      });
      if (!res.ok) throw new Error("forbidden");
      const data = (await res.json()) as { requests?: AdminRefundRow[] };
      return Array.isArray(data.requests) ? data.requests : [];
    },
  });

  const decide = useMutation({
    mutationFn: async (input: {
      id: string;
      action: "approve" | "deny";
      note?: string;
    }) => {
      const res = await backendFetch(`/admin/refunds/decide`, {
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
        throw new Error(
          data.stripeMessage || data.error || "Decision failed."
        );
      }
      return data;
    },
    onSuccess: (_d, vars) => {
      toast.success(
        vars.action === "approve" ? "Refund executed." : "Request denied."
      );
      queryClient.invalidateQueries({ queryKey: ["admin-refunds"] });
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Decision failed."),
  });

  if (queue.isError || !token) return null;
  const rows = queue.data ?? [];
  const pending = rows.filter((r) => r.status === "pending");
  const done = rows.filter((r) => r.status !== "pending").slice(0, 10);

  return (
    <section className="mt-12">
      <div className="flex items-center gap-2.5">
        <ReceiptText className="h-5 w-5" />
        <h2 className="text-[19px] font-extrabold">Refunds</h2>
        {pending.length > 0 && (
          <span className="rounded-full bg-amber-500/15 px-2.5 py-0.5 text-[11.5px] font-bold text-amber-600">
            {pending.length} pending
          </span>
        )}
      </div>
      <p className="mt-1 text-[13px] text-muted-foreground">
        Approving refunds the charge in Stripe and ends the subscription
        immediately. Policy windows: One/badge 14d · coaching 7d · programs
        14d.
      </p>

      {rows.length === 0 ? (
        <p className="mt-4 rounded-2xl border border-border bg-card px-4 py-6 text-center text-[13.5px] text-muted-foreground">
          No refund requests yet.
        </p>
      ) : (
        <div className="mt-4 space-y-2.5">
          {[...pending, ...done].map((r) => (
            <div
              key={r.id}
              className={cn(
                "rounded-2xl border border-border bg-card p-4",
                r.status !== "pending" && "opacity-70"
              )}
            >
              <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
                <p className="text-[14.5px] font-bold">
                  @{r.username ?? "unknown"}
                </p>
                <span className="text-[13px] text-muted-foreground">
                  {KIND_LABELS[r.kind] ?? r.kind}
                  {r.amountCents ? ` · ${formatCents(r.amountCents)}` : ""}
                </span>
                <span
                  className={cn(
                    "rounded-full px-2 py-0.5 text-[10.5px] font-bold uppercase tracking-wide",
                    r.eligibleAuto
                      ? "bg-emerald-500/10 text-emerald-600"
                      : "bg-red-500/10 text-red-500"
                  )}
                >
                  {r.eligibleAuto ? "in window" : "outside window"}
                </span>
                <span className="ml-auto text-[12px] text-muted-foreground">
                  {new Date(r.createdAt).toLocaleDateString()}
                </span>
              </div>
              {r.reason && (
                <p className="mt-1.5 text-[13.5px] leading-snug text-foreground/90">
                  “{r.reason}”
                </p>
              )}
              {r.status === "pending" ? (
                <div className="mt-3 flex gap-2">
                  <button
                    onClick={() =>
                      decide.mutate({ id: r.id, action: "approve" })
                    }
                    disabled={decide.isPending}
                    className="h-9 rounded-full bg-emerald-600 px-4 text-[13px] font-bold text-white disabled:opacity-50"
                  >
                    Approve &amp; refund
                  </button>
                  <button
                    onClick={() => {
                      const note =
                        window.prompt("Optional note to the user:") ??
                        undefined;
                      decide.mutate({ id: r.id, action: "deny", note });
                    }}
                    disabled={decide.isPending}
                    className="h-9 rounded-full border border-red-500/40 px-4 text-[13px] font-bold text-red-500 disabled:opacity-50"
                  >
                    Deny
                  </button>
                </div>
              ) : (
                <p className="mt-2 text-[12px] font-bold uppercase tracking-wide text-muted-foreground">
                  {r.status}
                  {r.adminNote ? ` · ${r.adminNote}` : ""}
                </p>
              )}
            </div>
          ))}
        </div>
      )}
    </section>
  );
}
