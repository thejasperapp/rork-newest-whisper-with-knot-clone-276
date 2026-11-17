import { memo, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  Search,
  TrendingUp,
  Users,
  Hash,
  X,
  BookOpen,
  Loader2,
} from "lucide-react";

import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";
import { useProfileSearch } from "@/hooks/useProfileSearch";
import { Avatar } from "@/components/Avatar";
import { LiveRail } from "@/components/LiveRail";
import { ViewMoreList } from "@/components/ui/ViewMoreList";
import { fetchProfilesByIds } from "@/lib/api";
import { fetchArticles, type Article } from "@/lib/articles";
import { supabase } from "@/lib/supabase";
import type { WhisperProfile } from "@/lib/types";

/* ------------------------------------------------------------------ */
/*  Trending topics — derived from recent post captions               */
/* ------------------------------------------------------------------ */

interface TrendingTag {
  tag: string;
  count: number;
}

async function fetchTrendingTags(): Promise<TrendingTag[]> {
  const { data } = await supabase
    .from("whisper_posts")
    .select("caption")
    .order("created_at", { ascending: false })
    .limit(200);
  const counts = new Map<string, number>();
  for (const row of (data as { caption: string }[] | null) ?? []) {
    const matches = row.caption?.match(/#[\w]+/g) ?? [];
    for (const m of matches) {
      const tag = m.toLowerCase();
      counts.set(tag, (counts.get(tag) ?? 0) + 1);
    }
  }
  return Array.from(counts.entries())
    .map(([tag, count]) => ({ tag, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 8);
}

/* ------------------------------------------------------------------ */
/*  Trending articles — formula: recency × views × featured boost     */
/* ------------------------------------------------------------------ */

interface TrendingArticle {
  article: Article;
  score: number;
}

async function fetchTrendingArticles(): Promise<TrendingArticle[]> {
  const articles = await fetchArticles();
  const now = Date.now();
  return articles
    .map((article) => {
      // Recency factor: posts within 7 days get full weight, decaying over 30 days
      const publishedMs = article.published_at
        ? new Date(article.published_at).getTime()
        : now;
      const daysSince = Math.max(0, (now - publishedMs) / 86_400_000);
      const recencyScore = Math.max(0.1, 1 - daysSince / 30);

      // View factor (if available, otherwise neutral)
      const views = (article as unknown as { views?: number }).views ?? 0;
      const viewScore = 1 + Math.log10(Math.max(1, views + 1));

      // Featured boost
      const featuredBoost = (article as unknown as { is_featured?: boolean }).is_featured
        ? 1.5
        : 1.0;

      // Final formula: recency × log(views+1) × featured_boost
      const score = recencyScore * viewScore * featuredBoost;
      return { article, score };
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, 4);
}

/* ------------------------------------------------------------------ */
/*  Inline search results                                              */
/* ------------------------------------------------------------------ */

/* ------------------------------------------------------------------ */
/*  Component                                                          */
/* ------------------------------------------------------------------ */

function RightRailBase() {
  const { user, profile } = useAuth();
  const navigate = useNavigate();
  const [searchQuery, setSearchQuery] = useState<string>("");
  const trimmed = searchQuery.trim();

  const trendingQuery = useQuery({
    queryKey: ["trending-tags"],
    queryFn: fetchTrendingTags,
    staleTime: 60_000,
  });

  const articlesQuery = useQuery({
    queryKey: ["trending-articles"],
    queryFn: fetchTrendingArticles,
    staleTime: 120_000,
  });

  // Inline search — populates results beneath the pill instead of navigating
  const searchResultsQuery = useProfileSearch(user?.id, searchQuery);

  const trending = trendingQuery.data ?? [];
  const trendingArticles = articlesQuery.data ?? [];
  const searchResults = (searchResultsQuery.data ?? []).slice(0, 6);
  const isSearching = searchResultsQuery.isSearching;

  return (
    <aside className="sticky top-0 hidden h-[100dvh] max-h-[100dvh] w-[320px] shrink-0 flex-col gap-5 overflow-y-auto py-6 pl-6 pr-1 xl:flex">
      {/* Inline search pill + results */}
      <div className="social-rail-panel rounded-2xl border border-border/50 bg-background/60 p-4 backdrop-blur-sm">
        <div className="flex items-center gap-3 rounded-full border border-border/60 bg-secondary/40 px-4 py-2.5 transition-colors focus-within:border-foreground/30">
          <Search className="h-4 w-4 shrink-0 text-muted-foreground" />
          <input
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search Whisper"
            autoCapitalize="none"
            autoCorrect="off"
            className="min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-muted-foreground"
          />
          {searchQuery.length > 0 && (
            <button
              onClick={() => setSearchQuery("")}
              aria-label="Clear search"
              className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-muted-foreground/30 text-background transition-transform active:scale-90"
            >
              <X className="h-3 w-3" strokeWidth={3} />
            </button>
          )}
        </div>

        {/* Inline results — appear beneath the pill */}
        {trimmed.length >= 1 && (
          <div className="mt-3">
            {isSearching ? (
              <div className="flex items-center gap-2 py-3 text-sm text-muted-foreground">
                <Loader2 className="h-4 w-4 animate-spin" />
                Searching…
              </div>
            ) : searchResultsQuery.isError ? (
              <div role="status" className="py-3 text-sm text-muted-foreground">
                <p>Search is unavailable for a moment.</p>
                <button type="button" onClick={() => void searchResultsQuery.refetch()} className="mt-2 min-h-11 rounded-full bg-secondary px-4 font-semibold text-foreground transition-colors hover:bg-secondary/70">Try again</button>
              </div>
            ) : searchResults.length === 0 ? (
              <p className="py-3 text-sm text-muted-foreground">
                No users found for "{trimmed}"
              </p>
            ) : (
              <div className="flex flex-col gap-1">
                {searchResults.map((p) => (
                  <Link
                    key={p.user_id}
                    to={`/u/${encodeURIComponent(p.username)}`}
                    onClick={() => setSearchQuery("")}
                    className="flex items-center gap-3 rounded-lg px-2 py-2 transition-colors hover:bg-secondary/60"
                  >
                    <Avatar
                      url={p.profile_image_url}
                      name={p.username}
                      size={36}
                    />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-semibold">
                        @{p.username}
                      </p>
                      <p className="truncate text-xs text-muted-foreground">
                        {p.display_name ||
                          (p.is_coach
                            ? "Coach"
                            : p.is_verified
                              ? "Creator"
                              : "Whisper member")}
                      </p>
                    </div>
                  </Link>
                ))}
                <Link
                  to={`/search?q=${encodeURIComponent(trimmed)}`}
                  onClick={() => setSearchQuery("")}
                  className="mt-1 rounded-lg px-2 py-2 text-sm font-semibold text-primary transition-colors hover:bg-secondary/60"
                >
                  See all results →
                </Link>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Trending topics */}
      {trending.length > 0 && (
        <section className="social-rail-panel rounded-2xl border border-border/50 bg-background/60 p-4 backdrop-blur-sm">
          <h3 className="mb-3 flex items-center gap-2 text-sm font-bold">
            <TrendingUp className="h-4 w-4" />
            Trending
          </h3>
          <ViewMoreList
            items={trending}
            maxVisible={6}
            itemClassName="flex flex-col gap-1"
            renderItem={(t) => (
              <Link
                key={t.tag}
                to={`/search?q=${encodeURIComponent(t.tag)}`}
                className="flex items-center justify-between rounded-lg px-2 py-1.5 transition-colors hover:bg-secondary/60"
              >
                <span className="flex items-center gap-2 text-sm font-medium">
                  <Hash className="h-3 w-3 text-muted-foreground" />
                  {t.tag.slice(1)}
                </span>
                <span className="text-xs text-muted-foreground">
                  {t.count}
                </span>
              </Link>
            )}
          />
        </section>
      )}

      {/* Trending articles */}
      {trendingArticles.length > 0 && (
        <section className="social-rail-panel rounded-2xl border border-border/50 bg-background/60 p-4 backdrop-blur-sm">
          <h3 className="mb-3 flex items-center gap-2 text-sm font-bold">
            <BookOpen className="h-4 w-4" />
            Trending articles
          </h3>
          <ViewMoreList
            items={trendingArticles}
            maxVisible={3}
            itemClassName="flex flex-col gap-2"
            renderItem={({ article }) => (
              <Link
                key={article.id}
                to={`/articles/${article.slug}`}
                className="flex items-start gap-3 rounded-lg px-1 py-1.5 transition-colors hover:bg-secondary/60"
              >
                <div className="h-12 w-12 shrink-0 overflow-hidden rounded-lg bg-secondary">
                  {article.cover_url ? (
                    <img
                      src={article.cover_url}
                      alt=""
                      loading="lazy"
                      className="h-full w-full object-cover"
                    />
                  ) : (
                    <div className="flex h-full w-full items-center justify-center">
                      <BookOpen className="h-4 w-4 text-muted-foreground" />
                    </div>
                  )}
                </div>
                <div className="min-w-0 flex-1">
                  <p className="line-clamp-2 text-[13px] font-semibold leading-snug">
                    {article.title}
                  </p>
                  <p className="mt-0.5 truncate text-[11px] text-muted-foreground">
                    {article.category} · {article.author_name}
                  </p>
                </div>
              </Link>
            )}
          />
        </section>
      )}

      {/* Live system — X-style live friends, Spaces, and trending */}
      <LiveRail />

      {/* Suggested people */}
      <section className="social-rail-panel rounded-2xl border border-border/50 bg-background/60 p-4 backdrop-blur-sm">
        <h3 className="mb-3 flex items-center gap-2 text-sm font-bold">
          <Users className="h-4 w-4" />
          Who to follow
        </h3>
        <SuggestedPeople />
      </section>

      {/* Footer */}

      {/* Footer */}
      <footer className="px-2 text-xs text-muted-foreground/60">
        <p>Whisper &middot; {new Date().getFullYear()}</p>
      </footer>
    </aside>
  );
}

/* ------------------------------------------------------------------ */
/*  Suggested people — recent verified/coach profiles                  */
/* ------------------------------------------------------------------ */

function SuggestedPeople() {
  const { user } = useAuth();
  const navigate = useNavigate();

  const { data } = useQuery({
    queryKey: ["suggested-people", user?.id],
    queryFn: async () => {
      const { data: rows } = await supabase
        .from("whisper_profiles")
        .select("user_id, username, display_name, profile_image_url, is_verified, is_coach")
        .neq("user_id", user!.id)
        .or("is_verified.eq.true,is_coach.eq.true")
        .order("created_at", { ascending: false })
        .limit(4);
      return (rows as {
        user_id: string;
        username: string;
        display_name: string | null;
        profile_image_url: string | null;
        is_verified: boolean | null;
        is_coach: boolean | null;
      }[] | null) ?? [];
    },
    enabled: !!user,
    staleTime: 120_000,
  });

  const suggestions = data ?? [];
  if (suggestions.length === 0) {
    return (
      <p className="py-2 text-sm text-muted-foreground">
        No suggestions yet.
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-1">
      {suggestions.map((s) => (
        <div
          key={s.user_id}
          className="flex items-center gap-3 rounded-lg px-2 py-1.5 transition-colors hover:bg-secondary/60"
        >
          <button onClick={() => navigate(`/u/${encodeURIComponent(s.username)}`)}>
            <Avatar
              url={s.profile_image_url}
              name={s.username}
              size={36}
            />
          </button>
          <button
            onClick={() => navigate(`/u/${encodeURIComponent(s.username)}`)}
            className="flex min-w-0 flex-1 flex-col text-left"
          >
            <span className="truncate text-sm font-semibold">
              @{s.username}
            </span>
            <span className="truncate text-xs text-muted-foreground">
              {s.display_name || (s.is_coach ? "Coach" : "Creator")}
            </span>
          </button>
        </div>
      ))}
    </div>
  );
}

export const RightRail = memo(RightRailBase);
