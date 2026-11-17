import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";

import { useAuth } from "@/hooks/useAuth";
import { fetchActivity } from "@/lib/api";
import { getActivitySeenAt } from "@/lib/settings";

/**
 * Count of activity events newer than the last time the user opened the
 * Notifications screen. Drives the nav badge dot.
 */
export function useUnreadActivity(): number {
  const { user } = useAuth();
  const [seenAt, setSeenAt] = useState<number>(getActivitySeenAt);

  useEffect(() => {
    const sync = (): void => setSeenAt(getActivitySeenAt());
    window.addEventListener("whisper-settings", sync);
    window.addEventListener("storage", sync);
    return () => {
      window.removeEventListener("whisper-settings", sync);
      window.removeEventListener("storage", sync);
    };
  }, []);

  const activityQuery = useQuery({
    queryKey: ["activity", user?.id],
    queryFn: () => fetchActivity(user!.id),
    enabled: !!user,
    refetchInterval: 60_000,
  });

  const events = activityQuery.data ?? [];
  return events.filter(
    (e) => new Date(e.createdAt ?? 0).getTime() > seenAt
  ).length;
}
