import {
  Sparkles,
  Trophy,
  Dumbbell,
  UserCheck,
  Building2,
  type LucideIcon,
} from "lucide-react";

import type { VerificationBadge } from "@/lib/verification";
import type {
  BrandProfile,
  SponsorApplication,
  SponsorBasis,
  SponsorDeal,
  SponsorPayment,
  SponsorPost,
} from "@/lib/brands";
import type { Prospect } from "@/lib/recruiter";

/** Project ID for building Rork asset URLs (brand product photos). */
const PROJECT_ID = "yrcam4b2gk8ngyp9hyd1g";
function assetUrl(uniqueKey: string): string {
  return `https://rork.app/pa/${PROJECT_ID}/${uniqueKey}`;
}

/** Real product-photo URLs for the sample brands (generated assets). */
export const SAMPLE_BRAND_PHOTOS: Record<string, string> = {
  "sample-apex": assetUrl("apex_protein_tub_shaker"),
  "sample-stride": assetUrl("athletic_apparel_folded"),
  "sample-forge": assetUrl("massage_gun_recovery_cups"),
};

/**
 * Pitch Mode — internal presentation decks used when walking prospects
 * (creators, athletes, coaches, recruiters) through exactly how Whisper works.
 * Visible only to moderators and above. All demo data below is clearly-marked
 * sample data rendered through the SAME components/layouts the real product
 * uses, so a prospect sees precisely what their experience would look like.
 */

/** Moderator, admin, and owner can open Pitch Mode. */
export function isModOrHigher(badge: VerificationBadge): boolean {
  return badge === "moderator" || badge === "admin" || badge === "owner";
}

/**
 * Pitch Mode access gate. Moderators, admins, and the founder can open any
 * deck; recruiters can also open Pitch Mode so they can walk prospects
 * through the recruiter deck (and the others they'd use to pitch talent).
 * The recruiter role is a separate `is_recruiter` boolean on
 * `whisper_profiles`, not part of the `VerificationBadge` hierarchy, so it's
 * threaded in alongside the badge.
 */
export function canOpenPitchMode(
  badge: VerificationBadge,
  isRecruiter: boolean
): boolean {
  return isModOrHigher(badge) || isRecruiter;
}

export type PitchAudience =
  | "creators"
  | "athletes"
  | "coaches"
  | "recruiters"
  | "brands";

export interface PitchAudienceMeta {
  id: PitchAudience;
  title: string;
  tagline: string;
  icon: LucideIcon;
  /** One-liner used on the hub card. */
  blurb: string;
  /** Short label shown on the public nav dropdown. */
  navLabel: string;
}

export const PITCH_AUDIENCES: PitchAudienceMeta[] = [
  {
    id: "brands",
    title: "Brands",
    tagline: "Sponsor the right creators — escrowed, tracked, automatic",
    icon: Building2,
    navLabel: "For Brands",
    blurb:
      "Post a sponsorship, fund escrow, watch tracked posts release payment — plus Whisper Ads: $5 CPM reach that funds the creator pool.",
  },
  {
    id: "creators",
    title: "Creators",
    tagline: "Get paid for the content you already make",
    icon: Sparkles,
    navLabel: "For Creators",
    blurb:
      "Brand marketplace walkthrough, sample sponsorship deals, and the WPP ad-revenue program.",
  },
  {
    id: "athletes",
    title: "Athletes",
    tagline: "Turn your training into sponsorships",
    icon: Trophy,
    navLabel: "For Athletes",
    blurb:
      "How athletes get discovered, featured, and sponsored — plus WPP earnings on top.",
  },
  {
    id: "coaches",
    title: "Coaches",
    tagline: "A real coaching business, built in",
    icon: Dumbbell,
    navLabel: "For Coaches",
    blurb:
      "The exact money flow: publish up to three plan tiers, clients subscribe, Stripe pays you out — coaches keep 90%. Live calculator.",
  },
  {
    id: "recruiters",
    title: "Recruiters",
    tagline: "Scout, track, and promote talent",
    icon: UserCheck,
    navLabel: "For Recruiters",
    blurb:
      "A live, clickable pipeline with sample talent, meeting requests, and one-tap promotions.",
  },
];

export function pitchAudienceMeta(id: string | undefined): PitchAudienceMeta | null {
  return PITCH_AUDIENCES.find((a) => a.id === id) ?? null;
}

// ---------------------------------------------------------------------------
// Real platform numbers (kept in sync with the backend)
// ---------------------------------------------------------------------------

/** Whisper keeps 10% on coach subscriptions (backend COACH_PLATFORM_FEE_PERCENT). */
export const COACH_PLATFORM_FEE_PERCENT = 10;
/** Whisper keeps 10% on brand sponsorship escrow (backend SPONSOR_PLATFORM_FEE_PERCENT). */
export const SPONSOR_PLATFORM_FEE_PERCENT = 10;
/** Coach monthly rate bounds enforced by the backend. */
export const COACH_RATE_MIN = 5;
export const COACH_RATE_MAX = 2000;

// ---------------------------------------------------------------------------
// WPP — Whisper Paid Partners (ad revenue share)
// ---------------------------------------------------------------------------

export interface WppTier {
  id: string;
  name: string;
  minFollowers: number;
  /** Estimated payout per 1,000 qualified views, in cents. */
  rpmCents: number;
  perks: string[];
}

export const WPP_TIERS: WppTier[] = [
  {
    id: "partner",
    name: "Partner",
    minFollowers: 1_000,
    rpmCents: 90,
    perks: ["Ad revenue share on Reels & threads", "Monthly payout via Stripe"],
  },
  {
    id: "plus",
    name: "Partner+",
    minFollowers: 10_000,
    rpmCents: 140,
    perks: [
      "Higher RPM on all formats",
      "Priority placement in brand marketplace",
      "Dedicated partner support",
    ],
  },
  {
    id: "elite",
    name: "Elite",
    minFollowers: 100_000,
    rpmCents: 220,
    perks: [
      "Top RPM tier",
      "First access to premium ad campaigns",
      "Custom brand introductions from our team",
    ],
  },
];

/** Estimated monthly WPP payout in cents for a view count at a tier. */
export function wppMonthlyCents(monthlyViews: number, tier: WppTier): number {
  return Math.round((monthlyViews / 1000) * tier.rpmCents);
}

export function formatUsd(cents: number): string {
  return (cents / 100).toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: cents % 100 === 0 ? 0 : 2,
  });
}

// ---------------------------------------------------------------------------
// Sample brands — shown through the real brand-marketplace card layout
// ---------------------------------------------------------------------------

export interface SampleBrand extends BrandProfile {
  /** Marks demo rows so nothing ever posts to the backend. */
  isSample: true;
}

function sampleBrand(input: Partial<BrandProfile> & { user_id: string; company_name: string }): SampleBrand {
  return {
    username: null,
    website: null,
    industry: null,
    about: null,
    logo_url: null,
    cover_url: null,
    media_urls: [],
    video_url: null,
    instagram: null,
    ember_verified: true,
    ember_score: 92,
    ember_summary: null,
    ember_checked_at: null,
    amenities: [],
    min_followers: 0,
    min_age: 18,
    min_posts: 0,
    pay_basis: "per_post",
    typical_pay_min_cents: null,
    typical_pay_max_cents: null,
    payment_terms: null,
    published: true,
    ...input,
    isSample: true,
  };
}

/** Sample brand applications for the brand-dashboard demo. */
export type SampleApplication = SponsorApplication & { isSample: true };
function sampleApp(
  input: Partial<SponsorApplication> & {
    id: string;
    brand_user_id: string;
    creator_user_id: string;
  }
): SampleApplication {
  return {
    brand_company: null,
    creator_username: null,
    creator_age: null,
    creator_followers: null,
    desired_basis: "per_post",
    desired_amount_cents: 0,
    message: null,
    terms_basis: null,
    terms_amount_cents: null,
    terms_notes: null,
    terms_deliverables: null,
    terms_exclusive: null,
    terms_expires_at: null,
    status: "pending",
    created_at: null,
    ...input,
    isSample: true,
  } as SampleApplication;
}

/** Sample sponsorship deal + escrow payment + tracked post. */
export type SampleDeal = SponsorDeal & { isSample: true };
export type SampleSponsorPayment = SponsorPayment & { isSample: true };
export type SampleSponsorPost = SponsorPost & { isSample: true };
function sampleDeal(
  input: Partial<SponsorDeal> & { id: string; brand_user_id: string; creator_user_id: string }
): SampleDeal {
  return {
    brand_company: null,
    creator_username: null,
    basis: "per_post",
    amount_cents: 0,
    notes: null,
    deliverables: null,
    exclusive: null,
    status: "active",
    created_at: null,
    ...input,
    isSample: true,
  } as SampleDeal;
}
function samplePayment(
  input: Partial<SponsorPayment> & { id: string; deal_id: string }
): SampleSponsorPayment {
  return {
    gross_cents: 0,
    fee_cents: 0,
    net_cents: 0,
    status: "pending",
    requires_post: true,
    hold_until: null,
    released_at: null,
    created_at: null,
    ...input,
    isSample: true,
  } as SampleSponsorPayment;
}
function samplePost(
  input: Partial<SponsorPost> & { id: string; deal_id: string }
): SampleSponsorPost {
  return {
    post_id: "",
    likes_count: null,
    comments_count: null,
    created_at: null,
    ...input,
    isSample: true,
  } as SampleSponsorPost;
}

export const SAMPLE_BRANDS: SampleBrand[] = [
  sampleBrand({
    user_id: "sample-apex",
    company_name: "Apex Nutrition",
    username: "apexnutrition",
    industry: "Supplements",
    website: "https://apexnutrition.example",
    instagram: "apexnutrition",
    about:
      "Performance supplements for lifters and endurance athletes. We sponsor creators who post honest training content — no script, no fake hype.",
    amenities: ["Free monthly product box", "Discount code for your audience", "Early product drops"],
    min_followers: 2_500,
    min_age: 18,
    min_posts: 12,
    pay_basis: "per_post",
    typical_pay_min_cents: 15_000,
    typical_pay_max_cents: 60_000,
    payment_terms: "Escrowed on acceptance, released when the tracked post goes live.",
    ember_score: 94,
    ember_summary: "Verified company, real product line, consistent creator payouts on record.",
  }),
  sampleBrand({
    user_id: "sample-stride",
    company_name: "Stride Athletics",
    username: "strideathletics",
    industry: "Apparel",
    website: "https://strideathletics.example",
    instagram: "strideathletics",
    about:
      "Training apparel built for athletes. Monthly ambassador deals for athletes who compete and post their journey.",
    amenities: ["Full seasonal kit", "Comp entry reimbursements", "Ambassador page feature"],
    min_followers: 5_000,
    min_age: 16,
    min_posts: 20,
    pay_basis: "per_month",
    typical_pay_min_cents: 40_000,
    typical_pay_max_cents: 120_000,
    payment_terms: "Monthly escrow, released against 4 tracked posts per month.",
    ember_score: 91,
    ember_summary: "Established apparel brand with an active ambassador program.",
  }),
  sampleBrand({
    user_id: "sample-forge",
    company_name: "Forge Recovery Lab",
    username: "forgerecovery",
    industry: "Recovery tech",
    website: "https://forgerecovery.example",
    instagram: "forgerecovery",
    about:
      "Percussion + cold therapy gear. We work with coaches and athletes on long-term yearly partnerships.",
    amenities: ["Full recovery suite (kept)", "Affiliate revenue share", "Clinic referrals"],
    min_followers: 10_000,
    min_age: 21,
    min_posts: 30,
    pay_basis: "per_year",
    typical_pay_min_cents: 300_000,
    typical_pay_max_cents: 900_000,
    payment_terms: "Quarterly escrow releases against agreed content calendar.",
    ember_score: 89,
    ember_summary: "Real hardware company; slower to counter but pays top-of-market.",
  }),
];

// ---------------------------------------------------------------------------
// Sample brand-dashboard data — applications, deals, escrow payments, posts
// (mirrors what a brand sees on /brand/dashboard in production)
// ---------------------------------------------------------------------------

/** Inbound creator applications for the sample brands (brand-side view). */
export const SAMPLE_BRAND_APPLICATIONS: SampleApplication[] = [
  sampleApp({
    id: "app-1",
    brand_user_id: "sample-apex",
    creator_user_id: "creator-1",
    creator_username: "mayalifts",
    creator_age: 24,
    creator_followers: 18_400,
    desired_basis: "per_post",
    desired_amount_cents: 45_000,
    message:
      "I've been using Apex whey for 8 months and my audience asks about it constantly. I'd love to do a 3-post meet-prep series showing how it fits into my peaking block.",
    status: "pending",
    created_at: new Date(Date.now() - 2 * 86400_000).toISOString(),
  }),
  sampleApp({
    id: "app-2",
    brand_user_id: "sample-apex",
    creator_user_id: "creator-2",
    creator_username: "reedruns",
    creator_age: 27,
    creator_followers: 9_300,
    desired_basis: "per_month",
    desired_amount_cents: 55_000,
    message:
      "My run club wears Stride but I'd rather rep Apex for fueling content — 4 Reels a month, long-form fueling guides, monthly code share.",
    status: "pending",
    created_at: new Date(Date.now() - 5 * 86400_000).toISOString(),
  }),
  sampleApp({
    id: "app-3",
    brand_user_id: "sample-stride",
    creator_user_id: "creator-3",
    creator_username: "eliaspark",
    creator_age: 22,
    creator_followers: 7_800,
    desired_basis: "per_month",
    desired_amount_cents: 50_000,
    message:
      "Calisthenics fits the technical apparel angle perfectly — I'd show kit durability through ring work and bar drills.",
    status: "countered",
    terms_basis: "per_month",
    terms_amount_cents: 42_000,
    terms_notes: "We can do $42/mo for the first 3 months, then revisit at 10k followers.",
    terms_deliverables: "4 Reels + 2 stories per month, tag @strideathletics, kit visible in every post",
    terms_exclusive: false,
    terms_expires_at: new Date(Date.now() + 10 * 86400_000).toISOString(),
    created_at: new Date(Date.now() - 8 * 86400_000).toISOString(),
  }),
];

/** Active deals the sample brands have with creators — funds in escrow. */
export const SAMPLE_BRAND_DEALS: SampleDeal[] = [
  sampleDeal({
    id: "deal-1",
    brand_user_id: "sample-apex",
    creator_user_id: "creator-1",
    creator_username: "rileychen",
    basis: "per_post",
    amount_cents: 50_000,
    notes: "Olympic lifting content — Apex visible in every Reel.",
    deliverables: "3 feed posts + 1 story, product visible, tag @apexnutrition",
    exclusive: false,
    status: "active",
    created_at: new Date(Date.now() - 14 * 86400_000).toISOString(),
  }),
  sampleDeal({
    id: "deal-2",
    brand_user_id: "sample-stride",
    creator_user_id: "creator-2",
    creator_username: "coachdw",
    basis: "per_month",
    amount_cents: 85_000,
    notes: "Monthly ambassador deal — Coach Dana + Stride kit in coaching Reels.",
    deliverables: "4 Reels + 2 stories per month, tag @strideathletics",
    exclusive: true,
    status: "active",
    created_at: new Date(Date.now() - 21 * 86400_000).toISOString(),
  }),
];

/** Escrow payments for the sample deals — some pending, some released. */
export const SAMPLE_BRAND_PAYMENTS: SampleSponsorPayment[] = [
  samplePayment({
    id: "pay-1",
    deal_id: "deal-1",
    gross_cents: 50_000,
    fee_cents: 5_000,
    net_cents: 45_000,
    status: "pending",
    requires_post: true,
    hold_until: new Date(Date.now() + 6 * 86400_000).toISOString(),
    created_at: new Date(Date.now() - 1 * 86400_000).toISOString(),
  }),
  samplePayment({
    id: "pay-2",
    deal_id: "deal-1",
    gross_cents: 50_000,
    fee_cents: 5_000,
    net_cents: 45_000,
    status: "released",
    requires_post: true,
    released_at: new Date(Date.now() - 4 * 86400_000).toISOString(),
    created_at: new Date(Date.now() - 10 * 86400_000).toISOString(),
  }),
  samplePayment({
    id: "pay-3",
    deal_id: "deal-2",
    gross_cents: 85_000,
    fee_cents: 8_500,
    net_cents: 76_500,
    status: "released",
    requires_post: true,
    released_at: new Date(Date.now() - 2 * 86400_000).toISOString(),
    created_at: new Date(Date.now() - 12 * 86400_000).toISOString(),
  }),
  samplePayment({
    id: "pay-4",
    deal_id: "deal-2",
    gross_cents: 85_000,
    fee_cents: 8_500,
    net_cents: 76_500,
    status: "pending",
    requires_post: true,
    hold_until: new Date(Date.now() + 3 * 86400_000).toISOString(),
    created_at: new Date(Date.now() - 0.5 * 86400_000).toISOString(),
  }),
];

/** Tracked sponsored posts attached to the sample deals. */
export const SAMPLE_BRAND_POSTS: SampleSponsorPost[] = [
  samplePost({
    id: "post-1",
    deal_id: "deal-1",
    post_id: "post-1001",
    likes_count: 1_240,
    comments_count: 86,
    created_at: new Date(Date.now() - 4 * 86400_000).toISOString(),
  }),
  samplePost({
    id: "post-2",
    deal_id: "deal-2",
    post_id: "post-1002",
    likes_count: 2_980,
    comments_count: 142,
    created_at: new Date(Date.now() - 2 * 86400_000).toISOString(),
  }),
];

// ---------------------------------------------------------------------------
// Sample creator-side earnings + coaching payments — used by the payments
// visualization so a prospect sees exactly what their account will look like
// when money lands. Mirrors the real /coach/earnings + /sponsorships views.
// ---------------------------------------------------------------------------

/** One row in the coach earnings history (matches CoachEarnings.payments). */
export interface SampleCoachPayment {
  isSample: true;
  gross_cents: number;
  fee_cents: number;
  net_cents: number;
  client_email: string | null;
  description: string | null;
  created_at: string;
}
function sampleCoachPayment(
  input: Partial<SampleCoachPayment> & { created_at: string }
): SampleCoachPayment {
  return {
    gross_cents: 0,
    fee_cents: 0,
    net_cents: 0,
    client_email: null,
    description: null,
    isSample: true,
    ...input,
  };
}

export const SAMPLE_COACH_PAYMENTS: SampleCoachPayment[] = [
  sampleCoachPayment({
    gross_cents: 15_000,
    fee_cents: 1_500,
    net_cents: 13_500,
    client_email: "athlete1@example.com",
    description: "Monthly coaching — Coach Dana",
    created_at: new Date(Date.now() - 2 * 86400_000).toISOString(),
  }),
  sampleCoachPayment({
    gross_cents: 15_000,
    fee_cents: 1_500,
    net_cents: 13_500,
    client_email: "athlete2@example.com",
    description: "Monthly coaching — Coach Dana",
    created_at: new Date(Date.now() - 9 * 86400_000).toISOString(),
  }),
  sampleCoachPayment({
    gross_cents: 15_000,
    fee_cents: 1_500,
    net_cents: 13_500,
    client_email: "athlete3@example.com",
    description: "Monthly coaching — Coach Dana",
    created_at: new Date(Date.now() - 16 * 86400_000).toISOString(),
  }),
];

/** Snapshot of a coach earnings account for the payments visualization. */
export const SAMPLE_COACH_EARNINGS = {
  isSample: true as const,
  connected: true,
  payoutsEnabled: true,
  chargesEnabled: true,
  totalEarnedCents: 40_500,
  availableCents: 27_000,
  pendingCents: 13_500,
  payments: SAMPLE_COACH_PAYMENTS,
};

/** Snapshot of a creator sponsorship earnings account. */
export const SAMPLE_CREATOR_EARNINGS = {
  isSample: true as const,
  pendingCents: 121_500,
  releasedCents: 76_500,
  refundedCents: 0,
  payoutsEnabled: true,
  payments: [
    samplePayment({
      id: "cpay-1",
      deal_id: "cdeal-1",
      gross_cents: 50_000,
      fee_cents: 5_000,
      net_cents: 45_000,
      status: "released",
      requires_post: true,
      released_at: new Date(Date.now() - 4 * 86400_000).toISOString(),
      created_at: new Date(Date.now() - 10 * 86400_000).toISOString(),
    }),
    samplePayment({
      id: "cpay-2",
      deal_id: "cdeal-1",
      gross_cents: 50_000,
      fee_cents: 5_000,
      net_cents: 45_000,
      status: "pending",
      requires_post: true,
      hold_until: new Date(Date.now() + 6 * 86400_000).toISOString(),
      created_at: new Date(Date.now() - 1 * 86400_000).toISOString(),
    }),
    samplePayment({
      id: "cpay-3",
      deal_id: "cdeal-2",
      gross_cents: 85_000,
      fee_cents: 8_500,
      net_cents: 76_500,
      status: "released",
      requires_post: true,
      released_at: new Date(Date.now() - 2 * 86400_000).toISOString(),
      created_at: new Date(Date.now() - 12 * 86400_000).toISOString(),
    }),
    samplePayment({
      id: "cpay-4",
      deal_id: "cdeal-2",
      gross_cents: 85_000,
      fee_cents: 8_500,
      net_cents: 76_500,
      status: "pending",
      requires_post: true,
      hold_until: new Date(Date.now() + 3 * 86400_000).toISOString(),
      created_at: new Date(Date.now() - 0.5 * 86400_000).toISOString(),
    }),
  ],
};

// ---------------------------------------------------------------------------
// Sample recruiter pipeline — rendered through the real pipeline layout
// ---------------------------------------------------------------------------

export type SampleProspect = Prospect & { isSample: true };

function sampleProspect(input: Partial<Prospect> & { id: string; prospect_display_name: string }): SampleProspect {
  return {
    recruiter_id: "sample-recruiter",
    prospect_user_id: null,
    prospect_username: null,
    prospect_image_url: null,
    source: "Instagram",
    location: null,
    niche: null,
    instagram: null,
    tiktok: null,
    suggested_role: null,
    status: "discovered",
    notes: null,
    rating: null,
    contact_log: [],
    created_at: null,
    updated_at: null,
    ...input,
    isSample: true,
  } as SampleProspect;
}

export const SAMPLE_PROSPECTS: SampleProspect[] = [
  sampleProspect({
    id: "sp-1",
    prospect_display_name: "Maya Torres",
    prospect_username: "mayalifts",
    niche: "Powerlifting",
    location: "Austin, TX",
    instagram: "@mayalifts",
    suggested_role: "athlete",
    status: "meeting",
    rating: 5,
    notes: "587 wilks, posts 4x/week, audience loves her meet-day vlogs.",
    source: "Instagram",
  }),
  sampleProspect({
    id: "sp-2",
    prospect_display_name: "Jordan Reed",
    prospect_username: "reedruns",
    niche: "Marathon / run club",
    location: "Chicago, IL",
    tiktok: "@reedruns",
    suggested_role: "creator",
    status: "interested",
    rating: 4,
    notes: "Runs a 2k-member run club. Wants a platform that isn't ad-soup.",
    source: "TikTok",
  }),
  sampleProspect({
    id: "sp-3",
    prospect_display_name: "Coach Dana Whitfield",
    prospect_username: "coachdw",
    niche: "Strength coaching",
    location: "Remote",
    instagram: "@coachdw",
    suggested_role: "coach",
    status: "contacted",
    rating: 4,
    notes: "12 online clients on spreadsheets today — perfect Coach Studio fit.",
    source: "Referral",
  }),
  sampleProspect({
    id: "sp-4",
    prospect_display_name: "Elias Park",
    prospect_username: "eliaspark",
    niche: "Calisthenics",
    location: "Seattle, WA",
    suggested_role: "creator",
    status: "discovered",
    rating: 3,
    notes: "Great content, small but fast-growing audience.",
    source: "Scouting",
  }),
  sampleProspect({
    id: "sp-5",
    prospect_display_name: "Riley Chen",
    prospect_username: "rileychen",
    niche: "Olympic weightlifting",
    location: "San Diego, CA",
    instagram: "@rileychen",
    suggested_role: "athlete",
    status: "ready",
    rating: 5,
    notes: "National qualifier. Verbal yes — ready to promote and feature.",
    source: "Competition",
  }),
];

/** Sample meeting requests for the recruiter deck (mirrors whisper_meeting_requests rows). */
export interface SampleMeeting {
  id: string;
  requester_name: string;
  requester_email: string;
  requested_time: string;
  requester_timezone: string;
  message: string;
  status: "pending" | "approved" | "denied";
}

export const SAMPLE_MEETINGS: SampleMeeting[] = [
  {
    id: "sm-1",
    requester_name: "Maya Torres",
    requester_email: "maya@example.com",
    requested_time: new Date(Date.now() + 3 * 86400_000).toISOString(),
    requester_timezone: "America/Chicago",
    message: "Saw your featured card — I'd love to hear about the athlete program.",
    status: "pending",
  },
  {
    id: "sm-2",
    requester_name: "Jordan Reed",
    requester_email: "jordan@example.com",
    requested_time: new Date(Date.now() + 5 * 86400_000).toISOString(),
    requester_timezone: "America/Chicago",
    message: "Interested in moving my run club community over.",
    status: "pending",
  },
];
