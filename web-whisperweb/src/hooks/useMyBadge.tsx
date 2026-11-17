import { useQuery } from "@tanstack/react-query";

import { useAuth } from "@/hooks/useAuth";
import {
  fetchVerificationBadges,
  type VerificationBadge,
} from "@/lib/verification";

/**
 * Resolves the signed-in user's verification badge (verified / moderator /
 * admin / owner) exactly like iOS — keyed by username on the `profiles` /
 * `usernames` tables, with a fallback to the `whisper_profiles.is_verified`
 * flag. Used to gate verified-only surfaces like the Creator Studio.
 */
export function useMyBadge(): VerificationBadge {
  const { profile } = useAuth();
  const username = profile?.username;

  const query = useQuery({
    queryKey: ["my-verification-badge", username],
    queryFn: () => fetchVerificationBadges([username!]),
    enabled: !!username,
    staleTime: 5 * 60 * 1000,
  });

  return (
    (username ? query.data?.[username.toLowerCase()] : undefined) ??
    (profile?.is_verified ? "verified" : "none")
  );
}
