import { supabase } from "@/lib/supabase";
import { backendFetch } from "@/lib/billing";

/**
 * Coach payments client — talks to the Cloudflare backend that owns the
 * Stripe Connect integration. Coaches set their own monthly rate, link a
 * bank account through Stripe's hosted onboarding, and cash out earnings.
 */

export interface ConnectStatus {
  connected: boolean;
  chargesEnabled?: boolean;
  payoutsEnabled?: boolean;
  detailsSubmitted?: boolean;
}

export interface CoachEarnings {
  connected: boolean;
  payoutsEnabled: boolean;
  chargesEnabled: boolean;
  totalEarnedCents: number;
  availableCents: number;
  pendingCents: number;
  payments: {
    gross_cents: number;
    fee_cents: number;
    net_cents: number;
    client_email: string | null;
    description: string | null;
    created_at: string;
  }[];
}

export interface CoachRate {
  monthlyPriceCents: number | null;
  active: boolean;
  acceptingPayments: boolean;
  username: string | null;
  displayName: string | null;
  /** The coach's published plan tiers (empty when they use the single rate). */
  tiers: CoachTier[];
}

/** One of a coach's plan tiers (max 3 per coach). */
export interface CoachTier {
  id: string;
  name: string;
  tagline: string | null;
  monthlyPriceCents: number;
  perks: string[];
  maxClients: number | null;
  sort: number;
}

/** Editable tier shape sent to the backend (id kept for stable updates). */
export interface CoachTierInput {
  id?: string;
  name: string;
  tagline?: string;
  priceCents: number;
  perks: string[];
  maxClients?: number | null;
  active?: boolean;
}

async function accessToken(): Promise<string> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error("Please sign in first.");
  return token;
}

async function authedFetch(
  path: string,
  init: { method?: string; body?: unknown } = {}
): Promise<Record<string, unknown>> {
  const token = await accessToken();
  // Version-aware backend resolution — money calls must never hit a stale
  // deploy host (frozen code AND frozen env: one alias shipped a corrupt
  // Stripe key that broke bank linking with "Invalid API Key: mk_…").
  const res = await backendFetch(path, {
    method: init.method ?? "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      ...(init.body !== undefined ? { "Content-Type": "application/json" } : {}),
    },
    body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
  });
  const data = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok) {
    const code = typeof data.error === "string" ? data.error : "";
    const messages: Record<string, string> = {
      sign_in_required: "Please sign in first.",
      not_a_coach: "Only approved coaches can use coach payouts.",
      not_payout_eligible:
        "Payouts unlock once you're a verified coach, athlete, or creator (or have an active sponsorship).",
      not_connected: "Link your bank account first.",
      insufficient_balance:
        "Your available balance is under $1 — nothing to cash out yet.",
      invalid_price: "Enter a monthly rate between $5 and $2,000.",
      billing_not_configured: "Payments aren't configured yet.",
      embedded_not_configured: "embedded_not_configured",
      connect_not_enabled:
        "Coach payouts aren't live yet — Stripe Connect needs to be enabled on Whisper's Stripe account. If you're the owner, activate it at dashboard.stripe.com/connect.",
    };
    throw new Error(
      messages[code] ??
        (typeof data.stripeMessage === "string" && data.stripeMessage
          ? data.stripeMessage
          : "Something went wrong. Please try again.")
    );
  }
  return data;
}

/**
 * Embedded onboarding session — lets us render bank linking inside the app
 * (Cash App / DoorDash style) instead of redirecting to a Stripe page.
 * Throws with code "embedded_not_configured" when the publishable key is
 * missing on the backend, so callers can fall back to the hosted redirect.
 */
export async function createConnectSession(): Promise<{
  clientSecret: string;
  publishableKey: string;
}> {
  const data = await authedFetch("/coach/connect/session", {
    method: "POST",
    body: {},
  });
  if (
    typeof data.clientSecret !== "string" ||
    typeof data.publishableKey !== "string"
  ) {
    throw new Error("Couldn't start bank linking.");
  }
  return {
    clientSecret: data.clientSecret,
    publishableKey: data.publishableKey,
  };
}

/** Start (or resume) Stripe onboarding — resolves by redirecting the browser. */
export async function startBankOnboarding(): Promise<void> {
  const data = await authedFetch("/coach/connect/onboard", {
    method: "POST",
    body: { origin: window.location.origin },
  });
  if (typeof data.url !== "string") throw new Error("Couldn't start onboarding.");
  window.location.assign(data.url);
}

/** Open the Stripe Express dashboard (manage bank details, see payouts). */
export async function openStripeDashboard(): Promise<void> {
  const data = await authedFetch("/coach/connect/dashboard", { method: "POST" });
  if (typeof data.url !== "string") throw new Error("Couldn't open the dashboard.");
  window.open(data.url, "_blank", "noopener");
}

export async function fetchConnectStatus(): Promise<ConnectStatus> {
  return (await authedFetch("/coach/connect/status")) as unknown as ConnectStatus;
}

// ── In-app Stripe panel — everything the Express dashboard shows ─────

export interface StripePayoutRow {
  amountCents: number;
  status: string;
  arrivalDate: string | null;
  createdAt: string | null;
}

export interface StripeTransferRow {
  amountCents: number;
  description: string;
  createdAt: string | null;
}

export interface StripeOverview {
  connected: boolean;
  chargesEnabled?: boolean;
  payoutsEnabled?: boolean;
  detailsSubmitted?: boolean;
  requirementsDue?: string[];
  disabledReason?: string | null;
  balance?: { availableCents: number; pendingCents: number };
  bank?: { bankName: string; last4: string; currency: string } | null;
  payoutSchedule?: { interval: string; delayDays: number };
  payouts?: StripePayoutRow[];
  transfers?: StripeTransferRow[];
}

/**
 * The user's full Stripe standing — status, requirements, balance, bank on
 * file, payout schedule, payouts, and incoming transfers — rendered inside
 * Whisper so nobody has to hop to the Stripe dashboard.
 */
export async function fetchStripeOverview(): Promise<StripeOverview> {
  return (await authedFetch(
    "/coach/stripe/overview"
  )) as unknown as StripeOverview;
}

export async function fetchCoachEarnings(): Promise<CoachEarnings> {
  return (await authedFetch("/coach/earnings")) as unknown as CoachEarnings;
}

export async function saveCoachRate(monthlyPriceCents: number): Promise<void> {
  await authedFetch("/coach/pricing", {
    method: "POST",
    body: { monthlyPriceCents, active: true },
  });
}

export async function cashOut(): Promise<number> {
  const data = await authedFetch("/coach/payout", { method: "POST", body: {} });
  return typeof data.amountCents === "number" ? data.amountCents : 0;
}

/** The signed-in client's payment standing with a coach. */
export interface HireStatus {
  /** True when the coach charges (active rate + payout-ready bank). */
  requiresPayment: boolean;
  priceCents: number | null;
  /** True when the client has a payment inside the current monthly cycle. */
  paid: boolean;
}

export async function fetchHireStatus(
  coachUserId: string
): Promise<HireStatus> {
  const data = await authedFetch(
    `/coach/hire-status?coachUserId=${encodeURIComponent(coachUserId)}`
  );
  return {
    requiresPayment: data.requiresPayment === true,
    priceCents:
      typeof data.priceCents === "number" ? data.priceCents : null,
    paid: data.paid === true,
  };
}

/** Public rate card for a coach (used by the hire page). */
export async function fetchCoachRate(coachUserId: string): Promise<CoachRate> {
  const res = await backendFetch(
    `/coach/pricing?userId=${encodeURIComponent(coachUserId)}`
  );
  if (!res.ok) throw new Error("Couldn't load this coach's rate.");
  const data = (await res.json()) as CoachRate & { tiers?: CoachTier[] };
  return { ...data, tiers: Array.isArray(data.tiers) ? data.tiers : [] };
}

/** A coach's active tiers (public — powers the hire page + search cards). */
export async function fetchCoachTiers(coachUserId: string): Promise<CoachTier[]> {
  const res = await backendFetch(
    `/coach/tiers?coachUserId=${encodeURIComponent(coachUserId)}`
  );
  if (!res.ok) return [];
  const data = (await res.json()) as { tiers?: CoachTier[] };
  return Array.isArray(data.tiers) ? data.tiers : [];
}

/** The signed-in coach replaces their plan tiers (max 3). */
export async function saveCoachTiers(tiers: CoachTierInput[]): Promise<void> {
  await authedFetch("/coach/tiers", { method: "POST", body: { tiers } });
}

const HIRE_ERROR_MESSAGES: Record<string, string> = {
  sign_in_required: "Please sign in before hiring a coach.",
  coach_not_priced: "This coach hasn't set their rate yet.",
  coach_not_ready: "This coach isn't accepting payments yet.",
  cannot_hire_self: "You can't hire yourself.",
  tier_not_found: "That plan is no longer available — pick another.",
  tier_not_priced: "That plan isn't priced correctly — pick another.",
};

/** A signed-in client subscribes to a coach's monthly rate. */
export async function startHireCheckout(opts: {
  coachUserId: string;
  userId: string;
  email: string;
  cancelPath: string;
  tierId?: string;
}): Promise<void> {
  const token = await accessToken();
  const res = await backendFetch(`/coach/hire-checkout`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      coachUserId: opts.coachUserId,
      tierId: opts.tierId ?? "",
      userId: opts.userId,
      email: opts.email,
      origin: window.location.origin,
      cancelPath: opts.cancelPath,
    }),
  });
  const data = (await res.json().catch(() => ({}))) as {
    url?: string;
    error?: string;
  };
  if (!res.ok || !data.url) {
    throw new Error(
      HIRE_ERROR_MESSAGES[data.error ?? ""] ??
        "Couldn't start checkout. Please try again."
    );
  }
  window.location.assign(data.url);
}

/**
 * Embedded coach hire — returns a Stripe client secret so the checkout
 * form renders inline (no redirect). Throws user-friendly errors.
 */
export async function startEmbeddedHireCheckout(opts: {
  coachUserId: string;
  userId: string;
  email: string;
  cancelPath: string;
  tierId?: string;
}): Promise<{ clientSecret: string; publishableKey: string }> {
  const token = await accessToken();
  const res = await backendFetch(`/coach/hire-checkout`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      coachUserId: opts.coachUserId,
      tierId: opts.tierId ?? "",
      userId: opts.userId,
      email: opts.email,
      origin: window.location.origin,
      cancelPath: opts.cancelPath,
      mode: "embedded",
    }),
  });
  const data = (await res.json().catch(() => ({}))) as {
    clientSecret?: string;
    publishableKey?: string;
    error?: string;
  };
  if (!res.ok || !data.clientSecret || !data.publishableKey) {
    throw new Error(
      HIRE_ERROR_MESSAGES[data.error ?? ""] ??
        "Couldn't start checkout. Please try again."
    );
  }
  return {
    clientSecret: data.clientSecret,
    publishableKey: data.publishableKey,
  };
}

// ─── One-time program purchases ────────────────────────────────────

const PROGRAM_ERROR_MESSAGES: Record<string, string> = {
  sign_in_required: "Please sign in before buying a program.",
  program_not_found: "This program no longer exists.",
  program_not_priced: "This program isn't for sale.",
  coach_not_ready: "This coach isn't accepting payments yet.",
  cannot_buy_own_program: "This is your own program.",
};

/** Whether the signed-in user can open a program (owner, free, or paid). */
export interface ProgramAccess {
  purchased: boolean;
  owner: boolean;
  priceCents: number | null;
  /** False when the program is priced but the coach can't take payments yet. */
  coachReady?: boolean;
}

export async function fetchProgramAccess(
  programId: string
): Promise<ProgramAccess> {
  const data = await authedFetch(
    `/coach/program-access?programId=${encodeURIComponent(programId)}`
  );
  return {
    purchased: data.purchased === true,
    owner: data.owner === true,
    priceCents: typeof data.priceCents === "number" ? data.priceCents : null,
    coachReady: data.coachReady !== false,
  };
}

/**
 * Embedded one-time program checkout — returns a Stripe client secret so
 * the payment form renders inline. Resolves `{ alreadyPurchased: true }`
 * when the buyer already owns it.
 */
export async function startEmbeddedProgramCheckout(opts: {
  programId: string;
  userId: string;
  email: string;
  cancelPath: string;
}): Promise<
  | { alreadyPurchased: true }
  | { alreadyPurchased?: false; clientSecret: string; publishableKey: string }
> {
  const token = await accessToken();
  const res = await backendFetch(`/coach/program-checkout`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      programId: opts.programId,
      userId: opts.userId,
      email: opts.email,
      origin: window.location.origin,
      cancelPath: opts.cancelPath,
      mode: "embedded",
    }),
  });
  const data = (await res.json().catch(() => ({}))) as {
    clientSecret?: string;
    publishableKey?: string;
    alreadyPurchased?: boolean;
    error?: string;
  };
  if (res.ok && data.alreadyPurchased) return { alreadyPurchased: true };
  if (!res.ok || !data.clientSecret || !data.publishableKey) {
    throw new Error(
      PROGRAM_ERROR_MESSAGES[data.error ?? ""] ??
        "Couldn't start checkout. Please try again."
    );
  }
  return {
    clientSecret: data.clientSecret,
    publishableKey: data.publishableKey,
  };
}

/** One of the signed-in client's active coaching subscriptions. */
export interface CoachSubscription {
  id: string;
  coachUserId: string | null;
  coachUsername: string | null;
  priceCents: number | null;
  status: string;
  cancelAtPeriodEnd: boolean;
  currentPeriodEnd: string | null;
}

/** The signed-in client's active coach subscriptions (for Settings). */
export async function fetchMyCoachSubscriptions(): Promise<CoachSubscription[]> {
  const data = await authedFetch("/coach/my-hires");
  const rows = Array.isArray(data.subscriptions)
    ? (data.subscriptions as Record<string, unknown>[])
    : [];
  return rows.map((s) => ({
    id: String(s.id ?? ""),
    coachUserId: (s.coachUserId as string | null) ?? null,
    coachUsername: (s.coachUsername as string | null) ?? null,
    priceCents: typeof s.priceCents === "number" ? s.priceCents : null,
    status: String(s.status ?? ""),
    cancelAtPeriodEnd: s.cancelAtPeriodEnd === true,
    currentPeriodEnd: (s.currentPeriodEnd as string | null) ?? null,
  }));
}

/** Stop a coaching subscription at the end of the paid month. */
export async function cancelCoachSubscription(
  subscriptionId: string
): Promise<void> {
  await authedFetch("/coach/hire-cancel", {
    method: "POST",
    body: { subscriptionId },
  });
}

export function formatCents(cents: number): string {
  return (cents / 100).toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
  });
}
