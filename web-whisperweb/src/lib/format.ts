/** Short relative time, e.g. "now", "5m", "3h", "2d", "4w". */
export function timeAgo(iso: string | null | undefined): string {
  if (!iso) return "";
  const then = new Date(iso).getTime();
  if (Number.isNaN(then)) return "";
  const secs = Math.max(0, Math.floor((Date.now() - then) / 1000));
  if (secs < 45) return "now";
  const mins = Math.floor(secs / 60);
  if (mins < 60) return `${mins}m`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d`;
  const weeks = Math.floor(days / 7);
  if (weeks < 52) return `${weeks}w`;
  return `${Math.floor(days / 365)}y`;
}

/** Clock-style timestamp for chat bubbles, e.g. "14:05". */
export function clockTime(iso: string | null | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

/** Compact count formatter matching Threads/iOS: 29K, 3.3K, 457, 99. */
export function compactCount(n: number): string {
  if (n >= 1_000_000) {
    const v = n / 1_000_000;
    return v >= 10 ? `${Math.round(v)}M` : `${v.toFixed(1)}M`;
  }
  if (n >= 1_000) {
    const v = n / 1_000;
    return v >= 10 ? `${Math.round(v)}K` : `${v.toFixed(1)}K`;
  }
  return `${n}`;
}

/** Deterministic accent hue derived from a string (for avatar fallbacks). */
export function hueFromString(value: string): number {
  let hash = 0;
  for (let i = 0; i < value.length; i += 1) {
    hash = value.charCodeAt(i) + ((hash << 5) - hash);
  }
  return Math.abs(hash) % 360;
}

/** First grapheme/letter of a name, uppercased, for monogram avatars. */
export function initial(name: string | null | undefined): string {
  const trimmed = (name ?? "").trim();
  return trimmed ? trimmed[0]!.toUpperCase() : "?";
}
