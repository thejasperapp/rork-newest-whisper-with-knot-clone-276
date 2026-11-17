import {
  campusPack,
  campusCommunity,
  gymCommunity,
  type Community,
} from "./communities";

/**
 * Geo-aware community suggestions — the web mirror of the iOS "Near you"
 * rail. Uses the browser's geolocation plus OpenStreetMap's public Overpass
 * API (no key) to find colleges and gyms around the user, then builds the
 * same client-side communities iOS builds (identical ids/names so caption
 * matching agrees across platforms).
 *
 * Discoveries are ADDITIVE and PER-ACCOUNT: every college and gym you've
 * been near stays on YOUR list (deduped, newest finds first). A new scan
 * ADDS hubs — it never replaces the ones you already unlocked — and one
 * account's scan can't touch another account's list. The scan result is
 * considered fresh for 24h; the unlocked hubs themselves never expire.
 */

const LEGACY_KEY = "whisper_nearby_communities_v1";
const MAX_CAMPUSES = 6;
const MAX_GYMS = 8;

interface CacheEntry {
  kind: "campus" | "gym";
  name: string;
  origin: string;
  /** Street address of the real place (optional — old caches decode fine). */
  address?: string;
}
interface NearbyCache {
  stamp: number;
  entries: CacheEntry[];
}

interface OverpassElement {
  type: string;
  lat?: number;
  lon?: number;
  center?: { lat: number; lon: number };
  tags?: Record<string, string>;
}

const slugOf = (name: string): string =>
  name.toLowerCase().replace(/[^a-z0-9]+/g, "");

function cacheKey(userId?: string | null): string {
  return `whisper_nearby_communities_v2_${(userId ?? "guest").toLowerCase()}`;
}

function readCache(userId?: string | null): NearbyCache | null {
  try {
    const raw = localStorage.getItem(cacheKey(userId));
    if (raw) return JSON.parse(raw) as NearbyCache;
    // One-time migration from the old shared, replace-on-scan cache — its
    // entries carry the same shape. stamp 0 marks the scan itself stale.
    const legacy = localStorage.getItem(LEGACY_KEY);
    if (!legacy) return null;
    const parsed = JSON.parse(legacy) as NearbyCache;
    if (!parsed.entries?.length) return null;
    return { stamp: 0, entries: parsed.entries };
  } catch {
    return null;
  }
}

function writeCache(userId: string | null | undefined, cache: NearbyCache): void {
  try {
    localStorage.setItem(cacheKey(userId), JSON.stringify(cache));
  } catch {
    // storage full/blocked — the live result still renders this session
  }
}

/** Add-or-refresh merge: fresh finds first (with updated distance labels),
 *  earlier finds kept, nothing ever removed. Capped per kind. */
function mergeEntries(existing: CacheEntry[], found: CacheEntry[]): CacheEntry[] {
  const seen = new Set<string>();
  const merged: CacheEntry[] = [];
  for (const entry of [...found, ...existing]) {
    if (!entry?.name) continue;
    const key = `${entry.kind}:${slugOf(entry.name)}`;
    if (seen.has(key)) continue;
    seen.add(key);
    merged.push(entry);
  }
  return [
    ...merged.filter((e) => e.kind === "campus").slice(0, MAX_CAMPUSES),
    ...merged.filter((e) => e.kind === "gym").slice(0, MAX_GYMS),
  ];
}

/** Renderable hubs: the field pack unlocked by the newest campus, one hub
 *  per discovered campus, one crew per discovered gym. */
function buildCommunities(entries: CacheEntry[]): Community[] {
  const out: Community[] = [];
  const campuses = entries.filter((e) => e.kind === "campus");
  if (campuses.length > 0) {
    out.push(...campusPack(campuses[0].name, campuses[0].address));
  }
  for (const c of campuses) {
    const hub = campusCommunity(c.name, undefined, c.address);
    if (c.origin) hub.origin = c.origin;
    out.push(hub);
  }
  for (const g of entries) {
    if (g.kind !== "gym") continue;
    const gym = gymCommunity(g.name, undefined, g.address);
    gym.origin = g.origin || gym.origin;
    out.push(gym);
  }
  return out;
}

/** Rebuilds this account's unlocked hubs — instant render on revisit. */
export function loadCachedNearby(userId?: string | null): Community[] | null {
  const cache = readCache(userId);
  if (!cache?.entries?.length) return null;
  const out = buildCommunities(cache.entries);
  return out.length > 0 ? out : null;
}

function haversineMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6_371_000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

function formatDistance(meters: number): string {
  return meters < 1000 ? `${Math.round(meters)} m away` : `${(meters / 1000).toFixed(1)} km away`;
}

/** Short human street address from OSM `addr:*` tags ("123 Main St, Cambridge"). */
function addressOf(tags?: Record<string, string>): string | undefined {
  if (!tags) return undefined;
  const street = tags["addr:street"];
  const num = tags["addr:housenumber"];
  const city = tags["addr:city"];
  const parts: string[] = [];
  if (street) parts.push(num ? `${num} ${street}` : street);
  if (city) parts.push(city);
  return parts.length > 0 ? parts.join(", ") : undefined;
}

/** Live lookup — asks for location (may prompt), queries Overpass, and
 *  MERGES the finds into this account's accumulated hubs. */
export async function fetchNearbyCommunities(
  userId?: string | null
): Promise<Community[]> {
  const pos = await new Promise<GeolocationPosition>((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(new Error("no_geolocation"));
      return;
    }
    navigator.geolocation.getCurrentPosition(resolve, reject, {
      timeout: 12_000,
      maximumAge: 600_000,
    });
  });
  const { latitude: lat, longitude: lon } = pos.coords;

  const query = `[out:json][timeout:10];(
node["amenity"~"university|college"](around:12000,${lat},${lon});
way["amenity"~"university|college"](around:12000,${lat},${lon});
node["leisure"="fitness_centre"](around:8000,${lat},${lon});
way["leisure"="fitness_centre"](around:8000,${lat},${lon});
);out center tags 60;`;

  const res = await fetch("https://overpass-api.de/api/interpreter", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: "data=" + encodeURIComponent(query),
    signal: AbortSignal.timeout(12_000),
  });
  if (!res.ok) throw new Error("overpass_failed");
  const data = (await res.json()) as { elements?: OverpassElement[] };
  const elements = data.elements ?? [];

  const campuses: { name: string; dist: number; address?: string }[] = [];
  const seenCampuses = new Set<string>();
  const gyms: { name: string; dist: number; address?: string }[] = [];
  const seenGyms = new Set<string>();

  for (const el of elements) {
    const name = el.tags?.name?.trim();
    if (!name) continue;
    const elat = el.lat ?? el.center?.lat;
    const elon = el.lon ?? el.center?.lon;
    if (elat == null || elon == null) continue;
    const dist = haversineMeters(lat, lon, elat, elon);
    const amenity = el.tags?.amenity ?? "";
    if (amenity === "university" || amenity === "college") {
      const key = slugOf(name);
      if (seenCampuses.has(key)) continue;
      seenCampuses.add(key);
      campuses.push({ name, dist, address: addressOf(el.tags) });
    } else if (el.tags?.leisure === "fitness_centre") {
      const key = slugOf(name);
      if (seenGyms.has(key)) continue;
      seenGyms.add(key);
      gyms.push({ name, dist, address: addressOf(el.tags) });
    }
  }
  campuses.sort((a, b) => a.dist - b.dist);
  gyms.sort((a, b) => a.dist - b.dist);

  // Up to 3 nearest distinct colleges + 3 nearest distinct gyms PER SCAN —
  // each merges into the account's list, so places accumulate over time.
  const found: CacheEntry[] = [
    ...campuses.slice(0, 3).map((c) => ({
      kind: "campus" as const,
      name: c.name,
      origin: formatDistance(c.dist),
      address: c.address,
    })),
    ...gyms.slice(0, 3).map((g) => ({
      kind: "gym" as const,
      name: g.name,
      origin: formatDistance(g.dist),
      address: g.address,
    })),
  ];

  const merged = mergeEntries(readCache(userId)?.entries ?? [], found);
  writeCache(userId, { stamp: Date.now(), entries: merged });
  return buildCommunities(merged);
}
