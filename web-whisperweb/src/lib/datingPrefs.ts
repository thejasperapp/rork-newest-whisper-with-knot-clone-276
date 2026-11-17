import { supabase } from "@/lib/supabase";

/**
 * Dating preferences — who you want to meet and how far you'll look.
 * Stored device-local for instant reads and synced to `whisper_dating_prefs`
 * (coarse coordinates only: rounded to ~1 km before they ever leave the
 * device). Mirrors iOS `WhisperDatingPrefs` exactly.
 */

export interface DatingPrefs {
  gender: string | null; // woman | man | nonbinary
  seeking: string[]; // empty = everyone
  age: number | null;
  ageMin: number;
  ageMax: number;
  radiusKm: number; // 0 = anywhere
  intent: string | null; // relationship | casual | friends | open
  lat: number | null;
  lng: number | null;
  cityLabel: string | null;
  /** Round 77 — MY lifestyle answers by topic (smoking · drinking · kids · faith · pets). Mirrors iOS. */
  lifestyle: Record<string, string>;
  /** Round 77 — DEALBREAKERS: topic → the answers I accept (enforced server-side in whisper_dating_fits). */
  dealbreakers: Record<string, string[]>;
}

export const DEFAULT_DATING_PREFS: DatingPrefs = {
  gender: null,
  seeking: [],
  age: null,
  ageMin: 18,
  ageMax: 99,
  radiusKm: 50,
  intent: null,
  lat: null,
  lng: null,
  cityLabel: null,
  lifestyle: {},
  dealbreakers: {},
};

/** Lifestyle topics + answer options — identical ids on iOS + SQL. */
export const LIFESTYLE_TOPICS: { id: string; label: string; options: { id: string; label: string }[] }[] = [
  { id: "smoking", label: "Smoking", options: [{ id: "never", label: "Never" }, { id: "sometimes", label: "Sometimes" }, { id: "regular", label: "Regularly" }] },
  { id: "drinking", label: "Drinking", options: [{ id: "never", label: "Never" }, { id: "social", label: "Socially" }, { id: "often", label: "Often" }] },
  { id: "kids", label: "Kids", options: [{ id: "have", label: "Have kids" }, { id: "want", label: "Want kids" }, { id: "dont_want", label: "Don't want" }, { id: "open", label: "Open" }] },
  { id: "faith", label: "Faith", options: [{ id: "important", label: "Important to me" }, { id: "spiritual", label: "Spiritual" }, { id: "not_religious", label: "Not religious" }, { id: "private", label: "Rather not say" }] },
  { id: "pets", label: "Pets", options: [{ id: "have", label: "Have pets" }, { id: "love", label: "Love them" }, { id: "allergic", label: "Allergic" }, { id: "none", label: "No pets" }] },
];

/** Does THEIR lifestyle pass MY dealbreakers? Same rule as SQL/iOS: only an answered topic outside the accepted set fails. */
export function dealbreakersAccept(mine: DatingPrefs, theirLifestyle: Record<string, string> | null | undefined): boolean {
  for (const [topic, accepted] of Object.entries(mine.dealbreakers ?? {})) {
    if (!accepted || accepted.length === 0) continue;
    const theirs = theirLifestyle?.[topic];
    if (theirs && !accepted.includes(theirs)) return false;
  }
  return true;
}

export const GENDER_OPTIONS: { id: string; label: string }[] = [
  { id: "woman", label: "Woman" },
  { id: "man", label: "Man" },
  { id: "nonbinary", label: "Non-binary" },
];

export const SEEKING_OPTIONS: { id: string; label: string }[] = [
  { id: "woman", label: "Women" },
  { id: "man", label: "Men" },
  { id: "nonbinary", label: "Non-binary" },
];

export const INTENT_OPTIONS: { id: string; label: string; emoji: string }[] = [
  { id: "relationship", label: "A relationship", emoji: "💍" },
  { id: "casual", label: "Something casual", emoji: "🍸" },
  { id: "friends", label: "Friends first", emoji: "🤝" },
  { id: "open", label: "Open to anything", emoji: "✨" },
];

/** The distance stops on the slider — last stop is "anywhere". */
export const RADIUS_STOPS: number[] = [5, 10, 25, 50, 100, 250, 0];

export function intentLabel(id: string | null | undefined): string | null {
  return INTENT_OPTIONS.find((o) => o.id === id)?.label ?? null;
}

export function prefsHasLocation(p: DatingPrefs): boolean {
  return p.lat != null && p.lng != null;
}

export function prefsIsConfigured(p: DatingPrefs): boolean {
  return !!p.gender || p.seeking.length > 0 || p.age != null || !!p.intent || prefsHasLocation(p);
}

/** "Within 25 km · 24–34 · Women · A relationship" */
export function prefsSummaryLine(p: DatingPrefs): string {
  const parts: string[] = [];
  parts.push(p.radiusKm <= 0 ? "Anywhere" : `Within ${p.radiusKm} km`);
  if (p.ageMin > 18 || p.ageMax < 99) parts.push(`${p.ageMin}–${p.ageMax}`);
  if (p.seeking.length === 0) {
    parts.push("Everyone");
  } else {
    parts.push(
      p.seeking
        .map((id) => SEEKING_OPTIONS.find((o) => o.id === id)?.label)
        .filter((x): x is string => !!x)
        .join(" & ")
    );
  }
  const intent = intentLabel(p.intent);
  if (intent) parts.push(intent);
  return parts.join(" · ");
}

const key = (userId: string): string => `whisper-dating-prefs:${userId.toLowerCase()}`;
const nearbyOnlyKey = (userId: string): string => `whisper-dating-nearby-only:${userId.toLowerCase()}`;

/** Instant local read — every filter and the queue snapshot run off this. */
export function loadDatingPrefs(userId: string): DatingPrefs {
  try {
    const raw = localStorage.getItem(key(userId));
    if (!raw) return { ...DEFAULT_DATING_PREFS };
    const parsed = JSON.parse(raw) as Partial<DatingPrefs>;
    return { ...DEFAULT_DATING_PREFS, ...parsed, seeking: Array.isArray(parsed.seeking) ? parsed.seeking : [] };
  } catch {
    return { ...DEFAULT_DATING_PREFS };
  }
}

/** "Nearby only" hub filter — on by default once a location is saved. */
export function loadNearbyOnly(userId: string): boolean {
  try {
    const raw = localStorage.getItem(nearbyOnlyKey(userId));
    return raw == null ? true : raw === "1";
  } catch {
    return true;
  }
}

export function saveNearbyOnly(userId: string, on: boolean): void {
  try {
    localStorage.setItem(nearbyOnlyKey(userId), on ? "1" : "0");
  } catch {
    // Storage blocked — the toggle just won't persist.
  }
}

function clean(p: DatingPrefs): DatingPrefs {
  const ageMin = Math.max(18, Math.min(p.ageMin, 99));
  const ageMax = Math.max(ageMin, Math.min(p.ageMax, 99));
  return {
    ...p,
    ageMin,
    ageMax,
    age: p.age == null ? null : Math.max(18, Math.min(p.age, 99)),
    // Coarse coordinates — ~1 km cells; the exact fix never leaves the device.
    lat: p.lat == null ? null : Math.round(p.lat * 100) / 100,
    lng: p.lng == null ? null : Math.round(p.lng * 100) / 100,
  };
}

/** Saves locally ALWAYS + upserts to Supabase best-effort. */
export async function saveDatingPrefs(userId: string, username: string | null, prefs: DatingPrefs): Promise<void> {
  const p = clean(prefs);
  try {
    localStorage.setItem(key(userId), JSON.stringify(p));
  } catch {
    // Storage blocked — the cloud copy still saves below.
  }
  const base = {
    user_id: userId,
    username,
    gender: p.gender,
    seeking: p.seeking,
    age: p.age,
    age_min: p.ageMin,
    age_max: p.ageMax,
    radius_km: p.radiusKm,
    intent: p.intent,
    lat: p.lat,
    lng: p.lng,
    city_label: p.cityLabel,
    updated_at: new Date().toISOString(),
  };
  try {
    const { error } = await supabase
      .from("whisper_dating_prefs")
      .upsert({ ...base, lifestyle: p.lifestyle ?? {}, dealbreakers: p.dealbreakers ?? {} });
    if (error) {
      // Pre-dating-v2 databases lack the lifestyle columns — save the rest.
      await supabase.from("whisper_dating_prefs").upsert(base);
    }
  } catch {
    // Table not migrated yet — the device copy still powers the hub filters.
  }
}

/** Cloud pull (best-effort) — a saved row wins over an empty device. */
export async function syncDatingPrefsFromCloud(userId: string): Promise<DatingPrefs> {
  try {
    const { data } = await supabase
      .from("whisper_dating_prefs")
      .select("*")
      .eq("user_id", userId)
      .maybeSingle();
    if (data) {
      const r = data as {
        gender: string | null;
        seeking: string[] | null;
        age: number | null;
        age_min: number | null;
        age_max: number | null;
        radius_km: number | null;
        intent: string | null;
        lat: number | null;
        lng: number | null;
        city_label: string | null;
        lifestyle?: Record<string, string> | null;
        dealbreakers?: Record<string, string[]> | null;
      };
      const prefs: DatingPrefs = {
        gender: r.gender,
        seeking: r.seeking ?? [],
        age: r.age,
        ageMin: r.age_min ?? 18,
        ageMax: r.age_max ?? 99,
        radiusKm: r.radius_km ?? 50,
        intent: r.intent,
        lat: r.lat,
        lng: r.lng,
        cityLabel: r.city_label,
        lifestyle: r.lifestyle ?? {},
        dealbreakers: r.dealbreakers ?? {},
      };
      try {
        localStorage.setItem(key(userId), JSON.stringify(prefs));
      } catch {
        // ignore
      }
      return prefs;
    }
  } catch {
    // Not migrated — local copy wins.
  }
  return loadDatingPrefs(userId);
}

/** One person inside my radius — coarse distance only. */
export interface NearbyPerson {
  user_id: string;
  username: string | null;
  distance_km: number | null;
  age: number | null;
  gender: string | null;
  intent: string | null;
  city_label: string | null;
}

export function nearbyDistanceLabel(p: NearbyPerson): string | null {
  if (p.distance_km == null) return null;
  if (p.distance_km < 1) return "under 1 km away";
  return `${Math.round(p.distance_km)} km away`;
}

/** People inside my radius (mutual fit) — empty until migrated or until prefs are saved. */
export async function fetchNearbyDaters(): Promise<NearbyPerson[]> {
  try {
    const { data, error } = await supabase.rpc("whisper_dating_nearby");
    if (error || !Array.isArray(data)) return [];
    return (data as NearbyPerson[]).map((r) => ({
      ...r,
      user_id: String(r.user_id).toLowerCase(),
      distance_km: r.distance_km == null ? null : Number(r.distance_km),
    }));
  } catch {
    return [];
  }
}

/** Coarse device location + a "City, Region" label (BigDataCloud, no key). */
export async function resolveCoarseLocation(): Promise<{ lat: number; lng: number; label: string | null }> {
  const pos = await new Promise<GeolocationPosition>((resolve, reject) => {
    if (!("geolocation" in navigator)) {
      reject(new Error("Geolocation unavailable"));
      return;
    }
    navigator.geolocation.getCurrentPosition(resolve, reject, {
      enableHighAccuracy: false,
      timeout: 10_000,
      maximumAge: 5 * 60 * 1000,
    });
  });
  const lat = Math.round(pos.coords.latitude * 100) / 100;
  const lng = Math.round(pos.coords.longitude * 100) / 100;
  let label: string | null = null;
  try {
    const res = await fetch(
      `https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${pos.coords.latitude}&longitude=${pos.coords.longitude}&localityLanguage=en`
    );
    if (res.ok) {
      const j = (await res.json()) as { city?: string; locality?: string; principalSubdivision?: string };
      const city = j.city || j.locality || "";
      const region = j.principalSubdivision || "";
      label = [city, region].filter(Boolean).join(", ") || null;
    }
  } catch {
    label = null;
  }
  return { lat, lng, label };
}
