/**
 * Whisper billing — thin client over the project's Cloudflare functions
 * backend, which owns the Stripe integration. The web app never touches
 * Stripe keys directly; it just asks the backend for a Checkout URL and
 * verifies sessions on the success page. Checkout calls carry the caller's
 * Supabase token — the backend attributes every purchase to the signed-in
 * user (live-mode hardening), so unauthenticated checkout is impossible.
 */

import { supabase } from "@/lib/supabase";

export type WhisperOnePlan = "one-monthly" | "one-annual";

/** The two paid badges. The retired Athlete badge is a Creator niche now. */
export type BadgeRole = "coach" | "verified";
export type BadgePlan = "coach-annual" | "verified-annual";
export type BusinessPlusPlan = "business-plus-monthly" | "business-plus-annual";
export type CheckoutPlan = WhisperOnePlan | BadgePlan | BusinessPlusPlan;

/**
 * The Cloudflare functions backend that owns the Stripe integration.
 * The env var is preferred, but we fall back to the stable deployed URL so
 * production builds (custom domain) never ship without a backend wired up.
 */
export const BACKEND_URL: string =
  (import.meta.env.EXPO_PUBLIC_RORK_FUNCTIONS_URL as string | undefined) ||
  // PERMANENT project alias — always tracks the newest functions deploy.
  // Per-deploy hosts (…-g6gawm9-…, …-pvganrz-…) freeze the code AND the
  // env they shipped with forever, so never hardcode one again. Verify
  // with GET /ping → { version, stripeKeyMode }.
  "https://mdt742q5xnsko5i7owb0v-backend.rork.app";

/**
 * Payment-path failover. The permanent alias occasionally lags behind the
 * newest deploy on the platform's routing layer — and a lagging deploy can
 * carry a STALE Stripe env (test keys / broken keys) or miss newer routes
 * like /billing/receipts. Money endpoints therefore probe the candidates
 * and prefer the first one that reports LIVE Stripe keys, falling back to
 * the first reachable one. Everything is cached for the session.
 */
const BACKEND_CANDIDATES: string[] = [
  ...new Set(
    [
      (import.meta.env.EXPO_PUBLIC_RORK_FUNCTIONS_URL as string | undefined) ??
        "",
      "https://mdt742q5xnsko5i7owb0v-backend.rork.app",
      // Per-deploy hosts churn on every deploy — keep the newest first;
      // the version-aware probe below always picks the freshest LIVE one.
      // r64 carries /meetings/invite-email (formatted invites + .ics) and
      // the transcript in the notes email.
      "https://whisper-008-clone-clone-clone-1ov2f86-backend.rork.app",
      // r63 carries /link/preview (chat link unfurling).
      "https://whisper-008-clone-clone-clone-o4g0jln-backend.rork.app",
      // r61 carries Business+ at $100/mo + meeting lead capture.
      "https://whisper-008-clone-clone-clone-1hosfav-backend.rork.app",
      // r56 carries /webrtc/ice-servers (TURN credentials for meetings).
      "https://whisper-008-clone-clone-clone-oh5z6ib-backend.rork.app",
      "https://whisper-008-clone-clone-clone-bg7wah6-backend.rork.app",
      "https://whisper-008-clone-clone-clone-vru24ih-backend.rork.app",
      "https://whisper-008-clone-clone-clone-pvganrz-backend.rork.app",
    ].filter(Boolean)
  ),
];

interface BackendProbe {
  url: string;
  ok: boolean;
  live: boolean;
  /** Deploy version parsed from /ping's "rNN" stamp (0 when absent). */
  version: number;
}

async function probeBackend(url: string): Promise<BackendProbe> {
  try {
    const controller = new AbortController();
    const timer = window.setTimeout(() => controller.abort(), 4_000);
    const res = await fetch(`${url}/ping`, { signal: controller.signal });
    window.clearTimeout(timer);
    if (!res.ok) return { url, ok: false, live: false, version: 0 };
    const data = (await res.json()) as {
      stripeKeyMode?: string;
      version?: string;
    };
    const version = Number((data.version ?? "").replace(/\D/g, "")) || 0;
    return { url, ok: true, live: data.stripeKeyMode === "live", version };
  } catch {
    return { url, ok: false, live: false, version: 0 };
  }
}

let resolvedBackend: Promise<string> | null = null;

/** The best backend for MONEY calls — prefers live Stripe keys. */
export function resolveBackend(): Promise<string> {
  if (!resolvedBackend) {
    resolvedBackend = (async () => {
      const probes = await Promise.all(BACKEND_CANDIDATES.map(probeBackend));
      const newestFirst = (a: BackendProbe, b: BackendProbe): number =>
        b.version - a.version;
      // Newest LIVE deploy wins — an older live host can miss endpoints or
      // fixes (e.g. Stripe API renames) that the newest deploy carries.
      const live = probes.filter((p) => p.live).sort(newestFirst);
      if (live[0]) return live[0].url;
      const reachable = probes.filter((p) => p.ok).sort(newestFirst);
      return reachable[0]?.url ?? BACKEND_URL;
    })();
  }
  return resolvedBackend;
}

/** fetch() against the resolved payment backend. */
export async function backendFetch(
  path: string,
  init?: RequestInit
): Promise<Response> {
  const base = await resolveBackend();
  return fetch(`${base}${path}`, init);
}

export const ONE_PLANS: Record<
  WhisperOnePlan,
  { price: string; detail: string; blurb: string }
> = {
  "one-monthly": {
    price: "$14.99",
    detail: "/month",
    blurb: "Cancel anytime",
  },
  "one-annual": {
    price: "$119.99",
    detail: "/year",
    blurb: "Two months free",
  },
};

/** Business+ pricing — must match the backend PLANS table. */
export const BUSINESS_PLUS_PLANS: Record<
  BusinessPlusPlan,
  { price: string; detail: string; blurb: string }
> = {
  "business-plus-monthly": {
    price: "$100.00",
    detail: "/month",
    blurb: "Cancel anytime",
  },
  "business-plus-annual": {
    price: "$999.99",
    detail: "/year",
    blurb: "Two months free",
  },
};

export const BUSINESS_PLUS_PERKS: string[] = [
  "Team roles — give every employee their title & color",
  "Hiring: your own application questions + auto-matching to open positions",
  "Private HQ group + a team group chat in DMs",
  "Internal team calendar with one-tap meet links",
  "Present live in meetings — company, roles & team cards with 👋 hand-raise leads",
  "Workspace meeting tools & Notebook for the whole team",
];

/** Annual verified-badge pricing — must match the backend PLANS table. */
export const BADGE_PLANS: Record<
  BadgeRole,
  { plan: BadgePlan; label: string; price: string; blurb: string }
> = {
  coach: {
    plan: "coach-annual",
    label: "Verified Coach",
    price: "$249.99",
    blurb: "Billed once per year · Coach profile role · unlimited clients · paywalled coaching",
  },
  verified: {
    plan: "verified-annual",
    label: "Verified Creator",
    price: "$99.99",
    blurb: "Billed once per year · Creator profile role · your niche in profile details · algorithm boost",
  },
};

interface CheckoutResponse {
  url?: string;
  clientSecret?: string;
  publishableKey?: string;
  error?: string;
  /** Sanitized Stripe error detail forwarded by the backend. */
  stripeMessage?: string | null;
}

/** Embedded checkout result — what the EmbeddedCheckoutSheet needs. */
export interface EmbeddedCheckoutResult {
  clientSecret: string;
  publishableKey: string;
}

const CHECKOUT_ERROR_MESSAGES: Record<string, string> = {
  billing_not_configured: "Payments are almost live — Stripe isn't connected yet.",
  sign_in_required: "Please sign in or create an account before subscribing.",
  not_approved:
    "These role tools unlock after your application is approved. Apply from the app and watch for the approval email.",
};

/** The caller's Supabase access token — required for every checkout. */
async function billingToken(): Promise<string> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) {
    throw new Error("Please sign in or create an account before subscribing.");
  }
  return token;
}

/**
 * Kick off an embedded Stripe Checkout (renders inline, no redirect).
 * Returns the client secret the EmbeddedCheckoutSheet needs. Throws a
 * user-friendly Error when checkout can't start.
 */
export async function startEmbeddedCheckout(
  plan: CheckoutPlan,
  opts: { userId?: string; email?: string } = {}
): Promise<EmbeddedCheckoutResult> {
  if (!BACKEND_URL) {
    throw new Error("Payments aren't configured yet — check back soon.");
  }
  if (!opts.userId) {
    throw new Error("Please sign in or create an account before subscribing.");
  }
  const token = await billingToken();
  let data: CheckoutResponse | null = null;
  let ok = false;
  try {
    const res = await backendFetch(`/stripe/checkout`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        plan,
        origin: window.location.origin,
        userId: opts.userId ?? "",
        email: opts.email ?? "",
        mode: "embedded",
      }),
    });
    ok = res.ok;
    data = (await res.json()) as CheckoutResponse;
  } catch {
    throw new Error("Couldn't reach the payment service. Please try again.");
  }
  if (!ok || !data?.clientSecret || !data.publishableKey) {
    if (data?.error && CHECKOUT_ERROR_MESSAGES[data.error]) {
      throw new Error(CHECKOUT_ERROR_MESSAGES[data.error]);
    }
    // Surface Stripe's own explanation — "couldn't start checkout" with no
    // reason is undebuggable for the user AND for us.
    if (data?.stripeMessage) {
      throw new Error(`Stripe: ${data.stripeMessage}`);
    }
    throw new Error("Couldn't start checkout. Please try again.");
  }
  return {
    clientSecret: data.clientSecret,
    publishableKey: data.publishableKey,
  };
}

/**
 * Kick off a Stripe Checkout for a Whisper One plan. Resolves by navigating
 * the browser to Stripe; throws a user-friendly Error when checkout can't
 * start (backend unreachable or Stripe not configured yet).
 */
export async function startCheckout(
  plan: CheckoutPlan,
  opts: { userId?: string; email?: string } = {}
): Promise<void> {
  if (!BACKEND_URL) {
    throw new Error("Payments aren't configured yet — check back soon.");
  }
  if (!opts.userId) {
    throw new Error("Please sign in or create an account before subscribing.");
  }
  const token = await billingToken();
  let data: CheckoutResponse | null = null;
  let ok = false;
  try {
    const res = await backendFetch(`/stripe/checkout`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        plan,
        origin: window.location.origin,
        userId: opts.userId ?? "",
        email: opts.email ?? "",
      }),
    });
    ok = res.ok;
    data = (await res.json()) as CheckoutResponse;
  } catch {
    throw new Error("Couldn't reach the payment service. Please try again.");
  }
  if (!ok || !data?.url) {
    if (data?.error && CHECKOUT_ERROR_MESSAGES[data.error]) {
      throw new Error(CHECKOUT_ERROR_MESSAGES[data.error]);
    }
    if (data?.stripeMessage) {
      throw new Error(`Stripe: ${data.stripeMessage}`);
    }
    throw new Error("Couldn't start checkout. Please try again.");
  }
  window.location.assign(data.url);
}

export interface CheckoutSessionInfo {
  status: string;
  paymentStatus: string;
  customerEmail: string | null;
  plan: string | null;
}

/** Verify a completed Checkout Session on the success page. */
export async function fetchCheckoutSession(
  sessionId: string
): Promise<CheckoutSessionInfo> {
  if (!BACKEND_URL) throw new Error("Payments aren't configured yet.");
  const res = await backendFetch(
    `/stripe/session?id=${encodeURIComponent(sessionId)}`
  );
  if (!res.ok) throw new Error("Couldn't verify your payment session.");
  return (await res.json()) as CheckoutSessionInfo;
}

// ─── Billing mode (test vs live) ───────────────────────────────────

export interface BillingMode {
  stripeKeyMode: string;
  /** True while Stripe runs on test keys — cards are never really charged. */
  testMode: boolean;
}

/** Reads the backend's Stripe mode so checkout UIs can show a test banner. */
export async function fetchBillingMode(): Promise<BillingMode> {
  const res = await backendFetch(`/ping`);
  if (!res.ok) return { stripeKeyMode: "unknown", testMode: false };
  const data = (await res.json()) as { stripeKeyMode?: string };
  const mode = data.stripeKeyMode ?? "missing";
  return { stripeKeyMode: mode, testMode: mode !== "live" };
}

// ─── Refunds ──────────────────────────────────────────────────

export type RefundKind = "one" | "badge" | "coach-hire" | "program" | "business-plus";

export interface RefundRequestRow {
  id: string;
  kind: RefundKind;
  amountCents: number | null;
  reason: string | null;
  status: string;
  adminNote: string | null;
  createdAt: string;
  decidedAt: string | null;
}

const REFUND_ERROR_MESSAGES: Record<string, string> = {
  no_active_membership: "We couldn't find an active membership on your account.",
  subscription_not_found: "We couldn't find that subscription.",
  purchase_not_found: "We couldn't find that purchase on your account.",
  reason_required: "Please tell us briefly why you'd like a refund.",
  billing_not_configured: "Payments aren't configured yet.",
};

/** File a refund request — lands in the admin review queue. */
export async function requestRefund(opts: {
  kind: RefundKind;
  subscriptionId?: string;
  programId?: string;
  reason: string;
}): Promise<{ duplicate: boolean; eligibleAuto: boolean }> {
  const token = await billingToken();
  const res = await backendFetch(`/refunds/request`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(opts),
  });
  const data = (await res.json().catch(() => ({}))) as {
    duplicate?: boolean;
    eligibleAuto?: boolean;
    error?: string;
  };
  if (!res.ok) {
    throw new Error(
      REFUND_ERROR_MESSAGES[data.error ?? ""] ??
        "Couldn't file the refund request. Please try again."
    );
  }
  return {
    duplicate: data.duplicate === true,
    eligibleAuto: data.eligibleAuto === true,
  };
}

/** The signed-in user's refund requests, newest first. */
export async function fetchMyRefunds(): Promise<RefundRequestRow[]> {
  const token = await billingToken();
  const res = await backendFetch(`/refunds/mine`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) return [];
  const data = (await res.json()) as { requests?: RefundRequestRow[] };
  return Array.isArray(data.requests) ? data.requests : [];
}

// ─── Receipts ──────────────────────────────────────────────────

export interface ReceiptRow {
  id: string;
  receiptNo: string;
  kind: string;
  description: string;
  amountCents: number;
  status: "paid" | "refunded";
  subscriptionId: string | null;
  createdAt: string;
  refundedAt: string | null;
}

/** The signed-in user's purchase history — written by the Stripe webhook. */
export async function fetchMyReceipts(): Promise<ReceiptRow[]> {
  const token = await billingToken();
  const res = await backendFetch(`/billing/receipts`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) return [];
  const data = (await res.json()) as { receipts?: ReceiptRow[] };
  return Array.isArray(data.receipts) ? data.receipts : [];
}

// ─── "What you get" briefs shown before every checkout ─────────────

export interface CheckoutBrief {
  /** Product name shown in the header, e.g. "Whisper One · Annual". */
  title: string;
  /** "$14.99" — formatted price. */
  price: string;
  /** "/month", "/year", "one-time"… */
  cadence: string;
  /** Staggered perk rows — what the buyer actually gets. */
  perks: string[];
  /** Published refund window in days (One/badges 14 · coaching 7). */
  refundDays: number;
  /** Small line under the title, e.g. "Cancel anytime". */
  note?: string;
}

export const ONE_PERKS: string[] = [
  "Membership tools without a public membership marker",
  "3 coaching client slots to earn as you grow",
  "Creator Studio Lite — analytics on every post",
  "Share live stat cards from your linked data",
  "Priority support from the Whisper team",
];

export const BADGE_PERKS: Record<BadgeRole, string[]> = {
  coach: [
    "Coach shown as plain profile text after review",
    "Unlimited paying clients + Coach Studio",
    "Publish up to 3 coaching tiers & programs",
    "Keep 90% of every coaching payment",
    "Priority placement in Coaches to hire",
  ],
  verified: [
    "Creator role shown as plain profile text",
    "Your niche (Athlete, Fitness, Music…) under your name",
    "Featured in the brand marketplace for sponsorships",
    "Algorithm boost on everything you post",
    "Creator tools & meeting analytics sharing",
  ],
};
