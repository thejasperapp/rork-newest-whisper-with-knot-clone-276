import type { VerificationBadge } from "@/lib/verification";
import type { WhisperPostStat } from "@/lib/types";

/**
 * Web port of the iOS `WhisperAlgorithmService` ranking. Used by the Creator
 * Studio's "What the algorithm sees" panel so creators understand exactly why
 * their posts surface the way they do — identical recipe and constants to iOS.
 *
 * Score recipe per post:
 *   base    = log10(1 + likes) * 4 + log10(1 + comments) * 6
 *   recency = exp(-hours / halfLife)            // newer posts win
 *   floor   = (likes + comments >= 3)           // gate the badge boost
 *   boost   = floor ? badge.algorithmBoost : 1  // verified+ amplified
 *   final   = (base + recency * 5) * boost
 */

/** Half-life for the recency curve, in hours. */
export const RECENCY_HALF_LIFE = 18;

/** Per-session "already seen" decay (informational on web). */
export const SEEN_DECAY = 0.7;

/** Minimum (likes + comments) before the verified-tier boost engages. */
export const BADGE_BOOST_FLOOR = 3;

/** The amplification multiplier a badge tier earns (matches iOS). */
export function algorithmBoost(badge: VerificationBadge): number {
  switch (badge) {
    case "owner":
      return 2.4;
    case "admin":
      return 2.0;
    case "moderator":
      return 1.8;
    case "verified":
      return 1.6;
    default:
      return 1.0;
  }
}

function hoursSince(createdAt: string | null): number {
  if (!createdAt) return 0;
  const ts = new Date(createdAt).getTime();
  if (Number.isNaN(ts)) return 0;
  return Math.max(0, (Date.now() - ts) / 3_600_000);
}

/** Score a single enriched post entry for the signed-in author. */
export function scorePost(
  entry: WhisperPostStat,
  badge: VerificationBadge
): number {
  const likes = Math.log10(1 + entry.likes) * 4;
  const comments = Math.log10(1 + entry.comments) * 6;
  const recency = Math.exp(-hoursSince(entry.post.created_at) / RECENCY_HALF_LIFE);
  const engaged = entry.likes + entry.comments >= BADGE_BOOST_FLOOR;
  const boost = engaged ? algorithmBoost(badge) : 1.0;
  return (likes + comments + recency * 5) * boost;
}

/** Rank a creator's posts highest-score first. */
export function rankEntries(
  entries: WhisperPostStat[],
  badge: VerificationBadge
): WhisperPostStat[] {
  return [...entries].sort((a, b) => scorePost(b, badge) - scorePost(a, badge));
}
