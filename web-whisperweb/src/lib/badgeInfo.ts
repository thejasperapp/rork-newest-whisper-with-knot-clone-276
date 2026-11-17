/**
 * Web port of the iOS `WhisperBadgeKind` / `WhisperBadgeInfoSheet` copy and
 * `WhisperRoleDescriptor`. Single source of truth for the pill labels, accent
 * colours, and the explainer text shown in the "About badges" sheet so a user
 * sees the exact same legend on iOS and web.
 */

import type { BadgeKind } from "@/lib/badges";
import type { VerificationBadge } from "@/lib/verification";

export interface BadgeMeta {
  /** Full name used in the info sheet. */
  title: string;
  /** Short label used inline next to a username. */
  pillLabel: string;
  /** One-sentence explainer shown in the info sheet. */
  explainer: string;
  /** Accent colour (predominant seal colour from iOS). */
  color: string;
}

/** Trust & identity chips (mirrors `WhisperBadgeKind`). */
export const BADGE_META: Record<BadgeKind, BadgeMeta> = {
  restricted: {
    title: "Restricted DMs",
    pillLabel: "Restricted",
    color: "#e63333",
    explainer:
      "Auto-applied after repeated safety strikes. New DMs from this account are throttled until a moderator reviews the activity.",
  },
  coach: {
    title: "Verified Coach",
    pillLabel: "Coach",
    color: "#fa7326",
    explainer:
      "Approved Jasper coach. Verified by the Whisper team to share programs, nutrition, and progress feedback with clients.",
  },
  director: {
    title: "Whisper Director",
    pillLabel: "Director",
    color: "#1a1a1a",
    explainer:
      "Whisper media team member. Directors produce Featured Film Friday shorts, organize creator collaborations, and run the studio workspace.",
  },
  blogger: {
    title: "Whisper Blogger",
    pillLabel: "Blogger",
    color: "#0d8a6f",
    explainer:
      "Dedicated writer on Whisper. Bloggers post articles and film reviews with featured-film tags and full byline credit.",
  },
  teen: {
    title: "Teen Account",
    pillLabel: "Teen",
    color: "#33a6fa",
    explainer:
      "Account belongs to a verified teen (13–17). Stricter DM defaults, no unsolicited messages from unverified adults.",
  },
  adult: {
    title: "18+ Verified",
    pillLabel: "18+",
    color: "#8c59fa",
    explainer:
      "User has self-attested they are 18 or older. Required to DM unfamiliar adults.",
  },
  trusted: {
    title: "Trusted Member",
    pillLabel: "Trusted",
    color: "#1abfa6",
    explainer:
      "Long-standing account with a clean record and positive community signal. Granted manually after sustained good standing.",
  },
  established: {
    title: "Established Member",
    pillLabel: "Established",
    color: "#f2b82e",
    explainer:
      "Account is at least 30 days old with zero safety strikes. Helps you spot brand-new or throwaway accounts at a glance.",
  },
  guardian: {
    title: "Community Guardian",
    pillLabel: "Guardian",
    color: "#4080f2",
    explainer:
      "User has filed at least 3 helpful reports that moderators confirmed. Thank-you chip for keeping the community safe.",
  },
  founding: {
    title: "Founding Member",
    pillLabel: "Founding",
    color: "#eb339e",
    explainer:
      "Joined Whisper in the launch window. A small thank-you to the first users on the platform.",
  },
};

/** The Liar Liar chip (kept separate — it isn't derived from `BadgeFlags`). */
export const LIAR_META: BadgeMeta = {
  title: "Liar Liar",
  pillLabel: "Liar Liar",
  color: "#eb2e2e",
  explainer:
    "Earned after 3 false or misleading public posts in 30 days. Only post text is evaluated — never DMs, workouts, or photos.",
};

/** The primary verification seal explainer (verified / mod / admin / owner). */
export const VERIFIED_META = {
  title: "Verified / Moderator / Admin / Owner",
  explainer:
    "The blue, silver, gold, or multi-colour seal next to a username. Granted manually by the Whisper team. Blue = verified user, silver = community moderator, gold = admin, multi-colour gradient = owner.",
};

export type RoleKind = "owner" | "admin" | "moderator" | "verified" | "coach";

export interface RoleMeta {
  text: string;
  color: string;
}

/** Mirrors `WhisperRoleDescriptor`. The highest-ranked role wins. */
export const ROLE_META: Record<RoleKind, RoleMeta> = {
  owner: { text: "Founder", color: "#d9408c" },
  admin: { text: "Admin", color: "#d99e1a" },
  moderator: { text: "Moderator", color: "#8c949e" },
  verified: { text: "Verified", color: "#218cf5" },
  coach: { text: "Coach", color: "#fa7326" },
};

/**
 * Resolve the single role pill shown first in the row, mirroring
 * `WhisperRoleResolver.descriptor`: owner > admin > moderator > verified >
 * coach.
 */
export function resolveRole(
  verified: VerificationBadge,
  isCoach: boolean
): RoleKind | null {
  if (verified === "owner") return "owner";
  if (verified === "admin") return "admin";
  if (verified === "moderator") return "moderator";
  if (verified === "verified") return "verified";
  if (isCoach) return "coach";
  return null;
}

/** Ordered catalogue used by the info sheet (matches the iOS list order). */
export const BADGE_CATALOG: BadgeKind[] = [
  "restricted",
  "coach",
  "director",
  "blogger",
  "teen",
  "adult",
  "trusted",
  "guardian",
  "established",
  "founding",
];
