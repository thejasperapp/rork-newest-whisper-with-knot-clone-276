import type { WhisperProfile } from "@/lib/types";

/**
 * THE ACCOUNT LADDER — one place that says who gets what, so the feature
 * sets can never overlap by accident. Mirrors iOS `WhisperAccountAccess` 1:1.
 *
 * - PERSONAL: post, waves, stories, DMs, communities, dating, meetings. No
 *   insights surface at all.
 * - PROFESSIONAL (self-selected "creator" / "business" account_type): plus
 *   ANALYTICS — the basic insights page — plus the niche line and contact
 *   buttons. NEVER Creator Studio. Anyone can flip this on for free, so it
 *   must not unlock anything earned or paid.
 * - WHISPER ONE (paid membership): plus the + badge, coach tools, longer
 *   posts, and Analytics (never Creator Studio).
 * - WHISPER PLUS (paid, the rung between One and Verified): everything One
 *   has PLUS the Jasper Intelligence pro pack — unlimited Jasper chats, voice
 *   mode, Imagine, /jasper in DMs and groups, the matchmaker and meeting
 *   companion without daily caps, memory across chats, priority answers.
 *   Never Creator Studio, never the blue check.
 * - VERIFIED CREATOR (applied, human-approved, paid yearly): the blue check
 *   plus CREATOR STUDIO (score, WPP creator pay, momentum), pinned posts,
 *   the grid composer, articles, creator tools in meetings, the algorithm
 *   boost, the long character limit.
 * - STAFF (moderator / admin / owner): everything a verified creator has.
 */

type Tierable = Pick<
  WhisperProfile,
  | "account_type"
  | "is_verified"
  | "is_moderator"
  | "is_admin"
  | "is_owner"
  | "is_one"
  | "is_coach"
  | "is_plus"
> | null | undefined;

/** Self-selected professional account (creator or business type). */
export function isProfessionalAccount(profile: Tierable): boolean {
  const t = (profile?.account_type ?? "").toLowerCase();
  return t === "creator" || t === "business";
}

/** Self-selected "business" type specifically. */
export function isBusinessAccount(profile: Tierable): boolean {
  return (profile?.account_type ?? "").toLowerCase() === "business";
}

/** Verified creator OR staff — the blue-check ladder. */
export function isVerifiedCreator(profile: Tierable): boolean {
  return !!(
    profile?.is_verified ||
    profile?.is_moderator ||
    profile?.is_admin ||
    profile?.is_owner
  );
}

/** Whisper One member (the paid + badge). */
export function isOneMember(profile: Tierable): boolean {
  return !!profile?.is_one;
}

/** Whisper Plus member — the Jasper Intelligence pro pack (whisper-plus.sql).
 *  Verified creators and staff inherit it. */
export function isPlusMember(profile: Tierable): boolean {
  if (isVerifiedCreator(profile)) return true;
  return !!profile?.is_plus;
}

/** What each rung of the ladder gets from Jasper (mirrors iOS 1:1). */
export interface JasperEntitlements {
  /** Daily chat turns in Jasper Intelligence (null = unlimited). */
  dailyChats: number | null;
  /** Daily Imagine renders (null = unlimited). */
  dailyImagines: number | null;
  voiceMode: boolean;
  jasperInChats: boolean;
  memory: boolean;
  webResearch: boolean;
  priority: boolean;
  tierName: string;
}

export const FREE_JASPER: JasperEntitlements = {
  dailyChats: 15,
  dailyImagines: 3,
  voiceMode: false,
  jasperInChats: true,
  memory: false,
  webResearch: false,
  priority: false,
  tierName: "Free",
};
export const ONE_JASPER: JasperEntitlements = {
  dailyChats: 60,
  dailyImagines: 15,
  voiceMode: true,
  jasperInChats: true,
  memory: false,
  webResearch: true,
  priority: false,
  tierName: "Whisper One",
};
export const PLUS_JASPER: JasperEntitlements = {
  dailyChats: null,
  dailyImagines: null,
  voiceMode: true,
  jasperInChats: true,
  memory: true,
  webResearch: true,
  priority: true,
  tierName: "Whisper Plus",
};

/** The Jasper pack for a profile. */
export function jasperEntitlements(profile: Tierable): JasperEntitlements {
  if (isPlusMember(profile)) return PLUS_JASPER;
  if (isOneMember(profile)) return ONE_JASPER;
  return FREE_JASPER;
}

/** Creator Studio — VERIFIED ONLY. */
export function canOpenCreatorStudio(profile: Tierable): boolean {
  return isVerifiedCreator(profile);
}

/**
 * Analytics — the basic insights page: professional accounts and One
 * members. Verified creators don't need it (Creator Studio supersedes).
 */
export function canOpenAnalytics(profile: Tierable): boolean {
  if (isVerifiedCreator(profile)) return false;
  return isProfessionalAccount(profile) || isOneMember(profile);
}

/** The IG-style grid (photo) composer — verified creators only. */
export function canPostGrid(profile: Tierable): boolean {
  return isVerifiedCreator(profile);
}

/** Pinned posts on the profile — verified creators only. */
export function canPinPosts(profile: Tierable): boolean {
  return isVerifiedCreator(profile);
}

export type InsightsDoor = "analytics" | "creatorStudio" | "businessSuite";

/**
 * The insights door for the profile header's top-left: Creator Studio
 * (verified), the Business Suite (business type — their own product),
 * Analytics (professional creator / One), or null for personal accounts.
 */
export function insightsDoor(profile: Tierable): InsightsDoor | null {
  if (canOpenCreatorStudio(profile)) return "creatorStudio";
  if (isBusinessAccount(profile)) return "businessSuite";
  if (canOpenAnalytics(profile)) return "analytics";
  return null;
}

export function insightsDoorPath(door: InsightsDoor): string {
  switch (door) {
    case "creatorStudio":
      return "/dashboard";
    case "businessSuite":
      return "/business";
    case "analytics":
      return "/analytics";
  }
}

export function insightsDoorLabel(door: InsightsDoor): string {
  switch (door) {
    case "creatorStudio":
      return "Creator Studio";
    case "businessSuite":
      return "Business Suite";
    case "analytics":
      return "Analytics";
  }
}

/** Human-readable tier label for settings / analytics headers. */
export function tierLabel(profile: Tierable): string {
  if (profile?.is_owner) return "Owner";
  if (profile?.is_admin) return "Admin";
  if (profile?.is_moderator) return "Moderator";
  if (profile?.is_verified) return "Verified creator";
  if (isPlusMember(profile)) return "Whisper Plus";
  if (isOneMember(profile)) return "Whisper One";
  if (isBusinessAccount(profile)) return "Business account";
  if (isProfessionalAccount(profile)) return "Creator account";
  return "Personal account";
}
