import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Layers, Loader2, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";

import {
  fetchCoachTiers,
  saveCoachTiers,
  type CoachTierInput,
} from "@/lib/coachPay";

interface TierDraft {
  id?: string;
  name: string;
  tagline: string;
  price: string;
  perksText: string;
}

const DEFAULT_NAMES = ["Check-ins", "Full coaching", "Elite 1-on-1"];

/**
 * Coach Studio → Plans & tiers. Coaches publish up to three plans (name,
 * monthly price, perks) that clients pick from on the hire page. Empty =
 * the single monthly rate above keeps working as before.
 */
export function CoachTierManager({ userId }: { userId: string | undefined }) {
  const queryClient = useQueryClient();
  const [drafts, setDrafts] = useState<TierDraft[]>([]);
  const [hydrated, setHydrated] = useState<boolean>(false);

  const tiers = useQuery({
    queryKey: ["coach-tiers", userId ?? ""],
    queryFn: () => fetchCoachTiers(userId!),
    enabled: !!userId,
  });

  useEffect(() => {
    if (hydrated || !tiers.data) return;
    setDrafts(
      tiers.data.map((t) => ({
        id: t.id,
        name: t.name,
        tagline: t.tagline ?? "",
        price: String(t.monthlyPriceCents / 100),
        perksText: t.perks.join("\n"),
      }))
    );
    setHydrated(true);
  }, [tiers.data, hydrated]);

  const save = useMutation({
    mutationFn: () => {
      const payload: CoachTierInput[] = drafts.map((d) => {
        const price = Math.round(Number(d.price) * 100);
        return {
          id: d.id,
          name: d.name.trim(),
          tagline: d.tagline.trim() || undefined,
          priceCents: price,
          perks: d.perksText
            .split("\n")
            .map((p) => p.trim())
            .filter(Boolean)
            .slice(0, 6),
          active: true,
        };
      });
      for (const t of payload) {
        if (t.name.length < 2) throw new Error("Every tier needs a name.");
        if (!Number.isFinite(t.priceCents) || t.priceCents < 500 || t.priceCents > 200000) {
          throw new Error("Tier prices must be between $5 and $2,000 per month.");
        }
      }
      return saveCoachTiers(payload);
    },
    onSuccess: () => {
      toast.success(
        drafts.length > 0
          ? "Plans published — clients now pick a tier on your hire page."
          : "Tiers cleared — your single monthly rate is back in charge."
      );
      queryClient.invalidateQueries({ queryKey: ["coach-tiers"] });
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Couldn't save plans."),
  });

  const addTier = () => {
    if (drafts.length >= 3) return;
    setDrafts([
      ...drafts,
      {
        name: DEFAULT_NAMES[drafts.length] ?? "New plan",
        tagline: "",
        price: "",
        perksText: "",
      },
    ]);
  };

  return (
    <div className="rounded-[24px] border border-border bg-card p-5">
      <div className="flex items-center gap-2.5">
        <Layers className="h-5 w-5" />
        <p className="text-[15px] font-bold">Plans &amp; tiers</p>
        <span className="ml-auto text-[11.5px] font-bold uppercase tracking-wide text-muted-foreground">
          {drafts.length}/3
        </span>
      </div>
      <p className="mt-1.5 text-[13px] leading-snug text-muted-foreground">
        Offer up to three plans — clients pick one on your hire page. Leave
        this empty to keep the single monthly rate above. $5–$2,000/mo ·{" "}
        <Link to="/policies#coaching" className="underline">
          coaching policy
        </Link>
        .
      </p>

      {tiers.isPending && !!userId ? (
        <div className="flex justify-center py-6">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      ) : (
        <div className="mt-3 space-y-3">
          {drafts.map((d, i) => (
            <div
              key={d.id ?? `new-${i}`}
              className="rounded-2xl border border-border bg-background p-3.5"
            >
              <div className="flex items-center gap-2">
                <input
                  value={d.name}
                  onChange={(e) =>
                    setDrafts(
                      drafts.map((x, j) =>
                        j === i ? { ...x, name: e.target.value } : x
                      )
                    )
                  }
                  placeholder="Plan name"
                  maxLength={40}
                  className="h-9 min-w-0 flex-1 rounded-lg border border-border bg-card px-3 text-[13.5px] font-semibold outline-none"
                />
                <div className="flex h-9 items-center rounded-lg border border-border bg-card px-2.5">
                  <span className="text-[13px] text-muted-foreground">$</span>
                  <input
                    value={d.price}
                    onChange={(e) =>
                      setDrafts(
                        drafts.map((x, j) =>
                          j === i ? { ...x, price: e.target.value } : x
                        )
                      )
                    }
                    placeholder="99"
                    inputMode="decimal"
                    className="w-14 bg-transparent px-1 text-[13.5px] font-semibold outline-none"
                  />
                  <span className="text-[11.5px] text-muted-foreground">/mo</span>
                </div>
                <button
                  onClick={() => setDrafts(drafts.filter((_, j) => j !== i))}
                  aria-label="Remove tier"
                  className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border border-border text-muted-foreground hover:text-red-500"
                >
                  <Trash2 className="h-4 w-4" />
                </button>
              </div>
              <input
                value={d.tagline}
                onChange={(e) =>
                  setDrafts(
                    drafts.map((x, j) =>
                      j === i ? { ...x, tagline: e.target.value } : x
                    )
                  )
                }
                placeholder="One-line tagline (optional)"
                maxLength={80}
                className="mt-2 h-9 w-full rounded-lg border border-border bg-card px-3 text-[13px] outline-none"
              />
              <textarea
                value={d.perksText}
                onChange={(e) =>
                  setDrafts(
                    drafts.map((x, j) =>
                      j === i ? { ...x, perksText: e.target.value } : x
                    )
                  )
                }
                placeholder={"What's included — one perk per line (max 6)\nWeekly check-ins\nCustom program"}
                rows={3}
                className="mt-2 w-full resize-none rounded-lg border border-border bg-card px-3 py-2 text-[13px] leading-relaxed outline-none"
              />
            </div>
          ))}

          <div className="flex gap-2">
            {drafts.length < 3 && (
              <button
                onClick={addTier}
                className="flex h-10 items-center gap-1.5 rounded-full border border-border px-4 text-[13.5px] font-bold"
              >
                <Plus className="h-4 w-4" /> Add plan
              </button>
            )}
            <button
              onClick={() => save.mutate()}
              disabled={save.isPending}
              className="ml-auto flex h-10 items-center gap-2 rounded-full bg-foreground px-5 text-[13.5px] font-bold text-background disabled:opacity-50"
            >
              {save.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
              Save plans
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
