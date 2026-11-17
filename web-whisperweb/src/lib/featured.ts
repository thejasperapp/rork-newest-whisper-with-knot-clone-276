import { supabase } from "@/lib/supabase";
import { BACKEND_URL } from "@/lib/billing";

/** Which public page a featured profile belongs to. */
export type FeaturedKind = "coach" | "athlete" | "creator" | "recruiter";

export interface FeaturedTestimonial {
  quote: string;
  name: string;
  result: string;
}

/**
 * A typed CTA button attached to a spotlight card. The admin picks the type
 * per button — the card renders up to three, first one primary.
 *  - `profile`  → signed-in users go to /u/<username>; visitors to signup
 *  - `link`     → external URL (opens in a new tab)
 *  - `email`    → mailto: link (href holds the bare email address)
 *  - `calendar` → internal Whisper shared calendar (signed-in) or signup
 */
export type FeaturedActionType = "profile" | "link" | "email" | "calendar";
export interface FeaturedActionButton {
  label: string;
  type: FeaturedActionType;
  /** URL for `link`, bare email for `email`, ignored otherwise. */
  href: string;
}

/**
 * An admin-curated spotlight card (the "Hudson" template) rendered on the
 * public Coaches page and the Athlete/Creator role pages.
 */
export interface FeaturedProfile {
  id: string;
  kind: FeaturedKind;
  name: string;
  username: string | null;
  user_id: string | null;
  photo_url: string;
  tier: number | null;
  discipline: string | null;
  age: string | null;
  chips: string[];
  paragraphs: string[];
  highlights: string[];
  testimonials: FeaturedTestimonial[];
  cta_label: string | null;
  cta_url: string | null;
  action_buttons: FeaturedActionButton[];
  sort_order: number;
  published: boolean;
}

function normalize(row: Record<string, unknown>): FeaturedProfile {
  const strings = (v: unknown): string[] =>
    Array.isArray(v) ? v.map((s) => String(s ?? "")).filter(Boolean) : [];
  const testimonials: FeaturedTestimonial[] = Array.isArray(row.testimonials)
    ? (row.testimonials as Record<string, unknown>[])
        .map((t) => ({
          quote: String(t?.quote ?? ""),
          name: String(t?.name ?? ""),
          result: String(t?.result ?? ""),
        }))
        .filter((t) => t.quote.length > 0)
    : [];
  const rawButtons = Array.isArray(row.action_buttons)
    ? (row.action_buttons as Record<string, unknown>[])
    : [];
  const actionButtons: FeaturedActionButton[] = rawButtons
    .map((b) => {
      const type = String(b?.type ?? "profile") as FeaturedActionType;
      const valid: FeaturedActionType[] = ["profile", "link", "email", "calendar"];
      return {
        label: String(b?.label ?? "").trim(),
        type: valid.includes(type) ? type : "profile",
        href: String(b?.href ?? "").trim(),
      };
    })
    .filter((b) => b.label.length > 0)
    .slice(0, 3);
  // Backward-compat: rows without action_buttons synthesize one from the
  // legacy cta_label/cta_url so existing profiles keep rendering a button.
  const fallbackButtons: FeaturedActionButton[] =
    actionButtons.length > 0
      ? actionButtons
      : (() => {
          const label = String(row.cta_label ?? "").trim();
          if (!label) return [];
          const href = String(row.cta_url ?? "").trim();
          return [
            {
              label,
              type: href ? "link" : "profile",
              href,
            },
          ];
        })();
  return {
    id: String(row.id ?? ""),
    kind: (row.kind as FeaturedKind) ?? "coach",
    name: String(row.name ?? ""),
    username: (row.username as string | null) ?? null,
    user_id: (row.user_id as string | null) ?? null,
    photo_url: String(row.photo_url ?? ""),
    tier: typeof row.tier === "number" ? row.tier : null,
    discipline: (row.discipline as string | null) ?? null,
    age: (row.age as string | null) ?? null,
    chips: strings(row.chips),
    paragraphs: strings(row.paragraphs),
    highlights: strings(row.highlights),
    testimonials,
    cta_label: (row.cta_label as string | null) ?? null,
    cta_url: (row.cta_url as string | null) ?? null,
    action_buttons: fallbackButtons,
    sort_order: typeof row.sort_order === "number" ? row.sort_order : 0,
    published: row.published !== false,
  };
}

/**
 * The original hand-built Hudson feature — the founding coach card. Shown on
 * the public Coaches page until an admin saves a database-managed "Hudson"
 * row (the admin editor offers this template as a starting point so the
 * account can be linked).
 */
export const HUDSON_TEMPLATE: FeaturedProfile = {
  id: "hudson-static",
  kind: "coach",
  name: "Hudson",
  username: null,
  user_id: null,
  photo_url: "/coaches/hudson.jpeg",
  tier: 1,
  discipline: "Bodybuilding",
  age: "27 years old",
  chips: ["Golf", "Family"],
  paragraphs: [
    "Hudson is a 27-year-old bodybuilding coach who lives by one word: begin. His programming is built around structured hypertrophy blocks, technique-first progressions, and honest weekly check-ins — no crash plans, no shortcuts.",
    "Off the gym floor you'll find him grinding down his golf handicap or with his family — the two things that keep him grounded. That balance shows up in how he coaches: patient, consistent, and built around your real life, not a spreadsheet ideal.",
  ],
  highlights: [
    "Structured hypertrophy blocks",
    "Weekly check-ins & progress photos",
    "Programs & macros right in your DMs",
    "Coaching that fits family life",
  ],
  testimonials: [
    {
      quote:
        "Eight weeks in and my bench finally moved after a year stuck. He rebuilt my technique before adding a single pound.",
      name: "Tyler M.",
      result: "+25 lbs bench · 8 weeks",
    },
    {
      quote:
        "The weekly check-ins are the difference. He actually looks at my progress photos and adjusts the block — not a copy-paste plan.",
      name: "Dani R.",
      result: "−9 lbs · 12 weeks",
    },
    {
      quote:
        "I train around two kids and a job. Hudson programs for my real week instead of a perfect one, so I've never missed a block.",
      name: "Marcus L.",
      result: "16-week streak · 0 missed check-ins",
    },
  ],
  cta_label: "Train with Hudson",
  cta_url: null,
  action_buttons: [{ label: "Train with Hudson", type: "profile", href: "" }],
  sort_order: -1,
  published: true,
};

/**
 * Taylor Brooke — creator spotlight template, pre-built from her website
 * (taylorbrookemedia.com) so the admin can import it with one click and
 * link her Whisper account. Her button links to her external website.
 */
export const TAYLOR_BROOKE_TEMPLATE: FeaturedProfile = {
  id: "taylor-brooke-static",
  kind: "creator",
  name: "Taylor Brooke",
  username: null,
  user_id: null,
  photo_url: "/creators/taylor-brooke.jpeg",
  tier: null,
  discipline: "PR & Brand Storytelling",
  age: null,
  chips: ["Media Personality", "Podcast Host", "Brand Strategist"],
  paragraphs: [
    "Taylor Brooke is a media personality turned PR strategist who doesn't just generate buzz — she builds movements. As the founder of Taylor Brooke Media, she turns brands into cultural forces through award-winning storytelling, social media mastery, and media outreach that actually moves the needle.",
    "Her philosophy is simple: buzz fades, movements last. Every campaign she touches is designed to create lasting influence, not a fleeting spike. She brings humor, candid storytelling, and real industry insight to everything she makes — from brand partnerships to her own shows.",
    "Taylor hosts The Taylor Taylor Taylor Show, a podcast featuring unfiltered conversations with creatives and changemakers. She's a tastemaker who's been Seen, Heard, and Shared across platforms, and she's just getting started.",
  ],
  highlights: [
    "Award-winning storytelling & strategic content",
    "Social media mastery & brand positioning",
    "Host of The Taylor Taylor Taylor Show",
    "PR that moves culture, not just clicks",
  ],
  testimonials: [],
  cta_label: "Visit Taylor Brooke Media",
  cta_url: "https://taylorbrookemedia.com",
  action_buttons: [
    { label: "Visit Taylor Brooke Media", type: "link", href: "https://taylorbrookemedia.com" },
  ],
  sort_order: 0,
  published: true,
};

/** Published featured profiles for a public page (anon read, RLS-guarded). */
export async function fetchFeaturedProfiles(
  kind: FeaturedKind
): Promise<FeaturedProfile[]> {
  const { data, error } = await supabase
    .from("whisper_featured_profiles")
    .select("*")
    .eq("kind", kind)
    .eq("published", true)
    .order("sort_order", { ascending: true })
    .order("created_at", { ascending: true });
  if (error) {
    // Table may not exist yet — public pages fall back to static content.
    console.warn("fetchFeaturedProfiles failed", error.message);
    return [];
  }
  return (data ?? []).map((row) => normalize(row as Record<string, unknown>));
}

/**
 * Published featured spotlight for a linked account, if an admin created one.
 * Used by the in-app coach preview and search cards to enrich real profiles.
 */
export async function fetchFeaturedProfileByUsername(
  username: string
): Promise<FeaturedProfile | null> {
  const clean = username.trim().replace(/^@/, "");
  if (!clean) return null;
  const { data, error } = await supabase
    .from("whisper_featured_profiles")
    .select("*")
    .ilike("username", clean)
    .eq("published", true)
    .limit(1)
    .maybeSingle();
  if (error || !data) return null;
  return normalize(data as Record<string, unknown>);
}

/** Admin: every row including drafts (requires admin token). */
export async function adminFetchFeatured(
  token: string
): Promise<FeaturedProfile[]> {
  const res = await fetch(`${BACKEND_URL}/admin/featured`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (res.status === 403) throw new Error("forbidden");
  if (!res.ok) throw new Error("Couldn't load featured profiles.");
  const data = (await res.json()) as { profiles?: Record<string, unknown>[] };
  return (data.profiles ?? []).map(normalize);
}

/** Payload the admin editor sends when saving a profile. */
export interface FeaturedUpsertInput {
  id?: string;
  kind: FeaturedKind;
  name: string;
  username: string | null;
  photo_url: string;
  tier: number | null;
  discipline: string | null;
  age: string | null;
  chips: string[];
  paragraphs: string[];
  highlights: string[];
  testimonials: FeaturedTestimonial[];
  cta_label: string | null;
  cta_url: string | null;
  action_buttons: FeaturedActionButton[];
  sort_order: number;
  published: boolean;
}

export async function adminUpsertFeatured(
  token: string,
  input: FeaturedUpsertInput
): Promise<{ id: string }> {
  const res = await fetch(`${BACKEND_URL}/admin/featured/upsert`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(input),
  });
  const data = (await res.json()) as { ok?: boolean; id?: string; error?: string };
  if (!res.ok || !data.ok || !data.id) {
    throw new Error(
      data.error === "forbidden"
        ? "Your account doesn't have admin permissions."
        : "Couldn't save the profile. Try again."
    );
  }
  return { id: data.id };
}

export async function adminDeleteFeatured(
  token: string,
  id: string
): Promise<void> {
  const res = await fetch(`${BACKEND_URL}/admin/featured/delete`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ id }),
  });
  const data = (await res.json()) as { ok?: boolean; error?: string };
  if (!res.ok || !data.ok) {
    throw new Error("Couldn't delete the profile. Try again.");
  }
}
