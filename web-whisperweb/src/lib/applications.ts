import { supabase } from "@/lib/supabase";

import { CREATOR_NICHES } from "@/lib/accountTypes";

/**
 * Web port of the iOS special-account application services
 * (`WhisperCoachService`, `WhisperVerificationService`). Talks to the exact
 * same Supabase tables so an application submitted on the web shows up in the
 * iOS mod dashboard and vice-versa.
 *
 * Two paid badges exist: Coach and Creator (the verified check). The retired
 * Athlete badge is now a Creator NICHE — see `CREATOR_NICHES`.
 */

export type SpecialRole = "coach" | "verified";

export type ApplicationStatus = "none" | "pending" | "approved" | "denied";

export interface RoleState {
  /** Latest application row status for the signed-in user. */
  application: ApplicationStatus;
  /** True once the role flag is live on the user's profile. */
  active: boolean;
}

const APPLICATION_TABLE: Record<SpecialRole, string> = {
  coach: "whisper_coach_applications",
  verified: "whisper_verification_requests",
};

function normalizeStatus(raw: string | undefined | null): ApplicationStatus {
  if (raw === "pending" || raw === "approved" || raw === "denied") return raw;
  return "none";
}

/**
 * Resolve the signed-in user's application + active state for one role.
 *
 * `active` is true ONLY when there's a paid, active subscription in
 * `whisper_badge_members` — not when the profile flag is set. Under the
 * paid-badge flow the profile flags are flipped by the Stripe webhook after
 * payment, so checking the ledger (not the flags) is what gates the payment
 * screen vs. the "badge is live" screen.
 */
export async function fetchRoleState(
  userId: string,
  role: SpecialRole
): Promise<RoleState> {
  const [appRes, badgeRes] = await Promise.all([
    supabase
      .from(APPLICATION_TABLE[role])
      .select("status")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
    supabase
      .from("whisper_badge_members")
      .select("status")
      .eq("user_id", userId)
      .eq("role", role)
      .eq("status", "active")
      .limit(1)
      .maybeSingle(),
  ]);

  const active = !!(badgeRes.data as { status?: string } | null)?.status;
  return {
    application: normalizeStatus(
      (appRes.data as { status?: string } | null)?.status
    ),
    active,
  };
}

/** Both role states at once — used by the Settings entry points. */
export async function fetchAllRoleStates(
  userId: string
): Promise<Record<SpecialRole, RoleState>> {
  const [coach, verified] = await Promise.all([
    fetchRoleState(userId, "coach"),
    fetchRoleState(userId, "verified"),
  ]);
  return { coach, verified };
}

// MARK: - Creator (verified) application (mirrors WhisperVerificationService.submit)

/**
 * The Creator badge's niches, as application categories. The label is stored
 * verbatim in `category` so approval can copy it straight onto the profile's
 * `professional_category` (the gray line under the name).
 */
export const VERIFICATION_CATEGORIES: { id: string; label: string }[] = [
  ...CREATOR_NICHES.map((niche) => ({ id: niche, label: niche })),
  { id: "Brand", label: "Brand" },
  { id: "Media / publisher", label: "Media / publisher" },
];

export async function submitVerificationRequest(input: {
  userId: string;
  username: string;
  email: string;
  fullName: string;
  category: string;
  reason: string;
  links: string;
  followers: number;
}): Promise<void> {
  const { error } = await supabase.from("whisper_verification_requests").insert({
    user_id: input.userId,
    username: input.username,
    email: input.email || null,
    full_name: input.fullName,
    category: input.category,
    reason: input.reason,
    links: input.links || null,
    followers: input.followers,
    status: "pending",
  });
  if (error) throw error;
}
