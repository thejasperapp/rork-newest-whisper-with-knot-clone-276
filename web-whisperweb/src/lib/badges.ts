/**
 * Web port of the iOS Whisper trust & identity badge derivation
 * (`WhisperBadgeKind.active`). Flags come from the Supabase `profiles` table —
 * the same columns the iOS `WhisperSafetyService` reads — so a user wears the
 * exact same chips on both platforms.
 */

export type BadgeKind =
  | "restricted"
  | "coach"
  | "director"
  | "blogger"
  | "teen"
  | "adult"
  | "trusted"
  | "established"
  | "guardian"
  | "founding";

export interface BadgeFlags {
  ageBand: string | null;
  isAdultAttested: boolean;
  isDmRestricted: boolean;
  createdAt: string | null;
  helpfulReportCount: number;
  isTrustedMember: boolean;
  /** Whisper media team member (directors) — set on whisper_profiles. */
  isDirector: boolean;
  /** Whisper blogger — dedicated writer role for articles & film reviews. */
  isBlogger: boolean;
  /** Legacy athlete flag — the Athlete badge is retired (it's a Creator
   *  niche now), so this never renders a chip. Kept for row compatibility. */
  isAthlete: boolean;
}

/** Accounts created before this date wear the Founding Member chip (matches iOS). */
const FOUNDING_CUTOFF = Date.parse("2026-06-08T00:00:00Z");
/** An account must be this old to earn the Established Member chip. */
const ESTABLISHED_MS = 30 * 24 * 60 * 60 * 1000;
/** Moderator-confirmed helpful reports required for the Community Guardian chip. */
const GUARDIAN_THRESHOLD = 3;

/**
 * Active chip kinds for a user, in render/priority order. Mirrors the iOS
 * priority: restricted → coach → age → reputation → founding.
 */
export function deriveBadges(
  isCoach: boolean,
  flags: BadgeFlags | null
): BadgeKind[] {
  const chips: BadgeKind[] = [];
  const restricted = !!flags?.isDmRestricted;

  if (restricted) chips.push("restricted");
  if (isCoach) chips.push("coach");
  if (flags?.isDirector) chips.push("director");
  if (flags?.isBlogger) chips.push("blogger");

  if (flags?.ageBand === "teen") chips.push("teen");
  else if (flags?.isAdultAttested) chips.push("adult");

  const created = flags?.createdAt ? Date.parse(flags.createdAt) : NaN;

  if (!restricted) {
    if (flags?.isTrustedMember) chips.push("trusted");
    else if (!Number.isNaN(created) && Date.now() - created >= ESTABLISHED_MS)
      chips.push("established");
    if ((flags?.helpfulReportCount ?? 0) >= GUARDIAN_THRESHOLD)
      chips.push("guardian");
  }

  if (!Number.isNaN(created) && created < FOUNDING_CUTOFF) chips.push("founding");

  return chips;
}
