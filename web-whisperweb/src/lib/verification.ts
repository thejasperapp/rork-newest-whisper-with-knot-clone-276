import { supabase } from "@/lib/supabase";

/**
 * Web port of the iOS `UserVerificationService`. The checkmark next to a
 * username is NOT stored on `whisper_profiles` — it lives on the `profiles`
 * row (and, for legacy accounts, the `usernames` reservation table) keyed by
 * username. Each row carries `is_verified` / `is_moderator` / `is_admin` /
 * `is_owner`, and the highest-rank flag wins. We resolve by username so a user
 * wears the exact same checkmark on iOS and web.
 */

export type VerificationBadge =
  | "none"
  | "verified"
  | "moderator"
  | "admin"
  | "owner";

export const RANK: Record<VerificationBadge, number> = {
  none: 0,
  verified: 1,
  moderator: 2,
  admin: 3,
  owner: 4,
};

interface BadgeRow {
  username: string | null;
  is_verified: boolean | null;
  is_moderator: boolean | null;
  is_admin: boolean | null;
  is_owner: boolean | null;
}

function rowToBadge(r: BadgeRow): VerificationBadge {
  if (r.is_owner) return "owner";
  if (r.is_admin) return "admin";
  if (r.is_moderator) return "moderator";
  if (r.is_verified) return "verified";
  return "none";
}

/**
 * Batch-fetch verification badges for a set of usernames, keyed by the
 * lowercased username. Best-effort — missing tables/columns simply yield no
 * badge rather than throwing.
 */
export async function fetchVerificationBadges(
  usernames: string[]
): Promise<Record<string, VerificationBadge>> {
  const list = Array.from(
    new Set(
      usernames
        .map((u) => u?.toLowerCase().trim())
        .filter((u): u is string => !!u)
    )
  );
  if (list.length === 0) return {};

  const map: Record<string, VerificationBadge> = {};
  const cols = "username,is_verified,is_moderator,is_admin,is_owner";

  // Primary source: `profiles` row (carries username + badge flags).
  try {
    const { data } = await supabase
      .from("profiles")
      .select(cols)
      .in("username", list);
    for (const r of (data as BadgeRow[] | null) ?? []) {
      const name = r.username?.toLowerCase();
      if (!name) continue;
      map[name] = rowToBadge(r);
    }
  } catch {
    // Fall through to the legacy `usernames` table.
  }

  // Secondary: legacy badges still on the `usernames` reservation table.
  // Take whichever badge has the higher rank so neither source can downgrade
  // the other (matches iOS).
  try {
    const { data } = await supabase
      .from("usernames")
      .select(cols)
      .in("username", list);
    for (const r of (data as BadgeRow[] | null) ?? []) {
      const name = r.username?.toLowerCase();
      if (!name) continue;
      const next = rowToBadge(r);
      const existing = map[name] ?? "none";
      if (RANK[next] > RANK[existing]) map[name] = next;
    }
  } catch {
    // Badges are non-critical.
  }

  return map;
}
