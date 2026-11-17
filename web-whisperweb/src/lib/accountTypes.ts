import { supabase } from "@/lib/supabase";

/**
 * Account types — the Instagram-style split. Everyone starts personal;
 * professional accounts (creator or business) wear a public category label,
 * can share contact details, and get pointed at the pro dashboards.
 *
 * Chosen at signup (Auth → stash → onboarding applies it) and switchable
 * anytime from Settings → Account type. Migration: supabase/account-types.sql.
 */

export type AccountType = "personal" | "creator" | "business";

export interface AccountTypeMeta {
  id: AccountType;
  label: string;
  short: string;
  blurb: string;
}

export const ACCOUNT_TYPES: AccountTypeMeta[] = [
  {
    id: "personal",
    label: "Personal",
    short: "Just you",
    blurb: "Post, follow, chat — the standard Whisper account.",
  },
  {
    id: "creator",
    label: "Creator",
    short: "Public figure",
    blurb: "Content makers, athletes, coaches & influencers — best with Creator Studio.",
  },
  {
    id: "business",
    label: "Business",
    short: "Company or brand",
    blurb: "Brands, shops & services — unlocks the Business Suite mindset (ads, hiring, Business+).",
  },
];

/**
 * Creator niches — the sub-categories of the Creator badge. The chosen niche is
 * stored as `professional_category` and rendered as the light-gray line under
 * the name on the profile (Instagram's "Digital creator" / "Athlete" line).
 * Free text is still allowed in Settings; these are the curated picks.
 */
export const CREATOR_NICHES: string[] = [
  "Athlete",
  "Fitness",
  "Nutrition",
  "Wellness",
  "Lifestyle",
  "Comedy",
  "Music",
  "Fashion",
  "Beauty",
  "Food",
  "Travel",
  "Gaming",
  "Art & design",
  "Photography",
  "Education",
  "Business",
  "Tech",
  "Writer",
  "Public figure",
  "Digital creator",
];

/** Category suggestions professional (creator) accounts pick from. */
export const CREATOR_CATEGORIES: string[] = CREATOR_NICHES;

export const BUSINESS_CATEGORIES: string[] = [
  "Local business",
  "Brand",
  "Gym & fitness",
  "Restaurant",
  "Retail",
  "Agency",
  "Software",
  "Media & entertainment",
];

/** What a professional account row carries. */
export interface AccountTypePatch {
  accountType: AccountType;
  category?: string;
  contactEmail?: string;
  contactPhone?: string;
}

const PENDING_KEY = "whisper_pending_account_type";

/** Signup stashes the choice; onboarding applies it when the profile row is born. */
export function stashPendingAccountType(patch: AccountTypePatch): void {
  try {
    localStorage.setItem(PENDING_KEY, JSON.stringify(patch));
  } catch {
    // Storage blocked — the user can still switch in Settings.
  }
}

export function readPendingAccountType(): AccountTypePatch | null {
  try {
    const raw = localStorage.getItem(PENDING_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as AccountTypePatch;
    if (
      parsed.accountType === "personal" ||
      parsed.accountType === "creator" ||
      parsed.accountType === "business"
    ) {
      return parsed;
    }
    return null;
  } catch {
    return null;
  }
}

export function clearPendingAccountType(): void {
  try {
    localStorage.removeItem(PENDING_KEY);
  } catch {
    // Nothing to clear.
  }
}

/**
 * Saves the account type onto the profile row. Throws a friendly message
 * when the account-types migration hasn't been run yet.
 */
export async function saveAccountType(
  userId: string,
  patch: AccountTypePatch
): Promise<void> {
  const professional = patch.accountType !== "personal";
  const { error } = await supabase
    .from("whisper_profiles")
    .update({
      account_type: patch.accountType,
      professional_category: professional ? patch.category?.trim() || null : null,
      contact_email: professional ? patch.contactEmail?.trim() || null : null,
      contact_phone: professional ? patch.contactPhone?.trim() || null : null,
      updated_at: new Date().toISOString(),
    })
    .eq("user_id", userId);
  if (error) {
    if (error.code === "42703" || /account_type|professional_category|contact_/.test(error.message ?? "")) {
      throw new Error("Run supabase/account-types.sql once to unlock account types.");
    }
    throw new Error("Couldn't save your account type. Try again.");
  }
}

/** Human label for the current type. */
export function accountTypeLabel(type: string | null | undefined): string {
  if (type === "creator") return "Creator account";
  if (type === "business") return "Business account";
  return "Personal account";
}
