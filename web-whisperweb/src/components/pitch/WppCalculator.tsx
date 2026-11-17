import { useMemo, useState } from "react";
import { BadgeDollarSign, Check, TrendingUp } from "lucide-react";

import { cn } from "@/lib/utils";
import { Slider } from "@/components/ui/slider";
import {
  WPP_TIERS,
  formatUsd,
  wppMonthlyCents,
  type WppTier,
} from "@/lib/pitch";

function compactNumber(n: number): string {
  return Intl.NumberFormat("en-US", { notation: "compact" }).format(n);
}

/**
 * WPP (Whisper Paid Partners) interactive earnings calculator. Prospects drag
 * the sliders live during a pitch to see what ad-revenue share would pay them
 * at each partner tier.
 */
export function WppCalculator() {
  const [followers, setFollowers] = useState<number>(12_000);
  const [monthlyViews, setMonthlyViews] = useState<number>(250_000);

  const tier: WppTier = useMemo(() => {
    const eligible = WPP_TIERS.filter((t) => followers >= t.minFollowers);
    return eligible[eligible.length - 1] ?? WPP_TIERS[0];
  }, [followers]);

  const eligible = followers >= WPP_TIERS[0].minFollowers;
  const payout = wppMonthlyCents(monthlyViews, tier);

  return (
    <div className="space-y-4">
      <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
        <div className="space-y-5">
          <div>
            <div className="flex items-baseline justify-between">
              <p className="text-sm font-semibold">Followers</p>
              <p className="text-sm font-bold">{compactNumber(followers)}</p>
            </div>
            <Slider
              className="mt-2"
              value={[followers]}
              min={0}
              max={250_000}
              step={500}
              onValueChange={(v) => setFollowers(v[0] ?? 0)}
            />
          </div>
          <div>
            <div className="flex items-baseline justify-between">
              <p className="text-sm font-semibold">Monthly qualified views</p>
              <p className="text-sm font-bold">{compactNumber(monthlyViews)}</p>
            </div>
            <Slider
              className="mt-2"
              value={[monthlyViews]}
              min={0}
              max={5_000_000}
              step={10_000}
              onValueChange={(v) => setMonthlyViews(v[0] ?? 0)}
            />
          </div>
        </div>

        <div className="mt-5 rounded-xl bg-foreground p-4 text-background">
          <p className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider opacity-70">
            <BadgeDollarSign className="h-3.5 w-3.5" /> Estimated WPP payout
          </p>
          {eligible ? (
            <>
              <p className="mt-1 text-3xl font-extrabold tracking-tight">
                {formatUsd(payout)}
                <span className="text-base font-semibold opacity-70">/mo</span>
              </p>
              <p className="mt-1 text-xs opacity-70">
                {tier.name} tier · {formatUsd(tier.rpmCents)} per 1k views · paid
                monthly via Stripe
              </p>
            </>
          ) : (
            <p className="mt-1 text-sm font-semibold">
              WPP opens at {WPP_TIERS[0].minFollowers.toLocaleString()} followers —
              drag the slider up to see earnings.
            </p>
          )}
        </div>
      </div>

      <div className="grid gap-2 sm:grid-cols-3">
        {WPP_TIERS.map((t) => {
          const active = t.id === tier.id && eligible;
          return (
            <button
              key={t.id}
              onClick={() => setFollowers(t.minFollowers)}
              className={cn(
                "rounded-2xl border p-3 text-left transition-all active:scale-[0.98]",
                active
                  ? "border-foreground bg-foreground text-background shadow-md"
                  : "border-border bg-card hover:border-foreground/30"
              )}
            >
              <div className="flex items-center justify-between">
                <p className="text-sm font-bold">{t.name}</p>
                {active && <TrendingUp className="h-4 w-4" />}
              </div>
              <p className={cn("text-xs", active ? "opacity-75" : "text-muted-foreground")}>
                {compactNumber(t.minFollowers)}+ followers ·{" "}
                {formatUsd(t.rpmCents)}/1k views
              </p>
              <ul className="mt-2 space-y-1">
                {t.perks.map((p) => (
                  <li
                    key={p}
                    className={cn(
                      "flex items-start gap-1 text-[11px] leading-snug",
                      active ? "opacity-85" : "text-foreground/75"
                    )}
                  >
                    <Check className="mt-0.5 h-3 w-3 shrink-0" />
                    {p}
                  </li>
                ))}
              </ul>
            </button>
          );
        })}
      </div>
    </div>
  );
}
