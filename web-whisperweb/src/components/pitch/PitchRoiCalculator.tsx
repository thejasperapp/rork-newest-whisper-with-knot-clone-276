import { useMemo, useState } from "react";
import { Calculator, TrendingUp, Users } from "lucide-react";
import { Slider } from "@/components/ui/slider";
import { formatUsd, SPONSOR_PLATFORM_FEE_PERCENT } from "@/lib/pitch";
import { cn } from "@/lib/utils";

export function BrandRoiCalculator() {
  const [budget, setBudget] = useState<number>(5000);
  const [postsPerMonth, setPostsPerMonth] = useState<number>(4);
  const [avgEngagement, setAvgEngagement] = useState<number>(2500);
  const [cpmEstimate, setCpmEstimate] = useState<number>(15);

  const months = 3;
  const totalBudget = budget * months;
  const totalPosts = postsPerMonth * months;
  const estimatedReach = totalPosts * avgEngagement;
  const whisperFee = Math.round((totalBudget * SPONSOR_PLATFORM_FEE_PERCENT) / 100);
  const netToCreators = totalBudget - whisperFee;
  const equivalentAdSpend = Math.round((estimatedReach / 1000) * cpmEstimate);
  const savingsVsAds = equivalentAdSpend - totalBudget;

  return (
    <div className="rounded-[20px] border border-border bg-card p-4 shadow-sm">
      <p className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
        ROI calculator
      </p>
      <h3 className="mt-1 text-[16px] font-extrabold">What your budget buys</h3>
      <p className="mt-1 text-[13px] leading-snug text-muted-foreground">
        Drag the sliders to show a prospect brand their 3-month reach and
        equivalent ad spend on Whisper.
      </p>

      <div className="mt-4 space-y-5">
        <div>
          <div className="flex items-baseline justify-between">
            <p className="text-sm font-semibold">Monthly sponsorship budget</p>
            <p className="text-sm font-bold">{formatUsd(budget * 100)}</p>
          </div>
          <Slider
            className="mt-2"
            value={[budget]}
            min={500}
            max={50_000}
            step={500}
            onValueChange={(v) => setBudget(v[0] ?? budget)}
          />
        </div>

        <div>
          <div className="flex items-baseline justify-between">
            <p className="text-sm font-semibold">Tracked posts per month</p>
            <p className="text-sm font-bold">{postsPerMonth}</p>
          </div>
          <Slider
            className="mt-2"
            value={[postsPerMonth]}
            min={1}
            max={20}
            step={1}
            onValueChange={(v) => setPostsPerMonth(v[0] ?? postsPerMonth)}
          />
        </div>

        <div>
          <div className="flex items-baseline justify-between">
            <p className="text-sm font-semibold">Avg. engagement per post</p>
            <p className="text-sm font-bold">{avgEngagement.toLocaleString()}</p>
          </div>
          <Slider
            className="mt-2"
            value={[avgEngagement]}
            min={500}
            max={50_000}
            step={500}
            onValueChange={(v) => setAvgEngagement(v[0] ?? avgEngagement)}
          />
        </div>

        <div>
          <div className="flex items-baseline justify-between">
            <p className="text-sm font-semibold">Compare CPM ($)</p>
            <p className="text-sm font-bold">${cpmEstimate}</p>
          </div>
          <Slider
            className="mt-2"
            value={[cpmEstimate]}
            min={5}
            max={50}
            step={1}
            onValueChange={(v) => setCpmEstimate(v[0] ?? cpmEstimate)}
          />
        </div>
      </div>

      <div className="mt-5 grid gap-2 sm:grid-cols-2">
        <div className="rounded-2xl bg-foreground p-4 text-background">
          <p className="text-[11px] font-bold uppercase tracking-wider opacity-70">
            3-month net to creators
          </p>
          <p className="mt-1 text-2xl font-extrabold">{formatUsd(netToCreators * 100)}</p>
          <p className="text-xs opacity-70">
            after {SPONSOR_PLATFORM_FEE_PERCENT}% Whisper fee
          </p>
        </div>
        <div className="rounded-2xl border border-border bg-secondary/40 p-4">
          <p className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
            Estimated reach
          </p>
          <p className="mt-1 text-2xl font-extrabold">
            {estimatedReach.toLocaleString()}
          </p>
          <p className="text-xs text-muted-foreground">
            likes + comments across {totalPosts} posts
          </p>
        </div>
      </div>

      <div className="mt-3 rounded-2xl border border-emerald-500/30 bg-emerald-500/5 p-4">
        <div className="flex items-center gap-2">
          <TrendingUp className="h-4 w-4 text-emerald-600" />
          <p className="text-sm font-bold text-emerald-600">
            vs. buying that reach as ads
          </p>
        </div>
        <p className="mt-1 text-[13px] leading-snug text-muted-foreground">
          Equivalent spend on a ${cpmEstimate} CPM ad platform would be
          roughly {formatUsd(equivalentAdSpend * 100)}. On Whisper you pay{" "}
          {formatUsd(totalBudget * 100)} — saving{" "}
          {formatUsd(Math.max(savingsVsAds, 0) * 100)} while only paying for
          verified, tracked creator posts.
        </p>
      </div>
    </div>
  );
}

export function CoachHoursCalculator() {
  const [hourlyRate, setHourlyRate] = useState<number>(75);
  const [hoursPerWeek, setHoursPerWeek] = useState<number>(10);
  const [weeksPerMonth, setWeeksPerMonth] = useState<number>(4);

  const monthlyGross = hourlyRate * hoursPerWeek * weeksPerMonth;
  const fee = Math.round((monthlyGross * 10) / 100);
  const net = monthlyGross - fee;
  const annual = net * 12;

  return (
    <div className="rounded-[20px] border border-border bg-card p-4 shadow-sm">
      <p className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
        Hourly coaching calculator
      </p>
      <h3 className="mt-1 text-[16px] font-extrabold">Side income, scaled</h3>
      <p className="mt-1 text-[13px] leading-snug text-muted-foreground">
        Show coaches what their coaching time is worth if they do it through Whisper instead of Venmo and spreadsheets.
      </p>
      <div className="mt-4 space-y-5">
        <div>
          <div className="flex items-baseline justify-between">
            <p className="text-sm font-semibold">Hourly rate</p>
            <p className="text-sm font-bold">${hourlyRate}</p>
          </div>
          <Slider
            className="mt-2"
            value={[hourlyRate]}
            min={25}
            max={300}
            step={5}
            onValueChange={(v) => setHourlyRate(v[0] ?? hourlyRate)}
          />
        </div>
        <div>
          <div className="flex items-baseline justify-between">
            <p className="text-sm font-semibold">Hours per week</p>
            <p className="text-sm font-bold">{hoursPerWeek}</p>
          </div>
          <Slider
            className="mt-2"
            value={[hoursPerWeek]}
            min={1}
            max={40}
            step={1}
            onValueChange={(v) => setHoursPerWeek(v[0] ?? hoursPerWeek)}
          />
        </div>
      </div>
      <div className="mt-5 rounded-2xl bg-foreground p-4 text-background">
        <p className="text-[11px] font-bold uppercase tracking-wider opacity-70">
          Projected take-home
        </p>
        <p className="mt-1 text-2xl font-extrabold">
          {formatUsd(net * 100)}/mo
        </p>
        <p className="text-xs opacity-70">
          {formatUsd(annual * 100)}/yr after 10% Whisper fee
        </p>
      </div>
    </div>
  );
}
