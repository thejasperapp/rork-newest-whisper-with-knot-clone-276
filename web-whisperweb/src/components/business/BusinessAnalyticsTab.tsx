/**
 * Ad analytics — real delivery numbers for the account's ads over the last
 * 30 days: totals, a daily impressions/clicks chart, and a per-ad breakdown
 * with CTR. Reads business_ad_daily_stats() (owner-scoped RPC).
 */
import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import {
  BarChart3,
  Download,
  Eye,
  MousePointerClick,
  Percent,
  Trophy,
} from "lucide-react";

import { supabase } from "@/lib/supabase";
import { useAuth } from "@/hooks/useAuth";
import { AdDailyStat, AdStatus, BusinessAd, businessNumber } from "@/lib/business";

interface DayPoint {
  day: string;
  label: string;
  impressions: number;
  clicks: number;
}

const STATUS_LABEL: Record<AdStatus, string> = {
  draft: "Draft",
  active: "Live",
  paused: "Paused",
  ended: "Ended",
};

export function BusinessAnalyticsTab() {
  const { user } = useAuth();

  const adsQuery = useQuery({
    queryKey: ["business-ads", user?.id ?? "anon"],
    enabled: !!user,
    queryFn: async (): Promise<BusinessAd[]> => {
      const { data, error } = await supabase
        .from("business_ads")
        .select("*")
        .order("created_at", { ascending: false });
      if (error) throw error;
      return (data ?? []) as BusinessAd[];
    },
  });

  const statsQuery = useQuery({
    queryKey: ["business-ad-stats", user?.id ?? "anon"],
    enabled: !!user,
    queryFn: async (): Promise<AdDailyStat[]> => {
      const { data, error } = await supabase.rpc("business_ad_daily_stats");
      if (error) throw error;
      return (data ?? []) as AdDailyStat[];
    },
  });

  const ads = useMemo(() => adsQuery.data ?? [], [adsQuery.data]);
  const stats = useMemo(() => statsQuery.data ?? [], [statsQuery.data]);

  const [range, setRange] = useState<number>(14);

  /** Stats filtered to the selected window (the RPC covers 90 days). */
  const rangeStats = useMemo((): AdDailyStat[] => {
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - (range - 1));
    const cutoffKey = cutoff.toISOString().slice(0, 10);
    return stats.filter((row) => row.day.slice(0, 10) >= cutoffKey);
  }, [stats, range]);

  /** Continuous last-14-day series (zero-filled) for the chart. */
  const series = useMemo((): DayPoint[] => {
    const byDay = new Map<string, { impressions: number; clicks: number }>();
    for (const row of rangeStats) {
      const key = row.day.slice(0, 10);
      const current = byDay.get(key) ?? { impressions: 0, clicks: 0 };
      current.impressions += Number(row.impressions) || 0;
      current.clicks += Number(row.clicks) || 0;
      byDay.set(key, current);
    }
    const points: DayPoint[] = [];
    for (let offset = range - 1; offset >= 0; offset -= 1) {
      const date = new Date();
      date.setDate(date.getDate() - offset);
      const key = date.toISOString().slice(0, 10);
      const value = byDay.get(key) ?? { impressions: 0, clicks: 0 };
      points.push({
        day: key,
        label: date.toLocaleDateString("en-US", { month: "short", day: "numeric" }),
        impressions: value.impressions,
        clicks: value.clicks,
      });
    }
    return points;
  }, [rangeStats, range]);

  const totals = useMemo(() => {
    let impressions = 0;
    let clicks = 0;
    for (const row of rangeStats) {
      impressions += Number(row.impressions) || 0;
      clicks += Number(row.clicks) || 0;
    }
    return {
      impressions,
      clicks,
      ctr: impressions > 0 ? (clicks / impressions) * 100 : 0,
    };
  }, [rangeStats]);

  const perAd = useMemo(() => {
    const map = new Map<string, { impressions: number; clicks: number }>();
    for (const row of rangeStats) {
      const current = map.get(row.ad_id) ?? { impressions: 0, clicks: 0 };
      current.impressions += Number(row.impressions) || 0;
      current.clicks += Number(row.clicks) || 0;
      map.set(row.ad_id, current);
    }
    return ads
      .map((ad) => {
        const value = map.get(ad.id) ?? { impressions: 0, clicks: 0 };
        return {
          ad,
          impressions: value.impressions,
          clicks: value.clicks,
          ctr: value.impressions > 0 ? (value.clicks / value.impressions) * 100 : 0,
        };
      })
      .sort((a, b) => b.impressions - a.impressions);
  }, [ads, rangeStats]);

  const hasAnyData = totals.impressions > 0 || totals.clicks > 0;

  /** Bookkeeping export — one CSV row per ad per day in the range. */
  const exportCsv = (): void => {
    const nameById = new Map(ads.map((ad) => [ad.id, ad.name]));
    const esc = (value: string): string =>
      /[",\n]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value;
    const lines = rangeStats.map((row) =>
      [
        esc(nameById.get(row.ad_id) ?? row.ad_id),
        row.day.slice(0, 10),
        String(Number(row.impressions) || 0),
        String(Number(row.clicks) || 0),
      ].join(",")
    );
    const blob = new Blob(
      [["ad,day,impressions,clicks", ...lines].join("\n")],
      { type: "text/csv" }
    );
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `whisper-ads-${range}d-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="space-y-3.5">
      {/* Totals */}
      <div className="grid grid-cols-3 gap-2.5">
        {[
          { label: "Impressions", value: businessNumber.format(totals.impressions), icon: Eye },
          { label: "Clicks", value: businessNumber.format(totals.clicks), icon: MousePointerClick },
          {
            label: "CTR",
            value: totals.impressions > 0 ? `${totals.ctr.toFixed(1)}%` : "—",
            icon: Percent,
          },
        ].map((chip) => (
          <div key={chip.label} className="glass rounded-2xl border border-border/60 px-3 py-2.5">
            <div className="flex items-center gap-1.5 text-muted-foreground">
              <chip.icon className="h-3.5 w-3.5" />
              <p className="text-[10px] font-bold uppercase tracking-wide">{chip.label}</p>
            </div>
            <p className="mt-1 text-[17px] font-extrabold tabular-nums">{chip.value}</p>
          </div>
        ))}
      </div>

      {/* Daily chart */}
      <div className="glass rounded-[22px] border border-border/60 p-4">
        <div className="flex items-center justify-between gap-2">
          <div>
            <p className="text-[13px] font-extrabold">Last {range} days</p>
            <p className="text-[11px] text-muted-foreground">
              Impressions and clicks across all ads
            </p>
          </div>
          <div className="flex gap-1">
            {[7, 14, 30, 90].map((option) => (
              <button
                key={option}
                onClick={() => setRange(option)}
                className={`rounded-full px-2.5 py-1 text-[10.5px] font-bold transition-colors ${
                  range === option
                    ? "bg-[#5A5FE8] text-white"
                    : "bg-muted/70 text-muted-foreground"
                }`}
              >
                {option}d
              </button>
            ))}
          </div>
        </div>
        <div className="mt-3 h-[190px] w-full">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={series} margin={{ top: 4, right: 4, left: -18, bottom: 0 }}>
              <defs>
                <linearGradient id="bizImpr" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="#5A5FE8" stopOpacity={0.32} />
                  <stop offset="100%" stopColor="#5A5FE8" stopOpacity={0.02} />
                </linearGradient>
                <linearGradient id="bizClicks" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="#5AA9F9" stopOpacity={0.32} />
                  <stop offset="100%" stopColor="#5AA9F9" stopOpacity={0.02} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" strokeOpacity={0.14} vertical={false} />
              <XAxis
                dataKey="label"
                tick={{ fontSize: 9.5 }}
                tickLine={false}
                axisLine={false}
                interval="preserveStartEnd"
              />
              <YAxis
                tick={{ fontSize: 9.5 }}
                tickLine={false}
                axisLine={false}
                allowDecimals={false}
                width={42}
              />
              <Tooltip
                contentStyle={{
                  borderRadius: 14,
                  fontSize: 11.5,
                  border: "1px solid rgba(120,120,140,0.25)",
                }}
              />
              <Area
                type="monotone"
                dataKey="impressions"
                name="Impressions"
                stroke="#5A5FE8"
                strokeWidth={2}
                fill="url(#bizImpr)"
              />
              <Area
                type="monotone"
                dataKey="clicks"
                name="Clicks"
                stroke="#5AA9F9"
                strokeWidth={2}
                fill="url(#bizClicks)"
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>
        <div className="mt-1.5 flex items-center gap-3.5">
          <span className="flex items-center gap-1.5 text-[10.5px] font-semibold text-muted-foreground">
            <span className="h-2 w-2 rounded-full bg-[#5A5FE8]" /> Impressions
          </span>
          <span className="flex items-center gap-1.5 text-[10.5px] font-semibold text-muted-foreground">
            <span className="h-2 w-2 rounded-full bg-[#5AA9F9]" /> Clicks
          </span>
        </div>
      </div>

      {/* Per-ad breakdown */}
      <div className="glass rounded-[22px] border border-border/60 p-4">
        <div className="flex items-center justify-between">
          <p className="text-[13px] font-extrabold">By ad</p>
          <button
            onClick={exportCsv}
            disabled={rangeStats.length === 0}
            className="flex h-7 items-center gap-1 rounded-full border border-border/60 px-2.5 text-[10.5px] font-bold text-muted-foreground transition-colors hover:text-foreground disabled:opacity-40"
          >
            <Download className="h-3 w-3" />
            CSV
          </button>
        </div>
        {perAd.length === 0 && !adsQuery.isLoading ? (
          <p className="mt-2 text-[11.5px] text-muted-foreground">
            No ads yet — create one in the Ads tab and launch it.
          </p>
        ) : (
          <div className="mt-2.5 space-y-2">
            {perAd.map((row, index) => (
              <div
                key={row.ad.id}
                className="flex items-center gap-2.5 rounded-2xl border border-border/50 bg-background/60 px-3 py-2.5"
              >
                <div className="min-w-0 flex-1">
                  <p className="flex items-center gap-1 text-[12.5px] font-bold">
                    {index === 0 && row.impressions > 0 && (
                      <Trophy className="h-3 w-3 shrink-0 text-amber-500" />
                    )}
                    <span className="truncate">{row.ad.name}</span>
                  </p>
                  <p className="text-[10.5px] text-muted-foreground">
                    {STATUS_LABEL[row.ad.status]}
                  </p>
                </div>
                <div className="flex shrink-0 items-center gap-3 text-right">
                  <div>
                    <p className="text-[12.5px] font-extrabold tabular-nums">
                      {businessNumber.format(row.impressions)}
                    </p>
                    <p className="text-[9px] font-bold uppercase tracking-wide text-muted-foreground">
                      Views
                    </p>
                  </div>
                  <div>
                    <p className="text-[12.5px] font-extrabold tabular-nums">
                      {businessNumber.format(row.clicks)}
                    </p>
                    <p className="text-[9px] font-bold uppercase tracking-wide text-muted-foreground">
                      Clicks
                    </p>
                  </div>
                  <div className="w-11">
                    <p className="text-[12.5px] font-extrabold tabular-nums">
                      {row.impressions > 0 ? `${row.ctr.toFixed(1)}%` : "—"}
                    </p>
                    <p className="text-[9px] font-bold uppercase tracking-wide text-muted-foreground">
                      CTR
                    </p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {!hasAnyData && !statsQuery.isLoading && (
        <div className="glass rounded-[22px] border border-border/60 p-5 text-center">
          <BarChart3 className="mx-auto h-7 w-7 text-muted-foreground/50" />
          <p className="mt-2 text-[12.5px] font-bold">Numbers land here once an ad is live</p>
          <p className="mx-auto mt-1 max-w-[300px] text-[11px] leading-relaxed text-muted-foreground">
            Launch an ad and Whisper starts counting real impressions and clicks as people
            scroll the feed.
          </p>
        </div>
      )}
    </div>
  );
}
