/**
 * Business overview — the "am I set up and is it working?" tab: a setup
 * checklist (profile → ad → live), 7-day delivery KPIs, the deal-pipeline
 * summary, and quick jumps into the other tabs.
 */
import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  ArrowRight,
  BarChart3,
  Building2,
  CheckCircle2,
  Circle,
  Eye,
  Handshake,
  Megaphone,
  MousePointerClick,
  TrendingUp,
  Trophy,
} from "lucide-react";

import { supabase } from "@/lib/supabase";
import { useAuth } from "@/hooks/useAuth";
import {
  AdDailyStat,
  BusinessAd,
  BusinessProfile,
  businessNumber,
  businessUsd,
} from "@/lib/business";

interface BusinessOverviewTabProps {
  onNavigate: (tab: string) => void;
  dealTotals: { pipeline: number; active: number; won: number };
}

export function BusinessOverviewTab({ onNavigate, dealTotals }: BusinessOverviewTabProps) {
  const { user } = useAuth();

  const profileQuery = useQuery({
    queryKey: ["business-profile", user?.id ?? "anon"],
    enabled: !!user,
    queryFn: async (): Promise<BusinessProfile | null> => {
      const { data, error } = await supabase
        .from("business_profiles")
        .select("*")
        .order("created_at", { ascending: true })
        .limit(1);
      if (error) throw error;
      return ((data ?? [])[0] as BusinessProfile | undefined) ?? null;
    },
  });

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

  const profile = profileQuery.data ?? null;
  const ads = useMemo(() => adsQuery.data ?? [], [adsQuery.data]);
  const liveAds = useMemo(() => ads.filter((ad) => ad.status === "active"), [ads]);

  /** Last-7-day delivery totals. */
  const week = useMemo(() => {
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - 7);
    const cutoffKey = cutoff.toISOString().slice(0, 10);
    let impressions = 0;
    let clicks = 0;
    for (const row of statsQuery.data ?? []) {
      if (row.day.slice(0, 10) >= cutoffKey) {
        impressions += Number(row.impressions) || 0;
        clicks += Number(row.clicks) || 0;
      }
    }
    return {
      impressions,
      clicks,
      ctr: impressions > 0 ? (clicks / impressions) * 100 : 0,
    };
  }, [statsQuery.data]);

  const steps: { done: boolean; label: string; detail: string; tab: string }[] = [
    {
      done: !!profile,
      label: "Create your business profile",
      detail: "Name, logo, and contact — it fronts every ad.",
      tab: "profile",
    },
    {
      done: ads.length > 0,
      label: "Build your first ad",
      detail: "Headline, image, and a button link — with live preview.",
      tab: "ads",
    },
    {
      done: liveAds.length > 0,
      label: "Launch it into the feed",
      detail: "Hit Launch and Whisper starts serving it to users.",
      tab: "ads",
    },
  ];
  const setupComplete = steps.every((step) => step.done);

  return (
    <div className="space-y-3.5">
      {/* Setup checklist until everything is live */}
      {!setupComplete && (
        <div className="glass rounded-[22px] border border-border/60 p-4">
          <p className="text-[13.5px] font-extrabold">Get your business live on Whisper</p>
          <div className="mt-2.5 space-y-1.5">
            {steps.map((step) => (
              <button
                key={step.label}
                onClick={() => onNavigate(step.tab)}
                className="flex w-full items-center gap-2.5 rounded-2xl border border-border/50 bg-background/60 px-3 py-2.5 text-left transition-colors hover:border-[#5A5FE8]/40"
              >
                {step.done ? (
                  <CheckCircle2 className="h-5 w-5 shrink-0 text-emerald-500" />
                ) : (
                  <Circle className="h-5 w-5 shrink-0 text-muted-foreground/50" />
                )}
                <div className="min-w-0 flex-1">
                  <p
                    className={`text-[12.5px] font-bold ${step.done ? "text-muted-foreground line-through" : ""}`}
                  >
                    {step.label}
                  </p>
                  {!step.done && (
                    <p className="text-[10.5px] text-muted-foreground">{step.detail}</p>
                  )}
                </div>
                {!step.done && <ArrowRight className="h-4 w-4 shrink-0 text-muted-foreground" />}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Delivery KPIs — 7 days */}
      <div className="glass rounded-[22px] border border-border/60 p-4">
        <div className="flex items-center justify-between">
          <p className="text-[13px] font-extrabold">Ads this week</p>
          <span className="rounded-full bg-muted/70 px-2 py-0.5 text-[10px] font-bold text-muted-foreground">
            {liveAds.length} live
          </span>
        </div>
        <div className="mt-2.5 grid grid-cols-3 gap-2">
          {[
            { label: "Impressions", value: businessNumber.format(week.impressions), icon: Eye },
            { label: "Clicks", value: businessNumber.format(week.clicks), icon: MousePointerClick },
            {
              label: "CTR",
              value: week.impressions > 0 ? `${week.ctr.toFixed(1)}%` : "—",
              icon: TrendingUp,
            },
          ].map((chip) => (
            <div key={chip.label} className="rounded-xl bg-muted/50 px-2.5 py-2">
              <div className="flex items-center gap-1 text-muted-foreground">
                <chip.icon className="h-3 w-3" />
                <p className="text-[9.5px] font-bold uppercase tracking-wide">{chip.label}</p>
              </div>
              <p className="text-[15px] font-extrabold tabular-nums">{chip.value}</p>
            </div>
          ))}
        </div>
      </div>

      {/* Deals summary */}
      <div className="glass rounded-[22px] border border-border/60 p-4">
        <div className="flex items-center justify-between">
          <p className="text-[13px] font-extrabold">Deal pipeline</p>
          <button
            onClick={() => onNavigate("deals")}
            className="flex items-center gap-1 text-[11.5px] font-bold text-[#5A5FE8]"
          >
            Open board
            <ArrowRight className="h-3.5 w-3.5" />
          </button>
        </div>
        <div className="mt-2.5 grid grid-cols-3 gap-2">
          {[
            { label: "In pipeline", value: businessUsd.format(dealTotals.pipeline), icon: TrendingUp },
            { label: "Active", value: businessUsd.format(dealTotals.active), icon: Handshake },
            { label: "Won", value: businessUsd.format(dealTotals.won), icon: Trophy },
          ].map((chip) => (
            <div key={chip.label} className="rounded-xl bg-muted/50 px-2.5 py-2">
              <div className="flex items-center gap-1 text-muted-foreground">
                <chip.icon className="h-3 w-3" />
                <p className="text-[9.5px] font-bold uppercase tracking-wide">{chip.label}</p>
              </div>
              <p className="text-[13.5px] font-extrabold tabular-nums">{chip.value}</p>
            </div>
          ))}
        </div>
      </div>

      {/* Quick actions */}
      <div className="grid grid-cols-3 gap-2.5">
        {[
          { label: "New ad", icon: Megaphone, tab: "ads" },
          { label: "Analytics", icon: BarChart3, tab: "analytics" },
          { label: "Profile", icon: Building2, tab: "profile" },
        ].map((action) => (
          <button
            key={action.label}
            onClick={() => onNavigate(action.tab)}
            className="glass flex flex-col items-center gap-1.5 rounded-2xl border border-border/60 py-3.5 transition-transform active:scale-95"
          >
            <action.icon className="h-5 w-5 text-[#5A5FE8]" />
            <p className="text-[11.5px] font-bold">{action.label}</p>
          </button>
        ))}
      </div>
    </div>
  );
}
