/**
 * WPP — Whisper Paid Partners client.
 *
 * The YouTube/TikTok revenue-share model: every month, 50% of REAL ad
 * spend (impressions × CPM) becomes the creator pool. A creator's month
 * = min(their qualified views × tier RPM, their view-share of the pool)
 * — payouts can never exceed collected ad revenue; tier RPMs (Partner
 * 1k+ ≈ $0.90 · Partner+ 10k+ ≈ $1.40 · Elite 100k+ ≈ $2.20 per 1,000
 * views) act as caps. Months finalize on the 1st; only closed months
 * cash out (min $10) through the same Stripe rail as coaches.
 *
 * Qualified views are reported by the feed through the wpp_track_views
 * RPC (deduped server-side per viewer/post/day, self-views ignored);
 * money endpoints ride the version-aware backend resolver.
 */
import { supabase } from "@/lib/supabase";
import { backendFetch } from "@/lib/billing";

export interface WppCashoutRow {
  amount_cents: number;
  created_at: string;
}

export interface WppSummary {
  eligible: boolean;
  tierId: string | null;
  tierLabel: string | null;
  rpmCents: number;
  followers: number;
  monthViews: number;
  allTimeViews: number;
  accruedCents: number;
  /** The live month's running estimate (finalizes on the 1st). */
  monthEstimatedCents: number;
  /** This month's creator pool so far — 50% of real ad spend. */
  poolMonthCents: number;
  /** This month's total ad revenue so far. */
  monthRevenueCents: number;
  cashedOutCents: number;
  availableCents: number;
  connected: boolean;
  payoutsReady: boolean;
  nextTierLabel: string | null;
  nextTierFollowers: number | null;
  cashouts: WppCashoutRow[];
}

async function authedFetch(
  path: string,
  init: { method?: string; body?: unknown } = {}
): Promise<Record<string, unknown>> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error("Please sign in first.");
  const res = await backendFetch(path, {
    method: init.method ?? "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      ...(init.body !== undefined ? { "Content-Type": "application/json" } : {}),
    },
    body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
  });
  const payload = (await res.json().catch(() => ({}))) as Record<
    string,
    unknown
  >;
  if (!res.ok) {
    const code = typeof payload.error === "string" ? payload.error : "";
    const messages: Record<string, string> = {
      sign_in_required: "Please sign in first.",
      not_eligible: "WPP opens at 1,000 followers — keep growing!",
      below_minimum: "You need at least $10 accrued to cash out.",
      not_connected: "Link your bank account first.",
      payouts_not_ready:
        "Finish linking your bank first — then cash outs are one tap.",
      billing_not_configured: "Payments aren't configured yet.",
    };
    throw new Error(
      messages[code] ??
        (typeof payload.stripeMessage === "string" && payload.stripeMessage
          ? payload.stripeMessage
          : "Something went wrong. Please try again.")
    );
  }
  return payload;
}

export async function fetchWppSummary(): Promise<WppSummary> {
  const data = await authedFetch("/wpp/summary");
  return {
    eligible: data.eligible === true,
    tierId: (data.tierId as string | null) ?? null,
    tierLabel: (data.tierLabel as string | null) ?? null,
    rpmCents: typeof data.rpmCents === "number" ? data.rpmCents : 0,
    followers: typeof data.followers === "number" ? data.followers : 0,
    monthViews: typeof data.monthViews === "number" ? data.monthViews : 0,
    allTimeViews:
      typeof data.allTimeViews === "number" ? data.allTimeViews : 0,
    accruedCents:
      typeof data.accruedCents === "number" ? data.accruedCents : 0,
    monthEstimatedCents:
      typeof data.monthEstimatedCents === "number"
        ? data.monthEstimatedCents
        : 0,
    poolMonthCents:
      typeof data.poolMonthCents === "number" ? data.poolMonthCents : 0,
    monthRevenueCents:
      typeof data.monthRevenueCents === "number" ? data.monthRevenueCents : 0,
    cashedOutCents:
      typeof data.cashedOutCents === "number" ? data.cashedOutCents : 0,
    availableCents:
      typeof data.availableCents === "number" ? data.availableCents : 0,
    connected: data.connected === true,
    payoutsReady: data.payoutsReady === true,
    nextTierLabel: (data.nextTierLabel as string | null) ?? null,
    nextTierFollowers:
      typeof data.nextTierFollowers === "number"
        ? data.nextTierFollowers
        : null,
    cashouts: Array.isArray(data.cashouts)
      ? (data.cashouts as WppCashoutRow[])
      : [],
  };
}

export async function wppCashOut(): Promise<{
  amountCents: number;
  sentToBank: boolean;
}> {
  const data = await authedFetch("/wpp/cashout", { method: "POST", body: {} });
  return {
    amountCents: typeof data.amountCents === "number" ? data.amountCents : 0,
    sentToBank: data.sentToBank === true,
  };
}

// ── Qualified-view reporting (batched, session-deduped) ──────────────

const seenViews = new Set<string>();
let viewQueue: { creatorId: string; postId: string }[] = [];
let flushTimer: number | null = null;

async function flushViews(): Promise<void> {
  flushTimer = null;
  const batch = viewQueue.splice(0, 30);
  if (batch.length === 0) return;
  try {
    await supabase.rpc("wpp_track_views", {
      p_creators: batch.map((b) => b.creatorId),
      p_posts: batch.map((b) => b.postId),
    });
  } catch {
    // Table not migrated yet or offline — views just don't count.
  }
  if (viewQueue.length > 0) {
    flushTimer = window.setTimeout(() => void flushViews(), 4_000);
  }
}

/**
 * Report posts the viewer has seen in the feed. Fire-and-forget: deduped
 * per session here and per viewer/post/day server-side.
 */
export function trackWppViews(
  entries: { creatorId: string; postId: string }[]
): void {
  for (const entry of entries) {
    if (!entry.creatorId || !entry.postId) continue;
    const key = `${entry.creatorId}:${entry.postId}`;
    if (seenViews.has(key)) continue;
    seenViews.add(key);
    viewQueue.push(entry);
  }
  if (viewQueue.length > 0 && flushTimer === null) {
    flushTimer = window.setTimeout(() => void flushViews(), 4_000);
  }
}
