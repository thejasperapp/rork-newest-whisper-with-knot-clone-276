/**
 * Whisper Business — /business
 *
 * The full business suite (v2), modeled on Meta Business Suite:
 *   Overview  — setup checklist, 7-day ad KPIs, deal totals, quick actions
 *   Ads       — create/edit/duplicate/pause ads with a live feed preview
 *   Analytics — real impressions/clicks/CTR, daily chart, per-ad breakdown
 *   Profile   — the company identity that fronts every ad
 *   Deals     — the five-stage sponsorship pipeline (v1 board)
 *
 * Data lives in supabase/business-suite.sql (v2): business_deals,
 * business_profiles, business_ads, business_ad_events + serving/tracking
 * RPCs. Everything is owner-only via RLS; ads are served into the feed
 * through business_active_ads().
 */
import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  BarChart3,
  Briefcase,
  Building2,
  ChevronLeft,
  ChevronRight,
  DollarSign,
  Handshake,
  LayoutGrid,
  Megaphone,
  Pencil,
  Plus,
  Trash2,
  TrendingUp,
  Trophy,
  X,
} from "lucide-react";

import { BusinessPlusMark } from "@/components/BusinessPlusMark";

import { Header } from "@/components/Header";
import { supabase } from "@/lib/supabase";
import { useAuth } from "@/hooks/useAuth";
import { isMissingBusinessSchema } from "@/lib/business";
import { BusinessOverviewTab } from "@/components/business/BusinessOverviewTab";
import { BusinessAdsTab } from "@/components/business/BusinessAdsTab";
import { BusinessAnalyticsTab } from "@/components/business/BusinessAnalyticsTab";
import { BusinessProfileTab } from "@/components/business/BusinessProfileTab";
import { BusinessPlusPanel } from "@/components/BusinessPlusPanel";
import { ACTIVE_PORTAL } from "@/lib/portal";
import BrandDashboard from "@/pages/BrandDashboard";

export type DealStage = "lead" | "pitched" | "negotiating" | "active" | "completed";

type SuiteTab = "overview" | "ads" | "analytics" | "profile" | "deals" | "plus" | "marketplace";

function isSuiteTab(value: string | null): value is SuiteTab {
  return (
    value === "overview" ||
    value === "ads" ||
    value === "analytics" ||
    value === "profile" ||
    value === "deals" ||
    value === "plus" || value === "marketplace"
  );
}

interface BusinessDeal {
  id: string;
  user_id: string;
  brand_name: string;
  contact: string | null;
  creator_username: string | null;
  value_cents: number;
  stage: DealStage;
  next_step: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

interface DealDraft {
  id: string | null;
  brandName: string;
  valueDollars: string;
  creatorUsername: string;
  contact: string;
  nextStep: string;
  notes: string;
  stage: DealStage;
}

const STAGES: { id: DealStage; label: string; accent: string; chip: string }[] = [
  { id: "lead", label: "Leads", accent: "#8B93B0", chip: "bg-slate-500/15 text-slate-300" },
  { id: "pitched", label: "Pitched", accent: "#5AA9F9", chip: "bg-sky-500/15 text-sky-300" },
  { id: "negotiating", label: "Negotiating", accent: "#F2B84B", chip: "bg-amber-500/15 text-amber-300" },
  { id: "active", label: "Active", accent: "#5A5FE8", chip: "bg-orange-500/15 text-orange-300" },
  { id: "completed", label: "Won", accent: "#7BD8A8", chip: "bg-emerald-500/15 text-emerald-300" },
];

const TABS: { id: SuiteTab; label: string; icon: typeof LayoutGrid }[] = [
  { id: "overview", label: "Overview", icon: LayoutGrid },
  { id: "plus", label: "Business+", icon: BusinessPlusMark },
  { id: "ads", label: "Ads", icon: Megaphone },
  { id: "analytics", label: "Analytics", icon: BarChart3 },
  { id: "profile", label: "Profile", icon: Building2 },
  { id: "marketplace", label: "Sponsorships", icon: Handshake },
  { id: "deals", label: "Manual pipeline", icon: Briefcase },
];

const usd = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  maximumFractionDigits: 0,
});

const emptyDraft: DealDraft = {
  id: null,
  brandName: "",
  valueDollars: "",
  creatorUsername: "",
  contact: "",
  nextStep: "",
  notes: "",
  stage: "lead",
};

function isMissingTable(error: unknown): boolean {
  const err = error as { code?: string; message?: string } | null;
  if (!err) return false;
  if (err.code === "42P01") return true;
  return (err.message ?? "").includes("business_deals") && (err.message ?? "").includes("does not exist");
}

export default function BusinessSuite() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const queryClient = useQueryClient();

  // The active tool lives in ?tab= so the portal sidebar (and links/
  // refreshes) can drive it; in-page tab clicks write the same param.
  const [searchParams, setSearchParams] = useSearchParams();
  const tab: SuiteTab = isSuiteTab(searchParams.get("tab"))
    ? (searchParams.get("tab") as SuiteTab)
    : "overview";
  const setTab = useCallback(
    (next: SuiteTab) => {
      setSearchParams(
        (prev) => {
          const sp = new URLSearchParams(prev);
          sp.set("tab", next);
          return sp;
        },
        { replace: false }
      );
    },
    [setSearchParams]
  );
  const inPortal = ACTIVE_PORTAL === "business";

  // Vanity subdomains land on their wing: ads.… → Ads Manager,
  // brands.… → Brand deals — only when no explicit tab is in the URL.
  useEffect(() => {
    if (searchParams.get("tab")) return;
    const host = window.location.hostname.toLowerCase();
    if (host.startsWith("ads.")) setTab("ads");
    else if (host.startsWith("brands.")) setTab("marketplace");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const [draft, setDraft] = useState<DealDraft | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);

  /** Probe for the v2 schema — one light query gates the new tabs. */
  const probeQuery = useQuery({
    queryKey: ["business-schema-probe", user?.id ?? "anon"],
    enabled: !!user,
    retry: false,
    queryFn: async (): Promise<boolean> => {
      const { error } = await supabase.from("business_profiles").select("id").limit(1);
      if (error) throw error;
      return true;
    },
  });
  const v2Missing = probeQuery.isError && isMissingBusinessSchema(probeQuery.error);

  const dealsQuery = useQuery({
    queryKey: ["business-deals", user?.id ?? "anon"],
    enabled: !!user,
    queryFn: async (): Promise<BusinessDeal[]> => {
      const { data, error } = await supabase
        .from("business_deals")
        .select("*")
        .order("updated_at", { ascending: false });
      if (error) throw error;
      return (data ?? []) as BusinessDeal[];
    },
  });

  const invalidate = () => {
    void queryClient.invalidateQueries({ queryKey: ["business-deals", user?.id ?? "anon"] });
  };

  const saveMutation = useMutation({
    mutationFn: async (input: DealDraft): Promise<void> => {
      if (!user) throw new Error("Sign in first.");
      const cents = Math.max(0, Math.round((parseFloat(input.valueDollars) || 0) * 100));
      const row = {
        brand_name: input.brandName.trim(),
        contact: input.contact.trim() || null,
        creator_username: input.creatorUsername.trim().replace(/^@/, "") || null,
        value_cents: cents,
        stage: input.stage,
        next_step: input.nextStep.trim() || null,
        notes: input.notes.trim() || null,
        updated_at: new Date().toISOString(),
      };
      if (input.id) {
        const { error } = await supabase.from("business_deals").update(row).eq("id", input.id);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from("business_deals")
          .insert({ ...row, user_id: user.id });
        if (error) throw error;
      }
    },
    onSuccess: () => {
      setDraft(null);
      setSaveError(null);
      invalidate();
    },
    onError: (error: unknown) => {
      const err = error as { message?: string };
      setSaveError(err.message ?? "Couldn't save the deal. Try again.");
    },
  });

  const moveMutation = useMutation({
    mutationFn: async ({ deal, dir }: { deal: BusinessDeal; dir: 1 | -1 }): Promise<void> => {
      const index = STAGES.findIndex((s) => s.id === deal.stage);
      const next = STAGES[index + dir];
      if (!next) return;
      const { error } = await supabase
        .from("business_deals")
        .update({ stage: next.id, updated_at: new Date().toISOString() })
        .eq("id", deal.id);
      if (error) throw error;
    },
    onSuccess: invalidate,
  });

  const deleteMutation = useMutation({
    mutationFn: async (id: string): Promise<void> => {
      const { error } = await supabase.from("business_deals").delete().eq("id", id);
      if (error) throw error;
    },
    onSuccess: invalidate,
  });

  const deals = useMemo(() => dealsQuery.data ?? [], [dealsQuery.data]);

  const stats = useMemo(() => {
    const sum = (stages: DealStage[]) =>
      deals
        .filter((d) => stages.includes(d.stage))
        .reduce((total, d) => total + d.value_cents, 0) / 100;
    return {
      pipeline: sum(["lead", "pitched", "negotiating"]),
      active: sum(["active"]),
      won: sum(["completed"]),
      count: deals.length,
    };
  }, [deals]);

  const migrationNeeded = dealsQuery.isError && isMissingTable(dealsQuery.error);

  const handleTabNavigate = (next: string): void => {
    const match = TABS.find((t) => t.id === next);
    if (match) setTab(match.id);
  };

  return (
    <div>
      {!inPortal && (
        <Header
          title="Whisper Business"
          left={
            <button
              onClick={() => navigate(-1)}
              aria-label="Back"
              className="glass flex h-10 w-10 items-center justify-center rounded-full border border-border/60 shadow-sm transition-transform active:scale-90"
            >
              <ArrowLeft className="h-5 w-5" />
            </button>
          }
          right={<span className="h-10 w-10" />}
        />
      )}

      <div className={inPortal ? "px-4 pt-6 pb-24 sm:px-6" : "px-4 pt-2 pb-24"}>
        <div
          className={`mx-auto ${inPortal ? "max-w-5xl" : "max-w-4xl"} space-y-3.5`}
        >
          {/* ── Hero ─────────────────────────────────────────────────────── */}
          <div
            className="rounded-[22px] p-4 text-white"
            style={{
              background:
                "linear-gradient(135deg, #0F142B 0%, #1A1A42 55%, #29174D 100%)",
            }}
          >
            <div className="flex items-center gap-3">
              <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-[#5A5FE8]/20">
                <Briefcase className="h-5.5 w-5.5 text-[#5A5FE8]" />
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-[16px] font-extrabold leading-tight">Business Suite</p>
                <p className="text-[11.5px] text-white/60">
                  Run your brand on Whisper — profile, ads, analytics, deals.
                </p>
              </div>
              {tab === "deals" && (
                <button
                  onClick={() => {
                    setSaveError(null);
                    setDraft({ ...emptyDraft });
                  }}
                  className="flex h-9 items-center gap-1.5 rounded-full bg-[#5A5FE8] px-3.5 text-[12px] font-bold text-white transition-transform active:scale-95"
                >
                  <Plus className="h-4 w-4" />
                  New deal
                </button>
              )}
            </div>

            {/* Tab rail — hidden in the portal, where the sidebar owns nav. */}
            {!inPortal && (
              <div className="no-scrollbar -mx-1 mt-3.5 flex gap-1.5 overflow-x-auto px-1">
                {TABS.map((item) => (
                  <button
                    key={item.id}
                    onClick={() => setTab(item.id)}
                    className={`flex shrink-0 items-center gap-1.5 rounded-full px-3.5 py-2 text-[12px] font-bold transition-colors ${
                      tab === item.id
                        ? "bg-[#5A5FE8] text-white"
                        : "bg-white/[0.07] text-white/65 hover:text-white"
                    }`}
                  >
                    <item.icon className="h-3.5 w-3.5" />
                    {item.label}
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* ── v2 migration needed (profiles / ads / analytics) ─────────── */}
          {v2Missing && !["deals", "marketplace", "plus"].includes(tab) && (
            <div className="glass rounded-[22px] border border-amber-500/40 p-4">
              <p className="text-[14px] font-bold">One-time database update needed</p>
              <p className="mt-1 text-[12.5px] leading-relaxed text-muted-foreground">
                Run the updated{" "}
                <code className="rounded bg-muted px-1 py-0.5">supabase/business-suite.sql</code>{" "}
                in the Supabase SQL editor — v2 adds business profiles, the ads manager, feed
                serving, and analytics. Re-running it is safe and takes seconds; this page lights
                up the moment it's done.
              </p>
            </div>
          )}

          {/* ── Tab content ──────────────────────────────────────────────── */}
          {!v2Missing && tab === "overview" && (
            <BusinessOverviewTab
              onNavigate={handleTabNavigate}
              dealTotals={{ pipeline: stats.pipeline, active: stats.active, won: stats.won }}
            />
          )}
          {!v2Missing && tab === "ads" && <BusinessAdsTab onNavigate={handleTabNavigate} />}
          {!v2Missing && tab === "analytics" && <BusinessAnalyticsTab />}
          {!v2Missing && tab === "profile" && <BusinessProfileTab />}

          {/* ── Business+ — team, hiring, HQ, team calendar ────────────── */}
          {tab === "plus" && <BusinessPlusPanel />}
          {tab === "marketplace" && <>
            <div className="rounded-2xl border border-border bg-background p-4 text-sm text-muted-foreground">Manage real marketplace applications, negotiated agreements and escrow here. The manual pipeline keeps your own leads and notes separately; it never creates a paid agreement.</div>
            <BrandDashboard embedded />
          </>}

          {/* ── Deals (v1 board) ─────────────────────────────────────────── */}
          {tab === "deals" && migrationNeeded && (
            <div className="glass rounded-[22px] border border-amber-500/40 p-4">
              <p className="text-[14px] font-bold">One-time database update needed</p>
              <p className="mt-1 text-[12.5px] leading-relaxed text-muted-foreground">
                Run <code className="rounded bg-muted px-1 py-0.5">supabase/business-suite.sql</code>{" "}
                in the Supabase SQL editor to create your deal pipeline. This page starts working
                the moment it's run — nothing else is affected.
              </p>
            </div>
          )}

          {tab === "deals" && !migrationNeeded && (
            <>
              <div className="glass rounded-[22px] border border-border/60 p-4">
                <p className="text-[14px] font-extrabold">Brand deals — your sponsorship pipeline</p>
                <p className="mt-1 text-[12.5px] leading-relaxed text-muted-foreground">
                  Separate from ads: ads buy reach in the feed, while brand deals track
                  the sponsorships your company runs with individual creators — from
                  first contact to a signed, paid partnership. Add a deal when you start
                  talking to a creator and move the card across stages as it progresses.
                </p>
              </div>

              <div className="grid grid-cols-3 gap-2">
                {[
                  { label: "In pipeline", value: usd.format(stats.pipeline), icon: TrendingUp },
                  { label: "Active", value: usd.format(stats.active), icon: Handshake },
                  { label: "Won", value: usd.format(stats.won), icon: Trophy },
                ].map((chip) => (
                  <div key={chip.label} className="glass rounded-2xl border border-border/60 px-3 py-2.5">
                    <div className="flex items-center gap-1.5 text-muted-foreground">
                      <chip.icon className="h-3.5 w-3.5" />
                      <p className="text-[10px] font-bold uppercase tracking-wide">{chip.label}</p>
                    </div>
                    <p className="mt-1 text-[15px] font-extrabold tabular-nums">{chip.value}</p>
                  </div>
                ))}
              </div>

              <div className="no-scrollbar -mx-4 flex snap-x gap-3 overflow-x-auto px-4 pb-2">
                {STAGES.map((stage) => {
                  const rows = deals.filter((d) => d.stage === stage.id);
                  const total = rows.reduce((sum, d) => sum + d.value_cents, 0) / 100;
                  return (
                    <div
                      key={stage.id}
                      className="glass w-[248px] shrink-0 snap-start rounded-[20px] border border-border/60 p-3"
                    >
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-2">
                          <span
                            className="h-2 w-2 rounded-full"
                            style={{ background: stage.accent }}
                          />
                          <p className="text-[12.5px] font-extrabold">{stage.label}</p>
                          <span className={`rounded-full px-1.5 py-0.5 text-[10px] font-bold ${stage.chip}`}>
                            {rows.length}
                          </span>
                        </div>
                        <p className="text-[10.5px] font-bold tabular-nums text-muted-foreground">
                          {total > 0 ? usd.format(total) : ""}
                        </p>
                      </div>

                      <div className="mt-2.5 space-y-2">
                        {rows.map((deal) => (
                          <div
                            key={deal.id}
                            className="rounded-2xl border border-border/50 bg-background/60 p-2.5"
                          >
                            <div className="flex items-start justify-between gap-2">
                              <div className="min-w-0">
                                <p className="truncate text-[13px] font-bold">{deal.brand_name}</p>
                                {deal.creator_username && (
                                  <p className="truncate text-[11px] text-muted-foreground">
                                    with @{deal.creator_username}
                                  </p>
                                )}
                              </div>
                              {deal.value_cents > 0 && (
                                <span className="flex shrink-0 items-center gap-0.5 rounded-full bg-emerald-500/12 px-1.5 py-0.5 text-[10.5px] font-extrabold tabular-nums text-emerald-500">
                                  <DollarSign className="h-3 w-3" />
                                  {usd.format(deal.value_cents / 100).replace("$", "")}
                                </span>
                              )}
                            </div>
                            {deal.next_step && (
                              <p className="mt-1.5 line-clamp-2 text-[11px] leading-snug text-muted-foreground">
                                Next: {deal.next_step}
                              </p>
                            )}
                            <div className="mt-2 flex items-center gap-1">
                              <button
                                onClick={() => moveMutation.mutate({ deal, dir: -1 })}
                                disabled={deal.stage === "lead"}
                                aria-label="Move to earlier stage"
                                className="flex h-7 w-7 items-center justify-center rounded-full bg-muted/70 text-muted-foreground transition-colors hover:text-foreground disabled:opacity-30"
                              >
                                <ChevronLeft className="h-3.5 w-3.5" />
                              </button>
                              <button
                                onClick={() => moveMutation.mutate({ deal, dir: 1 })}
                                disabled={deal.stage === "completed"}
                                aria-label="Move to next stage"
                                className="flex h-7 w-7 items-center justify-center rounded-full bg-muted/70 text-muted-foreground transition-colors hover:text-foreground disabled:opacity-30"
                              >
                                <ChevronRight className="h-3.5 w-3.5" />
                              </button>
                              <div className="flex-1" />
                              <button
                                onClick={() => {
                                  setSaveError(null);
                                  setDraft({
                                    id: deal.id,
                                    brandName: deal.brand_name,
                                    valueDollars: deal.value_cents > 0 ? String(deal.value_cents / 100) : "",
                                    creatorUsername: deal.creator_username ?? "",
                                    contact: deal.contact ?? "",
                                    nextStep: deal.next_step ?? "",
                                    notes: deal.notes ?? "",
                                    stage: deal.stage,
                                  });
                                }}
                                aria-label="Edit deal"
                                className="flex h-7 w-7 items-center justify-center rounded-full bg-muted/70 text-muted-foreground transition-colors hover:text-foreground"
                              >
                                <Pencil className="h-3.5 w-3.5" />
                              </button>
                              <button
                                onClick={() => {
                                  if (window.confirm(`Delete the ${deal.brand_name} deal?`)) {
                                    deleteMutation.mutate(deal.id);
                                  }
                                }}
                                aria-label="Delete deal"
                                className="flex h-7 w-7 items-center justify-center rounded-full bg-muted/70 text-muted-foreground transition-colors hover:text-red-500"
                              >
                                <Trash2 className="h-3.5 w-3.5" />
                              </button>
                            </div>
                          </div>
                        ))}

                        {rows.length === 0 && (
                          <button
                            onClick={() => {
                              setSaveError(null);
                              setDraft({ ...emptyDraft, stage: stage.id });
                            }}
                            className="flex w-full items-center justify-center gap-1.5 rounded-2xl border border-dashed border-border/70 py-4 text-[11.5px] font-semibold text-muted-foreground transition-colors hover:text-foreground"
                          >
                            <Plus className="h-3.5 w-3.5" />
                            Add here
                          </button>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>

              {deals.length === 0 && !dealsQuery.isLoading && (
                <p className="px-1 text-center text-[12px] text-muted-foreground">
                  Track every sponsorship from first DM to paid — add your first deal above.
                </p>
              )}
            </>
          )}
        </div>
      </div>

      {/* ── Add / edit deal modal ─────────────────────────────────────── */}
      {draft && (
        <div
          className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 p-4 backdrop-blur-sm sm:items-center"
          onClick={() => setDraft(null)}
        >
          <div
            className="glass w-full max-w-md rounded-[22px] border border-border/60 bg-background/95 p-4 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between">
              <p className="text-[15px] font-extrabold">{draft.id ? "Edit deal" : "New deal"}</p>
              <button
                onClick={() => setDraft(null)}
                aria-label="Close"
                className="flex h-8 w-8 items-center justify-center rounded-full bg-muted/70"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <div className="mt-3 space-y-2.5">
              <input
                value={draft.brandName}
                onChange={(e) => setDraft({ ...draft, brandName: e.target.value })}
                placeholder="Brand or partner name"
                className="w-full rounded-xl border border-border/60 bg-background px-3 py-2.5 text-[13.5px] outline-none focus:border-[#5A5FE8]/60"
              />
              <div className="flex gap-2.5">
                <input
                  value={draft.valueDollars}
                  onChange={(e) => setDraft({ ...draft, valueDollars: e.target.value })}
                  placeholder="Value (USD)"
                  inputMode="decimal"
                  className="w-full rounded-xl border border-border/60 bg-background px-3 py-2.5 text-[13.5px] outline-none focus:border-[#5A5FE8]/60"
                />
                <input
                  value={draft.creatorUsername}
                  onChange={(e) => setDraft({ ...draft, creatorUsername: e.target.value })}
                  placeholder="@creator"
                  className="w-full rounded-xl border border-border/60 bg-background px-3 py-2.5 text-[13.5px] outline-none focus:border-[#5A5FE8]/60"
                />
              </div>
              <input
                value={draft.contact}
                onChange={(e) => setDraft({ ...draft, contact: e.target.value })}
                placeholder="Contact (email / phone / IG)"
                className="w-full rounded-xl border border-border/60 bg-background px-3 py-2.5 text-[13.5px] outline-none focus:border-[#5A5FE8]/60"
              />
              <input
                value={draft.nextStep}
                onChange={(e) => setDraft({ ...draft, nextStep: e.target.value })}
                placeholder="Next step (e.g. send rate card Friday)"
                className="w-full rounded-xl border border-border/60 bg-background px-3 py-2.5 text-[13.5px] outline-none focus:border-[#5A5FE8]/60"
              />
              <textarea
                value={draft.notes}
                onChange={(e) => setDraft({ ...draft, notes: e.target.value })}
                placeholder="Notes"
                rows={2}
                className="w-full resize-none rounded-xl border border-border/60 bg-background px-3 py-2.5 text-[13.5px] outline-none focus:border-[#5A5FE8]/60"
              />
              <div className="no-scrollbar flex gap-1.5 overflow-x-auto">
                {STAGES.map((stage) => (
                  <button
                    key={stage.id}
                    onClick={() => setDraft({ ...draft, stage: stage.id })}
                    className={`shrink-0 rounded-full px-3 py-1.5 text-[11.5px] font-bold transition-colors ${
                      draft.stage === stage.id
                        ? "bg-[#5A5FE8] text-white"
                        : "bg-muted/70 text-muted-foreground"
                    }`}
                  >
                    {stage.label}
                  </button>
                ))}
              </div>

              {saveError && <p className="text-[11.5px] font-semibold text-red-500">{saveError}</p>}

              <button
                onClick={() => {
                  if (!draft.brandName.trim()) {
                    setSaveError("Give the deal a brand name.");
                    return;
                  }
                  saveMutation.mutate(draft);
                }}
                disabled={saveMutation.isPending}
                className="w-full rounded-full bg-[#5A5FE8] py-3 text-[13.5px] font-extrabold text-white transition-transform active:scale-[0.98] disabled:opacity-60"
              >
                {saveMutation.isPending ? "Saving…" : draft.id ? "Save changes" : "Add deal"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
