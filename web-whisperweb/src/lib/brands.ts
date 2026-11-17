import { supabase } from "@/lib/supabase";
import { backendFetch } from "@/lib/billing";

/**
 * Brand accounts + creator sponsorships client — talks to the Cloudflare
 * backend. Brands publish a profile with sponsorship requirements and
 * transparent typical pay; eligible creators apply; brands accept / counter
 * with editable terms / deny (deny = DM block); accepted deals are funded
 * into escrow and released once tracked posts land.
 */

export type SponsorBasis = "per_post" | "per_month" | "per_year";

export const BASIS_LABELS: Record<SponsorBasis, string> = {
  per_post: "Per post",
  per_month: "Per month",
  per_year: "Per year",
};

export const BASIS_SHORT: Record<SponsorBasis, string> = {
  per_post: "/post",
  per_month: "/mo",
  per_year: "/yr",
};

export interface BrandProfile {
  user_id: string;
  company_name: string;
  username: string | null;
  website: string | null;
  industry: string | null;
  about: string | null;
  logo_url: string | null;
  /** Optional cover/backdrop image shown behind the hero on the profile page. */
  cover_url: string | null;
  /** Ordered gallery of image URLs shown in the marketplace carousel. */
  media_urls: string[];
  /** Optional MP4 video URL — plays as the first slide when present. */
  video_url: string | null;
  instagram: string | null;
  ember_verified: boolean;
  ember_score: number | null;
  ember_summary: string | null;
  ember_checked_at: string | null;
  amenities: string[];
  min_followers: number;
  min_age: number;
  min_posts: number;
  pay_basis: SponsorBasis;
  typical_pay_min_cents: number | null;
  typical_pay_max_cents: number | null;
  payment_terms: string | null;
  published: boolean;
}

/**
 * Open-position counts per brand account — the marketplace's Business+
 * hiring tie-in (whisper_business_positions is public-read by design).
 */
export async function fetchHiringCounts(
  userIds: string[]
): Promise<Record<string, number>> {
  if (userIds.length === 0) return {};
  const { data, error } = await supabase
    .from("whisper_business_positions")
    .select("business_id, is_open")
    .in("business_id", userIds)
    .eq("is_open", true);
  if (error) return {};
  const counts: Record<string, number> = {};
  for (const row of (data as { business_id: string }[] | null) ?? []) {
    counts[row.business_id] = (counts[row.business_id] ?? 0) + 1;
  }
  return counts;
}

export interface BrandUpsertInput {
  companyName: string;
  website: string;
  industry: string;
  about: string;
  logoUrl: string;
  coverUrl: string;
  mediaUrls: string[];
  videoUrl: string;
  instagram: string;
  amenities: string[];
  minFollowers: number;
  minAge: number;
  minPosts: number;
  payBasis: SponsorBasis;
  typicalPayMinCents: number | null;
  typicalPayMaxCents: number | null;
  paymentTerms: string;
  published: boolean;
}

export interface SponsorApplication {
  id: string;
  brand_user_id: string;
  brand_company: string | null;
  creator_user_id: string;
  creator_username: string | null;
  creator_age: number | null;
  creator_followers: number | null;
  desired_basis: SponsorBasis;
  desired_amount_cents: number;
  message: string | null;
  terms_basis: SponsorBasis | null;
  terms_amount_cents: number | null;
  terms_notes: string | null;
  terms_deliverables: string | null;
  terms_exclusive: boolean | null;
  terms_expires_at: string | null;
  status: "pending" | "countered" | "accepted" | "denied" | "withdrawn";
  created_at: string | null;
}

export interface SponsorDeal {
  id: string;
  brand_user_id: string;
  brand_company: string | null;
  creator_user_id: string;
  creator_username: string | null;
  basis: SponsorBasis;
  amount_cents: number;
  notes: string | null;
  deliverables: string | null;
  exclusive: boolean | null;
  status: "active" | "completed" | "cancelled";
  created_at: string | null;
}

export interface SponsorPayment {
  id: string;
  deal_id: string;
  gross_cents: number;
  fee_cents: number;
  net_cents: number;
  status: "pending" | "released" | "failed" | "refunded";
  requires_post: boolean;
  hold_until: string | null;
  released_at: string | null;
  created_at: string | null;
}

export interface SponsorPost {
  id: string;
  deal_id: string;
  post_id: string;
  likes_count: number | null;
  comments_count: number | null;
  created_at: string | null;
}

/** The creator/athlete earnings gateway payload. */
export interface CreatorEarnings {
  pendingCents: number;
  releasedCents: number;
  refundedCents: number;
  payoutsEnabled: boolean;
  payments: SponsorPayment[];
}

export interface SponsorEligibility {
  eligible: boolean;
  blocked: boolean;
  followers: number;
  posts: number;
  minFollowers: number;
  minAge: number;
  minPosts: number;
  reasons: string[];
}

const ERROR_MESSAGES: Record<string, string> = {
  sign_in_required: "Please sign in first.",
  company_name_required: "Enter your company name first.",
  brand_not_found: "This brand profile isn't available.",
  cannot_apply_to_self: "You can't apply to your own brand.",
  already_applied: "You already have an application with this brand.",
  age_requirement: "You don't meet this brand's minimum age requirement.",
  invalid_amount: "Enter a valid amount.",
  already_decided: "This application has already been decided.",
  nothing_to_accept: "There's no counter-offer to accept.",
  deal_not_active: "This sponsorship deal isn't active.",
  post_not_found: "That post couldn't be found on your account.",
  not_payout_eligible:
    "Payouts unlock once you're a verified coach, athlete, or creator (or have an active sponsorship).",
  forbidden: "Your account doesn't have permission for this.",
  billing_not_configured: "Payments aren't configured yet.",
  offer_expired: "This offer has expired — ask the brand for fresh terms.",
  already_released:
    "This payment was already released and can't be disputed.",
  invalid_instagram: "Enter a valid Instagram handle first.",
};

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
  // Sponsorship money rides the version-aware backend resolver — never a
  // pinned host that can freeze stale code or a stale Stripe env.
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
    if (code === "not_eligible" && Array.isArray(data.reasons)) {
      throw new Error((data.reasons as string[]).join(" "));
    }
    throw new Error(
      ERROR_MESSAGES[code] ??
        (typeof data.stripeMessage === "string" && data.stripeMessage
          ? data.stripeMessage
          : "Something went wrong. Please try again.")
    );
  }
  return data;
}

/**
 * Normalize a raw brand row from the backend so array fields are never
 * null/undefined (older rows predate the `media_urls`/`amenities` defaults
 * and surface as null, which crashes spread syntax in the marketplace).
 */
function normalizeBrand(raw: Partial<BrandProfile> | null | undefined): BrandProfile | null {
  if (!raw || typeof raw !== "object" || !raw.user_id) return null;
  return {
    user_id: raw.user_id,
    company_name: raw.company_name ?? "",
    username: raw.username ?? null,
    website: raw.website ?? null,
    industry: raw.industry ?? null,
    about: raw.about ?? null,
    logo_url: raw.logo_url ?? null,
    cover_url: raw.cover_url ?? null,
    media_urls: Array.isArray(raw.media_urls) ? raw.media_urls : [],
    video_url: raw.video_url ?? null,
    instagram: raw.instagram ?? null,
    ember_verified: raw.ember_verified === true,
    ember_score: raw.ember_score ?? null,
    ember_summary: raw.ember_summary ?? null,
    ember_checked_at: raw.ember_checked_at ?? null,
    amenities: Array.isArray(raw.amenities) ? raw.amenities : [],
    min_followers: typeof raw.min_followers === "number" ? raw.min_followers : 0,
    min_age: typeof raw.min_age === "number" ? raw.min_age : 18,
    min_posts: typeof raw.min_posts === "number" ? raw.min_posts : 0,
    pay_basis: (raw.pay_basis as SponsorBasis) ?? "per_post",
    typical_pay_min_cents: raw.typical_pay_min_cents ?? null,
    typical_pay_max_cents: raw.typical_pay_max_cents ?? null,
    payment_terms: raw.payment_terms ?? null,
    published: raw.published !== false,
  };
}

/** Public directory of published brands. */
export async function fetchBrands(): Promise<BrandProfile[]> {
  const res = await backendFetch("/brands");
  if (!res.ok) throw new Error("Couldn't load brands.");
  const data = (await res.json()) as { brands?: BrandProfile[] };
  return (data.brands ?? [])
    .map((b) => normalizeBrand(b))
    .filter((b): b is BrandProfile => b !== null);
}

/** One brand profile (published, or the caller's own draft when signed in). */
export async function fetchBrand(userId: string): Promise<BrandProfile | null> {
  const { data: session } = await supabase.auth.getSession();
  const token = session.session?.access_token;
  const res = await backendFetch(
    `/brand/profile?userId=${encodeURIComponent(userId)}`,
    token ? { headers: { Authorization: `Bearer ${token}` } } : undefined
  );
  if (!res.ok) return null;
  const data = (await res.json()) as { brand?: BrandProfile | null };
  return normalizeBrand(data.brand);
}

/** Create or update the signed-in user's brand profile. */
export async function saveBrandProfile(input: BrandUpsertInput): Promise<void> {
  const response = await authedFetch("/brand/profile", { method: "POST", body: input });
  if (response.mediaPending === true) throw new Error("Your profile details were saved, but showcase media needs a server update before it can be saved.");
}

/** Whether the signed-in creator can apply to a brand. */
export async function fetchEligibility(
  brandUserId: string
): Promise<SponsorEligibility> {
  const data = await authedFetch(
    `/brand/eligibility?brandUserId=${encodeURIComponent(brandUserId)}`
  );
  return {
    eligible: data.eligible === true,
    blocked: data.blocked === true,
    followers: typeof data.followers === "number" ? data.followers : 0,
    posts: typeof data.posts === "number" ? data.posts : 0,
    minFollowers:
      typeof data.minFollowers === "number" ? data.minFollowers : 0,
    minAge: typeof data.minAge === "number" ? data.minAge : 18,
    minPosts: typeof data.minPosts === "number" ? data.minPosts : 0,
    reasons: Array.isArray(data.reasons) ? (data.reasons as string[]) : [],
  };
}

/** Creator applies for a sponsorship. */
export async function applyForSponsorship(opts: {
  brandUserId: string;
  basis: SponsorBasis;
  amountCents: number;
  message: string;
  age: number;
}): Promise<void> {
  await authedFetch("/brand/apply", { method: "POST", body: opts });
}

/** The caller's applications, both as brand and creator. */
export async function fetchApplications(): Promise<{
  asBrand: SponsorApplication[];
  asCreator: SponsorApplication[];
}> {
  const data = await authedFetch("/sponsorship/applications");
  return {
    asBrand: Array.isArray(data.asBrand)
      ? (data.asBrand as SponsorApplication[])
      : [],
    asCreator: Array.isArray(data.asCreator)
      ? (data.asCreator as SponsorApplication[])
      : [],
  };
}

/** Brand responds: accept, deny, or counter with edited terms. */
export async function respondToApplication(opts: {
  id: string;
  action: "accept" | "deny" | "counter";
  termsBasis?: SponsorBasis;
  termsAmountCents?: number;
  termsNotes?: string;
  termsDeliverables?: string;
  termsExclusive?: boolean;
  expiresInDays?: number;
}): Promise<void> {
  await authedFetch("/sponsorship/respond", { method: "POST", body: opts });
}

/** Persist Ember's Instagram verification verdict on the caller's brand. */
export async function saveBrandVerification(opts: {
  instagram: string;
  verified: boolean;
  score: number;
  summary: string;
}): Promise<void> {
  await authedFetch("/brand/verify", { method: "POST", body: opts });
}

/** Brand disputes a pending escrow payment — refunds it via Stripe. */
export async function disputePayment(opts: {
  paymentId: string;
  reason: string;
}): Promise<void> {
  await authedFetch("/sponsorship/dispute", { method: "POST", body: opts });
}

/** The creator/athlete earnings gateway — escrow totals + payout status. */
export async function fetchCreatorEarnings(): Promise<CreatorEarnings> {
  const data = await authedFetch("/creator/earnings");
  return {
    pendingCents: typeof data.pendingCents === "number" ? data.pendingCents : 0,
    releasedCents:
      typeof data.releasedCents === "number" ? data.releasedCents : 0,
    refundedCents:
      typeof data.refundedCents === "number" ? data.refundedCents : 0,
    payoutsEnabled: data.payoutsEnabled === true,
    payments: Array.isArray(data.payments)
      ? (data.payments as SponsorPayment[])
      : [],
  };
}

/** Creator accepts a counter-offer or withdraws. */
export async function creatorRespond(opts: {
  id: string;
  action: "accept" | "withdraw";
}): Promise<void> {
  await authedFetch("/sponsorship/creator-respond", {
    method: "POST",
    body: opts,
  });
}

/** The caller's deals + escrow ledger + tracked posts. */
export async function fetchDeals(): Promise<{
  deals: SponsorDeal[];
  payments: SponsorPayment[];
  posts: SponsorPost[];
}> {
  const data = await authedFetch("/sponsorship/deals");
  return {
    deals: Array.isArray(data.deals) ? (data.deals as SponsorDeal[]) : [],
    payments: Array.isArray(data.payments)
      ? (data.payments as SponsorPayment[])
      : [],
    posts: Array.isArray(data.posts) ? (data.posts as SponsorPost[]) : [],
  };
}

/** Brand funds the next payment for a deal — redirects to Stripe Checkout. */
export async function fundDeal(dealId: string): Promise<void> {
  const data = await authedFetch("/sponsorship/fund", {
    method: "POST",
    body: { dealId, origin: window.location.origin },
  });
  if (typeof data.url !== "string") throw new Error("Couldn't start checkout.");
  window.location.assign(data.url);
}

/** Creator links one of their posts to a deal. */
export async function trackSponsoredPost(opts: {
  dealId: string;
  postId: string;
}): Promise<void> {
  await authedFetch("/sponsorship/track-post", { method: "POST", body: opts });
}

/**
 * True when `senderId` has been DM-blocked from messaging `recipientId`
 * (brand denied the creator's sponsorship application).
 */
export async function isDmBlocked(
  senderId: string,
  recipientId: string
): Promise<boolean> {
  try {
    const { data } = await supabase
      .from("whisper_dm_blocks")
      .select("id")
      .eq("blocked_sender_id", senderId)
      .eq("protected_user_id", recipientId)
      .limit(1)
      .maybeSingle();
    return !!data;
  } catch {
    return false;
  }
}

export function formatSponsorAmount(
  cents: number,
  basis: SponsorBasis
): string {
  const dollars = (cents / 100).toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: cents % 100 === 0 ? 0 : 2,
  });
  return `${dollars} ${BASIS_SHORT[basis]}`;
}

/** "Typically pays $200–$500 /post" transparency line, or null. */
export function typicalPayText(brand: BrandProfile): string | null {
  const fmt = (c: number) =>
    (c / 100).toLocaleString("en-US", {
      style: "currency",
      currency: "USD",
      maximumFractionDigits: 0,
    });
  const lo = brand.typical_pay_min_cents;
  const hi = brand.typical_pay_max_cents;
  if (lo && hi && hi > lo)
    return `${fmt(lo)}–${fmt(hi)} ${BASIS_SHORT[brand.pay_basis]}`;
  if (lo || hi) return `~${fmt((lo ?? hi) as number)} ${BASIS_SHORT[brand.pay_basis]}`;
  return null;
}
