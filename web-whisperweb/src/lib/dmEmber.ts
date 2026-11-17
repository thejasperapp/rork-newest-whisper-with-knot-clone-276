import { resolveCurrentCity } from "@/lib/location";
import type { Verdict } from "@/lib/ember";

/**
 * Web ports of the iOS Whisper DM embed wire formats so the web app renders
 * Ember answers, fact-check verdicts and nearby-restaurant maps inline in a
 * DM thread instead of leaking the raw `::whisper-…::{json}` payload. The
 * prefixes match the Swift `WhisperEmberAnswerEmbed` / `WhisperFactCheckEmbed`
 * / `WhisperMapEmbed` enums exactly so iOS and web stay interoperable.
 */

/**
 * The deployed `whisper_messages.body` column has a
 * `check (char_length(body) <= 4000)` constraint. Verbose Ember embeds (a long
 * answer/explanation plus several source URLs serialised to JSON) can blow past
 * that, and the insert is rejected — which is why an Ember tool would show
 * optimistically then vanish on refresh (it never persisted). We keep every
 * embed body comfortably under the limit so the row always saves.
 */
const MAX_DM_BODY = 3800;

/** Trims `text` to at most `max` characters, appending an ellipsis when cut. */
function clampText(text: string, max: number): string {
  if (max <= 0) return "\u2026";
  if (text.length <= max) return text;
  return text.slice(0, Math.max(1, max - 1)).trimEnd() + "\u2026";
}

// MARK: - Ember answer (`/ember <question>` shared into chat)

const ANSWER_PREFIX = "::whisper-ember-answer-v1::";

export interface EmberAnswerPayload {
  id: string;
  question: string;
  answer: string;
  sources: string[];
  tldr: string | null;
}

export function encodeEmberAnswer(p: EmberAnswerPayload): string {
  let payload: EmberAnswerPayload = { ...p, sources: p.sources.slice(0, 4) };
  let out = ANSWER_PREFIX + JSON.stringify(payload);
  if (out.length <= MAX_DM_BODY) return out;
  payload = { ...payload, sources: payload.sources.slice(0, 3) };
  out = ANSWER_PREFIX + JSON.stringify(payload);
  if (out.length > MAX_DM_BODY) {
    payload = {
      ...payload,
      answer: clampText(payload.answer, payload.answer.length - (out.length - MAX_DM_BODY)),
    };
    out = ANSWER_PREFIX + JSON.stringify(payload);
  }
  return out;
}

export function decodeEmberAnswer(
  body: string | null | undefined
): EmberAnswerPayload | null {
  if (!body || !body.startsWith(ANSWER_PREFIX)) return null;
  try {
    const o = JSON.parse(body.slice(ANSWER_PREFIX.length)) as Partial<EmberAnswerPayload>;
    if (typeof o.answer !== "string") return null;
    return {
      id: o.id ?? crypto.randomUUID(),
      question: o.question ?? "",
      answer: o.answer,
      sources: Array.isArray(o.sources) ? o.sources : [],
      tldr: o.tldr ?? null,
    };
  } catch {
    return null;
  }
}

// MARK: - Fact-check verdict

const FACTCHECK_PREFIX = "::whisper-factcheck-v1::";

export interface FactCheckPayload {
  id: string;
  claim: string;
  verdictRaw: Verdict;
  summary: string;
  explanation: string;
  sources: string[];
}

export function encodeFactCheck(p: FactCheckPayload): string {
  let payload: FactCheckPayload = { ...p, sources: p.sources.slice(0, 4) };
  let out = FACTCHECK_PREFIX + JSON.stringify(payload);
  if (out.length <= MAX_DM_BODY) return out;
  // Trim the long explanation first, then the summary if still over budget.
  payload = {
    ...payload,
    explanation: clampText(payload.explanation, payload.explanation.length - (out.length - MAX_DM_BODY)),
  };
  out = FACTCHECK_PREFIX + JSON.stringify(payload);
  if (out.length > MAX_DM_BODY) {
    payload = {
      ...payload,
      summary: clampText(payload.summary, payload.summary.length - (out.length - MAX_DM_BODY)),
    };
    out = FACTCHECK_PREFIX + JSON.stringify(payload);
  }
  return out;
}

export function decodeFactCheck(
  body: string | null | undefined
): FactCheckPayload | null {
  if (!body || !body.startsWith(FACTCHECK_PREFIX)) return null;
  try {
    const o = JSON.parse(body.slice(FACTCHECK_PREFIX.length)) as Partial<FactCheckPayload>;
    if (typeof o.claim !== "string") return null;
    return {
      id: o.id ?? crypto.randomUUID(),
      claim: o.claim,
      verdictRaw: (o.verdictRaw as Verdict) ?? "unverified",
      summary: o.summary ?? "",
      explanation: o.explanation ?? "",
      sources: Array.isArray(o.sources) ? o.sources : [],
    };
  } catch {
    return null;
  }
}

// MARK: - Nearby restaurants map

const MAP_PREFIX = "::whisper-map-v1::";

export interface MapPlace {
  id: string;
  name: string;
  category: string | null;
  lat: number;
  lon: number;
}

export interface MapPayload {
  id: string;
  title: string;
  lat: number;
  lon: number;
  radiusMeters: number;
  places: MapPlace[];
  city: string | null;
}

export function encodeMap(p: MapPayload): string {
  let payload: MapPayload = { ...p };
  let out = MAP_PREFIX + JSON.stringify(payload);
  // Drop the least-relevant places until the body fits (rarely needed).
  while (out.length > MAX_DM_BODY && payload.places.length > 1) {
    payload = { ...payload, places: payload.places.slice(0, -1) };
    out = MAP_PREFIX + JSON.stringify(payload);
  }
  return out;
}

export function decodeMap(body: string | null | undefined): MapPayload | null {
  if (!body || !body.startsWith(MAP_PREFIX)) return null;
  try {
    const o = JSON.parse(body.slice(MAP_PREFIX.length)) as Partial<MapPayload>;
    if (typeof o.lat !== "number" || typeof o.lon !== "number") return null;
    return {
      id: o.id ?? crypto.randomUUID(),
      title: o.title ?? "Nearby restaurants",
      lat: o.lat,
      lon: o.lon,
      radiusMeters: o.radiusMeters ?? 1500,
      places: Array.isArray(o.places) ? (o.places as MapPlace[]) : [],
      city: o.city ?? null,
    };
  } catch {
    return null;
  }
}

interface Position {
  latitude: number;
  longitude: number;
}

function currentPosition(): Promise<Position | null> {
  return new Promise((resolve) => {
    if (!("geolocation" in navigator)) {
      resolve(null);
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => resolve({ latitude: pos.coords.latitude, longitude: pos.coords.longitude }),
      () => resolve(null),
      { enableHighAccuracy: false, timeout: 10000, maximumAge: 5 * 60 * 1000 }
    );
  });
}

const FALLBACK_PLACES: { name: string; category: string; dLat: number; dLon: number }[] = [
  { name: "Sweetgreen", category: "Salads & bowls", dLat: 0.003, dLon: -0.002 },
  { name: "Chipotle", category: "Mexican grill", dLat: -0.0025, dLon: 0.0018 },
  { name: "CAVA", category: "Mediterranean", dLat: 0.004, dLon: 0.003 },
  { name: "Shake Shack", category: "Burgers", dLat: -0.001, dLon: -0.004 },
  { name: "Tender Greens", category: "Healthy plates", dLat: 0.002, dLon: 0.0042 },
];

interface OverpassElement {
  lat?: number;
  lon?: number;
  center?: { lat: number; lon: number };
  tags?: { name?: string; cuisine?: string; amenity?: string };
}

/**
 * Builds a nearby-restaurants map payload — the web counterpart of the iOS
 * `nearbyRestaurantsPayload`. Uses browser geolocation + the free OpenStreetMap
 * Overpass API for real venues, falling back to a curated list so the embed is
 * never empty.
 */
export async function buildNearbyPayload(): Promise<MapPayload> {
  const pos = await currentPosition();
  const baseLat = pos?.latitude ?? 37.7749;
  const baseLon = pos?.longitude ?? -122.4194;
  const city = pos ? await resolveCurrentCity().catch(() => null) : null;

  let places: MapPlace[] = [];
  if (pos) {
    try {
      const query = `[out:json][timeout:8];node["amenity"~"restaurant|fast_food|cafe"](around:1500,${baseLat},${baseLon});out 8;`;
      const res = await fetch("https://overpass-api.de/api/interpreter", {
        method: "POST",
        body: query,
      });
      if (res.ok) {
        const json = (await res.json()) as { elements?: OverpassElement[] };
        places = (json.elements ?? [])
          .filter((e) => e.tags?.name)
          .slice(0, 6)
          .map((e) => ({
            id: crypto.randomUUID(),
            name: e.tags!.name!,
            category: e.tags?.cuisine?.replace(/_/g, " ") ?? e.tags?.amenity ?? null,
            lat: e.lat ?? e.center?.lat ?? baseLat,
            lon: e.lon ?? e.center?.lon ?? baseLon,
          }));
      }
    } catch {
      places = [];
    }
  }

  if (places.length === 0) {
    places = FALLBACK_PLACES.map((p) => ({
      id: crypto.randomUUID(),
      name: p.name,
      category: p.category,
      lat: baseLat + p.dLat,
      lon: baseLon + p.dLon,
    }));
  }

  return {
    id: crypto.randomUUID(),
    title: `Restaurants near ${city ?? "you"}`,
    lat: baseLat,
    lon: baseLon,
    radiusMeters: 1500,
    places,
    city,
  };
}

/** True when a DM body is any Ember-produced embed. */
export function isEmberEmbed(body: string | null | undefined): boolean {
  return !!(decodeEmberAnswer(body) || decodeFactCheck(body) || decodeMap(body));
}
