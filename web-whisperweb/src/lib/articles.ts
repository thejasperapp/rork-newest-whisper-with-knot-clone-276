import { supabase } from "@/lib/supabase";
import { BACKEND_URL } from "@/lib/billing";

/** An admin-written article shown on the public site. */
export interface Article {
  id: string;
  slug: string;
  title: string;
  excerpt: string;
  cover_url: string;
  category: string;
  author_name: string;
  /** Author's username — used to link the byline to their profile. */
  author_username?: string | null;
  /** Author's user_id — used to fetch their profile as a fallback. */
  author_user_id?: string | null;
  /** Author's avatar URL — hydrated client-side from whisper_profiles. */
  author_avatar_url?: string | null;
  /** Optional link to a Featured Film — the article renders the film's trailer (or clipped section). */
  film_id?: string | null;
  /** For clipped articles: the spot in the film the article is about. */
  clip_time_seconds?: number | null;
  paragraphs: string[];
  published: boolean;
  published_at: string | null;
}

/** Backend-generated film-frame cover token: `film-frame:<filmId>:<seconds>`.
 *  No <img> can load it directly — render it via the film's poster instead. */
export interface FilmFrameCover {
  filmId: string;
  timeSeconds: number;
}

export function parseFilmFrameCover(
  cover: string | null | undefined
): FilmFrameCover | null {
  const t = (cover ?? "").trim();
  if (!t.startsWith("film-frame:")) return null;
  const parts = t.split(":");
  const filmId = parts[1] ?? "";
  if (!filmId) return null;
  const secs = Number(parts[2] ?? 0);
  return { filmId, timeSeconds: Number.isFinite(secs) ? Math.max(0, secs) : 0 };
}

/** True when a cover value is a real URL an <img>/<video poster> can load. */
export function isRenderableCover(cover: string | null | undefined): boolean {
  return /^https?:\/\//.test((cover ?? "").trim());
}

function normalize(row: Record<string, unknown>): Article {
  return {
    id: String(row.id ?? ""),
    slug: String(row.slug ?? ""),
    title: String(row.title ?? ""),
    excerpt: String(row.excerpt ?? ""),
    cover_url: String(row.cover_url ?? ""),
    category: String(row.category ?? "Training"),
    author_name: String(row.author_name ?? "Whisper Team"),
    author_username: (row.author_username as string | null) ?? null,
    author_user_id: (row.author_user_id as string | null) ?? null,
    author_avatar_url: (row.author_avatar_url as string | null) ?? null,
    film_id: (row.film_id as string | null) ?? null,
    clip_time_seconds: (row.clip_time_seconds as number | null) ?? null,
    paragraphs: Array.isArray(row.paragraphs)
      ? (row.paragraphs as unknown[]).map((p) => String(p ?? "")).filter(Boolean)
      : [],
    published: row.published !== false,
    published_at: (row.published_at as string | null) ?? null,
  };
}

/** Hydrate author profile data (username, display_name, avatar) for articles
 *  whose author_username is missing or whose author_name is the generic
 *  "Whisper Team" fallback. Fetches whisper_profiles by author_user_id. */
async function withAuthorProfiles(articles: Article[]): Promise<Article[]> {
  const missing = articles.filter(
    (a) => a.author_user_id && (!a.author_username || a.author_name === "Whisper Team")
  );
  if (missing.length === 0) return articles;
  const ids = Array.from(new Set(missing.map((a) => a.author_user_id!).filter(Boolean)));
  try {
    const { data } = await supabase
      .from("whisper_profiles")
      .select("user_id,username,display_name,profile_image_url")
      .in("user_id", ids);
    const map: Record<string, { username: string | null; display_name: string | null; profile_image_url: string | null }> = {};
    for (const r of (data as { user_id: string; username: string | null; display_name: string | null; profile_image_url: string | null }[] | null) ?? []) {
      map[r.user_id] = r;
    }
    return articles.map((a) => {
      if (!a.author_user_id) return a;
      const p = map[a.author_user_id];
      if (!p) return a;
      return {
        ...a,
        author_username: a.author_username ?? p.username,
        author_name: a.author_name === "Whisper Team" ? (p.display_name ?? p.username ?? a.author_name) : a.author_name,
        author_avatar_url: p.profile_image_url ?? null,
      };
    });
  } catch {
    return articles;
  }
}

/** Published articles for the public Articles page (anon read, RLS-guarded). */
export async function fetchArticles(): Promise<Article[]> {
  const { data, error } = await supabase
    .from("whisper_articles")
    .select("*")
    .eq("published", true)
    .order("published_at", { ascending: false })
    .limit(100);
  if (error) {
    console.warn("fetchArticles failed", error.message);
    return [];
  }
  return (data ?? []).map((row) => normalize(row as Record<string, unknown>));
}

/** One published article by slug. */
export async function fetchArticle(slug: string): Promise<Article | null> {
  const { data, error } = await supabase
    .from("whisper_articles")
    .select("*")
    .eq("slug", slug)
    .eq("published", true)
    .limit(1);
  if (error) {
    console.warn("fetchArticle failed", error.message);
    return null;
  }
  const row = data?.[0];
  if (!row) return null;
  const article = normalize(row as Record<string, unknown>);
  // Hydrate author profile if the byline is missing or generic.
  const hydrated = await withAuthorProfiles([article]);
  return hydrated[0] ?? article;
}

/** Badge holder (coach/athlete/creator): their own articles, drafts included. */
export async function authorFetchArticles(token: string): Promise<Article[]> {
  const res = await fetch(`${BACKEND_URL}/author/articles`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (res.status === 403) throw new Error("forbidden");
  if (!res.ok) throw new Error("Couldn't load your articles.");
  const data = (await res.json()) as { articles?: Record<string, unknown>[] };
  return (data.articles ?? []).map(normalize);
}

/** Badge holder saves one of their own articles (byline locked server-side). */
export async function authorUpsertArticle(
  token: string,
  input: ArticleUpsertInput
): Promise<{ id: string; slug: string }> {
  const res = await fetch(`${BACKEND_URL}/author/articles/upsert`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(input),
  });
  const data = (await res.json()) as {
    ok?: boolean;
    id?: string;
    slug?: string;
    error?: string;
  };
  if (!res.ok || !data.ok || !data.id) {
    throw new Error(
      data.error === "forbidden"
        ? "Only coaches, athletes, and verified creators can publish articles."
        : "Couldn't save the article. Try again."
    );
  }
  return { id: data.id, slug: data.slug ?? "" };
}

/** Badge holder deletes one of their own articles. */
export async function authorDeleteArticle(
  token: string,
  id: string
): Promise<void> {
  const res = await fetch(`${BACKEND_URL}/author/articles/delete`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ id }),
  });
  const data = (await res.json()) as { ok?: boolean };
  if (!res.ok || !data.ok) {
    throw new Error("Couldn't delete the article. Try again.");
  }
}

/** Admin: every article including drafts. */
export async function adminFetchArticles(token: string): Promise<Article[]> {
  const res = await fetch(`${BACKEND_URL}/admin/articles`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (res.status === 403) throw new Error("forbidden");
  if (!res.ok) throw new Error("Couldn't load articles.");
  const data = (await res.json()) as { articles?: Record<string, unknown>[] };
  return (data.articles ?? []).map(normalize);
}

/** Payload the admin editor sends when saving an article. */
export interface ArticleUpsertInput {
  id?: string;
  slug?: string;
  title: string;
  excerpt: string;
  cover_url: string;
  category: string;
  author_name: string;
  paragraphs: string[];
  published: boolean;
  /** Optional link to a Featured Film — the article renders the film's trailer (or clipped section). */
  film_id?: string;
  /** For clipped articles: the spot in the film the article is about. */
  clip_time_seconds?: number;
}

export async function adminUpsertArticle(
  token: string,
  input: ArticleUpsertInput
): Promise<{ id: string; slug: string }> {
  const res = await fetch(`${BACKEND_URL}/admin/articles/upsert`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(input),
  });
  const data = (await res.json()) as {
    ok?: boolean;
    id?: string;
    slug?: string;
    error?: string;
  };
  if (!res.ok || !data.ok || !data.id) {
    throw new Error(
      data.error === "forbidden"
        ? "Your account doesn't have admin permissions."
        : "Couldn't save the article. Try again."
    );
  }
  return { id: data.id, slug: data.slug ?? "" };
}

/**
 * Admin: insert the Whisper-written starter articles (skips slugs that
 * already exist, so it's safe to press twice).
 */
export async function adminSeedArticles(
  token: string
): Promise<{ inserted: number }> {
  const res = await fetch(`${BACKEND_URL}/admin/articles/seed`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });
  const data = (await res.json().catch(() => ({}))) as {
    ok?: boolean;
    inserted?: number;
    error?: string;
  };
  if (!res.ok || !data.ok) {
    throw new Error(
      data.error === "forbidden"
        ? "Your account doesn't have admin permissions."
        : "Couldn't add the starter articles. Try again."
    );
  }
  return { inserted: data.inserted ?? 0 };
}

export async function adminDeleteArticle(
  token: string,
  id: string
): Promise<void> {
  const res = await fetch(`${BACKEND_URL}/admin/articles/delete`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ id }),
  });
  const data = (await res.json()) as { ok?: boolean };
  if (!res.ok || !data.ok) {
    throw new Error("Couldn't delete the article. Try again.");
  }
}
