import {
  Dumbbell,
  Flame,
  Footprints,
  Heart,
  Flower2,
  Bike,
  Waves,
  Apple,
  Brain,
  Coffee,
  BookOpen,
  Music,
  Film,
  Gamepad2,
  Mountain,
  Moon,
  Sparkles,
  Trophy,
  Users,
  Landmark,
  GraduationCap,
  Stethoscope,
  Briefcase,
  Code2,
  type LucideIcon,
} from "lucide-react";

import { supabase } from "@/lib/supabase";
import { stripPostMeta } from "@/lib/postMeta";

/**
 * A community is a curated topic hub. Lightweight enough to live entirely on
 * the client (mirrors the iOS `WhisperCommunity` catalog) — a post belongs to
 * a community when its caption contains the `#name` hashtag or any keyword.
 */
export interface Community {
  id: string;
  name: string;
  tagline: string;
  icon: LucideIcon;
  /** Two-stop gradient (hex) for the avatar disc + hero. */
  gradient: [string, string];
  keywords: string[];
  /** Signature react emoji — replaces the like heart inside this
   *  community's feed (geo hubs always carry one). */
  specialReact?: string;
  /** Provenance line for geo-suggested hubs ("Near Harvard University"). */
  origin?: string;
  /** Street address of the real place behind a geo hub (campus / gym). */
  originAddress?: string;
  /** Viewable only when the user's Jasper account is linked — posts inside
   *  wear the ember glow shell. Mirrors the iOS catalog flag. */
  requiresJasperLink?: boolean;
  /** "private" = invite-only group — feed and member list open to members. */
  visibility?: "public" | "private";
  /** Creator of a user-made community (owns invites on private groups). */
  creatorId?: string;
  creatorUsername?: string;
}

/** Signature reacts for the built-in catalog — mirrors the iOS mapping so
 *  both apps burst the same emoji inside each community. */
export const COMMUNITY_REACTS: Record<string, string> = {
  dating: "💘",
  workouts: "💪",
  running: "🏃",
  yoga: "🧘",
  cycling: "🚴",
  swimming: "🏊",
  nutrition: "🥗",
  mindset: "🧠",
  mindfulness: "🫧",
  outdoors: "🌲",
  sleep: "😴",
  coffee: "☕️",
  books: "📚",
  music: "🎵",
  movies: "🎬",
  gaming: "🎮",
  sports: "🏆",
};

/** The react a community actually uses — explicit override first, then the
 *  catalog mapping. undefined = standard heart. */
export function communityReact(c: Community): string | undefined {
  return c.specialReact ?? COMMUNITY_REACTS[c.id];
}

// ─── Geo communities (shared naming with iOS for caption matching) ────

/** Campus field hubs unlocked by a nearby college — exact same ids, names,
 *  and keywords as iOS so posts match across platforms. */
export function campusPack(campusName: string, address?: string): Community[] {
  const origin = `Near ${campusName}`;
  return [
    {
      id: "geo-law",
      name: "Whisper Law",
      tagline: "Case briefs, cold calls, bar prep — the law students' common room.",
      icon: Landmark,
      gradient: ["#293861", "#B8944D"],
      keywords: ["whisperlaw", "law school", "law student", "bar exam", "case brief", "1l ", "2l ", "3l "],
      specialReact: "⚖️",
      origin,
      originAddress: address,
    },
    {
      id: "geo-med",
      name: "Whisper Med",
      tagline: "Rotations, match day, and surviving anatomy — future docs unite.",
      icon: Stethoscope,
      gradient: ["#298C8F", "#73D6C7"],
      keywords: ["whispermed", "med school", "med student", "rotations", "match day", "anatomy", "usmle"],
      specialReact: "🩺",
      origin,
      originAddress: address,
    },
    {
      id: "geo-business",
      name: "Whisper Business",
      tagline: "Pitches, internships, first ventures — the business school floor.",
      icon: Briefcase,
      gradient: ["#3B404D", "#D9AD61"],
      keywords: ["whisperbusiness", "b-school", "mba", "internship", "pitch deck", "startup"],
      specialReact: "💼",
      origin,
      originAddress: address,
    },
    {
      id: "geo-code",
      name: "Whisper Code",
      tagline: "Problem sets, hackathons, ship days — engineers and CS kids.",
      icon: Code2,
      gradient: ["#523D99", "#9E85F5"],
      keywords: ["whispercode", "hackathon", "problem set", "leetcode", "comp sci", "engineering"],
      specialReact: "💻",
      origin,
      originAddress: address,
    },
  ];
}

/** One community per nearby college — named after the real campus so every
 *  discovered school ACCUMULATES as its own hub (same ids as iOS). */
export function campusCommunity(
  name: string,
  distanceMeters?: number,
  address?: string
): Community {
  const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, "");
  let origin = "Near you";
  if (typeof distanceMeters === "number" && Number.isFinite(distanceMeters)) {
    origin =
      distanceMeters < 1000
        ? `${Math.round(distanceMeters)} m away`
        : `${(distanceMeters / 1000).toFixed(1)} km away`;
  }
  return {
    id: `geo-campus-${slug}`,
    name,
    tagline: `The ${name} yard — classes, clubs, and campus life.`,
    icon: GraduationCap,
    gradient: ["#3E5AA8", "#8FB7F5"],
    keywords: [name.toLowerCase(), slug],
    specialReact: "\u{1F393}",
    origin,
    originAddress: address,
  };
}

/** One community per nearby gym, named after the real place (matches iOS). */
export function gymCommunity(
  name: string,
  distanceMeters?: number,
  address?: string
): Community {
  const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, "");
  let origin = "Near you";
  if (typeof distanceMeters === "number" && Number.isFinite(distanceMeters)) {
    origin =
      distanceMeters < 1000
        ? `${Math.round(distanceMeters)} m away`
        : `${(distanceMeters / 1000).toFixed(1)} km away`;
  }
  return {
    id: `geo-gym-${slug}`,
    name,
    tagline: `The ${name} crew — sessions, PRs, and meetups at the gym.`,
    icon: Dumbbell,
    gradient: ["#ED6B38", "#FFB366"],
    keywords: [name.toLowerCase(), slug],
    specialReact: "💪",
    origin,
    originAddress: address,
  };
}

/** Linked-accounts-only lounge — anyone can see it in the list, but the
 *  feed opens only once the Jasper account link exists. Its posts stay
 *  white and wear the Jasper ember glow. Mirrors the iOS catalog entry. */
export const JASPER_CIRCLE: Community = {
  id: "jasper-circle",
  name: "Jasper Circle",
  tagline: "The linked-account lounge — train, track, and talk with Jasper's people.",
  icon: Flame,
  gradient: ["#F97316", "#FFB366"],
  keywords: ["jasper", "jaspercircle", "jasper circle", "jasperapp"],
  specialReact: "👻",
  requiresJasperLink: true,
};

/** The dating hub — carries its own icebreakers, say-hi flow, and safety
 *  card on the community page (mirrored on iOS). */
export const DATING_COMMUNITY: Community = {
  id: "dating",
  name: "Dating",
  tagline: "Meet someone real — it starts with a whisper.",
  icon: Heart,
  gradient: ["#E8467C", "#FF9EB8"],
  keywords: ["dating", "single", "date night", "first date", "situationship", "meet someone", "relationship"],
};

export const COMMUNITIES: Community[] = [
  JASPER_CIRCLE,
  DATING_COMMUNITY,
  {
    id: "workouts",
    name: "Workouts",
    tagline: "Daily splits, PRs, and program drops.",
    icon: Dumbbell,
    gradient: ["#FB8333", "#FFB86B"],
    keywords: ["workout", "lift", "session", "gym"],
  },
  {
    id: "running",
    name: "Running",
    tagline: "Long runs, intervals, race day.",
    icon: Footprints,
    gradient: ["#6B9EEB", "#8CD1F5"],
    keywords: ["run", "mile", "5k", "10k", "marathon", "pace"],
  },
  {
    id: "yoga",
    name: "Yoga",
    tagline: "Slow flows, deep stretch, breath.",
    icon: Flower2,
    gradient: ["#85D6DC", "#DBEB9E"],
    keywords: ["yoga", "flow", "asana"],
  },
  {
    id: "cycling",
    name: "Cycling",
    tagline: "Watts, wheels, long rides.",
    icon: Bike,
    gradient: ["#4073A6", "#9ED6F5"],
    keywords: ["cycle", "cycling", "bike", "ride", "watts"],
  },
  {
    id: "swimming",
    name: "Swimming",
    tagline: "Laps, open water, breath sets.",
    icon: Waves,
    gradient: ["#3380B8", "#85D6DC"],
    keywords: ["swim", "pool", "open water"],
  },
  {
    id: "nutrition",
    name: "Nutrition",
    tagline: "Meals, macros, the plate.",
    icon: Apple,
    gradient: ["#F58C52", "#FFC76B"],
    keywords: ["nutrition", "meal", "macro", "protein", "calorie"],
  },
  {
    id: "mindset",
    name: "Mindset",
    tagline: "Hard things, done daily.",
    icon: Brain,
    gradient: ["#2E2E38", "#C780EB"],
    keywords: ["mindset", "discipline", "grit"],
  },
  {
    id: "mindfulness",
    name: "Mindfulness",
    tagline: "Breath, presence, quiet wins.",
    icon: Sparkles,
    gradient: ["#C780EB", "#F5C7EB"],
    keywords: ["mindful", "meditat", "breath"],
  },
  {
    id: "outdoors",
    name: "Outdoors",
    tagline: "Trail, mountain, salt air.",
    icon: Mountain,
    gradient: ["#338052", "#C2E080"],
    keywords: ["outdoor", "trail", "nature", "hike", "summit"],
  },
  {
    id: "sleep",
    name: "Sleep",
    tagline: "Lights out. Real gains.",
    icon: Moon,
    gradient: ["#2E3373", "#8C80EB"],
    keywords: ["sleep", "rest", "rem"],
  },
  {
    id: "coffee",
    name: "Coffee",
    tagline: "Beans, brews, slow mornings.",
    icon: Coffee,
    gradient: ["#66402E", "#C78C61"],
    keywords: ["coffee", "espresso", "latte", "barista", "brew"],
  },
  {
    id: "books",
    name: "Books",
    tagline: "What you're reading right now.",
    icon: BookOpen,
    gradient: ["#8C599E", "#EBC78C"],
    keywords: ["book", "reading", "novel", "chapter", "author"],
  },
  {
    id: "music",
    name: "Music",
    tagline: "Albums, playlists, live shows.",
    icon: Music,
    gradient: ["#EB4D9E", "#8C61EB"],
    keywords: ["music", "song", "album", "playlist", "concert", "band"],
  },
  {
    id: "movies",
    name: "Movies",
    tagline: "Theatre nights and deep cuts.",
    icon: Film,
    gradient: ["#2E2E4D", "#C73352"],
    keywords: ["movie", "film", "cinema", "theatre"],
  },
  {
    id: "gaming",
    name: "Gaming",
    tagline: "Runs, raids, ranked grinds.",
    icon: Gamepad2,
    gradient: ["#408CEB", "#8C4DEB"],
    keywords: ["game", "gaming", "playstation", "xbox", "steam"],
  },
  {
    id: "sports",
    name: "Sports",
    tagline: "Game day, every day.",
    icon: Trophy,
    gradient: ["#3380EB", "#8CEB9E"],
    keywords: ["sports", "team", "season", "match"],
  },
];

export function communityById(id: string): Community | undefined {
  return COMMUNITIES.find((c) => c.id === id);
}

// ─── Custom (user-created) communities ──────────────────────────────────

interface CustomCommunityRow {
  id: string;
  slug: string;
  name: string;
  tagline: string;
  color1: string;
  color2: string;
  keywords: string[] | null;
  creator_id?: string | null;
  creator_username: string;
  visibility?: string | null;
}

function rowToCommunity(row: CustomCommunityRow): Community {
  return {
    id: row.slug,
    name: row.name,
    tagline: row.tagline || `Started by @${row.creator_username}`,
    icon: Users,
    gradient: [row.color1 || "#FB8333", row.color2 || "#FFB86B"],
    keywords: row.keywords ?? [],
    visibility: row.visibility === "private" ? "private" : "public",
    creatorId: row.creator_id ?? undefined,
    creatorUsername: row.creator_username,
  };
}

/** All user-created PUBLIC communities, newest first — private groups never
 *  show in the browse grid (they surface via your memberships instead). */
export async function fetchCustomCommunities(): Promise<Community[]> {
  const { data } = await supabase
    .from("whisper_communities")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(100);
  return ((data as CustomCommunityRow[] | null) ?? [])
    .filter((r) => r.visibility !== "private")
    .map(rowToCommunity);
}

/** One custom community by its slug (used when the catalog misses an id). */
export async function fetchCustomCommunity(
  slug: string
): Promise<Community | null> {
  const { data } = await supabase
    .from("whisper_communities")
    .select("*")
    .eq("slug", slug.toLowerCase())
    .limit(1)
    .maybeSingle();
  return data ? rowToCommunity(data as CustomCommunityRow) : null;
}

export function slugify(name: string): string {
  return name
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9\s-]/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .slice(0, 40);
}

const CUSTOM_GRADIENTS: [string, string][] = [
  ["#FB8333", "#FFB86B"],
  ["#6B9EEB", "#8CD1F5"],
  ["#33A06B", "#8CEB9E"],
  ["#C780EB", "#F5A7D6"],
  ["#EB4D6B", "#F5A780"],
  ["#2E3373", "#8C80EB"],
];

/** Creates a new community. Throws with a friendly message on conflicts. */
export async function createCommunity(input: {
  name: string;
  tagline: string;
  keywords: string[];
  creatorId: string;
  creatorUsername: string;
  /** "private" makes an invite-only group (needs community-posts.sql). */
  visibility?: "public" | "private";
}): Promise<Community> {
  const slug = slugify(input.name);
  if (slug.length < 2) throw new Error("Pick a longer community name.");
  if (communityById(slug)) {
    throw new Error("That community already exists — join it instead.");
  }
  const gradient =
    CUSTOM_GRADIENTS[Math.floor(Math.random() * CUSTOM_GRADIENTS.length)];
  const wantsPrivate = input.visibility === "private";
  const basePayload: Record<string, unknown> = {
    slug,
    name: input.name.trim(),
    tagline: input.tagline.trim(),
    color1: gradient[0],
    color2: gradient[1],
    keywords: [slug, ...input.keywords.map((k) => k.toLowerCase().trim()).filter(Boolean)],
    creator_id: input.creatorId,
    creator_username: input.creatorUsername,
  };
  if (wantsPrivate) basePayload.visibility = "private";
  const { data, error } = await supabase
    .from("whisper_communities")
    .insert(basePayload)
    .select()
    .limit(1);
  if (error && wantsPrivate && /visibility/.test(error.message ?? "")) {
    // The privacy column doesn't exist yet — NEVER silently create a public
    // group when a private one was asked for.
    throw new Error(
      "Private groups need a one-time update — run supabase/community-posts.sql, then try again."
    );
  }
  if (error) {
    if (error.code === "23505") {
      throw new Error("That community already exists — join it instead.");
    }
    if (error.code === "42P01") {
      throw new Error("Communities table missing — run supabase/communities.sql once.");
    }
    throw new Error("Couldn't create the community. Try again.");
  }
  const row = (data as CustomCommunityRow[] | null)?.[0];
  if (!row) throw new Error("Couldn't create the community. Try again.");
  if (wantsPrivate) {
    // The creator is the group's first member/owner — best-effort (the page
    // also treats the creator as owner when the row is missing).
    await supabase.from("whisper_community_members").upsert(
      {
        community_slug: slug,
        user_id: input.creatorId,
        username: input.creatorUsername,
        role: "owner",
        status: "member",
      },
      { onConflict: "community_slug,user_id" }
    );
  }
  return rowToCommunity(row);
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Strict keyword hit — the keyword must START at a word boundary (so "run"
 * can't fire inside "brunch", "mile" inside "smile") and may continue at
 * most 4 letters before the next boundary (so "run" still catches
 * "running" but "rest" can't catch "restaurant").
 */
function keywordHit(needle: string, keyword: string): boolean {
  const k = keyword.trim().toLowerCase();
  if (!k) return false;
  try {
    return new RegExp(`(^|[^a-z0-9])${escapeRegex(k)}[a-z]{0,4}($|[^a-z0-9])`).test(needle);
  } catch {
    return needle.includes(k);
  }
}

/** Legacy caption matching — the community's hashtag, or a STRICT
 *  word-boundary keyword hit (the old substring matching mis-filed posts:
 *  "brunch" landed in Running). Used only for posts without an explicit
 *  community pick. */
export function communityMatches(community: Community, caption: string): boolean {
  const needle = ` ${(caption ?? "").toLowerCase()} `;
  const nameLower = community.name.toLowerCase();
  if (needle.includes(`#${nameLower}`)) return true;
  if (needle.includes(`#${nameLower.replace(/\s+/g, "")}`)) return true;
  if (needle.includes(`#${community.id.toLowerCase()}`)) return true;
  return community.keywords.some((k) => keywordHit(needle, k));
}

/**
 * The one true "does this post belong here" check — EXPLICIT-ONLY. A post
 * belongs to a community only when the author picked it at compose time.
 * Keyword/hashtag auto-filing is fully retired: captions can never leak a
 * post into a hub the author didn't choose.
 */
export function communityMatchesPost(
  community: Community,
  post: { caption: string; community_id?: string | null }
): boolean {
  return !!post.community_id && post.community_id === community.id;
}

/**
 * Composer auto-suggest — finds the first catalog community whose keywords
 * strictly match the draft. Never suggests link-gated or private hubs, and
 * only speaks up once there's a real sentence to read.
 */
export function suggestCommunityForCaption(
  caption: string,
  candidates?: Community[]
): Community | null {
  const text = (caption ?? "").trim();
  if (text.length < 12) return null;
  const pool = (candidates ?? COMMUNITIES).filter(
    (c) => !c.requiresJasperLink && c.visibility !== "private"
  );
  const needle = ` ${text.toLowerCase()} `;
  return pool.find((c) => c.keywords.some((k) => keywordHit(needle, k))) ?? null;
}

/**
 * Communities the user belongs to — derived from their picked interests
 * (matched against community names). Falls back to a popular starter set so
 * the sidebar is never empty.
 */
export function communitiesForInterests(
  interests: string[] | null | undefined
): Community[] {
  const picked = (interests ?? []).map((i) => i.toLowerCase());
  const matched = COMMUNITIES.filter((c) =>
    picked.some(
      (i) => i === c.name.toLowerCase() || c.keywords.includes(i)
    )
  );
  if (matched.length > 0) return matched;
  return COMMUNITIES.slice(0, 5);
}

// ─── Dating community extras (mirrored on iOS) ───────────────────────

/** Icebreaker prompts — one surfaces per HOUR in the Dating hub. */
export const DATING_ICEBREAKERS: string[] = [
  "What's your idea of a perfect first date — coffee, a walk, or something braver?",
  "Two truths and a lie — go.",
  "What's a green flag people don't talk about enough?",
  "What song would play when you walk into a room?",
  "Early bird date or late-night talker?",
  "What's the best meal you could cook for someone?",
  "What hobby could you talk about for an hour straight?",
  "Describe your weekend in three emojis.",
  "What's something small that instantly makes your day?",
  "Dogs, cats, or 'let me show you my plant'?",
  "What's a place you'd take someone to show them who you are?",
  "What are you actually looking for right now — honestly?",
  "Your go-to karaoke song. No skipping.",
  "What's the most spontaneous thing you've ever done?",
];

/**
 * Deterministic HOURLY pick — the same prompt for everyone worldwide,
 * rotating at the top of every UTC hour so matches dial in as the day
 * moves. Mirrors iOS `datingIcebreakerForHour` exactly.
 */
export function datingIcebreakerForHour(at: Date = new Date()): string {
  const start = Date.UTC(at.getUTCFullYear(), 0, 0);
  const day = Math.floor(
    (Date.UTC(at.getUTCFullYear(), at.getUTCMonth(), at.getUTCDate()) - start) / 86_400_000
  );
  return DATING_ICEBREAKERS[(day * 24 + at.getUTCHours()) % DATING_ICEBREAKERS.length];
}

/** Minutes until the prompt rotates (top of the next hour, UTC). */
export function minutesUntilNextIcebreaker(at: Date = new Date()): number {
  return Math.max(1, 60 - at.getUTCMinutes());
}

/** Safety card shown in the Dating hub — short, real, no lecture. */
export const DATING_SAFETY_TIPS: string[] = [
  "Meet in public for the first few dates.",
  "Tell a friend where you're going and with whom.",
  "Keep chats on Whisper until you trust them — report anything off.",
  "Never send money or financial info. Ever.",
  "Video-chat before meeting — it should feel easy, not pressured.",
];

// ─── Dating "For you" match engine (mirrors iOS `WhisperDatingMatch`) ───

export interface DatingAnswer {
  prompt: string | null;
  text: string;
}

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

const DATING_STOPWORDS = new Set<string>([
  "the", "and", "for", "you", "your", "with", "that", "this", "have", "has",
  "was", "are", "but", "not", "its", "out", "about", "into", "just", "like",
  "them", "they", "then", "than", "what", "when", "where", "would", "could",
  "should", "really", "very", "been", "being", "from", "some", "something",
  "someone", "honestly", "actually",
]);

function datingTokens(s: string): Set<string> {
  return new Set(
    s
      .toLowerCase()
      .split(/[^a-z0-9]+/)
      .filter((w) => w.length > 2 && !DATING_STOPWORDS.has(w))
  );
}

/**
 * Pure on-device answer similarity — Jaccard over answer tokens, +0.3 when
 * both answered the SAME prompt. No AI call, no credits; identical on iOS.
 */
export function datingSimilarity(mine: DatingAnswer, caption: string | null | undefined): number {
  const theirs = datingAnswerFromCaption(caption);
  if (!theirs.text) return 0;
  const a = datingTokens(mine.text);
  const b = datingTokens(theirs.text);
  let score = 0;
  if (a.size > 0 && b.size > 0) {
    let inter = 0;
    a.forEach((t) => {
      if (b.has(t)) inter += 1;
    });
    const union = a.size + b.size - inter;
    if (union > 0) score = inter / union;
  }
  if (mine.prompt && theirs.prompt && mine.prompt.toLowerCase() === theirs.prompt.toLowerCase()) {
    score += 0.3;
  }
  return score;
}

// ─── Private groups — membership + invites (whisper_community_members) ───

export interface CommunityMemberRow {
  community_slug: string;
  user_id: string;
  username: string;
  role: "owner" | "member";
  status: "member" | "invited";
  invited_by: string | null;
  created_at: string | null;
}

function memberRows(data: unknown): CommunityMemberRow[] {
  return (data as CommunityMemberRow[] | null) ?? [];
}

/** Everyone in (or invited to) a group — members first, then invites. */
export async function fetchGroupMembers(slug: string): Promise<CommunityMemberRow[]> {
  const { data, error } = await supabase
    .from("whisper_community_members")
    .select("*")
    .eq("community_slug", slug)
    .order("created_at", { ascending: true });
  if (error) return [];
  const rows = memberRows(data);
  return [...rows.filter((r) => r.status === "member"), ...rows.filter((r) => r.status !== "member")];
}

/** My membership/invite rows across every private group. */
export async function fetchMyGroupRows(userId: string): Promise<CommunityMemberRow[]> {
  const { data, error } = await supabase
    .from("whisper_community_members")
    .select("*")
    .eq("user_id", userId);
  if (error) return [];
  return memberRows(data);
}

/** The private groups I belong to (or am invited to), as Community cards. */
export async function fetchMyPrivateGroups(userId: string): Promise<Community[]> {
  const rows = await fetchMyGroupRows(userId);
  if (rows.length === 0) return [];
  const { data } = await supabase
    .from("whisper_communities")
    .select("*")
    .in("slug", rows.map((r) => r.community_slug));
  return ((data as CustomCommunityRow[] | null) ?? [])
    .filter((r) => r.visibility === "private")
    .map(rowToCommunity);
}

/** Owner invites someone by username — resolves the @handle to an account. */
export async function inviteToGroup(input: {
  slug: string;
  username: string;
  invitedBy: string;
}): Promise<void> {
  const handle = input.username.trim().replace(/^@/, "").toLowerCase();
  if (!handle) throw new Error("Type a @username to invite.");
  const { data } = await supabase
    .from("whisper_profiles")
    .select("user_id, username")
    .ilike("username", handle)
    .limit(1)
    .maybeSingle();
  const person = data as { user_id: string; username: string } | null;
  if (!person) throw new Error(`No one named @${handle} on Whisper.`);
  const { error } = await supabase.from("whisper_community_members").upsert(
    {
      community_slug: input.slug,
      user_id: person.user_id,
      username: person.username,
      role: "member",
      status: "invited",
      invited_by: input.invitedBy,
    },
    { onConflict: "community_slug,user_id", ignoreDuplicates: true }
  );
  if (error) {
    if (error.code === "42P01") {
      throw new Error("Private groups need supabase/community-posts.sql — run it once.");
    }
    throw new Error("Couldn't send the invite. Try again.");
  }
}

/** Invited → member (accepting your own invite). */
export async function acceptGroupInvite(slug: string, userId: string): Promise<void> {
  const { error } = await supabase
    .from("whisper_community_members")
    .update({ status: "member" })
    .eq("community_slug", slug)
    .eq("user_id", userId);
  if (error) throw new Error("Couldn't accept the invite. Try again.");
}

/** Leave / decline / (owner) remove a member. */
export async function removeGroupRow(slug: string, userId: string): Promise<void> {
  await supabase
    .from("whisper_community_members")
    .delete()
    .eq("community_slug", slug)
    .eq("user_id", userId);
}
