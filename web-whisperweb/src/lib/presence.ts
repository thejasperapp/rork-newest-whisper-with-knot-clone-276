import { supabase } from "@/lib/supabase";

/** Window (ms) within which a user counts as "Active now". */
const ACTIVE_WINDOW_MS = 2 * 60 * 1000;

/**
 * Publish my own presence heartbeat — mirrors the iOS inbox heartbeat so
 * both platforms light up the same green dot.
 */
export async function heartbeatPresence(userId: string): Promise<void> {
  try {
    await supabase
      .from("whisper_presence")
      .upsert(
        { user_id: userId, last_seen_at: new Date().toISOString() },
        { onConflict: "user_id" },
      );
  } catch {
    /* best effort — presence is cosmetic */
  }
}

/** Fetch last-seen timestamps for a set of users: uid → ISO string. */
export async function fetchPresence(userIds: string[]): Promise<Record<string, string>> {
  const unique = [...new Set(userIds)].filter(Boolean);
  if (unique.length === 0) return {};
  try {
    const { data } = await supabase
      .from("whisper_presence")
      .select("user_id, last_seen_at")
      .in("user_id", unique);
    const map: Record<string, string> = {};
    for (const row of (data ?? []) as { user_id: string; last_seen_at: string }[]) {
      map[row.user_id] = row.last_seen_at;
    }
    return map;
  } catch {
    return {};
  }
}

export function isActiveNow(lastSeenAt: string | null | undefined): boolean {
  if (!lastSeenAt) return false;
  const t = new Date(lastSeenAt).getTime();
  return Number.isFinite(t) && Date.now() - t < ACTIVE_WINDOW_MS;
}

/** "Active now" / "Active 5m ago" / "Active 2h ago" — null when stale (>8h). */
export function presenceLabel(lastSeenAt: string | null | undefined): string | null {
  if (!lastSeenAt) return null;
  const t = new Date(lastSeenAt).getTime();
  if (!Number.isFinite(t)) return null;
  const diff = Date.now() - t;
  if (diff < ACTIVE_WINDOW_MS) return "Active now";
  const mins = Math.floor(diff / 60_000);
  if (mins < 60) return `Active ${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours <= 8) return `Active ${hours}h ago`;
  return null;
}
