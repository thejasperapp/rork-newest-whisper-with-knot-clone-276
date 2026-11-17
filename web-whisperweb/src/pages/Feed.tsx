import { useEffect, useMemo, useState } from "react";
import { ConversationListEnd } from "@/components/ConversationListEnd";
import { useQuery } from "@tanstack/react-query";

import { Link } from "react-router-dom";
import { Plus, Heart, Send, ChevronDown, Check } from "lucide-react";

import { WhisperLogo } from "@/components/WhisperLogo";
import { FloatingHeader, FloatingButton } from "@/components/FloatingHeader";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Stories } from "@/components/Stories";
import { PostCard } from "@/components/PostCard";
import { PostSkeletonList } from "@/components/PostSkeleton";
import { FeedComposer } from "@/components/FeedComposer";
import FeedFilmShelf from "@/components/FeedFilmShelf";
import { FeedArticlesShelf, FeedPeopleShelf, FeedWavesShelf } from "@/components/FeedBreakShelves";
import { PullToRefresh } from "@/components/PullToRefresh";
import { CreateSelector } from "@/components/CreateSelector";
import {
  fetchLiarBadges,
  fetchMyLikedPostIds,
  fetchMyRepostIds,
  fetchRepostCounts,
  fetchMyBookmarkIds,
  fetchProfilesByIds,
  fetchStories,
  fetchLikeCounts,
  fetchCommentCounts,
  fetchFollowing,
} from "@/lib/api";
import { useAuth } from "@/hooks/useAuth";
import { useUnreadActivity } from "@/hooks/useUnreadActivity";
import { getMutedWords, isMuted } from "@/lib/settings";
import { useRankedFeed } from "@/hooks/useRankedFeed";
import { fetchActiveAds } from "@/lib/business";
import { SponsoredAdCard } from "@/components/business/SponsoredAdCard";

type FeedScope = "foryou" | "following";

export default function Feed() {
  const { user } = useAuth();
  const [mutedWords, setMutedWordsState] = useState<string[]>(getMutedWords);

  // Kit 4.0 "For you ⌄" header — the feed scope switcher (For you / Following).
  const [feedScope, setFeedScope] = useState<FeedScope>(() => {
    if (typeof window === "undefined") return "foryou";
    return window.localStorage.getItem("whisper-feed-scope") === "following"
      ? "following"
      : "foryou";
  });
  const setScope = (scope: FeedScope): void => {
    setFeedScope(scope);
    try {
      window.localStorage.setItem("whisper-feed-scope", scope);
    } catch {
      /* private mode — scope just won't persist */
    }
  };

  useEffect(() => {
    const sync = (): void => setMutedWordsState(getMutedWords());
    window.addEventListener("whisper-settings", sync);
    window.addEventListener("storage", sync);
    return () => {
      window.removeEventListener("whisper-settings", sync);
      window.removeEventListener("storage", sync);
    };
  }, []);

  // Ranked home feed — recency-decayed engagement + follow affinity +
  // author diversity (identical math to iOS; see lib/feedAlgorithm.ts).
  const feedQuery = useRankedFeed(user?.id);
  const storiesQuery = useQuery({
    queryKey: ["stories"],
    queryFn: fetchStories,
  });

  const handleRefresh = async (): Promise<void> => {
    await Promise.all([
      feedQuery.refetch(),
      storiesQuery.refetch(),
      likesQuery.refetch(),
      repostsQuery.refetch(),
    ]);
  };
  const likesQuery = useQuery({
    queryKey: ["my-likes", user?.id],
    queryFn: () => fetchMyLikedPostIds(user!.id),
    enabled: !!user,
  });
  const repostsQuery = useQuery({
    queryKey: ["my-reposts", user?.id],
    queryFn: () => fetchMyRepostIds(user!.id),
    enabled: !!user,
  });
  const bookmarksQuery = useQuery({
    queryKey: ["my-bookmarks", user?.id],
    queryFn: () => fetchMyBookmarkIds(user!.id),
    enabled: !!user,
  });

  // Following scope — the set of authors the viewer follows.
  const myFollowingQuery = useQuery({
    queryKey: ["following", user?.id],
    queryFn: () => fetchFollowing(user!.id),
    enabled: !!user,
    staleTime: 5 * 60 * 1000,
  });
  const followingSet = useMemo(
    () => new Set((myFollowingQuery.data ?? []).map((f) => f.userId)),
    [myFollowingQuery.data]
  );

  // Sponsored rotation from Whisper Business — resolves to [] when the
  // migration hasn't run or nothing is live, leaving the feed untouched.
  const activeAdsQuery = useQuery({
    queryKey: ["business-active-ads", "feed"],
    queryFn: () => fetchActiveAds("feed", 6),
    enabled: !!user,
    staleTime: 5 * 60 * 1000,
  });
  const activeAds = activeAdsQuery.data ?? [];

  const allPosts = feedQuery.data ?? [];
  const posts = useMemo(
    () => allPosts.filter((p) => !isMuted(p.caption, mutedWords)),
    [allPosts, mutedWords]
  );
  const stories = storiesQuery.data ?? [];

  // The rendered feed under the active scope — Following shows only posts
  // from followed authors (IG grammar); For you keeps the ranked feed.
  const scopedPosts = useMemo(
    () =>
      feedScope === "following"
        ? posts.filter((p) => followingSet.has(p.user_id))
        : posts,
    [posts, feedScope, followingSet]
  );

  // Use the same stable batch as the ranker, even when muted words hide a
  // subset. Reordering the feed should not create another engagement query.
  const postIds = useMemo(() => allPosts.map((p) => p.id).sort(), [allPosts]);
  const repostCountsQuery = useQuery({
    queryKey: ["repost-counts", postIds],
    queryFn: () => fetchRepostCounts(postIds),
    enabled: postIds.length > 0,
    staleTime: 30_000,
  });

  // Resolve profiles for every author visible in the feed AND in the stories
  // strip so usernames + photos render correctly (instead of placeholders).
  const authorIds = useMemo(
    () => Array.from(new Set([
      ...posts.map((p) => p.user_id),
      ...stories.map((s) => s.user_id),
    ])).sort(),
    [posts, stories]
  );

  const profilesQuery = useQuery({
    queryKey: ["profiles", authorIds],
    queryFn: () => fetchProfilesByIds(authorIds),
    enabled: authorIds.length > 0,
  });

  const profiles = profilesQuery.data ?? {};

  // Liar Liar badges for every author visible in the feed (keyed by username).
  const authorUsernames = useMemo(
    () => posts.map((p) => profiles[p.user_id]?.username ?? p.username ?? ""),
    [posts, profiles]
  );
  const liarQuery = useQuery({
    queryKey: ["liar-badges", authorUsernames],
    queryFn: () => fetchLiarBadges(authorUsernames),
    enabled: authorUsernames.some(Boolean),
  });
  const liarBadges = liarQuery.data ?? {};
  const likedSet = useMemo(
    () => new Set(likesQuery.data ?? []),
    [likesQuery.data]
  );
  const repostedSet = useMemo(
    () => new Set(repostsQuery.data ?? []),
    [repostsQuery.data]
  );
  const bookmarkedSet = useMemo(
    () => new Set(bookmarksQuery.data ?? []),
    [bookmarksQuery.data]
  );
  const repostCounts = repostCountsQuery.data ?? {};

  // Fetch real like + comment counts from the engagement tables (source of
  // truth). The whisper_posts.likes_count / comments_count columns may be NULL
  // if the SQL triggers haven't been applied or are out of sync, so we always
  // overlay the real counts from the likes/comments tables on top.
  const likeCountsQuery = useQuery({
    queryKey: ["feed-like-counts", postIds],
    queryFn: () => fetchLikeCounts(postIds),
    enabled: postIds.length > 0,
    staleTime: 30_000,
  });
  const commentCountsQuery = useQuery({
    queryKey: ["feed-comment-counts", postIds],
    queryFn: () => fetchCommentCounts(postIds),
    enabled: postIds.length > 0,
    staleTime: 30_000,
  });
  const realLikeCounts = likeCountsQuery.data ?? {};
  const realCommentCounts = commentCountsQuery.data ?? {};

  const unreadActivity = useUnreadActivity();
  const [createOpen, setCreateOpen] = useState<boolean>(false);

  return (
    <div>
      <CreateSelector open={createOpen} onOpenChange={setCreateOpen} />

      <FloatingHeader
        title={
          <DropdownMenu>
            <DropdownMenuTrigger className="flex items-center gap-1 outline-none">
              <span>{feedScope === "following" ? "Following" : "whisper"}</span>
              <ChevronDown className="h-3.5 w-3.5 opacity-70" strokeWidth={3} />
            </DropdownMenuTrigger>
            <DropdownMenuContent align="center" className="w-44">
              <DropdownMenuItem onClick={() => setScope("foryou")}>
                <span className="flex-1">For you</span>
                {feedScope === "foryou" && <Check className="h-4 w-4" />}
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => setScope("following")}>
                <span className="flex-1">Following</span>
                {feedScope === "following" && <Check className="h-4 w-4" />}
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        }
        left={
          <FloatingButton onClick={() => setCreateOpen(true)} label="New post">
            <Plus className="h-6 w-6" strokeWidth={2.2} />
          </FloatingButton>
        }
        right={
          <>
            <FloatingButton to="/notifications" label="Activity" badge={unreadActivity > 0 ? <span className="absolute -right-0.5 -top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-primary px-1 text-[10px] font-bold text-primary-foreground">{unreadActivity > 9 ? "9+" : unreadActivity}</span> : undefined}>
              <Heart className="h-[22px] w-[22px]" strokeWidth={2} />
            </FloatingButton>
            <FloatingButton to="/messages" label="Messages">
              <Send className="h-[20px] w-[20px]" strokeWidth={2} />
            </FloatingButton>
          </>
        }
      />

      <PullToRefresh onRefresh={handleRefresh}>
      <div className="px-0 pt-0 sm:px-0 sm:pt-4">
        <Stories stories={stories} profiles={profiles} />

        {/* Feed card — composer pinned on top, posts below (Threads-style) */}
        <div className="social-feed-surface overflow-hidden border-b border-border bg-background sm:rounded-[24px] sm:border-x sm:border-b">
          <FeedComposer />

          <div className="border-t border-border">
            {feedQuery.isLoading && <PostSkeletonList count={3} />}

            {!feedQuery.isLoading && !feedQuery.isError && !feedQuery.hasNextPage && scopedPosts.length === 0 && (
              <div className="flex flex-col items-center gap-4 px-6 py-24 text-center">
                <div className="flex h-16 w-16 items-center justify-center rounded-full border-2 border-foreground">
                  <WhisperLogo size={26} />
                </div>
                <h2 className="font-display text-lg font-bold">
                  It's quiet in here
                </h2>
                <p className="max-w-xs text-sm text-muted-foreground">
                  {feedScope === "following"
                    ? "No posts from people you follow yet. Follow more people to fill this view."
                    : "No whispers yet. Follow people or share your first post to fill your feed."}
                </p>
              </div>
            )}

            {scopedPosts.map((post, i) => (
              <div key={post.id}>
                <PostCard
                  post={post}
                  author={profiles[post.user_id]}
                  liar={
                    liarBadges[
                      (profiles[post.user_id]?.username ??
                        post.username ??
                        "").toLowerCase()
                    ]
                  }
                  liked={likedSet.has(post.id)}
                  reposted={repostedSet.has(post.id)}
                  repostCount={repostCounts[post.id] ?? 0}
                  bookmarked={bookmarkedSet.has(post.id)}
                  realLikeCount={realLikeCounts[post.id]}
                  realCommentCount={realCommentCounts[post.id]}
                />
                {/* The break shelves (iOS parity) — native content units that
                    slot between posts, each with See all → a full grid:
                    People to follow after the 2nd post, Waves after the 6th,
                    From the journal after the 9th. */}
                {i === 1 && <FeedPeopleShelf />}
                {i === 5 && <FeedWavesShelf posts={allPosts} />}
                {i === 8 && <FeedArticlesShelf />}
                {/* Featured Film Friday shelf — slots in once, after the
                    4th post, so premieres are discoverable in-context like a
                    native content unit (seamless, not boxed). */}
                {i === 3 && <FeedFilmShelf />}
                {/* Sponsored card — one every 6 posts, cycling the active
                    rotation. Impressions/clicks feed the advertiser's real
                    analytics in Whisper Business. */}
                {activeAds.length > 0 && (i + 1) % 6 === 0 && (
                  <div className="border-t border-border">
                    <SponsoredAdCard
                      ad={activeAds[Math.floor(i / 6) % activeAds.length]}
                    />
                  </div>
                )}
              </div>
            ))}
            <ConversationListEnd content="posts" active={feedQuery.visible} hasMore={feedQuery.hasNextPage}
              busy={feedQuery.isFetching} loading={feedQuery.isFetchingNextPage} failed={feedQuery.isError}
              onLoad={() => feedQuery.isFetchNextPageError || !feedQuery.isError ? feedQuery.fetchNextPage({ cancelRefetch: false }) : feedQuery.refetch()} />
          </div>
        </div>
      </div>
      </PullToRefresh>
    </div>
  );
}
