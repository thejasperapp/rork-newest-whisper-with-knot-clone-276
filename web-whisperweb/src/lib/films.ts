import { supabase } from "@/lib/supabase";
import { BACKEND_URL } from "@/lib/billing";

/**
 * Featured Film Friday client — short films produced by the Whisper media
 * team (Directors). Films are published by directors/mods/admins/owners;
 * users with blogging permissions can timestamp moments and generate clip
 * placeholders for articles.
 */

export interface Film {
  id: string;
  director_id: string;
  title: string;
  synopsis: string | null;
  video_url: string;
  /** Optional short trailer the director uploads alongside the full film. */
  trailer_url: string | null;
  poster_url: string | null;
  duration_seconds: number | null;
  featured_date: string | null;
  published: boolean;
  created_at: string;
  updated_at: string;
  /** Joined director display name (from whisper_profiles). */
  director_name?: string | null;
  /** Joined director username — used to link to the director's profile. */
  director_username?: string | null;
  /** Tags describing the film (genre, mood, subject). */
  tags?: string[] | null;
}

/** Fetch a single profile by user_id from whisper_profiles (client-side
 *  fallback when the backend join misses a director). */
async function fetchProfileByUserId(
  userId: string
): Promise<{ username: string | null; display_name: string | null } | null> {
  try {
    const { data } = await supabase
      .from("whisper_profiles")
      .select("username,display_name")
      .eq("user_id", userId)
      .limit(1)
      .maybeSingle();
    return (data as { username: string | null; display_name: string | null } | null) ?? null;
  } catch {
    return null;
  }
}

/** Batch-fetch profiles by user_id (client-side fallback for film lists). */
async function fetchProfilesByUserIds(
  userIds: string[]
): Promise<Record<string, { username: string | null; display_name: string | null }>> {
  const unique = Array.from(new Set(userIds.filter(Boolean)));
  if (unique.length === 0) return {};
  try {
    const { data } = await supabase
      .from("whisper_profiles")
      .select("user_id,username,display_name")
      .in("user_id", unique);
    const map: Record<string, { username: string | null; display_name: string | null }> = {};
    for (const r of (data as { user_id: string; username: string | null; display_name: string | null }[] | null) ?? []) {
      map[r.user_id] = { username: r.username, display_name: r.display_name };
    }
    return map;
  } catch {
    return {};
  }
}

/** Ensure every film has director_name + director_username, fetching
 *  client-side when the backend join came back empty. */
async function withDirectorProfiles(films: Film[]): Promise<Film[]> {
  const missing = films.filter(
    (f) => !f.director_username && !f.director_name && f.director_id
  );
  if (missing.length === 0) return films;
  const profiles = await fetchProfilesByUserIds(missing.map((f) => f.director_id));
  return films.map((f) => {
    const p = profiles[f.director_id];
    if (!p) return f;
    return {
      ...f,
      director_name: f.director_name ?? p.display_name,
      director_username: f.director_username ?? p.username,
    };
  });
}

export interface FilmTimestamp {
  id: string;
  film_id: string;
  user_id: string;
  label: string;
  time_seconds: number;
  poster_url: string | null;
  created_at: string;
  /** Joined author display name. */
  author_name?: string | null;
  /** Joined author username. */
  author_username?: string | null;
}

async function accessToken(): Promise<string> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error("Please sign in first.");
  return token;
}

const FILM_COLUMNS =
  "id,director_id,title,synopsis,video_url,trailer_url,poster_url,duration_seconds,featured_date,published,created_at,updated_at";

/** Fetch all published films, newest featured first. Uses the backend GET
 *  /films endpoint so the director's profile is joined for proper credit. */
export async function fetchFilms(): Promise<Film[]> {
  try {
    const res = await fetch(`${BACKEND_URL}/films`);
    if (!res.ok) throw new Error("films_failed");
    const data = (await res.json()) as { films?: Film[] };
    return data.films ?? [];
  } catch {
    // Fallback to the public Supabase read if the backend is unreachable.
    const { data, error } = await supabase
      .from("whisper_films")
      .select(FILM_COLUMNS)
      .eq("published", true)
      .order("featured_date", { ascending: false, nullsFirst: false })
      .order("created_at", { ascending: false })
      .limit(30);
    if (error) return [];
    return await withDirectorProfiles((data as Film[]) ?? []);
  }
}

/** Fetch a single published film by id. Uses the backend GET /films/get
 *  endpoint so the director's profile is joined for proper credit. */
export async function fetchFilm(id: string): Promise<Film | null> {
  try {
    const res = await fetch(`${BACKEND_URL}/films/get?id=${encodeURIComponent(id)}`);
    if (!res.ok) throw new Error("film_failed");
    const data = (await res.json()) as { film?: Film };
    return data.film ?? null;
  } catch {
    const { data, error } = await supabase
      .from("whisper_films")
      .select(FILM_COLUMNS)
      .eq("id", id)
      .eq("published", true)
      .limit(1)
      .maybeSingle();
    if (error || !data) return null;
    const film = data as Film;
    // Client-side fallback when the backend isn't reachable — fetch the
    // director's profile so the credit still links to a real profile.
    if (film.director_id && !film.director_username && !film.director_name) {
      const p = await fetchProfileByUserId(film.director_id);
      if (p) {
        film.director_name = p.display_name;
        film.director_username = p.username;
      }
    }
    return film;
  }
}

/** Fetch timestamps for a film (public — visible to all viewers). */
export async function fetchFilmTimestamps(filmId: string): Promise<FilmTimestamp[]> {
  const { data, error } = await supabase
    .from("whisper_film_timestamps")
    .select(
      "id,film_id,user_id,label,time_seconds,poster_url,created_at"
    )
    .eq("film_id", filmId)
    .order("time_seconds", { ascending: true });
  if (error) return [];
  return (data as FilmTimestamp[]) ?? [];
}

/**
 * Create a timestamp at a specific moment in a film. The backend generates
 * a poster frame placeholder URL that can substitute for the cover image in
 * an article paragraph.
 */
export async function createFilmTimestamp(opts: {
  filmId: string;
  label: string;
  timeSeconds: number;
}): Promise<FilmTimestamp> {
  const token = await accessToken();
  const res = await fetch(`${BACKEND_URL}/films/timestamps`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      filmId: opts.filmId,
      label: opts.label.trim(),
      timeSeconds: Math.max(0, Math.round(opts.timeSeconds)),
    }),
  });
  const body = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok || !body.ok) {
    throw new Error(
      typeof body.error === "string" ? body.error : "Couldn't save that timestamp."
    );
  }
  return body.timestamp as FilmTimestamp;
}

/** Delete a timestamp (only the author can delete their own). */
export async function deleteFilmTimestamp(id: string): Promise<void> {
  const token = await accessToken();
  const res = await fetch(`${BACKEND_URL}/films/timestamps`, {
    method: "DELETE",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ id }),
  });
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as Record<string, unknown>;
    throw new Error(
      typeof body.error === "string" ? body.error : "Couldn't delete that timestamp."
    );
  }
}

/** Create a new film (directors/mods/admins/owners only). */
export async function createFilm(opts: {
  title: string;
  synopsis: string;
  videoUrl: string;
  /** Optional short trailer shown on any article written about the film. */
  trailerUrl?: string;
  posterUrl: string;
  durationSeconds: number | null;
  featuredDate: string | null;
  published: boolean;
}): Promise<void> {
  const token = await accessToken();
  const res = await fetch(`${BACKEND_URL}/films/create`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      ...opts,
      trailerUrl: opts.trailerUrl ?? "",
    }),
  });
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as Record<string, unknown>;
    throw new Error(
      typeof body.error === "string" ? body.error : "Couldn't publish that film."
    );
  }
}

/* ------------------------------------------------------------------ */
/* Film engagement — likes, dislikes, comments, shares                  */
/* ------------------------------------------------------------------ */

export interface FilmReactionCounts {
  likes: number;
  dislikes: number;
  /** "like" | "dislike" | null if the user hasn't reacted. */
  mine: "like" | "dislike" | null;
}

export interface FilmComment {
  id: string;
  film_id: string;
  user_id: string;
  body: string;
  reply_to_comment_id: string | null;
  created_at: string;
  /** Joined author display name. */
  author_name?: string | null;
  /** Joined author username. */
  author_username?: string | null;
  /** Author avatar URL (hydrated client-side). */
  author_avatar_url?: string | null;
  /** Child replies (hydrated client-side for threading). */
  replies?: FilmComment[];
}

/** Canonical public origin for shareable Whisper links. */
export const WHISPER_ORIGIN = "https://mydailywhisper.com";

/** Fetch reaction counts + the signed-in user's own reaction for a film. */
export async function fetchFilmReactions(
  filmId: string
): Promise<FilmReactionCounts> {
  // Count rows via the public view.
  const { data: countRow, error: countErr } = await supabase
    .from("whisper_film_reaction_counts")
    .select("like_count,dislike_count")
    .eq("film_id", filmId)
    .limit(1)
    .maybeSingle();
  if (countErr) {
    return { likes: 0, dislikes: 0, mine: null };
  }
  const row = countRow as { like_count?: number; dislike_count?: number } | null;
  const likes = Number(row?.like_count ?? 0);
  const dislikes = Number(row?.dislike_count ?? 0);

  // The signed-in user's own reaction.
  const { data: session } = await supabase.auth.getSession();
  if (!session.session?.user) return { likes, dislikes, mine: null };
  const { data: mineRow } = await supabase
    .from("whisper_film_reactions")
    .select("weight")
    .eq("film_id", filmId)
    .eq("user_id", session.session.user.id)
    .limit(1)
    .maybeSingle();
  const mine = (mineRow as { weight?: string } | null)?.weight;
  return {
    likes,
    dislikes,
    mine: mine === "like" || mine === "dislike" ? mine : null,
  };
}

/** Set or toggle the signed-in user's reaction. */
export async function setFilmReaction(
  filmId: string,
  weight: "like" | "dislike"
): Promise<void> {
 const { data: session } = await supabase.auth.getSession();
  const userId = session.session?.user?.id;
  if (!userId) throw new Error("Please sign in to react.");
  // Toggle: if the user already has this reaction, remove it.
  const { data: existing } = await supabase
    .from("whisper_film_reactions")
    .select("id,weight")
    .eq("film_id", filmId)
    .eq("user_id", userId)
    .limit(1)
    .maybeSingle();
  const existingRow = existing as { id?: string; weight?: string } | null;
  if (existingRow?.weight === weight) {
    // Same reaction → remove it (take back).
    const { error } = await supabase
      .from("whisper_film_reactions")
      .delete()
      .eq("id", existingRow.id!);
    if (error) throw new Error("Couldn't update your reaction.");
    return;
  }
  if (existingRow?.id) {
    // Different reaction → update it.
    const { error } = await supabase
      .from("whisper_film_reactions")
      .update({ weight })
      .eq("id", existingRow.id);
    if (error) throw new Error("Couldn't update your reaction.");
    return;
  }
  // No existing reaction → insert.
  const { error } = await supabase
    .from("whisper_film_reactions")
    .insert({ film_id: filmId, user_id: userId, weight });
  if (error) throw new Error("Couldn't save your reaction.");
}

/** Fetch comments for a film, newest first. Hydrates author profiles
 *  (username, display_name, avatar) client-side so every comment shows a
 *  real avatar and links to a real profile — the comments table only stores
 *  user_id, so without this step every commenter looks like "Member". */
export async function fetchFilmComments(filmId: string): Promise<FilmComment[]> {
  const { data, error } = await supabase
    .from("whisper_film_comments")
    .select("id,film_id,user_id,body,reply_to_comment_id,created_at")
    .eq("film_id", filmId)
    .order("created_at", { ascending: true })
    .limit(200);
  if (error) return [];
  const rows = (data as FilmComment[]) ?? [];
  if (rows.length === 0) return [];

  // Batch-fetch author profiles so avatars + usernames render.
  const userIds = Array.from(new Set(rows.map((r) => r.user_id).filter(Boolean)));
  const profileMap: Record<string, { username: string | null; display_name: string | null; profile_image_url: string | null }> = {};
  if (userIds.length > 0) {
    try {
      const { data: profiles } = await supabase
        .from("whisper_profiles")
        .select("user_id,username,display_name,profile_image_url")
        .in("user_id", userIds);
      for (const p of (profiles as { user_id: string; username: string | null; display_name: string | null; profile_image_url: string | null }[] | null) ?? []) {
        profileMap[p.user_id] = p;
      }
    } catch {
      // best-effort — comments still render without avatars
    }
  }

  const hydrated = rows.map((c) => {
    const p = profileMap[c.user_id];
    return {
      ...c,
      author_username: p?.username ?? null,
      author_name: p?.display_name ?? null,
      author_avatar_url: p?.profile_image_url ?? null,
    };
  });

  // Build a threaded structure: top-level comments with nested replies.
  const byId = new Map(hydrated.map((c) => [c.id, { ...c, replies: [] as FilmComment[] }]));
  const topLevel: FilmComment[] = [];
  for (const c of hydrated) {
    if (c.reply_to_comment_id && byId.has(c.reply_to_comment_id)) {
      byId.get(c.reply_to_comment_id)!.replies!.push(c);
    } else {
      topLevel.push(byId.get(c.id)!);
    }
  }
  // Top-level newest first, replies oldest first (conversation order).
  topLevel.sort((a, b) => (b.created_at > a.created_at ? 1 : -1));
  for (const c of topLevel) {
    c.replies?.sort((a, b) => (a.created_at > b.created_at ? 1 : -1));
  }
  return topLevel;
}

/** Post a comment (optionally a reply to another comment). */
export async function createFilmComment(opts: {
  filmId: string;
  body: string;
  replyToCommentId?: string | null;
}): Promise<void> {
  const { data: session } = await supabase.auth.getSession();
  const userId = session.session?.user?.id;
  if (!userId) throw new Error("Please sign in to comment.");
  const body = opts.body.trim().slice(0, 2000);
  if (!body) throw new Error("Comment can't be empty.");
  const { error } = await supabase.from("whisper_film_comments").insert({
    film_id: opts.filmId,
    user_id: userId,
    body,
    reply_to_comment_id: opts.replyToCommentId ?? null,
  });
  if (error) throw new Error("Couldn't post that comment.");
}

/** Delete the signed-in user's own comment. */
export async function deleteFilmComment(id: string): Promise<void> {
  const { error } = await supabase
    .from("whisper_film_comments")
    .delete()
    .eq("id", id);
  if (error) throw new Error("Couldn't delete that comment.");
}

/** Edit the signed-in user's own comment body. */
export async function editFilmComment(id: string, body: string): Promise<void> {
  const trimmed = body.trim().slice(0, 2000);
  if (!trimmed) throw new Error("Comment can't be empty.");
  const { error } = await supabase
    .from("whisper_film_comments")
    .update({ body: trimmed })
    .eq("id", id);
  if (error) throw new Error("Couldn't edit that comment.");
}

/** Format seconds as M:SS. */
export function formatTimecode(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}
