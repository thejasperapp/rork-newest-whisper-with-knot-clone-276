import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  Search as SearchIcon,
  Sparkles,
  TrendingUp,
  Loader2,
  Hash,
  Building2,
  Flame,
  Layers,
  X,
  Heart,
  MessageCircle,
  Play,
} from "lucide-react";

import { cn } from "@/lib/utils";
import { Avatar } from "@/components/Avatar";
import { CoachSearchCard } from "@/components/CoachSearchCard";
import { GridPostCard } from "@/components/GridPostCard";
import { UserBadges } from "@/components/UserBadges";
import { UserRow } from "@/components/FollowListDialog";
import { FloatingHeader } from "@/components/FloatingHeader";
import { useAuth } from "@/hooks/useAuth";
import { useProfileSearch } from "@/hooks/useProfileSearch";
import { fetchSuggestions, fetchProfilesByIds } from "@/lib/api";
import { useRankedFeed } from "@/hooks/useRankedFeed";
import { fetchBrands, typicalPayText } from "@/lib/brands";
import { COMMUNITIES } from "@/lib/communities";
import { compactCount } from "@/lib/format";
import { waveCoverUrl } from "@/lib/postMeta";
import type { WhisperPost } from "@/lib/types";

interface TrendingTag {
  tag: string;
  count: number;
}

/** One tile in the Discover mosaic — a media post or a WAVE (waves take the tall slots). */
interface MosaicItem {
  kind: "post" | "wave";
  post: WhisperPost;
}

/** Hours since a post was created (used by the trending-window filter). */
function hoursSince(iso: string | null): number {
  if (!iso) return Number.MAX_SAFE_INTEGER;
  return (Date.now() - new Date(iso).getTime()) / 36e5;
}

/** First displayable image URL of a post (videos are skipped). */
function postImage(p: WhisperPost): string | null {
  const url = (p.media_urls ?? [])[0];
  if (!url) return null;
  if (/\.(mp4|mov|webm|m3u8)(\?|$)/i.test(url)) return null;
  return url;
}

export default function Search() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [query, setQuery] = useState<string>("");
  const [selectedPost, setSelectedPost] = useState<WhisperPost | null>(null);
  const trimmed = query.trim();
  // `#tag` queries route to caption search instead of usernames — mirrors iOS.
  const isHashtagQuery = trimmed.startsWith("#");
  const hashtagToken = trimmed.slice(1).toLowerCase();

  const results = useProfileSearch(user?.id, query);

  const suggestionsQuery = useQuery({
    queryKey: ["suggestions", user?.id],
    queryFn: () => fetchSuggestions(user!.id),
    enabled: !!user && trimmed.length === 0,
  });

  const [settledTag, setSettledTag] = useState("");
  useEffect(() => {
    const timer = window.setTimeout(() => setSettledTag(hashtagToken), 250);
    return () => window.clearTimeout(timer);
  }, [hashtagToken]);
  const waitingForTag = isHashtagQuery && settledTag !== hashtagToken;
  // Each community/tag has its own raw page sequence; never search a capped Home pool.
  const feedQuery = useRankedFeed(user?.id,
    isHashtagQuery ? { kind: "search", term: hashtagToken } : { kind: "discover" },
    trimmed.length === 0 || (isHashtagQuery && hashtagToken.length > 0 && !waitingForTag));
  const posts = waitingForTag ? [] : feedQuery.data;
  const feedProgress = (
    <div className="flex flex-col items-center gap-2 px-4 py-5 text-center text-sm text-muted-foreground">
      {(waitingForTag || feedQuery.isFetching) ? <p role="status">Loading posts…</p> : feedQuery.isError ? <>
        <p role="status">Posts couldn’t load just now.</p>
        <button type="button" className="min-h-11 rounded-full bg-secondary px-5 font-semibold text-foreground" onClick={() => void (feedQuery.isFetchNextPageError ? feedQuery.fetchNextPage() : feedQuery.refetch())}>Try again</button>
      </> : feedQuery.hasNextPage ? <button type="button" className="min-h-11 rounded-full bg-secondary px-5 font-semibold text-foreground" onClick={() => void feedQuery.fetchNextPage()}>More posts</button> : null}
    </div>
  );

  // Hashtag results — caption-contains match against the live feed pool,
  // rendered as the same 3-column grid the iOS app shows.
  const hashtagResults = useMemo<WhisperPost[]>(() => {
    if (!isHashtagQuery || hashtagToken.length === 0) return [];
    return posts.filter((p) => {
      const c = (p.caption ?? "").toLowerCase();
      return c.includes(`#${hashtagToken}`) || c.includes(hashtagToken);
    });
  }, [isHashtagQuery, hashtagToken, posts]);

  // Trending posts — top-liked posts from the last 14 days (mirrors the iOS
  // Discover trending rail's freshness window).
  const trendingPosts = useMemo<WhisperPost[]>(() => {
    return posts
      .filter((p) => !p.is_ghost && hoursSince(p.created_at) <= 24 * 14)
      .slice()
      .sort((a, b) => (b.likes_count ?? 0) - (a.likes_count ?? 0))
      .slice(0, 6);
  }, [posts]);

  // WAVES on Discover — the tall 9:16 tiles INSIDE the explore mosaic (no
  // separate rail): newest media-backed waves take every double-height slot
  // first; tap opens the Waves player ON that wave.
  const waveReels = useMemo<WhisperPost[]>(() => {
    return posts
      .filter((p) => !p.is_ghost && p.is_reel === true && (p.media_urls ?? []).length > 0);
  }, [posts]);

  // The IG explore mosaic — media posts ranked by engagement, filling a
  // 3-column grid with an occasional double-height reel-style tile.
  const explorePosts = useMemo<WhisperPost[]>(() => {
    return posts
      .filter((p) => !p.is_ghost && !p.is_reel && postImage(p) !== null);
  }, [posts]);

  // The mosaic model — built ONCE per data change (never in render): media
  // posts fill the squares, waves take the tall slots (positions 2 and 7 of
  // every ten), and any waves left after the posts render as tall tiles too.
  const mosaicItems = useMemo<MosaicItem[]>(() => {
    const out: MosaicItem[] = [];
    let pi = 0;
    let wi = 0;
    const total = explorePosts.length + waveReels.length;
    for (let i = 0; i < total; i++) {
      const tallSlot = i % 10 === 2 || i % 10 === 7;
      if (tallSlot && wi < waveReels.length) {
        out.push({ kind: "wave", post: waveReels[wi++] });
      } else if (pi < explorePosts.length) {
        out.push({ kind: "post", post: explorePosts[pi++] });
      } else if (wi < waveReels.length) {
        out.push({ kind: "wave", post: waveReels[wi++] });
      }
    }
    return out;
  }, [explorePosts, waveReels]);

  // Resolve author handles for trending rows that arrive without a username —
  // Discover must never show a "user" placeholder.
  const missingAuthorIds = useMemo<string[]>(() => {
    return Array.from(
      new Set(
        trendingPosts.filter((p) => !p.username && p.user_id).map((p) => p.user_id)
      )
    );
  }, [trendingPosts]);
  const trendingAuthors = useQuery({
    queryKey: ["discover-authors", missingAuthorIds.join(",")],
    queryFn: () => fetchProfilesByIds(missingAuthorIds),
    enabled: missingAuthorIds.length > 0,
  });
  const handleFor = (p: WhisperPost): string | null =>
    p.username ?? trendingAuthors.data?.[p.user_id]?.username ?? null;

  // Sponsor brands rail — published brands surface on Discover so
  // creators/athletes stumble into sponsorship opportunities (mirrors iOS).
  const brandsQuery = useQuery({
    queryKey: ["brands"],
    queryFn: fetchBrands,
    enabled: trimmed.length === 0,
  });
  const brands = brandsQuery.data ?? [];

  const trendingTags = useMemo<TrendingTag[]>(() => {
    const counts = new Map<string, number>();
    for (const p of posts) {
      const matches = (p.caption ?? "").match(/#[a-z0-9_]+/gi) ?? [];
      for (const raw of matches) {
        const tag = raw.toLowerCase();
        counts.set(tag, (counts.get(tag) ?? 0) + 1);
      }
    }
    return Array.from(counts.entries())
      .map(([tag, count]) => ({ tag, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 12);
  }, [posts]);

  const trendingCommunities = useMemo(() => {
    return COMMUNITIES.map((c) => ({
      community: c,
      count: posts.filter((p) => p.community_id === c.id).length,
    }))
      .filter((x) => x.count > 0)
      .sort((a, b) => b.count - a.count)
      .slice(0, 6);
  }, [posts]);

  const profiles = results.data ?? [];
  const suggestions = suggestionsQuery.data ?? [];
  // Coaches and verified creators get rich spotlight-style cards at the
  // top of results; everyone else keeps the plain rows.
  const coachResults = useMemo(
    () => profiles.filter((p) => !!p.is_coach),
    [profiles]
  );
  const creatorResults = useMemo(
    () => profiles.filter((p) => !p.is_coach && !!p.is_verified),
    [profiles]
  );
  const otherResults = useMemo(
    () => profiles.filter((p) => !p.is_coach && !p.is_verified),
    [profiles]
  );

  return (
    <div>
      <FloatingHeader title="Search" />
      <div className="sticky top-14 z-20 px-4 pb-2.5 pt-2">
        <div className="glass flex items-center gap-2.5 rounded-full border border-border/40 px-4 py-2.5 shadow-sm">
          <SearchIcon className="h-5 w-5 shrink-0 text-muted-foreground" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search"
            autoCapitalize="none"
            autoCorrect="off"
            className="min-w-0 flex-1 bg-transparent text-[15px] outline-none placeholder:text-muted-foreground"
          />
          {query.length > 0 && (
            <button
              onClick={() => setQuery("")}
              aria-label="Clear search"
              className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-muted-foreground/30 text-background transition-transform active:scale-90"
            >
              <X className="h-3 w-3" strokeWidth={3} />
            </button>
          )}
        </div>
      </div>

      {/* Hashtag results — 3-column post grid, like iOS */}
      {isHashtagQuery && hashtagToken.length > 0 && (
        <div className="pb-12 pt-2">
          {hashtagResults.length === 0 && !waitingForTag && !feedQuery.isPending && !feedQuery.isError && !feedQuery.hasNextPage ? (
            <div className="flex flex-col items-center gap-1.5 px-6 py-14 text-center">
              <Hash className="h-6 w-6 text-muted-foreground" />
              <p className="text-sm font-semibold">
                No posts tagged #{hashtagToken}
              </p>
              <p className="text-xs text-muted-foreground">
                Be the first to post one.
              </p>
            </div>
          ) : (
            <>
              <p className="px-4 pb-2 text-xs font-bold text-muted-foreground">
                #{hashtagToken} · {hashtagResults.length}{" "}
                {hashtagResults.length === 1 ? "post" : "posts"}
              </p>
              <div className="grid grid-cols-3 gap-0.5 px-0.5">
                {hashtagResults.map((p) => {
                  const img = postImage(p);
                  return (
                    <button
                      type="button"
                      key={p.id}
                      aria-label="Open post"
                      onClick={() => p.is_reel ? navigate(`/reels?wave=${p.id}`) : setSelectedPost(p)}
                      className="relative aspect-square overflow-hidden bg-secondary"
                    >
                      {img ? (
                        <img
                          src={img}
                          alt=""
                          loading="lazy"
                          className="h-full w-full object-cover"
                        />
                      ) : (
                        <div
                          className="flex h-full w-full items-center justify-center p-2"
                          style={{
                            background: p.accent_hex
                              ? `linear-gradient(135deg, ${p.accent_hex}f2, ${p.accent_hex}8c)`
                              : "linear-gradient(135deg, #8b8b96, #6b6b75)",
                          }}
                        >
                          <p className="line-clamp-4 text-center text-[11px] font-bold leading-tight text-white/95">
                            {p.caption}
                          </p>
                        </div>
                      )}
                    </button>
                  );
                })}
              </div>
            </>
          )}
          {feedProgress}
        </div>
      )}

      {/* Search results */}
      {trimmed.length >= 1 && !isHashtagQuery && (
        <>
          {coachResults.length > 0 && (
            <div className="space-y-2.5 px-3 pb-4 sm:px-4">
              <SectionHeader icon={<Sparkles className="h-4 w-4" />}>
                Coaches
              </SectionHeader>
              {coachResults.map((p) => (
                <CoachSearchCard key={p.user_id} profile={p} kind="coach" />
              ))}
            </div>
          )}
          {creatorResults.length > 0 && (
            <div className="space-y-2.5 px-3 pb-4 sm:px-4">
              <SectionHeader icon={<Sparkles className="h-4 w-4" />}>
                Creators
              </SectionHeader>
              {creatorResults.map((p) => (
                <CoachSearchCard key={p.user_id} profile={p} kind="creator" />
              ))}
            </div>
          )}
          <div className="divide-y divide-border">
            {otherResults.map((p) => (
              <Link
                key={p.user_id}
                to={`/u/${p.username}`}
                className="flex items-center gap-3 px-3 py-3 transition-colors hover:bg-secondary/50 sm:px-4"
              >
                <Avatar url={p.profile_image_url} name={p.username} size={48} />
                <div className="min-w-0">
                  <p className="flex items-center gap-1.5 font-semibold">
                    <span className="truncate">
                      {p.display_name || p.username}
                    </span>
                    <UserBadges profile={p} size={12} className="shrink-0" />
                  </p>
                  <p className="truncate text-sm text-muted-foreground">
                    @{p.username}
                  </p>
                </div>
              </Link>
            ))}
          </div>
          {results.isSearching && (
            <div role="status" className="flex items-center justify-center gap-2 px-6 py-10 text-sm text-muted-foreground">
              <Loader2 aria-hidden="true" className="h-4 w-4 animate-spin motion-reduce:animate-none" />
              Searching…
            </div>
          )}
          {results.isError && (
            <div role="status" className="px-6 py-10 text-center text-sm text-muted-foreground">
              <p>Search is unavailable for a moment.</p>
              <button type="button" onClick={() => void results.refetch()} className="mt-2 min-h-11 rounded-full bg-secondary px-5 font-semibold text-foreground transition-colors hover:bg-secondary/70">Try again</button>
            </div>
          )}
          {!results.isSearching && !results.isError && profiles.length === 0 && (
            <div className="flex flex-col items-center gap-1.5 px-6 py-14 text-center">
              <SearchIcon className="h-6 w-6 text-muted-foreground" />
              <p className="text-sm font-semibold">
                No Whisper users match "{trimmed}"
              </p>
              <p className="text-xs text-muted-foreground">
                Only people who've finished Whisper signup show up here.
              </p>
            </div>
          )}
        </>
      )}

      {/* Trending / discover */}
      {/* Post detail — the real IG card (photo + comments) in a dialog */}
      {selectedPost && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm"
          onClick={() => setSelectedPost(null)}
        >
          <div
            className="max-h-[88vh] w-full max-w-md overflow-y-auto rounded-[22px] bg-background shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between border-b border-border px-4 py-3">
              <button
                onClick={() => setSelectedPost(null)}
                className="flex h-8 w-8 items-center justify-center rounded-full transition-colors hover:bg-secondary"
              >
                <X className="h-5 w-5" />
              </button>
              <span className="text-sm font-bold">Post</span>
              <span className="w-8" />
            </div>
            <GridPostCard post={selectedPost} liked={false} />
          </div>
        </div>
      )}

      {trimmed.length === 0 && (
        <div className="space-y-6 px-3 pb-12 sm:px-4">
          {/* Trending communities */}
          {trendingCommunities.length > 0 && (
            <section>
              <SectionHeader icon={<TrendingUp className="h-4 w-4" />}>
                Trending now
              </SectionHeader>
              <div className="grid grid-cols-2 gap-2">
                {trendingCommunities.map(({ community, count }) => {
                  const Icon = community.icon;
                  return (
                    <Link
                      key={community.id}
                      to={`/c/${community.id}`}
                      className="overflow-hidden rounded-2xl border border-border transition-transform active:scale-[0.98]"
                    >
                      <div
                        className="flex items-center gap-2 px-3 py-3"
                        style={{
                          backgroundImage: `linear-gradient(135deg, ${community.gradient[0]}, ${community.gradient[1]})`,
                        }}
                      >
                        <span className="flex h-8 w-8 items-center justify-center rounded-xl bg-white/25 text-white backdrop-blur">
                          <Icon className="h-4 w-4" />
                        </span>
                        <div className="min-w-0">
                          <p className="truncate text-sm font-bold text-white">
                            {community.name}
                          </p>
                          <p className="text-[11px] font-semibold text-white/85">
                            {compactCount(count)} {count === 1 ? "post" : "posts"}
                          </p>
                        </div>
                      </div>
                    </Link>
                  );
                })}
              </div>
            </section>
          )}

          {/* Sponsor brands */}
          {brands.length > 0 && (
            <section>
              <div className="mb-2 flex items-center justify-between">
                <SectionHeader icon={<Building2 className="h-4 w-4" />}>
                  Sponsor brands
                </SectionHeader>
                <Link
                  to="/brands"
                  className="pb-2 text-[13px] font-semibold text-muted-foreground transition-colors hover:text-foreground"
                >
                  See all
                </Link>
              </div>
              <div className="-mx-3 flex gap-2.5 overflow-x-auto px-3 pb-1 sm:-mx-4 sm:px-4 [scrollbar-width:none]">
                {brands.slice(0, 10).map((b) => {
                  const payText = typicalPayText(b);
                  return (
                    <Link
                      key={b.user_id}
                      to={`/brands/${b.user_id}`}
                      className="w-[230px] shrink-0 rounded-2xl border border-border bg-card p-3 transition-transform active:scale-[0.98]"
                    >
                      <div className="flex items-center gap-2.5">
                        <div className="flex h-11 w-11 shrink-0 items-center justify-center overflow-hidden rounded-xl bg-secondary">
                          {b.logo_url ? (
                            <img
                              src={b.logo_url}
                              alt={b.company_name}
                              className="h-full w-full object-cover"
                            />
                          ) : (
                            <Building2 className="h-5 w-5 text-muted-foreground" />
                          )}
                        </div>
                        <div className="min-w-0">
                          <p className="truncate text-sm font-bold">
                            {b.company_name}
                          </p>
                          {b.ember_verified ? (
                            <p className="flex items-center gap-1 text-[10px] font-bold text-orange-500">
                              <Flame className="h-3 w-3" /> Jasper verified
                            </p>
                          ) : b.industry ? (
                            <p className="truncate text-[11px] text-muted-foreground">
                              {b.industry}
                            </p>
                          ) : null}
                        </div>
                      </div>
                      <p className="mt-2 truncate text-xs">
                        {payText ? (
                          <span className="font-bold text-emerald-600">
                            Typically pays {payText}
                          </span>
                        ) : (
                          <span className="text-muted-foreground">
                            {compactCount(b.min_followers)}+ followers ·{" "}
                            {b.min_age}+
                          </span>
                        )}
                      </p>
                    </Link>
                  );
                })}
              </div>
            </section>
          )}

          {/* Explore — the IG mosaic: 3-column media grid where every
              double-height cell is a WAVE (poster frame, author chip, play +
              count → the Waves player) and the squares are media posts (hover
              reveals the counts, tap opens the real post in place). */}
          {mosaicItems.length > 0 && (
            <section>
              <SectionHeader icon={<Flame className="h-4 w-4" />}>
                Explore
              </SectionHeader>
              <div className="-mx-3 grid grid-flow-dense grid-cols-3 gap-0.5 sm:-mx-4">
                {mosaicItems.map((item, i) => {
                  const p = item.post;
                  if (item.kind === "wave") {
                    const url = (p.media_urls ?? [])[0];
                    const handle = handleFor(p);
                    return (
                      <button
                        key={`w-${p.id}`}
                        type="button"
                        onClick={() => navigate(`/reels?wave=${p.id}`)}
                        className="group relative row-span-2 overflow-hidden bg-black"
                        aria-label={handle ? `Wave by @${handle}` : "Open wave"}
                      >
                        {url && (
                          <video
                            src={url}
                            poster={waveCoverUrl(p.caption)}
                            muted
                            playsInline
                            preload={waveCoverUrl(p.caption) ? "none" : "metadata"}
                            className="absolute inset-0 h-full w-full object-cover transition-transform duration-300 group-hover:scale-[1.03]"
                          />
                        )}
                        <span className="pointer-events-none absolute inset-x-0 top-0 h-14 bg-gradient-to-b from-black/50 to-transparent" />
                        <span className="pointer-events-none absolute inset-x-0 bottom-0 h-14 bg-gradient-to-t from-black/60 to-transparent" />
                        {handle && (
                          <span className="absolute left-1.5 top-1.5 flex max-w-[85%] items-center gap-1.5">
                            <Avatar name={handle} size={18} />
                            <span className="truncate text-[10.5px] font-semibold text-white drop-shadow">
                              {handle}
                            </span>
                          </span>
                        )}
                        <span className="absolute bottom-1.5 left-1.5 flex items-center gap-1 text-[11px] font-extrabold text-white drop-shadow">
                          <Play className="h-3 w-3 fill-white" />
                          {compactCount(p.likes_count ?? 0)}
                        </span>
                      </button>
                    );
                  }
                  const img = postImage(p);
                  if (!img) return null;
                  const tall = i % 10 === 2 || i % 10 === 7;
                  return (
                    <button
                      key={p.id}
                      onClick={() => setSelectedPost(p)}
                      className={cn(
                        "group relative overflow-hidden bg-secondary",
                        tall ? "row-span-2" : "aspect-square"
                      )}
                    >
                      <img
                        src={img}
                        alt=""
                        loading="lazy"
                        className="absolute inset-0 h-full w-full object-cover transition-transform duration-300 group-hover:scale-[1.03]"
                      />
                      {(p.media_urls ?? []).length > 1 && (
                        <span className="absolute right-1.5 top-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-black/40 backdrop-blur-sm">
                          <Layers className="h-3 w-3 text-white" />
                        </span>
                      )}
                      {/* IG hover overlay — hearts + comments */}
                      <span className="absolute inset-0 flex items-center justify-center gap-4 bg-black/40 opacity-0 transition-opacity group-hover:opacity-100">
                        <span className="flex items-center gap-1.5 text-[13px] font-bold text-white">
                          <Heart className="h-4 w-4 fill-white" />
                          {compactCount(p.likes_count ?? 0)}
                        </span>
                        <span className="flex items-center gap-1.5 text-[13px] font-bold text-white">
                          <MessageCircle className="h-4 w-4 fill-white" />
                          {compactCount(p.comments_count ?? 0)}
                        </span>
                      </span>
                    </button>
                  );
                })}
              </div>
            </section>
          )}

          {/* Trending hashtags */}
          {trendingTags.length > 0 && (
            <section>
              <SectionHeader icon={<Hash className="h-4 w-4" />}>
                Trending tags
              </SectionHeader>
              <div className="flex flex-wrap gap-2">
                {trendingTags.map(({ tag, count }) => (
                  <button
                    type="button"
                    key={tag}
                    onClick={() => setQuery(tag)}
                    className="flex items-center gap-1.5 rounded-full border border-border bg-card px-3 py-1.5 text-sm font-semibold transition-colors hover:bg-secondary/60"
                  >
                    <span>{tag}</span>
                    <span className="text-xs text-muted-foreground">
                      {compactCount(count)}
                    </span>
                  </button>
                ))}
              </div>
            </section>
          )}

          {/* Trending creators — quick author rail from the hottest posts */}
          {trendingPosts.length > 0 && (
            <section>
              <SectionHeader icon={<TrendingUp className="h-4 w-4" />}>
                Trending creators
              </SectionHeader>
              <div className="-mx-3 flex gap-3 overflow-x-auto px-3 pb-1 sm:-mx-4 sm:px-4 [scrollbar-width:none]">
                {Array.from(
                  new Map(
                    trendingPosts
                      .map((p) => handleFor(p))
                      .filter((h): h is string => !!h)
                      .map((h) => [h.toLowerCase(), h])
                  ).values()
                ).map((handle) => (
                  <Link
                    key={handle}
                    to={`/u/${encodeURIComponent(handle)}`}
                    className="flex w-16 shrink-0 flex-col items-center gap-1.5"
                  >
                    <Avatar name={handle} size={56} />
                    <span className="w-full truncate text-center text-[11px] font-semibold">
                      @{handle}
                    </span>
                  </Link>
                ))}
              </div>
            </section>
          )}

          {feedProgress}

          {/* Suggested people */}
          <section>
            <SectionHeader icon={<Sparkles className="h-4 w-4" />}>
              Suggested for you
            </SectionHeader>
            {suggestionsQuery.isLoading ? (
              <p className="px-2 py-10 text-center text-sm text-muted-foreground">
                Finding people…
              </p>
            ) : suggestions.length === 0 ? (
              <p className="px-2 py-10 text-center text-sm text-muted-foreground">
                Find people by username or name.
              </p>
            ) : (
              <div className="divide-y divide-border">
                {suggestions.map((person) => (
                  <UserRow key={person.userId} person={person} />
                ))}
              </div>
            )}
          </section>
        </div>
      )}
    </div>
  );
}

function SectionHeader({
  icon,
  children,
}: {
  icon: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <div className="mb-2 flex items-center gap-2 px-1 text-[13px] font-bold uppercase tracking-wider text-muted-foreground">
      {icon}
      {children}
    </div>
  );
}
