import { DATING_ICEBREAKERS } from "@/lib/communities";
import { stripPostMeta } from "@/lib/postMeta";
import type { DatingPrefs, NearbyPerson } from "@/lib/datingPrefs";

/**
 * The Dating hub's match engine v2 — pure on-device text math (no AI call,
 * no credits) that turns icebreaker ANSWERS into a compatibility score:
 *   • stem-lite tokens (plurals/-ing/-ed folded) with stopwords dropped
 *   • a THEME lexicon so "hiking" and "trail runs" resonate — cosine over
 *     theme vectors + a shared-theme bonus
 *   • Jaccard over the raw tokens for literal overlap
 *   • +0.3 when both answered the SAME prompt
 *   • preference boosts when the person is inside my radius / shares my intent
 * Mirrors iOS `WhisperDatingMatch` EXACTLY — same lexicon, same weights.
 */

export interface DatingAnswer {
  prompt: string | null;
  text: string;
}

interface Theme {
  id: string;
  label: string;
  words: string[];
}

export const DATING_THEMES: Theme[] = [
  { id: "outdoors", label: "Outdoors", words: ["hike", "hiking", "trail", "trails", "camp", "camping", "mountain", "mountains", "beach", "surf", "surfing", "ski", "skiing", "snowboard", "kayak", "nature", "sunrise", "sunset", "lake", "ocean", "outdoors", "outdoor"] },
  { id: "fitness", label: "Fitness", words: ["gym", "lift", "lifting", "workout", "workouts", "run", "running", "runner", "marathon", "crossfit", "yoga", "pilates", "climb", "climbing", "cycling", "bike", "biking", "training", "athlete", "fitness", "fit", "sweat"] },
  { id: "food", label: "Food", words: ["cook", "cooking", "chef", "restaurant", "restaurants", "brunch", "tacos", "sushi", "pizza", "coffee", "wine", "bake", "baking", "foodie", "dinner", "ramen", "pasta", "recipe", "recipes", "eat", "eating", "snack", "dessert"] },
  { id: "travel", label: "Travel", words: ["travel", "traveling", "travelling", "trip", "trips", "countries", "passport", "flight", "flights", "adventure", "explore", "exploring", "backpacking", "roadtrip", "abroad", "wander"] },
  { id: "music", label: "Music", words: ["music", "concert", "concerts", "festival", "festivals", "vinyl", "guitar", "piano", "sing", "singing", "karaoke", "playlist", "playlists", "dj", "band", "bands", "song", "songs"] },
  { id: "film", label: "Film & TV", words: ["movie", "movies", "film", "films", "cinema", "netflix", "series", "show", "shows", "anime", "documentary", "documentaries", "binge"] },
  { id: "books", label: "Books", words: ["book", "books", "reading", "read", "novel", "novels", "poetry", "library", "writer", "writing", "bookstore"] },
  { id: "art", label: "Art & design", words: ["art", "artist", "paint", "painting", "draw", "drawing", "museum", "gallery", "design", "designer", "photography", "photo", "photos", "creative", "pottery"] },
  { id: "games", label: "Games", words: ["game", "games", "gaming", "gamer", "chess", "board", "boardgames", "nintendo", "playstation", "xbox", "dnd", "puzzle", "puzzles", "trivia"] },
  { id: "pets", label: "Pets & plants", words: ["dog", "dogs", "puppy", "cat", "cats", "kitten", "pet", "pets", "plant", "plants", "garden", "gardening"] },
  { id: "faith", label: "Faith & mindfulness", words: ["church", "faith", "god", "jesus", "pray", "prayer", "spiritual", "spirituality", "meditation", "meditate", "mindful", "mindfulness"] },
  { id: "family", label: "Family & commitment", words: ["family", "kids", "children", "marriage", "married", "settle", "serious", "partner", "partnership", "commitment", "commit", "longterm", "forever"] },
  { id: "nightlife", label: "Nightlife", words: ["bar", "bars", "club", "clubbing", "party", "parties", "drinks", "cocktails", "dancing", "dance", "nightlife"] },
  { id: "homebody", label: "Cozy nights", words: ["cozy", "home", "couch", "chill", "quiet", "introvert", "tea", "candles", "sunday", "blanket", "pajamas", "homebody"] },
  { id: "ambition", label: "Ambition", words: ["career", "business", "startup", "founder", "hustle", "goals", "goal", "ambitious", "driven", "entrepreneur", "work", "working", "grind"] },
  { id: "humor", label: "Humor", words: ["funny", "laugh", "laughing", "laughs", "jokes", "joke", "humor", "sarcastic", "witty", "banter", "memes", "meme", "silly", "goofy"] },
  { id: "kindness", label: "Kindness & honesty", words: ["kind", "kindness", "honest", "honesty", "loyal", "loyalty", "genuine", "respect", "respectful", "empathy", "gentle", "communication", "trust", "trustworthy"] },
  { id: "sports", label: "Sports", words: ["football", "soccer", "basketball", "baseball", "hockey", "tennis", "golf", "nfl", "nba", "fan", "team", "teams", "pickleball"] },
  { id: "wellness", label: "Wellness", words: ["health", "healthy", "sleep", "sober", "therapy", "growth", "journaling", "journal", "wellness", "balance", "selfcare"] },
  { id: "spontaneous", label: "Spontaneity", words: ["spontaneous", "adventurous", "random", "impulsive", "lastminute", "yes"] },
];

const STOPWORDS = new Set<string>([
  "the", "and", "for", "you", "your", "with", "that", "this", "have", "has",
  "was", "are", "but", "not", "its", "out", "about", "into", "just", "like",
  "them", "they", "then", "than", "what", "when", "where", "would", "could",
  "should", "really", "very", "been", "being", "from", "some", "something",
  "someone", "honestly", "actually", "thing", "things", "love", "loves",
  "want", "wants", "good", "great", "much", "more", "also", "always",
]);

/** Stem-lite — folds plurals and -ing/-ed so "hiking" ≈ "hike". Same rules on iOS. */
export function stemLite(raw: string): string {
  let w = raw;
  if (w.length > 5 && w.endsWith("ing")) {
    w = w.slice(0, -3);
    if (w.length > 2 && w[w.length - 1] === w[w.length - 2]) w = w.slice(0, -1); // running → run
  } else if (w.length > 4 && w.endsWith("ies")) {
    w = `${w.slice(0, -3)}y`;
  } else if (w.length > 4 && w.endsWith("es")) {
    w = w.slice(0, -2);
  } else if (w.length > 3 && w.endsWith("s") && !w.endsWith("ss")) {
    w = w.slice(0, -1);
  } else if (w.length > 4 && w.endsWith("ed")) {
    w = w.slice(0, -2);
  }
  return w;
}

const THEME_INDEX: Map<string, number> = (() => {
  const m = new Map<string, number>();
  DATING_THEMES.forEach((t, i) => t.words.forEach((w) => m.set(stemLite(w), i)));
  return m;
})();

/** Splits a caption into (the matched icebreaker prompt, the answer text). */
export function datingAnswerFromCaption(caption: string | null | undefined): DatingAnswer {
  const clean = stripPostMeta(caption ?? "").trim();
  if (!clean) return { prompt: null, text: "" };
  const lines = clean.split("\n");
  const first = (lines[0] ?? "").trim();
  const known = DATING_ICEBREAKERS.find((p) => p.toLowerCase() === first.toLowerCase());
  if (known && lines.length > 1) {
    const rest = lines.slice(1).join(" ").trim();
    if (rest) return { prompt: known, text: rest };
  }
  return { prompt: null, text: clean };
}

export function datingTokens(s: string): Set<string> {
  return new Set(
    s
      .toLowerCase()
      .split(/[^a-z0-9]+/)
      .filter((w) => w.length > 2 && !STOPWORDS.has(w))
      .map(stemLite)
  );
}

function themeVector(tokens: Set<string>): Map<number, number> {
  const v = new Map<number, number>();
  tokens.forEach((t) => {
    const i = THEME_INDEX.get(t);
    if (i != null) v.set(i, (v.get(i) ?? 0) + 1);
  });
  return v;
}

function cosine(a: Map<number, number>, b: Map<number, number>): number {
  if (a.size === 0 || b.size === 0) return 0;
  let dot = 0;
  a.forEach((va, k) => {
    const vb = b.get(k);
    if (vb != null) dot += va * vb;
  });
  let na = 0;
  a.forEach((v) => (na += v * v));
  let nb = 0;
  b.forEach((v) => (nb += v * v));
  na = Math.sqrt(na);
  nb = Math.sqrt(nb);
  return na > 0 && nb > 0 ? dot / (na * nb) : 0;
}

/** Answer-to-answer resonance (0…~1.3). */
export function answerSimilarity(mine: DatingAnswer, theirs: DatingAnswer): number {
  if (!theirs.text || !mine.text) return 0;
  const a = datingTokens(mine.text);
  const b = datingTokens(theirs.text);
  let jaccard = 0;
  if (a.size > 0 && b.size > 0) {
    let inter = 0;
    a.forEach((t) => {
      if (b.has(t)) inter += 1;
    });
    const union = a.size + b.size - inter;
    if (union > 0) jaccard = inter / union;
  }
  const ta = themeVector(a);
  const tb = themeVector(b);
  const cos = cosine(ta, tb);
  let shared = 0;
  ta.forEach((_, k) => {
    if (tb.has(k)) shared += 1;
  });
  let score = 0.45 * jaccard + 0.35 * cos + 0.2 * Math.min(1, shared / 3);
  if (mine.prompt && theirs.prompt && mine.prompt.toLowerCase() === theirs.prompt.toLowerCase()) {
    score += 0.3;
  }
  return score;
}

/** My answer vs a raw caption. */
export function datingSimilarityV2(mine: DatingAnswer, caption: string | null | undefined): number {
  return answerSimilarity(mine, datingAnswerFromCaption(caption));
}

/** Best resonance between ANY of my answers and a caption. */
export function bestSimilarity(mine: DatingAnswer[], caption: string | null | undefined): number {
  const theirs = datingAnswerFromCaption(caption);
  return mine.reduce((best, m) => Math.max(best, answerSimilarity(m, theirs)), 0);
}

/** Theme labels both sides light up on (up to 3) — the "why" chip. */
export function sharedThemes(mine: DatingAnswer[], theirsText: string): string[] {
  const my = new Set<number>();
  mine.forEach((a) => themeVector(datingTokens(a.text)).forEach((_, k) => my.add(k)));
  const theirs = themeVector(datingTokens(theirsText));
  return [...my]
    .filter((k) => theirs.has(k))
    .sort((a, b) => a - b)
    .slice(0, 3)
    .map((k) => DATING_THEMES[k].label);
}

/** Preference boost for someone inside my radius / sharing my intent. */
export function prefsBoost(nearby: NearbyPerson | undefined, prefs: DatingPrefs): number {
  if (!nearby) return 0;
  let boost = 0;
  const hasLocation = prefs.lat != null && prefs.lng != null;
  if (nearby.distance_km != null && hasLocation && prefs.radiusKm > 0) {
    boost += 0.15 * Math.max(0, 1 - Math.min(1, nearby.distance_km / Math.max(1, prefs.radiusKm)));
  } else if (nearby.distance_km != null) {
    boost += 0.05;
  }
  if (prefs.intent && nearby.intent && prefs.intent === nearby.intent) boost += 0.1;
  return boost;
}

/** The person-level score the For-you sort ranks by. */
export function personScore(
  myAnswers: DatingAnswer[],
  caption: string | null | undefined,
  nearby: NearbyPerson | undefined,
  prefs: DatingPrefs
): number {
  return bestSimilarity(myAnswers, caption) + prefsBoost(nearby, prefs);
}
