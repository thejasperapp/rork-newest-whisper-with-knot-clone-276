/**
 * Ads Manager — structured EXACTLY like Meta's Ads Manager:
 *
 *   Campaign  (the WHY  — objective + on/off)
 *     └─ Ad set  (the WHO/WHEN — audience, schedule, placement, daily pacing)
 *          └─ Ad  (the WHAT — the creative users actually see)
 *
 * Three drill-down levels with delivery stats aggregated at every level, a
 * guided create flow (objective → audience → creative) that mirrors Meta's
 * campaign wizard, and a live preview of the exact feed card. Every
 * impression an ad buys also funds the WPP creator pool.
 *
 * Tables: supabase/business-suite-v4.sql (campaigns + ad sets; older ads
 * are auto-wrapped by the migration).
 */
import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Building2,
  ChevronRight,
  Copy,
  Eye,
  Folder,
  Layers,
  Megaphone,
  MousePointerClick,
  Pause,
  Pencil,
  Play,
  Plus,
  Sparkles,
  Trash2,
  Upload,
  Wallet,
  X,
  Zap,
} from "lucide-react";
import { toast } from "sonner";

import { supabase } from "@/lib/supabase";
import { useAuth } from "@/hooks/useAuth";
import {
  ActiveAd,
  AD_PLACEMENT_OPTIONS,
  AD_TARGET_OPTIONS,
  AdDailyStat,
  AdPlacement,
  BusinessAd,
  BusinessAdSet,
  BusinessCampaign,
  BusinessProfile,
  CAMPAIGN_OBJECTIVES,
  CampaignObjective,
  FOLLOWER_BANDS,
  HierarchyStatus,
  businessNumber,
  disableAutoRecharge,
  enableAutoRecharge,
  fetchAdWallet,
  fetchAutoRecharge,
  isMissingBusinessSchema,
  runAutoRechargeCheck,
  startAdCreditsTopup,
  startAutoRechargeSetup,
  uploadAdMedia,
} from "@/lib/business";
import { SponsoredAdCard } from "@/components/business/SponsoredAdCard";
import { EmbeddedCheckoutSheet } from "@/components/EmbeddedCheckoutSheet";

type Level = "campaigns" | "adsets" | "ads";

const ACCENT = "#5A5FE8";

const PLACEMENTS: { id: AdPlacement; label: string }[] = [
  { id: "feed", label: "Feed" },
  { id: "discover", label: "Discover" },
  { id: "both", label: "Feed + Discover" },
];

const PLACEMENT_LABEL: Record<string, string> = {
  feed: "Feed",
  reels: "Reels",
  comments: "Comments",
  discover: "Discover",
};

const STATUS_CHIP: Record<string, { label: string; chip: string }> = {
  draft: { label: "Draft", chip: "bg-slate-500/15 text-slate-400" },
  active: { label: "Live", chip: "bg-emerald-500/15 text-emerald-500" },
  paused: { label: "Paused", chip: "bg-amber-500/15 text-amber-500" },
  ended: { label: "Ended", chip: "bg-slate-500/15 text-slate-400" },
};

interface Totals {
  impressions: number;
  clicks: number;
}

interface WizardState {
  /** 1 = campaign, 2 = ad set, 3 = ad creative. */
  step: 1 | 2 | 3;
  /** Present when adding into an existing campaign / ad set. */
  campaignId: string | null;
  adSetId: string | null;
  campaignName: string;
  objective: CampaignObjective;
  /** Optional lifetime spend cap, in dollars (empty = no cap). */
  lifetimeBudget: string;
  setName: string;
  targetRoles: string[];
  placement: AdPlacement;
  /** v5 — real placements: feed / reels / comments. */
  placements: string[];
  /** v5 — follower-band id from FOLLOWER_BANDS. */
  followerBand: string;
  startAt: string;
  endAt: string;
  dailyCap: string;
  adName: string;
  headline: string;
  body: string;
  imageUrl: string;
  videoUrl: string;
  mediaType: "image" | "video";
  ctaLabel: string;
  ctaUrl: string;
}

const emptyWizard: WizardState = {
  step: 1,
  campaignId: null,
  adSetId: null,
  campaignName: "",
  objective: "traffic",
  lifetimeBudget: "",
  setName: "",
  targetRoles: [],
  placement: "feed",
  placements: ["feed"],
  followerBand: "any",
  startAt: "",
  endAt: "",
  dailyCap: "",
  adName: "",
  headline: "",
  body: "",
  imageUrl: "",
  videoUrl: "",
  mediaType: "image",
  ctaLabel: "Learn more",
  ctaUrl: "",
};

interface BusinessAdsTabProps {
  onNavigate: (tab: string) => void;
}

const usd = (cents: number): string =>
  (cents / 100).toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
  });

export function BusinessAdsTab({ onNavigate }: BusinessAdsTabProps) {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  const [level, setLevel] = useState<Level>("campaigns");
  const [selCampaign, setSelCampaign] = useState<string | null>(null);
  const [selAdSet, setSelAdSet] = useState<string | null>(null);
  const [wizard, setWizard] = useState<WizardState | null>(null);
  const [editAd, setEditAd] = useState<BusinessAd | null>(null);
  const [adDraft, setAdDraft] = useState<{
    name: string;
    headline: string;
    body: string;
    imageUrl: string;
    videoUrl: string;
    mediaType: "image" | "video";
    ctaLabel: string;
    ctaUrl: string;
  } | null>(null);
  const [uploading, setUploading] = useState<boolean>(false);

  /** Shared upload path for the wizard + editor — photo OR video. */
  const pickMedia = async (
    file: File,
    apply: (media: { url: string; type: "image" | "video" }) => void
  ): Promise<void> => {
    if (!user) return;
    setUploading(true);
    try {
      const media = await uploadAdMedia(user.id, file);
      apply(media);
      toast.success(
        media.type === "video" ? "Video uploaded." : "Photo uploaded."
      );
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Upload failed.");
    } finally {
      setUploading(false);
    }
  };

  // ── Ads wallet — prepaid delivery; impressions bill at CPM and fund WPP ──
  const walletQuery = useQuery({
    queryKey: ["ad-wallet"],
    queryFn: fetchAdWallet,
    staleTime: 60_000,
  });
  const [topup, setTopup] = useState<{
    clientSecret: string;
    publishableKey: string;
  } | null>(null);
  const [topupBusy, setTopupBusy] = useState<number | null>(null);
  const startTopup = async (amountCents: number): Promise<void> => {
    setTopupBusy(amountCents);
    try {
      setTopup(await startAdCreditsTopup(amountCents));
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Couldn't start checkout."
      );
    } finally {
      setTopupBusy(null);
    }
  };
  const [error, setError] = useState<string | null>(null);

  // ── Auto-recharge — a saved card tops the wallet up when it runs low ──
  const arQuery = useQuery({
    queryKey: ["ad-autorecharge"],
    queryFn: fetchAutoRecharge,
    staleTime: 60_000,
  });
  const [arSetup, setArSetup] = useState<{
    clientSecret: string;
    publishableKey: string;
  } | null>(null);
  const [arForm, setArForm] = useState<boolean>(false);
  const [arThreshold, setArThreshold] = useState<number>(500);
  const [arAmount, setArAmount] = useState<number>(2500);
  const [arBusy, setArBusy] = useState<boolean>(false);
  const arCheckedRef = useRef<boolean>(false);

  // One quiet check per visit: if auto-recharge is on and the balance sits
  // under the threshold, the backend charges the saved card off-session.
  useEffect(() => {
    if (arCheckedRef.current) return;
    arCheckedRef.current = true;
    void runAutoRechargeCheck().then((charged) => {
      if (charged) {
        void queryClient.invalidateQueries({ queryKey: ["ad-wallet"] });
        void queryClient.invalidateQueries({ queryKey: ["ad-autorecharge"] });
        toast.success("Auto-recharge topped up your ads wallet.");
      }
    });
  }, [queryClient]);

  const arEnable = async (): Promise<void> => {
    setArBusy(true);
    try {
      if (arQuery.data?.hasCard) {
        await enableAutoRecharge({
          thresholdCents: arThreshold,
          amountCents: arAmount,
        });
        void queryClient.invalidateQueries({ queryKey: ["ad-autorecharge"] });
        setArForm(false);
        toast.success("Auto-recharge is on.");
      } else {
        setArSetup(await startAutoRechargeSetup());
      }
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Couldn't set up auto-recharge."
      );
    } finally {
      setArBusy(false);
    }
  };

  const profileQuery = useQuery({
    queryKey: ["business-profile", user?.id ?? "anon"],
    enabled: !!user,
    queryFn: async (): Promise<BusinessProfile | null> => {
      const { data, error: queryError } = await supabase
        .from("business_profiles")
        .select("*")
        .order("created_at", { ascending: true })
        .limit(1);
      if (queryError) throw queryError;
      return ((data ?? [])[0] as BusinessProfile | undefined) ?? null;
    },
  });

  const campaignsQuery = useQuery({
    queryKey: ["business-campaigns", user?.id ?? "anon"],
    enabled: !!user,
    retry: false,
    queryFn: async (): Promise<BusinessCampaign[]> => {
      const { data, error: queryError } = await supabase
        .from("business_campaigns")
        .select("*")
        .order("created_at", { ascending: false });
      if (queryError) throw queryError;
      return (data ?? []) as BusinessCampaign[];
    },
  });

  const adSetsQuery = useQuery({
    queryKey: ["business-ad-sets", user?.id ?? "anon"],
    enabled: !!user,
    retry: false,
    queryFn: async (): Promise<BusinessAdSet[]> => {
      const { data, error: queryError } = await supabase
        .from("business_ad_sets")
        .select("*")
        .order("created_at", { ascending: false });
      if (queryError) throw queryError;
      return (data ?? []) as BusinessAdSet[];
    },
  });

  const adsQuery = useQuery({
    queryKey: ["business-ads", user?.id ?? "anon"],
    enabled: !!user,
    queryFn: async (): Promise<BusinessAd[]> => {
      const { data, error: queryError } = await supabase
        .from("business_ads")
        .select("*")
        .order("created_at", { ascending: false });
      if (queryError) throw queryError;
      return (data ?? []) as BusinessAd[];
    },
  });

  const statsQuery = useQuery({
    queryKey: ["business-ad-stats", user?.id ?? "anon"],
    enabled: !!user,
    queryFn: async (): Promise<AdDailyStat[]> => {
      const { data, error: queryError } = await supabase.rpc(
        "business_ad_daily_stats"
      );
      if (queryError) throw queryError;
      return (data ?? []) as AdDailyStat[];
    },
  });

  const v4Missing =
    !!campaignsQuery.error && isMissingBusinessSchema(campaignsQuery.error);
  const profile = profileQuery.data ?? null;
  const campaigns = useMemo(
    () => campaignsQuery.data ?? [],
    [campaignsQuery.data]
  );
  const adSets = useMemo(() => adSetsQuery.data ?? [], [adSetsQuery.data]);
  const ads = useMemo(() => adsQuery.data ?? [], [adsQuery.data]);

  const totalsByAd = useMemo(() => {
    const map = new Map<string, Totals>();
    for (const row of statsQuery.data ?? []) {
      const current = map.get(row.ad_id) ?? { impressions: 0, clicks: 0 };
      current.impressions += Number(row.impressions) || 0;
      current.clicks += Number(row.clicks) || 0;
      map.set(row.ad_id, current);
    }
    return map;
  }, [statsQuery.data]);

  const sumTotals = (list: BusinessAd[]): Totals =>
    list.reduce<Totals>(
      (acc, ad) => {
        const t = totalsByAd.get(ad.id);
        acc.impressions += t?.impressions ?? 0;
        acc.clicks += t?.clicks ?? 0;
        return acc;
      },
      { impressions: 0, clicks: 0 }
    );

  const visibleAdSets = useMemo(
    () =>
      selCampaign ? adSets.filter((s) => s.campaign_id === selCampaign) : adSets,
    [adSets, selCampaign]
  );
  const visibleAds = useMemo(() => {
    if (selAdSet) return ads.filter((a) => a.ad_set_id === selAdSet);
    if (selCampaign) return ads.filter((a) => a.campaign_id === selCampaign);
    return ads;
  }, [ads, selAdSet, selCampaign]);

  const scopeTotals = useMemo(() => {
    const list =
      level === "campaigns" ? ads : level === "adsets" ? visibleAdSetsAds() : visibleAds;
    function visibleAdSetsAds(): BusinessAd[] {
      const ids = new Set(visibleAdSets.map((s) => s.id));
      return ads.filter((a) => (a.ad_set_id ? ids.has(a.ad_set_id) : false));
    }
    return sumTotals(list);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [level, ads, visibleAds, visibleAdSets, totalsByAd]);

  const invalidate = (): void => {
    for (const key of [
      "business-campaigns",
      "business-ad-sets",
      "business-ads",
      "business-ad-stats",
    ]) {
      void queryClient.invalidateQueries({ queryKey: [key, user?.id ?? "anon"] });
    }
  };

  // ── Mutations ──────────────────────────────────────────────────────

  const wizardSave = useMutation({
    mutationFn: async (w: WizardState): Promise<void> => {
      if (!user) throw new Error("Sign in first.");
      const band =
        FOLLOWER_BANDS.find((b) => b.id === w.followerBand) ??
        FOLLOWER_BANDS[0];
      const budgetDollars = parseFloat(w.lifetimeBudget);
      let campaignId = w.campaignId;
      if (!campaignId) {
        const { data, error: insertError } = await supabase
          .from("business_campaigns")
          .insert({
            user_id: user.id,
            name: w.campaignName.trim(),
            objective: w.objective,
            status: "active",
            ...(Number.isFinite(budgetDollars) && budgetDollars > 0
              ? { lifetime_budget_cents: Math.round(budgetDollars * 100) }
              : {}),
          })
          .select("id")
          .single();
        if (insertError) throw insertError;
        campaignId = (data as { id: string }).id;
      }
      let adSetId = w.adSetId;
      if (!adSetId) {
        const placements =
          w.placements.length > 0 ? w.placements : ["feed"];
        const { data, error: insertError } = await supabase
          .from("business_ad_sets")
          .insert({
            user_id: user.id,
            campaign_id: campaignId,
            name: w.setName.trim() || `${w.campaignName.trim() || "Ad set"} — ad set`,
            status: "active",
            target_roles: w.targetRoles.length > 0 ? w.targetRoles : null,
            placement: placements.includes("feed") ? "feed" : "feed",
            placements,
            follower_min: band.min,
            follower_max: band.max,
            daily_impression_cap: Math.max(
              0,
              Math.round(parseFloat(w.dailyCap) || 0)
            ),
            ...(w.startAt
              ? { start_at: new Date(`${w.startAt}T00:00:00`).toISOString() }
              : {}),
            end_at: w.endAt
              ? new Date(`${w.endAt}T23:59:59`).toISOString()
              : null,
          })
          .select("id")
          .single();
        if (insertError) throw insertError;
        adSetId = (data as { id: string }).id;
      }
      const set = adSets.find((s) => s.id === adSetId);
      const { error: adError } = await supabase.from("business_ads").insert({
        user_id: user.id,
        profile_id: profile?.id ?? null,
        campaign_id: campaignId,
        ad_set_id: adSetId,
        name: w.adName.trim() || w.headline.trim(),
        headline: w.headline.trim(),
        body: w.body.trim() || null,
        image_url: w.imageUrl.trim() || null,
        video_url: w.videoUrl.trim() || null,
        media_type: w.mediaType,
        cta_label: w.ctaLabel.trim() || "Learn more",
        cta_url: w.ctaUrl.trim() || null,
        placement: set?.placement ?? "feed",
        status: "draft",
      });
      if (adError) throw adError;
    },
    onSuccess: () => {
      setWizard(null);
      setError(null);
      invalidate();
    },
    onError: (e: unknown) =>
      setError((e as { message?: string }).message ?? "Couldn't save. Try again."),
  });

  const campaignStatus = useMutation({
    mutationFn: async (input: { id: string; status: HierarchyStatus }) => {
      const { error: updateError } = await supabase
        .from("business_campaigns")
        .update({ status: input.status, updated_at: new Date().toISOString() })
        .eq("id", input.id);
      if (updateError) throw updateError;
    },
    onSuccess: invalidate,
  });

  const adSetStatus = useMutation({
    mutationFn: async (input: { id: string; status: HierarchyStatus }) => {
      const { error: updateError } = await supabase
        .from("business_ad_sets")
        .update({ status: input.status, updated_at: new Date().toISOString() })
        .eq("id", input.id);
      if (updateError) throw updateError;
    },
    onSuccess: invalidate,
  });

  const adStatus = useMutation({
    mutationFn: async (input: { id: string; status: string }) => {
      const { error: updateError } = await supabase
        .from("business_ads")
        .update({ status: input.status, updated_at: new Date().toISOString() })
        .eq("id", input.id);
      if (updateError) throw updateError;
    },
    onSuccess: invalidate,
  });

  const deleteRow = useMutation({
    mutationFn: async (input: { table: string; id: string }) => {
      const { error: deleteError } = await supabase
        .from(input.table)
        .delete()
        .eq("id", input.id);
      if (deleteError) throw deleteError;
    },
    onSuccess: () => {
      setSelAdSet(null);
      invalidate();
    },
  });

  const duplicateAd = useMutation({
    mutationFn: async (ad: BusinessAd) => {
      if (!user) throw new Error("Sign in first.");
      const { error: insertError } = await supabase.from("business_ads").insert({
        user_id: user.id,
        profile_id: ad.profile_id,
        campaign_id: ad.campaign_id ?? null,
        ad_set_id: ad.ad_set_id ?? null,
        name: `${ad.name} copy`,
        headline: ad.headline,
        body: ad.body,
        image_url: ad.image_url,
        video_url: ad.video_url ?? null,
        media_type: ad.media_type ?? "image",
        cta_label: ad.cta_label,
        cta_url: ad.cta_url,
        placement: ad.placement,
        status: "draft",
      });
      if (insertError) throw insertError;
    },
    onSuccess: invalidate,
  });

  const saveAdCreative = useMutation({
    mutationFn: async () => {
      if (!editAd || !adDraft) return;
      const { error: updateError } = await supabase
        .from("business_ads")
        .update({
          name: adDraft.name.trim() || adDraft.headline.trim(),
          headline: adDraft.headline.trim(),
          body: adDraft.body.trim() || null,
          image_url: adDraft.imageUrl.trim() || null,
          video_url: adDraft.videoUrl.trim() || null,
          media_type: adDraft.mediaType,
          cta_label: adDraft.ctaLabel.trim() || "Learn more",
          cta_url: adDraft.ctaUrl.trim() || null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", editAd.id);
      if (updateError) throw updateError;
    },
    onSuccess: () => {
      setEditAd(null);
      setAdDraft(null);
      invalidate();
    },
    onError: (e: unknown) =>
      setError((e as { message?: string }).message ?? "Couldn't save the ad."),
  });

  // ── UI helpers ─────────────────────────────────────────────────────

  const inputClass =
    "w-full rounded-xl border border-border/60 bg-background px-3 py-2.5 text-[13.5px] outline-none focus:border-[#5A5FE8]/60";

  const pill = (active: boolean): string =>
    `shrink-0 rounded-full px-3 py-1.5 text-[11.5px] font-bold transition-colors ${
      active ? "bg-[#5A5FE8] text-white" : "bg-muted/70 text-muted-foreground"
    }`;

  const statBox = (
    icon: React.ReactNode,
    label: string,
    value: string
  ): React.ReactNode => (
    <div className="rounded-xl bg-muted/50 px-2.5 py-2">
      <div className="flex items-center gap-1 text-muted-foreground">
        {icon}
        <p className="text-[9.5px] font-bold uppercase tracking-wide">{label}</p>
      </div>
      <p className="text-[14.5px] font-extrabold tabular-nums">{value}</p>
    </div>
  );

  const rowStats = (t: Totals): React.ReactNode => {
    const ctr = t.impressions > 0 ? (t.clicks / t.impressions) * 100 : 0;
    return (
      <div className="mt-2.5 grid grid-cols-3 gap-2">
        {statBox(<Eye className="h-3 w-3" />, "Views", businessNumber.format(t.impressions))}
        {statBox(
          <MousePointerClick className="h-3 w-3" />,
          "Clicks",
          businessNumber.format(t.clicks)
        )}
        {statBox(
          <Megaphone className="h-3 w-3" />,
          "CTR",
          t.impressions > 0 ? `${ctr.toFixed(1)}%` : "—"
        )}
      </div>
    );
  };

  const toggleButton = (
    isLive: boolean,
    onToggle: (next: HierarchyStatus) => void,
    draft?: boolean
  ): React.ReactNode =>
    isLive ? (
      <button
        onClick={() => onToggle("paused")}
        className="flex h-8 items-center gap-1 rounded-full bg-amber-500/12 px-3 text-[11.5px] font-bold text-amber-500 transition-transform active:scale-95"
      >
        <Pause className="h-3.5 w-3.5" /> Pause
      </button>
    ) : (
      <button
        onClick={() => onToggle("active")}
        className="flex h-8 items-center gap-1 rounded-full bg-emerald-500/12 px-3 text-[11.5px] font-bold text-emerald-500 transition-transform active:scale-95"
      >
        <Play className="h-3.5 w-3.5" /> {draft ? "Launch" : "Resume"}
      </button>
    );

  const previewAd: ActiveAd | null = useMemo(() => {
    const source = wizard ?? (adDraft ? { ...adDraft } : null);
    if (!source) return null;
    const w = source as {
      headline: string;
      body: string;
      imageUrl: string;
      videoUrl?: string;
      mediaType?: "image" | "video";
      ctaLabel: string;
      ctaUrl: string;
    };
    return {
      id: "preview",
      headline: w.headline.trim() || "Your headline here",
      body: w.body.trim() || null,
      image_url: w.imageUrl.trim() || null,
      video_url: (w.videoUrl ?? "").trim() || null,
      media_type: w.mediaType ?? "image",
      cta_label: w.ctaLabel.trim() || "Learn more",
      cta_url: w.ctaUrl.trim() || null,
      business_name: profile?.name ?? "Your business",
      business_logo_url: profile?.logo_url ?? null,
      business_website: profile?.website ?? null,
    };
  }, [wizard, adDraft, profile]);

  const selCampaignRow = campaigns.find((c) => c.id === selCampaign) ?? null;
  const selAdSetRow = adSets.find((s) => s.id === selAdSet) ?? null;

  // ── Render ─────────────────────────────────────────────────────────

  return (
    <div className="space-y-3.5">
      {/* Business identity gate */}
      {!profileQuery.isLoading && !profile && (
        <div className="glass rounded-[22px] border border-[#5A5FE8]/40 p-4">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-2xl bg-[#5A5FE8]/15">
              <Building2 className="h-5 w-5 text-[#5A5FE8]" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-[13.5px] font-extrabold">Create your business profile first</p>
              <p className="text-[11.5px] text-muted-foreground">
                Your company name and logo front every ad.
              </p>
            </div>
            <button
              onClick={() => onNavigate("profile")}
              className="shrink-0 rounded-full bg-[#5A5FE8] px-3.5 py-2 text-[12px] font-bold text-white transition-transform active:scale-95"
            >
              Set up
            </button>
          </div>
        </div>
      )}

      {/* v4 migration gate */}
      {v4Missing && (
        <div className="glass rounded-[22px] border border-amber-500/40 p-4">
          <p className="text-[13.5px] font-extrabold">One-time upgrade needed</p>
          <p className="mt-1 text-[11.5px] leading-relaxed text-muted-foreground">
            Run <span className="font-mono font-bold">supabase/business-suite-v4.sql</span>{" "}
            then <span className="font-mono font-bold">business-suite-v5.sql</span> in
            the Supabase SQL editor to unlock the Campaign → Ad set → Ad structure
            plus uploads, placements, budgets &amp; auto-recharge.
          </p>
        </div>
      )}

      {/* Ads wallet — the money side: prepaid credits, CPM billing, WPP. */}
      <div className="rounded-[22px] border border-border/60 bg-card p-4">
        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <Wallet className="h-4 w-4" style={{ color: ACCENT }} />
            <p className="text-[13.5px] font-extrabold">Ads wallet</p>
          </div>
          <span
            className="rounded-full px-2.5 py-1 text-[10px] font-black uppercase tracking-wide"
            style={{ color: ACCENT, backgroundColor: `${ACCENT}1a` }}
          >
            $5.00 per 1k views
          </span>
        </div>
        {walletQuery.data ? (
          <>
            <div className="mt-2.5 grid grid-cols-3 gap-2">
              <div className="rounded-xl bg-muted/50 px-2.5 py-2">
                <p className="text-[9.5px] font-bold uppercase tracking-wide text-muted-foreground">
                  Balance
                </p>
                <p
                  className={`text-[15px] font-extrabold tabular-nums ${
                    walletQuery.data.balanceCents <= 0 ? "text-red-500" : ""
                  }`}
                >
                  {usd(walletQuery.data.balanceCents)}
                </p>
              </div>
              <div className="rounded-xl bg-muted/50 px-2.5 py-2">
                <p className="text-[9.5px] font-bold uppercase tracking-wide text-muted-foreground">
                  Spend · month
                </p>
                <p className="text-[15px] font-extrabold tabular-nums">
                  {usd(walletQuery.data.monthSpendCents)}
                </p>
              </div>
              <div className="rounded-xl bg-muted/50 px-2.5 py-2">
                <p className="text-[9.5px] font-bold uppercase tracking-wide text-muted-foreground">
                  Views · month
                </p>
                <p className="text-[15px] font-extrabold tabular-nums">
                  {businessNumber.format(walletQuery.data.monthImpressions)}
                </p>
              </div>
            </div>
            {walletQuery.data.balanceCents <= 0 && (
              <p className="mt-2 rounded-xl border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-[11.5px] font-semibold">
                Ads are paused — add funds to resume delivery.
              </p>
            )}
            <div className="mt-3 flex flex-wrap items-center gap-2">
              {[2500, 10000, 25000].map((cents) => (
                <button
                  key={cents}
                  onClick={() => void startTopup(cents)}
                  disabled={topupBusy !== null}
                  className="h-9 rounded-full px-4 text-[12.5px] font-bold text-white transition-transform active:scale-[0.97] disabled:opacity-50"
                  style={{ backgroundColor: ACCENT }}
                >
                  {topupBusy === cents ? "Starting…" : `Add ${usd(cents)}`}
                </button>
              ))}
            </div>
            {/* Auto-recharge — optional; the saved card is charged off-session. */}
            <div className="mt-3 rounded-xl border border-border/60 bg-background/60 p-3">
              <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-1.5">
                  <Zap className="h-3.5 w-3.5" style={{ color: ACCENT }} />
                  <p className="text-[12px] font-extrabold">Auto-recharge</p>
                </div>
                <span
                  className={`rounded-full px-2 py-0.5 text-[9.5px] font-black uppercase tracking-wide ${
                    arQuery.data?.enabled
                      ? "bg-emerald-500/15 text-emerald-500"
                      : "bg-muted/70 text-muted-foreground"
                  }`}
                >
                  {arQuery.data?.enabled ? "On" : "Off"}
                </span>
              </div>
              {arQuery.data?.enabled ? (
                <>
                  <p className="mt-1.5 text-[11px] leading-snug text-muted-foreground">
                    Adds {usd(arQuery.data.amountCents)} whenever the balance
                    drops under {usd(arQuery.data.thresholdCents)}
                    {arQuery.data.cardLast4
                      ? ` · ${arQuery.data.cardBrand ?? "card"} ····${arQuery.data.cardLast4}`
                      : ""}
                    . Checked every time your suite opens.
                  </p>
                  <button
                    onClick={() => {
                      void disableAutoRecharge().then(() => {
                        void queryClient.invalidateQueries({
                          queryKey: ["ad-autorecharge"],
                        });
                        toast.success("Auto-recharge turned off.");
                      });
                    }}
                    className="mt-2 h-8 rounded-full bg-muted/70 px-3.5 text-[11.5px] font-bold text-muted-foreground transition-colors hover:text-foreground"
                  >
                    Turn off
                  </button>
                </>
              ) : arForm ? (
                <div className="mt-2 space-y-2">
                  <div>
                    <p className="mb-1 text-[10px] font-bold text-muted-foreground">
                      When balance drops under…
                    </p>
                    <div className="flex gap-1.5">
                      {[500, 1000, 2500].map((c) => (
                        <button
                          key={c}
                          onClick={() => setArThreshold(c)}
                          className={pill(arThreshold === c)}
                        >
                          {usd(c)}
                        </button>
                      ))}
                    </div>
                  </div>
                  <div>
                    <p className="mb-1 text-[10px] font-bold text-muted-foreground">
                      …automatically add
                    </p>
                    <div className="flex gap-1.5">
                      {[2500, 10000, 25000].map((c) => (
                        <button
                          key={c}
                          onClick={() => setArAmount(c)}
                          className={pill(arAmount === c)}
                        >
                          {usd(c)}
                        </button>
                      ))}
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => void arEnable()}
                      disabled={arBusy}
                      className="h-9 rounded-full px-4 text-[12px] font-extrabold text-white transition-transform active:scale-95 disabled:opacity-50"
                      style={{ backgroundColor: ACCENT }}
                    >
                      {arBusy
                        ? "Starting…"
                        : arQuery.data?.hasCard
                          ? "Turn on"
                          : "Save a card & turn on"}
                    </button>
                    <button
                      onClick={() => setArForm(false)}
                      className="h-9 rounded-full bg-muted/70 px-3.5 text-[12px] font-bold text-muted-foreground"
                    >
                      Cancel
                    </button>
                  </div>
                </div>
              ) : (
                <>
                  <p className="mt-1.5 text-[11px] leading-snug text-muted-foreground">
                    Optional: save a card once and delivery never pauses — the
                    wallet refills itself when it runs low.
                  </p>
                  <button
                    onClick={() => setArForm(true)}
                    className="mt-2 h-8 rounded-full px-3.5 text-[11.5px] font-bold text-white transition-transform active:scale-95"
                    style={{ backgroundColor: ACCENT }}
                  >
                    Set up
                  </button>
                </>
              )}
            </div>
            <p className="mt-2 text-[10.5px] leading-snug text-muted-foreground">
              Includes a {usd(walletQuery.data.launchCreditCents)} launch
              credit · payment stays in-app · 50% of every ad dollar funds the
              WPP creator pool.
            </p>
          </>
        ) : (
          <p className="mt-2 text-[11.5px] leading-relaxed text-muted-foreground">
            Run{" "}
            <span className="font-mono font-bold">
              supabase/business-suite-v4.sql
            </span>{" "}
            to activate the wallet — a $10 launch credit is included.
          </p>
        )}
      </div>

      {topup && (
        <EmbeddedCheckoutSheet
          clientSecret={topup.clientSecret}
          publishableKey={topup.publishableKey}
          onClose={() => setTopup(null)}
          onComplete={() => {
            setTopup(null);
            void queryClient.invalidateQueries({ queryKey: ["ad-wallet"] });
            toast.success("Credits added — delivery resumes instantly.");
          }}
        />
      )}

      {arSetup && (
        <EmbeddedCheckoutSheet
          clientSecret={arSetup.clientSecret}
          publishableKey={arSetup.publishableKey}
          onClose={() => setArSetup(null)}
          onComplete={() => {
            setArSetup(null);
            void enableAutoRecharge({
              thresholdCents: arThreshold,
              amountCents: arAmount,
            })
              .then(() => {
                void queryClient.invalidateQueries({
                  queryKey: ["ad-autorecharge"],
                });
                setArForm(false);
                toast.success("Card saved — auto-recharge is on.");
              })
              .catch(() =>
                toast.error(
                  "Card saved, but enabling failed — tap Set up again."
                )
              );
          }}
        />
      )}

      {/* Delivery summary for the current scope */}
      <div className="rounded-[22px] border border-border/60 bg-card p-4">
        <div className="flex items-center justify-between gap-2">
          <p className="text-[11px] font-black uppercase tracking-[0.16em] text-muted-foreground">
            {level === "campaigns"
              ? "Account delivery"
              : level === "adsets"
                ? selCampaignRow
                  ? `${selCampaignRow.name} — delivery`
                  : "Ad sets delivery"
                : selAdSetRow
                  ? `${selAdSetRow.name} — delivery`
                  : "Ads delivery"}
          </p>
          <span
            className="flex items-center gap-1 rounded-full px-2.5 py-1 text-[10px] font-black uppercase tracking-wide"
            style={{ color: ACCENT, backgroundColor: `${ACCENT}1a` }}
          >
            <Sparkles className="h-3 w-3" /> Funds creator pay (WPP)
          </span>
        </div>
        {rowStats(scopeTotals)}
        <p className="mt-2 text-[10.5px] leading-snug text-muted-foreground">
          Every impression bills your wallet at your campaign's CPM — and 50%
          of all ad spend becomes the monthly WPP creator pool.
        </p>
      </div>

      {/* Breadcrumb + level tabs — Meta's hierarchy strip */}
      <div className="glass rounded-[22px] border border-border/60 p-2">
        <div className="flex items-center gap-1 px-2 pt-1 text-[11.5px] font-bold text-muted-foreground">
          <button
            onClick={() => {
              setLevel("campaigns");
              setSelCampaign(null);
              setSelAdSet(null);
            }}
            className={selCampaign ? "hover:text-foreground" : "text-foreground"}
          >
            All campaigns
          </button>
          {selCampaignRow && (
            <>
              <ChevronRight className="h-3 w-3" />
              <button
                onClick={() => {
                  setLevel("adsets");
                  setSelAdSet(null);
                }}
                className={selAdSet ? "hover:text-foreground" : "text-foreground"}
              >
                {selCampaignRow.name}
              </button>
            </>
          )}
          {selAdSetRow && (
            <>
              <ChevronRight className="h-3 w-3" />
              <span className="text-foreground">{selAdSetRow.name}</span>
            </>
          )}
        </div>
        <div className="mt-1.5 grid grid-cols-3 gap-1.5">
          {(
            [
              { id: "campaigns", label: "Campaigns", icon: Folder },
              { id: "adsets", label: "Ad sets", icon: Layers },
              { id: "ads", label: "Ads", icon: Megaphone },
            ] as { id: Level; label: string; icon: typeof Folder }[]
          ).map((tabDef) => (
            <button
              key={tabDef.id}
              onClick={() => setLevel(tabDef.id)}
              className={`flex items-center justify-center gap-1.5 rounded-2xl py-2.5 text-[12px] font-extrabold transition-colors ${
                level === tabDef.id
                  ? "text-white"
                  : "bg-muted/50 text-muted-foreground hover:text-foreground"
              }`}
              style={level === tabDef.id ? { backgroundColor: ACCENT } : undefined}
            >
              <tabDef.icon className="h-3.5 w-3.5" />
              {tabDef.label}
            </button>
          ))}
        </div>
      </div>

      {/* Create button, scoped to the level */}
      {!v4Missing && (
        <button
          onClick={() => {
            setError(null);
            if (level === "adsets" && selCampaignRow) {
              setWizard({
                ...emptyWizard,
                step: 2,
                campaignId: selCampaignRow.id,
                campaignName: selCampaignRow.name,
                objective: selCampaignRow.objective,
              });
            } else if (level === "ads" && selAdSetRow) {
              setWizard({
                ...emptyWizard,
                step: 3,
                campaignId: selAdSetRow.campaign_id,
                adSetId: selAdSetRow.id,
                setName: selAdSetRow.name,
                placement: selAdSetRow.placement,
              });
            } else {
              setWizard({ ...emptyWizard });
            }
          }}
          className="flex w-full items-center justify-center gap-1.5 rounded-full py-3 text-[13.5px] font-extrabold text-white transition-transform active:scale-[0.98]"
          style={{ backgroundColor: ACCENT }}
        >
          <Plus className="h-4 w-4" />
          {level === "adsets" && selCampaignRow
            ? "New ad set"
            : level === "ads" && selAdSetRow
              ? "New ad"
              : "Create campaign"}
        </button>
      )}

      {/* ── CAMPAIGNS level ─────────────────────────────────────────── */}
      {level === "campaigns" &&
        !v4Missing &&
        campaigns.map((c) => {
          const sets = adSets.filter((s) => s.campaign_id === c.id);
          const cAds = ads.filter((a) => a.campaign_id === c.id);
          const style = STATUS_CHIP[c.status];
          const objective = CAMPAIGN_OBJECTIVES.find((o) => o.id === c.objective);
          return (
            <div key={c.id} className="glass rounded-[22px] border border-border/60 p-3.5">
              <button
                onClick={() => {
                  setSelCampaign(c.id);
                  setSelAdSet(null);
                  setLevel("adsets");
                }}
                className="flex w-full items-start justify-between gap-2 text-left"
              >
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="truncate text-[14px] font-extrabold">{c.name}</p>
                    <span className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] font-bold ${style.chip}`}>
                      {style.label}
                    </span>
                  </div>
                  <p className="mt-0.5 truncate text-[11px] font-semibold text-muted-foreground">
                    Objective: {objective?.label ?? c.objective} · {sets.length}{" "}
                    ad set{sets.length === 1 ? "" : "s"} · {cAds.length} ad
                    {cAds.length === 1 ? "" : "s"}
                  </p>
                </div>
                <ChevronRight className="mt-1 h-4 w-4 shrink-0 text-muted-foreground" />
              </button>
              {rowStats(sumTotals(cAds))}
              <div className="mt-2.5 flex items-center gap-1.5">
                {toggleButton(c.status === "active", (next) =>
                  campaignStatus.mutate({ id: c.id, status: next })
                )}
                <div className="flex-1" />
                <button
                  onClick={() => {
                    if (window.confirm(`Delete campaign "${c.name}"? Its ad sets and ads go with it.`)) {
                      deleteRow.mutate({ table: "business_campaigns", id: c.id });
                    }
                  }}
                  aria-label="Delete campaign"
                  className="flex h-8 w-8 items-center justify-center rounded-full bg-muted/70 text-muted-foreground transition-colors hover:text-red-500"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              </div>
            </div>
          );
        })}

      {level === "campaigns" && !v4Missing && !campaignsQuery.isLoading && campaigns.length === 0 && (
        <div className="glass rounded-[22px] border border-border/60 p-6 text-center">
          <Folder className="mx-auto h-8 w-8 text-muted-foreground/50" />
          <p className="mt-2 text-[13.5px] font-bold">No campaigns yet</p>
          <p className="mx-auto mt-1 max-w-[300px] text-[11.5px] leading-relaxed text-muted-foreground">
            Campaigns hold your objective. Inside each one, ad sets pick the
            audience and schedule, and ads carry the creative — exactly how
            Meta structures it.
          </p>
        </div>
      )}

      {/* ── AD SETS level ───────────────────────────────────────────── */}
      {level === "adsets" &&
        !v4Missing &&
        visibleAdSets.map((s) => {
          const sAds = ads.filter((a) => a.ad_set_id === s.id);
          const style = STATUS_CHIP[s.status];
          const campaign = campaigns.find((c) => c.id === s.campaign_id);
          return (
            <div key={s.id} className="glass rounded-[22px] border border-border/60 p-3.5">
              <button
                onClick={() => {
                  setSelCampaign(s.campaign_id);
                  setSelAdSet(s.id);
                  setLevel("ads");
                }}
                className="flex w-full items-start justify-between gap-2 text-left"
              >
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="truncate text-[14px] font-extrabold">{s.name}</p>
                    <span className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] font-bold ${style.chip}`}>
                      {style.label}
                    </span>
                  </div>
                  <p className="mt-0.5 truncate text-[11px] font-semibold text-muted-foreground">
                    {campaign ? `${campaign.name} · ` : ""}
                    {(s.target_roles?.length ?? 0) > 0
                      ? `Audience: ${(s.target_roles ?? []).join(" · ")}`
                      : "Audience: everyone"}
                    {s.daily_impression_cap > 0 ? ` · ${s.daily_impression_cap}/day` : ""}
                    {" · "}
                    {(s.placements?.length ?? 0) > 0
                      ? (s.placements ?? [])
                          .map((p) => PLACEMENT_LABEL[p] ?? p)
                          .join(" + ")
                      : (PLACEMENTS.find((p) => p.id === s.placement)?.label ??
                        s.placement)}
                  </p>
                </div>
                <ChevronRight className="mt-1 h-4 w-4 shrink-0 text-muted-foreground" />
              </button>
              {rowStats(sumTotals(sAds))}
              <div className="mt-2.5 flex items-center gap-1.5">
                {toggleButton(s.status === "active", (next) =>
                  adSetStatus.mutate({ id: s.id, status: next })
                )}
                <div className="flex-1" />
                <button
                  onClick={() => {
                    if (window.confirm(`Delete ad set "${s.name}"? Its ads go with it.`)) {
                      deleteRow.mutate({ table: "business_ad_sets", id: s.id });
                    }
                  }}
                  aria-label="Delete ad set"
                  className="flex h-8 w-8 items-center justify-center rounded-full bg-muted/70 text-muted-foreground transition-colors hover:text-red-500"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              </div>
            </div>
          );
        })}

      {level === "adsets" && !v4Missing && visibleAdSets.length === 0 && !adSetsQuery.isLoading && (
        <div className="glass rounded-[22px] border border-border/60 p-6 text-center">
          <Layers className="mx-auto h-8 w-8 text-muted-foreground/50" />
          <p className="mt-2 text-[13.5px] font-bold">No ad sets here yet</p>
          <p className="mx-auto mt-1 max-w-[280px] text-[11.5px] leading-relaxed text-muted-foreground">
            Ad sets choose WHO sees your ads and WHEN — audience, schedule,
            placement, and daily pacing.
          </p>
        </div>
      )}

      {/* ── ADS level ───────────────────────────────────────────────── */}
      {level === "ads" &&
        visibleAds.map((ad) => {
          const totals = totalsByAd.get(ad.id) ?? { impressions: 0, clicks: 0 };
          const style = STATUS_CHIP[ad.status];
          const set = adSets.find((s) => s.id === ad.ad_set_id);
          return (
            <div key={ad.id} className="glass rounded-[22px] border border-border/60 p-3.5">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="truncate text-[14px] font-extrabold">{ad.name}</p>
                    <span className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] font-bold ${style.chip}`}>
                      {style.label}
                    </span>
                  </div>
                  <p className="mt-0.5 truncate text-[12px] text-muted-foreground">{ad.headline}</p>
                  {set && (
                    <p className="mt-0.5 truncate text-[10.5px] font-semibold text-muted-foreground/80">
                      In: {set.name}
                    </p>
                  )}
                </div>
                <span className="shrink-0 rounded-full bg-muted/70 px-2 py-1 text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
                  {(set?.placements?.length ?? 0) > 0
                    ? (set?.placements ?? [])
                        .map((p) => PLACEMENT_LABEL[p] ?? p)
                        .join(" + ")
                    : (PLACEMENTS.find(
                        (p) => p.id === (set?.placement ?? ad.placement)
                      )?.label ?? ad.placement)}
                </span>
              </div>
              {rowStats(totals)}
              <div className="mt-2.5 flex items-center gap-1.5">
                {toggleButton(
                  ad.status === "active",
                  (next) => adStatus.mutate({ id: ad.id, status: next }),
                  ad.status === "draft"
                )}
                <div className="flex-1" />
                <button
                  onClick={() => {
                    setError(null);
                    setEditAd(ad);
                    setAdDraft({
                      name: ad.name,
                      headline: ad.headline,
                      body: ad.body ?? "",
                      imageUrl: ad.image_url ?? "",
                      videoUrl: ad.video_url ?? "",
                      mediaType:
                        (ad.media_type as "image" | "video" | undefined) ??
                        "image",
                      ctaLabel: ad.cta_label,
                      ctaUrl: ad.cta_url ?? "",
                    });
                  }}
                  aria-label="Edit ad"
                  className="flex h-8 w-8 items-center justify-center rounded-full bg-muted/70 text-muted-foreground transition-colors hover:text-foreground"
                >
                  <Pencil className="h-3.5 w-3.5" />
                </button>
                <button
                  onClick={() => duplicateAd.mutate(ad)}
                  aria-label="Duplicate ad"
                  className="flex h-8 w-8 items-center justify-center rounded-full bg-muted/70 text-muted-foreground transition-colors hover:text-foreground"
                >
                  <Copy className="h-3.5 w-3.5" />
                </button>
                <button
                  onClick={() => {
                    if (window.confirm(`Delete "${ad.name}"? Its stats go with it.`)) {
                      deleteRow.mutate({ table: "business_ads", id: ad.id });
                    }
                  }}
                  aria-label="Delete ad"
                  className="flex h-8 w-8 items-center justify-center rounded-full bg-muted/70 text-muted-foreground transition-colors hover:text-red-500"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              </div>
            </div>
          );
        })}

      {level === "ads" && visibleAds.length === 0 && !adsQuery.isLoading && (
        <div className="glass rounded-[22px] border border-border/60 p-6 text-center">
          <Megaphone className="mx-auto h-8 w-8 text-muted-foreground/50" />
          <p className="mt-2 text-[13.5px] font-bold">No ads here yet</p>
          <p className="mx-auto mt-1 max-w-[280px] text-[11.5px] leading-relaxed text-muted-foreground">
            Ads are the creative people actually see — headline, media, and a
            button. Create one and launch it into the feed.
          </p>
        </div>
      )}

      {/* ── Create wizard (objective → audience → creative) ─────────── */}
      {wizard && (
        <div
          className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 p-4 backdrop-blur-sm sm:items-center"
          onClick={() => setWizard(null)}
        >
          <div
            className="glass max-h-[88vh] w-full max-w-md overflow-y-auto rounded-[22px] border border-border/60 bg-background/95 p-4 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between">
              <div>
                <p className="text-[15px] font-extrabold">
                  {wizard.step === 1
                    ? "Campaign — pick your objective"
                    : wizard.step === 2
                      ? "Ad set — audience & schedule"
                      : "Ad — the creative"}
                </p>
                <p className="text-[10.5px] font-bold text-muted-foreground">
                  Step {wizard.step === 1 ? 1 : wizard.step === 2 ? (wizard.campaignId ? 1 : 2) : wizard.adSetId ? 1 : wizard.campaignId ? 2 : 3}{" "}
                  of {wizard.adSetId ? 1 : wizard.campaignId ? 2 : 3} · Campaign → Ad set → Ad
                </p>
              </div>
              <button
                onClick={() => setWizard(null)}
                aria-label="Close"
                className="flex h-8 w-8 items-center justify-center rounded-full bg-muted/70"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <div className="mt-3 space-y-2.5">
              {wizard.step === 1 && (
                <>
                  <input
                    value={wizard.campaignName}
                    onChange={(e) => setWizard({ ...wizard, campaignName: e.target.value })}
                    placeholder="Campaign name (e.g. Spring launch)"
                    className={inputClass}
                  />
                  <div className="space-y-1.5">
                    {CAMPAIGN_OBJECTIVES.map((o) => (
                      <button
                        key={o.id}
                        onClick={() => setWizard({ ...wizard, objective: o.id })}
                        className={`flex w-full items-center justify-between rounded-xl border px-3 py-2.5 text-left transition-colors ${
                          wizard.objective === o.id
                            ? "border-[#5A5FE8] bg-[#5A5FE8]/10"
                            : "border-border/60 bg-background"
                        }`}
                      >
                        <span>
                          <span className="block text-[13px] font-extrabold">{o.label}</span>
                          <span className="block text-[11px] text-muted-foreground">{o.hint}</span>
                        </span>
                        {wizard.objective === o.id && (
                          <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: ACCENT }} />
                        )}
                      </button>
                    ))}
                  </div>
                  <label className="block">
                    <span className="text-[10px] font-bold text-muted-foreground">
                      Lifetime budget in USD (optional — delivery stops at the cap)
                    </span>
                    <input
                      value={wizard.lifetimeBudget}
                      onChange={(e) =>
                        setWizard({ ...wizard, lifetimeBudget: e.target.value })
                      }
                      placeholder="e.g. 250"
                      inputMode="decimal"
                      className={inputClass}
                    />
                  </label>
                  <button
                    onClick={() => {
                      if (!wizard.campaignName.trim()) {
                        setError("Name the campaign first.");
                        return;
                      }
                      setError(null);
                      setWizard({ ...wizard, step: 2 });
                    }}
                    className="w-full rounded-full py-3 text-[13.5px] font-extrabold text-white transition-transform active:scale-[0.98]"
                    style={{ backgroundColor: ACCENT }}
                  >
                    Next — audience &amp; schedule
                  </button>
                </>
              )}

              {wizard.step === 2 && (
                <>
                  <input
                    value={wizard.setName}
                    onChange={(e) => setWizard({ ...wizard, setName: e.target.value })}
                    placeholder="Ad set name (e.g. Coaches, March)"
                    className={inputClass}
                  />
                  <div>
                    <p className="mb-1.5 text-[10.5px] font-extrabold uppercase tracking-wider text-muted-foreground">
                      Audience
                    </p>
                    <div className="no-scrollbar flex gap-1.5 overflow-x-auto">
                      <button
                        onClick={() => setWizard({ ...wizard, targetRoles: [] })}
                        className={pill(wizard.targetRoles.length === 0)}
                      >
                        Everyone
                      </button>
                      {AD_TARGET_OPTIONS.map((option) => {
                        const active = wizard.targetRoles.includes(option.id);
                        return (
                          <button
                            key={option.id}
                            onClick={() =>
                              setWizard({
                                ...wizard,
                                targetRoles: active
                                  ? wizard.targetRoles.filter((r) => r !== option.id)
                                  : [...wizard.targetRoles, option.id],
                              })
                            }
                            className={pill(active)}
                          >
                            {option.label}
                          </button>
                        );
                      })}
                    </div>
                  </div>
                  <div>
                    <p className="mb-1.5 text-[10.5px] font-extrabold uppercase tracking-wider text-muted-foreground">
                      Placements — where it serves
                    </p>
                    <div className="space-y-1.5">
                      {AD_PLACEMENT_OPTIONS.map((p) => {
                        const active = wizard.placements.includes(p.id);
                        return (
                          <button
                            key={p.id}
                            onClick={() =>
                              setWizard({
                                ...wizard,
                                placements: active
                                  ? wizard.placements.filter((x) => x !== p.id)
                                  : [...wizard.placements, p.id],
                              })
                            }
                            className={`flex w-full items-center justify-between rounded-xl border px-3 py-2 text-left transition-colors ${
                              active
                                ? "border-[#5A5FE8] bg-[#5A5FE8]/10"
                                : "border-border/60 bg-background"
                            }`}
                          >
                            <span>
                              <span className="block text-[12.5px] font-extrabold">
                                {p.label}
                              </span>
                              <span className="block text-[10.5px] text-muted-foreground">
                                {p.hint}
                              </span>
                            </span>
                            <span
                              className={`flex h-5 w-5 items-center justify-center rounded-md border text-[10px] font-black text-white ${
                                active
                                  ? "border-[#5A5FE8] bg-[#5A5FE8]"
                                  : "border-border"
                              }`}
                            >
                              {active ? "✓" : ""}
                            </span>
                          </button>
                        );
                      })}
                    </div>
                  </div>
                  <div>
                    <p className="mb-1.5 text-[10.5px] font-extrabold uppercase tracking-wider text-muted-foreground">
                      Audience size
                    </p>
                    <div className="no-scrollbar flex gap-1.5 overflow-x-auto">
                      {FOLLOWER_BANDS.map((b) => (
                        <button
                          key={b.id}
                          onClick={() =>
                            setWizard({ ...wizard, followerBand: b.id })
                          }
                          className={pill(wizard.followerBand === b.id)}
                        >
                          {b.label}
                        </button>
                      ))}
                    </div>
                  </div>
                  <div>
                    <p className="mb-1.5 text-[10.5px] font-extrabold uppercase tracking-wider text-muted-foreground">
                      Schedule &amp; pacing
                    </p>
                    <div className="flex gap-2.5">
                      <label className="w-full">
                        <span className="text-[10px] font-bold text-muted-foreground">Starts</span>
                        <input
                          type="date"
                          value={wizard.startAt}
                          onChange={(e) => setWizard({ ...wizard, startAt: e.target.value })}
                          className={inputClass}
                        />
                      </label>
                      <label className="w-full">
                        <span className="text-[10px] font-bold text-muted-foreground">Ends (optional)</span>
                        <input
                          type="date"
                          value={wizard.endAt}
                          onChange={(e) => setWizard({ ...wizard, endAt: e.target.value })}
                          className={inputClass}
                        />
                      </label>
                    </div>
                    <input
                      value={wizard.dailyCap}
                      onChange={(e) => setWizard({ ...wizard, dailyCap: e.target.value })}
                      placeholder="Daily view cap across this ad set (0 = unlimited)"
                      inputMode="numeric"
                      className={`${inputClass} mt-2`}
                    />
                  </div>
                  <button
                    onClick={() => {
                      if (wizard.placements.length === 0) {
                        setError("Pick at least one placement.");
                        return;
                      }
                      setError(null);
                      setWizard({ ...wizard, step: 3 });
                    }}
                    className="w-full rounded-full py-3 text-[13.5px] font-extrabold text-white transition-transform active:scale-[0.98]"
                    style={{ backgroundColor: ACCENT }}
                  >
                    Next — the creative
                  </button>
                </>
              )}

              {wizard.step === 3 && (
                <>
                  <input
                    value={wizard.adName}
                    onChange={(e) => setWizard({ ...wizard, adName: e.target.value })}
                    placeholder="Ad name (private, for your dashboard)"
                    className={inputClass}
                  />
                  <input
                    value={wizard.headline}
                    onChange={(e) => setWizard({ ...wizard, headline: e.target.value })}
                    placeholder="Headline users see"
                    className={inputClass}
                  />
                  <textarea
                    value={wizard.body}
                    onChange={(e) => setWizard({ ...wizard, body: e.target.value })}
                    placeholder="Body text (optional)"
                    rows={2}
                    className={`${inputClass} resize-none`}
                  />
                  <div className="rounded-xl border border-dashed border-border/70 p-3">
                    <div className="flex items-center justify-between gap-2">
                      <p className="text-[10.5px] font-extrabold uppercase tracking-wider text-muted-foreground">
                        Creative — photo or video
                      </p>
                      <label
                        className={`flex cursor-pointer items-center gap-1.5 rounded-full px-3 py-1.5 text-[11.5px] font-bold text-white ${
                          uploading ? "opacity-60" : ""
                        }`}
                        style={{ backgroundColor: ACCENT }}
                      >
                        <Upload className="h-3.5 w-3.5" />
                        {uploading ? "Uploading…" : "Upload"}
                        <input
                          type="file"
                          accept="image/*,video/*"
                          className="hidden"
                          disabled={uploading}
                          onChange={(e) => {
                            const file = e.target.files?.[0];
                            e.target.value = "";
                            if (!file) return;
                            void pickMedia(file, (m) =>
                              setWizard((w) =>
                                w
                                  ? {
                                      ...w,
                                      mediaType: m.type,
                                      imageUrl:
                                        m.type === "image" ? m.url : w.imageUrl,
                                      videoUrl:
                                        m.type === "video" ? m.url : "",
                                    }
                                  : w
                              )
                            );
                          }}
                        />
                      </label>
                    </div>
                    {wizard.mediaType === "video" && wizard.videoUrl ? (
                      <video
                        src={wizard.videoUrl}
                        muted
                        loop
                        playsInline
                        autoPlay
                        className="mt-2 aspect-video w-full rounded-lg bg-black object-cover"
                      />
                    ) : wizard.imageUrl ? (
                      <img
                        src={wizard.imageUrl}
                        alt="Creative"
                        className="mt-2 aspect-video w-full rounded-lg object-cover"
                      />
                    ) : null}
                    <input
                      value={wizard.imageUrl}
                      onChange={(e) =>
                        setWizard({
                          ...wizard,
                          imageUrl: e.target.value,
                          mediaType: "image",
                          videoUrl: "",
                        })
                      }
                      placeholder="…or paste an image URL"
                      className={`${inputClass} mt-2`}
                    />
                  </div>
                  <div className="flex gap-2.5">
                    <input
                      value={wizard.ctaLabel}
                      onChange={(e) => setWizard({ ...wizard, ctaLabel: e.target.value })}
                      placeholder="Button label"
                      className={inputClass}
                    />
                    <input
                      value={wizard.ctaUrl}
                      onChange={(e) => setWizard({ ...wizard, ctaUrl: e.target.value })}
                      placeholder="Button link (acme.com)"
                      className={inputClass}
                    />
                  </div>
                  {previewAd && (
                    <div>
                      <p className="mb-1.5 text-[10.5px] font-extrabold uppercase tracking-wider text-muted-foreground">
                        Live preview
                      </p>
                      <SponsoredAdCard ad={previewAd} preview />
                    </div>
                  )}
                  <button
                    onClick={() => {
                      if (!wizard.headline.trim()) {
                        setError("Write the headline users will see.");
                        return;
                      }
                      setError(null);
                      wizardSave.mutate(wizard);
                    }}
                    disabled={wizardSave.isPending}
                    className="w-full rounded-full py-3 text-[13.5px] font-extrabold text-white transition-transform active:scale-[0.98] disabled:opacity-60"
                    style={{ backgroundColor: ACCENT }}
                  >
                    {wizardSave.isPending ? "Saving…" : "Save — ad starts as a draft"}
                  </button>
                  <p className="text-center text-[10.5px] text-muted-foreground">
                    New ads save as drafts — hit Launch on the ad when you're ready.
                  </p>
                </>
              )}

              {error && <p className="text-[11.5px] font-semibold text-red-500">{error}</p>}
            </div>
          </div>
        </div>
      )}

      {/* ── Ad creative editor ──────────────────────────────────────── */}
      {editAd && adDraft && (
        <div
          className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 p-4 backdrop-blur-sm sm:items-center"
          onClick={() => {
            setEditAd(null);
            setAdDraft(null);
          }}
        >
          <div
            className="glass max-h-[88vh] w-full max-w-md overflow-y-auto rounded-[22px] border border-border/60 bg-background/95 p-4 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between">
              <p className="text-[15px] font-extrabold">Edit ad</p>
              <button
                onClick={() => {
                  setEditAd(null);
                  setAdDraft(null);
                }}
                aria-label="Close"
                className="flex h-8 w-8 items-center justify-center rounded-full bg-muted/70"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
            <div className="mt-3 space-y-2.5">
              <input
                value={adDraft.name}
                onChange={(e) => setAdDraft({ ...adDraft, name: e.target.value })}
                placeholder="Ad name"
                className={inputClass}
              />
              <input
                value={adDraft.headline}
                onChange={(e) => setAdDraft({ ...adDraft, headline: e.target.value })}
                placeholder="Headline users see"
                className={inputClass}
              />
              <textarea
                value={adDraft.body}
                onChange={(e) => setAdDraft({ ...adDraft, body: e.target.value })}
                placeholder="Body text (optional)"
                rows={2}
                className={`${inputClass} resize-none`}
              />
              <div className="rounded-xl border border-dashed border-border/70 p-3">
                <div className="flex items-center justify-between gap-2">
                  <p className="text-[10.5px] font-extrabold uppercase tracking-wider text-muted-foreground">
                    Creative — photo or video
                  </p>
                  <label
                    className={`flex cursor-pointer items-center gap-1.5 rounded-full px-3 py-1.5 text-[11.5px] font-bold text-white ${
                      uploading ? "opacity-60" : ""
                    }`}
                    style={{ backgroundColor: ACCENT }}
                  >
                    <Upload className="h-3.5 w-3.5" />
                    {uploading ? "Uploading…" : "Upload"}
                    <input
                      type="file"
                      accept="image/*,video/*"
                      className="hidden"
                      disabled={uploading}
                      onChange={(e) => {
                        const file = e.target.files?.[0];
                        e.target.value = "";
                        if (!file) return;
                        void pickMedia(file, (m) =>
                          setAdDraft((d) =>
                            d
                              ? {
                                  ...d,
                                  mediaType: m.type,
                                  imageUrl:
                                    m.type === "image" ? m.url : d.imageUrl,
                                  videoUrl: m.type === "video" ? m.url : "",
                                }
                              : d
                          )
                        );
                      }}
                    />
                  </label>
                </div>
                {adDraft.mediaType === "video" && adDraft.videoUrl ? (
                  <video
                    src={adDraft.videoUrl}
                    muted
                    loop
                    playsInline
                    autoPlay
                    className="mt-2 aspect-video w-full rounded-lg bg-black object-cover"
                  />
                ) : adDraft.imageUrl ? (
                  <img
                    src={adDraft.imageUrl}
                    alt="Creative"
                    className="mt-2 aspect-video w-full rounded-lg object-cover"
                  />
                ) : null}
                <input
                  value={adDraft.imageUrl}
                  onChange={(e) =>
                    setAdDraft({
                      ...adDraft,
                      imageUrl: e.target.value,
                      mediaType: "image",
                      videoUrl: "",
                    })
                  }
                  placeholder="…or paste an image URL"
                  className={`${inputClass} mt-2`}
                />
              </div>
              <div className="flex gap-2.5">
                <input
                  value={adDraft.ctaLabel}
                  onChange={(e) => setAdDraft({ ...adDraft, ctaLabel: e.target.value })}
                  placeholder="Button label"
                  className={inputClass}
                />
                <input
                  value={adDraft.ctaUrl}
                  onChange={(e) => setAdDraft({ ...adDraft, ctaUrl: e.target.value })}
                  placeholder="Button link"
                  className={inputClass}
                />
              </div>
              {previewAd && <SponsoredAdCard ad={previewAd} preview />}
              {error && <p className="text-[11.5px] font-semibold text-red-500">{error}</p>}
              <button
                onClick={() => saveAdCreative.mutate()}
                disabled={saveAdCreative.isPending}
                className="w-full rounded-full py-3 text-[13.5px] font-extrabold text-white transition-transform active:scale-[0.98] disabled:opacity-60"
                style={{ backgroundColor: ACCENT }}
              >
                {saveAdCreative.isPending ? "Saving…" : "Save changes"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
