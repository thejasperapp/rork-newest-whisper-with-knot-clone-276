/**
 * Whisper Business — shared types, queries, and ad-serving helpers.
 *
 * Tables + RPCs live in supabase/business-suite.sql (v2):
 *   business_profiles — the company identity behind ads
 *   business_ads      — creative + placement + budget + status
 *   business_ad_events — impressions/clicks (inserted via RPC only)
 *   business_active_ads(p_placement, p_limit)  — serving rotation
 *   business_track_ad(p_ad, p_kind)            — impression/click tracking
 *   business_ad_daily_stats()                  — owner analytics (30d)
 */
import { supabase } from "@/lib/supabase";
import { backendFetch } from "@/lib/billing";

export type AdPlacement = "feed" | "discover" | "both";
export type AdStatus = "draft" | "active" | "paused" | "ended";

/** v5 — where ads can actually serve. Ad sets store an ARRAY of these. */
export type ServePlacement = "feed" | "reels" | "comments" | "discover";

export const AD_PLACEMENT_OPTIONS: {
  id: ServePlacement;
  label: string;
  hint: string;
}[] = [
  { id: "feed", label: "Feed", hint: "A sponsored card every 6 posts" },
  { id: "reels", label: "Reels", hint: "A full-screen slide between reels" },
  { id: "comments", label: "Comments", hint: "One quiet card inside threads" },
];

/** v5 — follower-size bands for detailed targeting. */
export const FOLLOWER_BANDS: {
  id: string;
  label: string;
  min: number;
  max: number | null;
}[] = [
  { id: "any", label: "Any audience size", min: 0, max: null },
  { id: "under1k", label: "Under 1k followers", min: 0, max: 999 },
  { id: "1kto10k", label: "1k – 10k followers", min: 1000, max: 10000 },
  { id: "over10k", label: "10k+ followers", min: 10000, max: null },
];

// ── v4: the Meta Ads Manager hierarchy ────────────────────────────────
// Campaign (WHY — objective) → Ad set (WHO/WHEN — audience, schedule,
// placement, pacing) → Ad (WHAT — creative). Tables in
// supabase/business-suite-v4.sql; serving respects the full funnel.

export type CampaignObjective =
  | "awareness"
  | "traffic"
  | "engagement"
  | "leads"
  | "sales";
export type HierarchyStatus = "active" | "paused" | "ended";

export interface BusinessCampaign {
  id: string;
  user_id: string;
  name: string;
  objective: CampaignObjective;
  status: HierarchyStatus;
  /** v5 — optional lifetime spend cap in cents (delivery stops at the cap). */
  lifetime_budget_cents?: number | null;
  cpm_cents?: number;
  created_at: string;
  updated_at: string;
}

export interface BusinessAdSet {
  id: string;
  user_id: string;
  campaign_id: string;
  name: string;
  status: HierarchyStatus;
  target_roles: string[] | null;
  placement: AdPlacement;
  /** v5 — the real placement list: feed / reels / comments. */
  placements?: string[] | null;
  /** v5 — follower-band targeting (0 / null = everyone). */
  follower_min?: number;
  follower_max?: number | null;
  start_at: string;
  end_at: string | null;
  daily_impression_cap: number;
  created_at: string;
  updated_at: string;
}

/** Meta's campaign objectives, in Whisper terms. */
export const CAMPAIGN_OBJECTIVES: {
  id: CampaignObjective;
  label: string;
  hint: string;
}[] = [
  { id: "awareness", label: "Awareness", hint: "Reach as many people as possible" },
  { id: "traffic", label: "Traffic", hint: "Send people to your website" },
  { id: "engagement", label: "Engagement", hint: "Get taps, follows & replies" },
  { id: "leads", label: "Leads", hint: "Collect interest & sign-ups" },
  { id: "sales", label: "Sales", hint: "Drive purchases" },
];

export interface BusinessProfile {
  id: string;
  user_id: string;
  name: string;
  category: string | null;
  website: string | null;
  email: string | null;
  phone: string | null;
  logo_url: string | null;
  about: string | null;
  created_at: string;
  updated_at: string;
}

export interface BusinessAd {
  id: string;
  user_id: string;
  profile_id: string | null;
  name: string;
  headline: string;
  body: string | null;
  image_url: string | null;
  cta_label: string;
  cta_url: string | null;
  placement: AdPlacement;
  status: AdStatus;
  daily_budget_cents: number;
  total_budget_cents: number;
  start_at: string;
  end_at: string | null;
  /** v3 — audience role targeting (null/empty = everyone). */
  target_roles?: string[] | null;
  /** v3 — max impressions per day (0 = unlimited). */
  daily_impression_cap?: number;
  /** v4 — hierarchy links (null on pre-v4 rows until the migration runs). */
  campaign_id?: string | null;
  ad_set_id?: string | null;
  /** v5 — uploaded creative: photo or video. */
  media_type?: "image" | "video";
  video_url?: string | null;
  created_at: string;
  updated_at: string;
}

/** Audience options an ad can target — resolved server-side at serve time. */
export const AD_TARGET_OPTIONS: { id: string; label: string }[] = [
  { id: "athletes", label: "Athletes" },
  { id: "coaches", label: "Coaches" },
  { id: "creators", label: "Creators" },
  { id: "recruiters", label: "Recruiters" },
  { id: "brands", label: "Brands" },
];

/** Row shape returned by business_active_ads() for serving. */
export interface ActiveAd {
  id: string;
  headline: string;
  body: string | null;
  image_url: string | null;
  /** v5 — present when the creative is an uploaded video. */
  video_url?: string | null;
  media_type?: string | null;
  cta_label: string;
  cta_url: string | null;
  business_name: string;
  business_logo_url: string | null;
  business_website: string | null;
}

export interface AdDailyStat {
  ad_id: string;
  day: string;
  impressions: number;
  clicks: number;
}

export const businessUsd = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  maximumFractionDigits: 0,
});

export const businessNumber = new Intl.NumberFormat("en-US", {
  notation: "compact",
  maximumFractionDigits: 1,
});

/** True when the error means the v2 business tables/RPCs haven't been migrated yet. */
export function isMissingBusinessSchema(error: unknown): boolean {
  const err = error as { code?: string; message?: string } | null;
  if (!err) return false;
  if (err.code === "42P01" || err.code === "PGRST202") return true;
  const message = err.message ?? "";
  return (
    (message.includes("business_") && message.includes("does not exist")) ||
    message.includes("Could not find the function")
  );
}

/** Active rotation for a placement — [] on any error so surfaces stay calm. */
export async function fetchActiveAds(
  placement: AdPlacement | ServePlacement,
  limit = 6
): Promise<ActiveAd[]> {
  try {
    const { data, error } = await supabase.rpc("business_active_ads", {
      p_placement: placement,
      p_limit: limit,
    });
    if (error) return [];
    return (data ?? []) as ActiveAd[];
  } catch {
    return [];
  }
}

// ── v5: real media uploads (ad-media storage bucket) ────────────────────

export interface UploadedAdMedia {
  url: string;
  type: "image" | "video";
}

const AD_MEDIA_MAX_BYTES = 80 * 1024 * 1024; // 80 MB — short videos included

/**
 * Upload an ad photo or video to the public ad-media bucket
 * (supabase/business-suite-v5.sql creates it). Returns the public URL.
 */
export async function uploadAdMedia(
  userId: string,
  file: File
): Promise<UploadedAdMedia> {
  if (file.size > AD_MEDIA_MAX_BYTES) {
    throw new Error("Keep uploads under 80 MB.");
  }
  const isVideo = file.type.startsWith("video/");
  const isImage = file.type.startsWith("image/");
  if (!isVideo && !isImage) {
    throw new Error("Upload a photo or a video file.");
  }
  const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, "_").slice(-60);
  const path = `${userId}/${Date.now()}-${safeName}`;
  const { error } = await supabase.storage
    .from("ad-media")
    .upload(path, file, { contentType: file.type, upsert: false });
  if (error) {
    const msg = error.message ?? "";
    if (/bucket.*not.*found/i.test(msg)) {
      throw new Error(
        "Run supabase/business-suite-v5.sql first — it creates the ad-media storage bucket."
      );
    }
    throw new Error(msg || "Upload failed. Try again.");
  }
  const { data } = supabase.storage.from("ad-media").getPublicUrl(path);
  return { url: data.publicUrl, type: isVideo ? "video" : "image" };
}

// ── v5: the public Ad Library (like Meta's transparency library) ────────

export interface AdLibraryEntry {
  id: string;
  headline: string;
  body: string | null;
  image_url: string | null;
  video_url: string | null;
  media_type: string;
  cta_label: string;
  cta_url: string | null;
  business_name: string;
  business_logo_url: string | null;
  objective: string;
  placements: string[];
  started_at: string;
}

/** Every ad live right now — public, searchable by advertiser/headline. */
export async function fetchAdsLibrary(
  query: string,
  limit = 40
): Promise<AdLibraryEntry[]> {
  const { data, error } = await supabase.rpc("business_ads_library", {
    p_query: query.trim() || null,
    p_limit: limit,
  });
  if (error) throw error;
  return (data ?? []) as AdLibraryEntry[];
}

/** Session-level dedupe so a re-rendering feed doesn't spam impressions. */
const trackedImpressions = new Set<string>();

export function trackAdImpression(adId: string): void {
  if (!adId || trackedImpressions.has(adId)) return;
  trackedImpressions.add(adId);
  void supabase
    .rpc("business_track_ad", { p_ad: adId, p_kind: "impression" })
    .then(({ error }) => { if (error) trackedImpressions.delete(adId); }, () => { trackedImpressions.delete(adId); });
}

export function trackAdClick(adId: string): void {
  if (!adId) return;
  void supabase
    .rpc("business_track_ad", { p_ad: adId, p_kind: "click" })
    .then(undefined, () => undefined);
}

// ── Ads wallet — prepaid delivery credits (impressions bill at CPM) ───

export interface AdWallet {
  balanceCents: number;
  launchCreditCents: number;
  topupCents: number;
  spendCents: number;
  monthSpendCents: number;
  monthImpressions: number;
}

/** The signed-in business's wallet — null when the v4.1 migration is pending. */
export async function fetchAdWallet(): Promise<AdWallet | null> {
  try {
    const { data, error } = await supabase.rpc("business_wallet_summary");
    if (error) return null;
    const row = (Array.isArray(data) ? data[0] : data) as Record<
      string,
      unknown
    > | null;
    if (!row) return null;
    return {
      balanceCents: Number(row.balance_cents ?? 0),
      launchCreditCents: Number(row.launch_credit_cents ?? 0),
      topupCents: Number(row.topup_cents ?? 0),
      spendCents: Number(row.spend_cents ?? 0),
      monthSpendCents: Number(row.month_spend_cents ?? 0),
      monthImpressions: Number(row.month_impressions ?? 0),
    };
  } catch {
    return null;
  }
}

/**
 * Start an in-app ad-credits top-up — returns the embedded Stripe checkout
 * secrets so payment renders inside the suite (no redirect).
 */
export async function startAdCreditsTopup(
  amountCents: number
): Promise<{ clientSecret: string; publishableKey: string }> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error("Please sign in first.");
  const res = await backendFetch("/business/ads/topup", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ amountCents, origin: window.location.origin }),
  });
  const payload = (await res.json().catch(() => ({}))) as {
    clientSecret?: string;
    publishableKey?: string;
    stripeMessage?: string;
  };
  if (!res.ok || !payload.clientSecret || !payload.publishableKey) {
    throw new Error(payload.stripeMessage || "Couldn't start checkout.");
  }
  return {
    clientSecret: payload.clientSecret,
    publishableKey: payload.publishableKey,
  };
}

// ── v5: auto-recharge — saved card tops the wallet up when it runs low ──

export interface AutoRechargeSettings {
  enabled: boolean;
  thresholdCents: number;
  amountCents: number;
  cardBrand: string | null;
  cardLast4: string | null;
  hasCard: boolean;
  lastChargedAt: string | null;
}

async function authedBackend(
  path: string,
  init?: { method?: string; body?: unknown }
): Promise<Record<string, unknown>> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error("Please sign in first.");
  const res = await backendFetch(path, {
    method: init?.method ?? "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    ...(init?.body !== undefined ? { body: JSON.stringify(init.body) } : {}),
  });
  const payload = (await res.json().catch(() => ({}))) as Record<
    string,
    unknown
  >;
  if (!res.ok) {
    throw new Error(
      String(payload.stripeMessage ?? payload.error ?? "Request failed.")
    );
  }
  return payload;
}

/** Current auto-recharge settings — null when never configured. */
export async function fetchAutoRecharge(): Promise<AutoRechargeSettings | null> {
  try {
    const payload = await authedBackend("/business/wallet/autorecharge");
    if (!payload.settings) return null;
    const s = payload.settings as Record<string, unknown>;
    return {
      enabled: !!s.enabled,
      thresholdCents: Number(s.thresholdCents ?? 500),
      amountCents: Number(s.amountCents ?? 2500),
      cardBrand: (s.cardBrand as string | null) ?? null,
      cardLast4: (s.cardLast4 as string | null) ?? null,
      hasCard: !!s.hasCard,
      lastChargedAt: (s.lastChargedAt as string | null) ?? null,
    };
  } catch {
    return null;
  }
}

/** Start the save-a-card flow — embedded Stripe checkout in setup mode. */
export async function startAutoRechargeSetup(): Promise<{
  clientSecret: string;
  publishableKey: string;
}> {
  const payload = await authedBackend("/business/wallet/autorecharge/start", {
    method: "POST",
    body: { origin: window.location.origin },
  });
  if (!payload.clientSecret || !payload.publishableKey) {
    throw new Error("Couldn't start the card setup.");
  }
  return {
    clientSecret: String(payload.clientSecret),
    publishableKey: String(payload.publishableKey),
  };
}

/** Enable auto-recharge (after the setup sheet completes, or re-enable). */
export async function enableAutoRecharge(input: {
  thresholdCents: number;
  amountCents: number;
}): Promise<AutoRechargeSettings | null> {
  await authedBackend("/business/wallet/autorecharge/enable", {
    method: "POST",
    body: input,
  });
  return fetchAutoRecharge();
}

export async function disableAutoRecharge(): Promise<void> {
  await authedBackend("/business/wallet/autorecharge/disable", {
    method: "POST",
    body: {},
  });
}

/**
 * Ask the backend to run the auto-recharge check now — charges the saved
 * card off-session when the balance sits under the threshold (6h cooldown).
 * Returns true when a charge landed.
 */
export async function runAutoRechargeCheck(): Promise<boolean> {
  try {
    const payload = await authedBackend(
      "/business/wallet/autorecharge/check",
      { method: "POST", body: {} }
    );
    return !!payload.charged;
  } catch {
    return false;
  }
}

/** Prefix-safe external URL (users paste "acme.com" as often as full links). */
export function externalUrl(raw: string | null | undefined): string | null {
  const trimmed = (raw ?? "").trim();
  if (!trimmed) return null;
  try {
    const url = new URL(trimmed.includes(":") ? trimmed : `https://${trimmed}`);
    return ["http:", "https:"].includes(url.protocol) && url.hostname && !url.username && !url.password ? url.href : null;
  } catch {
    return null;
  }
}
