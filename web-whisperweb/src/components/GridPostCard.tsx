/**
 * GridPostCard — Instagram-style full-bleed media card for grid posts.
 *
 * Only used for posts with `kind === "grid"` (created via the Grid composer).
 * Regular thread posts with images keep their Threads-style carousel layout
 * in PostCard.
 *
 * Features inline comments (no separate /post/:id route needed).
 */

import { memo, useEffect, useMemo, useRef, useState } from "react";
import { removePagedFeedPost } from "@/lib/feedPaging";
import { Link, useNavigate } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Heart,
  MessageCircle,
  Send,
  Bookmark,
  MoreHorizontal,
  ChevronLeft,
  ChevronRight,
  Grip,
  Loader2,
  Repeat2,
  MapPin,
  Music,
} from "lucide-react";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import { timeAgo, compactCount } from "@/lib/format";
import { Avatar } from "@/components/Avatar";
import { UserBadges } from "@/components/UserBadges";
import { PostCorrectionNotice } from "@/components/PostCorrectionNotice";
import { MentionText } from "@/components/MentionText";
import { SharePostDialog } from "@/components/SharePostDialog";
import { RepostOptionsSheet } from "@/components/RepostOptionsSheet";
import { ComposerModal } from "@/components/ComposerModal";
import { parsePostMeta, stripPostMeta } from "@/lib/postMeta";
import { WavesTabGlyph } from "@/components/WavesTabGlyph";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  addComment,
  toggleLike,
  toggleBookmark,
  toggleRepost,
  fetchComments,
  fetchProfilesByUsernames,
  fetchProfilesByIds,
  fetchPostLikersPreview,
  fetchStories,
  deletePost,
  reportPost,
} from "@/lib/api";
import { loadSeenStoryIds } from "@/lib/storySeen";
import { WHISPER_STORY_RING_TW } from "@/lib/storyRing";
import { communityById } from "@/lib/communities";
import { StoryViewer, type StoryGroup } from "@/components/StoryViewer";
import { useAuth } from "@/hooks/useAuth";
import type { WhisperPost, WhisperProfile, WhisperComment } from "@/lib/types";

interface GridPostCardProps {
  post: WhisperPost;
  author?: WhisperProfile;
  liked: boolean;
  reposted?: boolean;
  repostCount?: number;
  bookmarked?: boolean;
  /** Real like count from the engagement table (overrides post.likes_count). */
  realLikeCount?: number;
  /** Real comment count from the engagement table (overrides post.comments_count). */
  realCommentCount?: number;
}

/** Long-form Instagram bottom timestamp — "2 hours ago". */
function longTimeAgo(iso: string | null | undefined): string {
  if (!iso) return "";
  const ms = Date.parse(iso);
  if (Number.isNaN(ms)) return "";
  const s = Math.max(0, (Date.now() - ms) / 1000);
  if (s < 60) return "just now";
  const m = Math.floor(s / 60);
  if (m < 60) return `${m} minute${m === 1 ? "" : "s"} ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h} hour${h === 1 ? "" : "s"} ago`;
  const d = Math.floor(h / 24);
  if (d < 7) return `${d} day${d === 1 ? "" : "s"} ago`;
  const w = Math.floor(d / 7);
  return `${w} week${w === 1 ? "" : "s"} ago`;
}

/**
 * Instagram's reel-in-feed media: the wave inside the card's 4:5 frame,
 * playing muted only while it's mostly on screen, the Waves mark top-right, a
 * single tap opens the full-screen player on this wave, a double tap likes.
 */
function WaveFeedMedia({
  src,
  poster,
  onOpen,
  onDoubleTap,
}: {
  src: string;
  poster?: string;
  onOpen: () => void;
  onDoubleTap: () => void;
}) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const lastTap = useRef<number>(0);
  const singleTimer = useRef<number | null>(null);
  const [failed, setFailed] = useState<boolean>(false);

  useEffect(() => {
    const el = videoRef.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    const io = new IntersectionObserver(
      (entries) => {
        const entry = entries[0];
        if (!entry) return;
        if (entry.intersectionRatio >= 0.6) {
          // Autoplay policy reads the PROPERTY, so set it before play().
          el.muted = true;
          void el.play().catch(() => {});
        } else {
          el.pause();
        }
      },
      { threshold: [0, 0.6] }
    );
    io.observe(el);
    return () => {
      io.disconnect();
      if (singleTimer.current) window.clearTimeout(singleTimer.current);
    };
  }, []);

  const handleClick = (): void => {
    const now = Date.now();
    if (now - lastTap.current < 280) {
      lastTap.current = 0;
      if (singleTimer.current) window.clearTimeout(singleTimer.current);
      singleTimer.current = null;
      onDoubleTap();
      return;
    }
    lastTap.current = now;
    singleTimer.current = window.setTimeout(() => {
      singleTimer.current = null;
      onOpen();
    }, 280);
  };

  return (
    <div
      className="relative aspect-[4/5] w-full cursor-pointer select-none overflow-hidden bg-black"
      onClick={handleClick}
      role="button"
      aria-label="Open wave"
    >
      {poster && (
        <img
          src={poster}
          alt=""
          aria-hidden="true"
          className="absolute inset-0 h-full w-full scale-110 object-cover opacity-60 blur-2xl"
          draggable={false}
        />
      )}
      {!failed ? (
        <video
          ref={videoRef}
          src={src}
          poster={poster}
          muted
          loop
          playsInline
          preload="metadata"
          onError={() => setFailed(true)}
          // Letterboxed over the blurred cover (never cropped) — the same
          // framing iOS gives a wave inside the 4:5 card.
          className="relative h-full w-full object-contain"
        />
      ) : poster ? (
        <img src={poster} alt="" className="relative h-full w-full object-cover" draggable={false} />
      ) : null}
      <span className="absolute right-3 top-3 text-white drop-shadow-[0_2px_8px_rgba(0,0,0,0.5)]">
        <WavesTabGlyph size={22} />
      </span>
    </div>
  );
}

function Carousel({
  urls,
  index,
  onIndexChange,
  onDoubleTap,
  altText,
}: {
  urls: string[];
  index: number;
  onIndexChange: (i: number) => void;
  onDoubleTap: () => void;
  /** Accessibility alt text from the composer — read to screen readers. */
  altText?: string;
}) {
  const [touchStart, setTouchStart] = useState<number | null>(null);
  const lastTap = useRef<number>(0);

  const next = (): void => onIndexChange(Math.min(urls.length - 1, index + 1));
  const prev = (): void => onIndexChange(Math.max(0, index - 1));

  const handleTap = (): void => {
    const now = Date.now();
    if (now - lastTap.current < 280) onDoubleTap();
    lastTap.current = now;
  };

  const handleTouchStart = (e: React.TouchEvent): void => {
    setTouchStart(e.touches[0]?.clientX ?? null);
  };

  const handleTouchEnd = (e: React.TouchEvent): void => {
    if (touchStart === null) return;
    const delta = (e.changedTouches[0]?.clientX ?? 0) - touchStart;
    if (Math.abs(delta) > 50) {
      if (delta > 0) prev();
      else next();
    }
    setTouchStart(null);
  };

  // MOUSE / TRACKPAD SWIPE — desktop gets the same gesture as a phone: press,
  // drag sideways past 50px, release → next / previous photo. A drag that
  // paged suppresses the click so it can't double as a like-tap.
  const mouseStart = useRef<number | null>(null);
  const suppressClick = useRef<boolean>(false);
  const handleMouseDown = (e: React.MouseEvent): void => {
    if (e.button !== 0) return;
    mouseStart.current = e.clientX;
  };
  const handleMouseUp = (e: React.MouseEvent): void => {
    const start = mouseStart.current;
    mouseStart.current = null;
    if (start === null || urls.length < 2) return;
    const delta = e.clientX - start;
    if (Math.abs(delta) > 50) {
      suppressClick.current = true;
      if (delta > 0) prev();
      else next();
      window.setTimeout(() => {
        suppressClick.current = false;
      }, 0);
    }
  };
  const handleTapGuarded = (): void => {
    if (suppressClick.current) return;
    handleTap();
  };

  return (
    <div
      className="relative w-full select-none bg-black"
      onTouchStart={handleTouchStart}
      onTouchEnd={handleTouchEnd}
      onMouseDown={handleMouseDown}
      onMouseUp={handleMouseUp}
      onMouseLeave={() => {
        mouseStart.current = null;
      }}
    >
      {/* Sliding track — Instagram page slide instead of a crossfade. */}
      <div className="aspect-[4/5] w-full overflow-hidden">
        <div
          className="flex h-full w-full transition-transform duration-300 ease-out"
          style={{ transform: `translateX(-${index * 100}%)` }}
        >
          {urls.map((url) => (
            <img
              key={url}
              src={url}
              alt={altText ?? ""}
              draggable={false}
              onClick={handleTapGuarded}
              className="h-full w-full shrink-0 cursor-grab select-none object-contain active:cursor-grabbing"
            />
          ))}
        </div>
      </div>

      {/* Side arrows */}
      {urls.length > 1 && index > 0 && (
        <button
          onClick={prev}
          className="absolute left-2 top-1/2 flex h-8 w-8 -translate-y-1/2 items-center justify-center rounded-full bg-black/40 text-white backdrop-blur-sm transition-transform active:scale-90"
          aria-label="Previous photo"
        >
          <ChevronLeft className="h-5 w-5" />
        </button>
      )}
      {urls.length > 1 && index < urls.length - 1 && (
        <button
          onClick={next}
          className="absolute right-2 top-1/2 flex h-8 w-8 -translate-y-1/2 items-center justify-center rounded-full bg-black/40 text-white backdrop-blur-sm transition-transform active:scale-90"
          aria-label="Next photo"
        >
          <ChevronRight className="h-5 w-5" />
        </button>
      )}

      {/* "1/3" counter chip — multi-photo posts only (IG kit) */}
      {urls.length > 1 && (
        <div className="absolute right-3 top-3 rounded-full bg-black/60 px-2.5 py-1 text-[11px] font-bold text-white backdrop-blur-sm">
          {index + 1}/{urls.length}
        </div>
      )}
    </div>
  );
}

function InlineComments({
  postId,
  postCommentsCount,
  createdAt,
  onCountChange,
  commentsOff = false,
}: {
  postId: string;
  postCommentsCount?: number;
  /** Post creation time — renders the Instagram bottom timestamp. */
  createdAt?: string | null;
  onCountChange?: (count: number) => void;
  /** Instagram "turn off commenting" — hides every comment affordance. */
  commentsOff?: boolean;
}) {
  const { user, profile } = useAuth();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<string>("");
  const [showAll, setShowAll] = useState<boolean>(false);

  const commentsQuery = useQuery({
    queryKey: ["comments", postId],
    queryFn: () => fetchComments(postId),
  });

  const comments = commentsQuery.data ?? [];
  const topLevel = comments.filter((c) => !c.parent_comment_id);
  const count = Math.max(postCommentsCount ?? 0, topLevel.length);

  useEffect(() => {
    onCountChange?.(topLevel.length);
  }, [topLevel.length, onCountChange]);

  // Profile pictures for comment avatars
  const commentUsernames = useMemo(
    () =>
      Array.from(
        new Set(
          comments
            .map((c) => c.username)
            .filter((u) => u && u.toLowerCase() !== "ember")
        )
      ),
    [comments]
  );
  const commentProfilesQuery = useQuery({
    queryKey: ["comment-profiles", postId, commentUsernames],
    queryFn: () => fetchProfilesByUsernames(commentUsernames),
    enabled: commentUsernames.length > 0,
  });
  const commentProfiles = commentProfilesQuery.data ?? {};
  const avatarFor = (uname: string): string | null =>
    commentProfiles[uname.toLowerCase()]?.profile_image_url ?? null;

  const commentMutation = useMutation({
    mutationFn: async (body: string): Promise<void> => {
      if (!user) throw new Error("Sign in to comment");
      await addComment(postId, user.id, profile?.username ?? "you", body);
    },
    onSuccess: () => {
      setDraft("");
      queryClient.invalidateQueries({ queryKey: ["comments", postId] });
      // Optimistically bump the post's comments_count in the feed cache so
      // the count stays visible even before the trigger updates the row.
      queryClient.setQueryData<WhisperPost[]>(["feed"], (old) => {
        if (!old) return old;
        return old.map((p) =>
          p.id === postId
            ? { ...p, comments_count: (p.comments_count ?? 0) + 1 }
            : p
        );
      });
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Couldn't post comment");
    },
  });

  const visible = showAll ? topLevel : topLevel.slice(0, 2);

  return (
    <div className="mt-2">
      {/* Instagram order — "View all N comments" first, then 1–2 previews. */}
      {!commentsOff && count > 0 && !showAll && (
        <>
          <button
            onClick={() => setShowAll(true)}
            className="text-[13px] text-muted-foreground hover:text-foreground"
          >
            {count > 2
              ? `View all ${count} comments`
              : `View comment${count > 1 ? "s" : ""}`}
          </button>
          {visible.map((c) => (
            <div key={c.id} className="mt-0.5 flex gap-1.5 text-[13.5px] leading-snug">
              <Link
                to={`/u/${c.username}`}
                className="shrink-0 font-semibold hover:underline"
              >
                {c.username}
              </Link>
              <span className="line-clamp-1 text-foreground/90">{c.body}</span>
            </div>
          ))}
        </>
      )}

      {/* Full comments list */}
      {!commentsOff && showAll && (
        <div className="mt-2 max-h-[300px] space-y-3 overflow-y-auto border-t border-border pt-3">
          {topLevel.map((c) => {
            const isEmber = c.username.toLowerCase() === "ember";
            return (
              <div key={c.id} className="flex gap-2.5">
                {isEmber ? (
                  <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-emerald-500/10 text-xs font-bold text-emerald-500">
                    E
                  </div>
                ) : (
                  <Link to={`/u/${c.username}`} className="shrink-0">
                    <Avatar url={avatarFor(c.username)} name={c.username} size={28} />
                  </Link>
                )}
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-1.5">
                    <Link
                      to={`/u/${c.username}`}
                      className="text-[13px] font-semibold hover:underline"
                    >
                      {isEmber ? "Jasper" : c.username}
                    </Link>
                    <span className="text-[11px] text-muted-foreground">
                      {timeAgo(c.created_at)}
                    </span>
                  </div>
                  <p className="text-[14px] leading-snug">{c.body}</p>
                </div>
              </div>
            );
          })}
          <button
            onClick={() => setShowAll(false)}
            className="text-[12px] text-muted-foreground hover:text-foreground"
          >
            Hide comments
          </button>
        </div>
      )}

      {/* Instagram bottom timestamp — long form, quiet. */}
      {createdAt && (
        <p className="mt-2 text-[11.5px] text-muted-foreground">
          {longTimeAgo(createdAt)}
        </p>
      )}

      {/* Comment input with the IG emoji shortcuts */}
      {user && !commentsOff && (
        <div className="mt-2.5 flex items-center gap-2 border-t border-border pt-3">
          <Avatar
            url={profile?.profile_image_url ?? null}
            name={profile?.username ?? "you"}
            size={26}
          />
          <input
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && draft.trim()) {
                commentMutation.mutate(draft.trim());
              }
            }}
            placeholder="Add a comment…"
            className="flex-1 bg-transparent text-[13px] outline-none placeholder:text-muted-foreground"
          />
          {!draft.trim() && (
            <>
              <button
                type="button"
                onClick={() => setDraft((d) => d + "❤️")}
                className="text-[14px] transition-transform active:scale-90"
                aria-label="Add heart emoji"
              >
                ❤️
              </button>
              <button
                type="button"
                onClick={() => setDraft((d) => d + "🙌")}
                className="text-[14px] transition-transform active:scale-90"
                aria-label="Add raised hands emoji"
              >
                🙌
              </button>
            </>
          )}
          {draft.trim() && (
            <button
              onClick={() => commentMutation.mutate(draft.trim())}
              disabled={commentMutation.isPending}
              className="text-[13px] font-bold text-emerald-500 transition-opacity active:scale-95 disabled:opacity-50"
            >
              Post
            </button>
          )}
        </div>
      )}
    </div>
  );
}

function GridPostCardBase({
  post,
  author,
  liked,
  reposted = false,
  repostCount = 0,
  bookmarked = false,
  realLikeCount,
  realCommentCount,
}: GridPostCardProps) {
  const { user, profile } = useAuth();
  const queryClient = useQueryClient();
  const [optimisticLiked, setOptimisticLiked] = useState<boolean>(liked);
  const [optimisticSaved, setOptimisticSaved] = useState<boolean>(bookmarked);
  const [optimisticReposted, setOptimisticReposted] = useState<boolean>(reposted);
  const [likeBump, setLikeBump] = useState<number>(0);
  const [repostBump, setRepostBump] = useState<number>(0);
  const [heartBurst, setHeartBurst] = useState<number>(0);
  const [shareOpen, setShareOpen] = useState<boolean>(false);
  const [repostMenuOpen, setRepostMenuOpen] = useState<boolean>(false);
  const [quoteOpen, setQuoteOpen] = useState<boolean>(false);
  const [deleted, setDeleted] = useState<boolean>(false);
  const [mediaIndex, setMediaIndex] = useState<number>(0);
  const [captionExpanded, setCaptionExpanded] = useState<boolean>(false);
  const [storyViewerOpen, setStoryViewerOpen] = useState<boolean>(false);

  // Authoritative engagement sets resolve after the feed renders — keep the
  // optimistic mirrors in sync so liked/reposted state survives a refresh.
  useEffect(() => setOptimisticLiked(liked), [liked]);
  useEffect(() => setOptimisticSaved(bookmarked), [bookmarked]);
  useEffect(() => setOptimisticReposted(reposted), [reposted]);

  const knownUsername = author?.username ?? post.username ?? null;
  // Grid posts in search/discovery can arrive without a handle — resolve the
  // author instead of ever showing a "user" placeholder.
  const authorLookup = useQuery({
    queryKey: ["post-author", post.user_id],
    queryFn: () => fetchProfilesByIds([post.user_id]),
    enabled: !knownUsername && !!post.user_id,
    staleTime: 5 * 60_000,
  });
  const resolvedAuthor = knownUsername ? undefined : authorLookup.data?.[post.user_id];
  const username = knownUsername ?? resolvedAuthor?.username ?? "";
  const displayName =
    author?.display_name ?? resolvedAuthor?.display_name ?? (username || "Whisper member");
  const media = post.media_urls ?? [];
  const meta = parsePostMeta(post.caption);
  const caption = stripPostMeta(post.caption);
  // A wave that opted into the feed ("Also share to feed") renders as
  // Instagram's reel-in-feed: same card, the video in the frame, the sound
  // line under the name, tap opens the player.
  const isWave = post.is_reel === true;
  const navigate = useNavigate();
  const hideCounts = meta?.hideCounts === true;
  const commentsOff = meta?.commentsOff === true;
  const isMyPost = !!user && post.user_id === user.id;

  const baseLikes = realLikeCount ?? post.likes_count ?? 0;
  const likeDelta = (optimisticLiked ? 1 : 0) - (liked ? 1 : 0);
  const likeCount = baseLikes + likeDelta;
  const repostDelta = (optimisticReposted ? 1 : 0) - (reposted ? 1 : 0);
  const liveRepostCount = repostCount + repostDelta;

  // Instagram story ring — the author's active stories from the shared
  // ["stories"] cache (gradient while any is unseen, gray once viewed).
  const storiesQuery = useQuery({
    queryKey: ["stories"],
    queryFn: fetchStories,
    staleTime: 60_000,
  });
  const authorStories = useMemo(
    () => (storiesQuery.data ?? []).filter((s) => s.user_id === post.user_id),
    [storiesQuery.data, post.user_id]
  );
  const hasStory = authorStories.length > 0;
  const hasUnseenStory = useMemo(() => {
    if (!hasStory) return false;
    const seen = loadSeenStoryIds();
    return authorStories.some((s) => !seen.has(s.id));
  }, [authorStories, hasStory]);
  const authorAvatarUrl =
    author?.profile_image_url ?? resolvedAuthor?.profile_image_url ?? null;
  // Tapping a ringed avatar opens the author's active story (IG behavior).
  const authorStoryGroup = useMemo<StoryGroup[]>(() => {
    if (!hasStory) return [];
    return [
      {
        userId: post.user_id,
        username: username || displayName,
        avatarUrl: authorAvatarUrl,
        stories: authorStories,
      },
    ];
  }, [hasStory, post.user_id, username, displayName, authorAvatarUrl, authorStories]);

  // "Liked by X and others" — first likers with profiles (lazy, cached).
  const likersQuery = useQuery({
    queryKey: ["post-likers", post.id],
    queryFn: () => fetchPostLikersPreview(post.id),
    enabled: likeCount > 0 && !hideCounts,
    staleTime: 60_000,
  });
  const likers = likersQuery.data ?? [];

  const likeMutation = useMutation({
    mutationFn: () => toggleLike(post.id, user!.id, optimisticLiked),
    onMutate: () => {
      setOptimisticLiked((v) => !v);
      setLikeBump((v) => v + 1);
      // Optimistically update the feed cache so the like count & state
      // remain visible even before the server trigger updates the row.
      queryClient.setQueryData<WhisperPost[]>(["feed"], (old) => {
        if (!old) return old;
        return old.map((p) =>
          p.id === post.id
            ? {
                ...p,
                likes_count: (p.likes_count ?? 0) + (optimisticLiked ? -1 : 1),
              }
            : p
        );
      });
    },
    onError: () => {
      setOptimisticLiked((v) => !v);
      toast.error("Couldn't update like");
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ["my-likes"] });
      queryClient.invalidateQueries({ queryKey: ["feed"] });
    },
  });

  const saveMutation = useMutation({
    mutationFn: () => toggleBookmark(post.id, user!.id, optimisticSaved),
    onMutate: () => setOptimisticSaved((v) => !v),
    onError: () => {
      setOptimisticSaved((v) => !v);
      toast.error("Couldn't update bookmark");
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: ["my-bookmarks"] }),
  });

  const repostMutation = useMutation({
    mutationFn: () => toggleRepost(post.id, user!.id, optimisticReposted),
    onMutate: () => {
      setOptimisticReposted((v) => !v);
      setRepostBump((v) => v + 1);
    },
    onSuccess: () => toast(optimisticReposted ? "Reposted" : "Removed repost"),
    onError: () => {
      setOptimisticReposted((v) => !v);
      toast.error("Couldn't repost — try again");
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ["my-reposts"] });
      queryClient.invalidateQueries({ queryKey: ["repost-counts"] });
      queryClient.invalidateQueries({ queryKey: ["user-reposts"] });
    },
  });

  const deleteMutation = useMutation({
    mutationFn: () => deletePost(post.id),
    onSuccess: () => {
      setDeleted(true);
      removePagedFeedPost(queryClient, post.id);
      toast("Post deleted");
      queryClient.invalidateQueries({ queryKey: ["feed"] });
    },
  });

  const reportMutation = useMutation({
    mutationFn: () =>
      reportPost({
        reporterId: user!.id,
        reporterUsername: profile?.username ?? user?.id ?? "unknown",
        postId: post.id,
        targetUserId: post.user_id,
        targetUsername: username || post.user_id,
        reason: "inappropriate",
      }),
    onSuccess: () => toast("Report submitted"),
  });

  const handleDoubleTap = (): void => {
    setHeartBurst((v) => v + 1);
    if (!optimisticLiked) likeMutation.mutate();
  };

  if (deleted) return null;

  return (
    <article className="relative border-b border-border bg-background">
      {/* Header — identity + timestamp up top (IG style), location below. */}
      <div className="flex items-center justify-between px-3 py-3">
        <div className="flex min-w-0 items-center gap-2.5">
          {/* Story ring — Whisper gradient while unseen, gray once viewed.
              A ringed avatar opens the story viewer; otherwise it links to
              the profile (IG behavior). */}
          {hasStory ? (
            <button
              onClick={() => setStoryViewerOpen(true)}
              aria-label={`View ${username || displayName}'s story`}
              className={cn(
                "shrink-0 rounded-full p-[2px] transition-transform active:scale-95",
                hasUnseenStory ? WHISPER_STORY_RING_TW : "bg-border"
              )}
            >
              <span className="block rounded-full bg-background p-[2px]">
                <Avatar url={authorAvatarUrl} name={displayName} size={34} />
              </span>
            </button>
          ) : (
            <Link
              to={username ? `/u/${encodeURIComponent(username)}` : "/"}
              className="shrink-0"
            >
              <Avatar
                url={authorAvatarUrl}
                name={displayName}
                size={38}
                className="ring-1 ring-border"
              />
            </Link>
          )}
          <div className="flex min-w-0 flex-col">
            <span className="flex min-w-0 items-center gap-1 text-[13.5px] font-bold leading-tight">
              <Link
                to={username ? `/u/${encodeURIComponent(username)}` : "/"}
                className="truncate hover:underline"
              >
                {username || displayName}
              </Link>
              <UserBadges profile={author} size={13} />
              {post.community_id && (
                <Link
                  to={`/c/${post.community_id}`}
                  className="flex min-w-0 items-center gap-1 transition-opacity hover:opacity-80"
                >
                  <ChevronRight
                    className="h-3 w-3 shrink-0 text-muted-foreground/50"
                    strokeWidth={2.5}
                  />
                  <Grip className="h-3 w-3 shrink-0 text-muted-foreground" />
                  <span className="min-w-0 truncate text-[12.5px] font-semibold text-foreground/75">
                    {post.community_name ??
                      communityById(post.community_id)?.name ??
                      post.community_id}
                  </span>
                </Link>
              )}
            </span>
            {isWave ? (
              // Instagram's reel-in-feed header line: the sound under the name.
              <span className="flex min-w-0 items-center gap-1 text-[12px] leading-tight text-muted-foreground">
                <Music className="h-3 w-3 shrink-0" />
                <span className="truncate">
                  {meta?.music
                    ? `${meta.music.title} · ${meta.music.artist}`
                    : `${username || displayName} · Original audio`}
                </span>
              </span>
            ) : (
              meta?.location && (
                <span className="flex min-w-0 items-center gap-0.5 text-[12px] leading-tight text-muted-foreground">
                  <MapPin className="h-3 w-3 shrink-0" />
                  <span className="truncate">{meta.location}</span>
                </span>
              )
            )}
          </div>
        </div>

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button className="flex h-8 w-8 items-center justify-center rounded-full transition-colors active:scale-90">
              <MoreHorizontal className="h-5 w-5 text-foreground/70" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-44">
            <DropdownMenuItem onClick={() => setShareOpen(true)}>
              Share post
            </DropdownMenuItem>
            {!isMyPost && (
              <DropdownMenuItem onClick={() => reportMutation.mutate()}>
                Report
              </DropdownMenuItem>
            )}
            {isMyPost && (
              <DropdownMenuItem
                onClick={() => deleteMutation.mutate()}
                className="text-destructive focus:text-destructive"
              >
                {deleteMutation.isPending ? (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                ) : null}
                Delete
              </DropdownMenuItem>
            )}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      {/* Full-bleed media — a wave plays as Instagram's reel-in-feed (muted
          in view, the Waves mark top-right, tap opens the player); photos
          ride the carousel. */}
      {isWave ? (
        <WaveFeedMedia
          src={media[0] ?? ""}
          poster={meta?.cover ?? undefined}
          onOpen={() => navigate(`/reels?wave=${encodeURIComponent(post.id)}`)}
          onDoubleTap={handleDoubleTap}
        />
      ) : (
        <Carousel
          urls={media}
          index={mediaIndex}
          onIndexChange={setMediaIndex}
          onDoubleTap={handleDoubleTap}
          altText={meta?.altText}
        />
      )}

      {/* Instagram double-tap heart burst — big white heart */}
      {heartBurst > 0 && (
        <div
          key={heartBurst}
          className="animate-heart-burst pointer-events-none absolute inset-0 flex items-center justify-center"
        >
          <Heart className="h-24 w-24 fill-white text-white drop-shadow-[0_6px_20px_rgba(0,0,0,0.45)]" />
        </div>
      )}

      {/* Engagement bar */}
      <div className="px-3 pt-3">
        <div className="relative flex items-center justify-between">
          <div className="flex items-center gap-1">
            <button
              onClick={() => likeMutation.mutate()}
              className={cn(
                "flex h-9 items-center justify-center gap-1 rounded-full px-1 transition-all active:scale-90",
                optimisticLiked
                  ? "text-rose-500"
                  : "text-foreground/90 hover:text-foreground"
              )}
              aria-label="Like"
            >
              <Heart
                key={likeBump}
                className={cn(
                  "h-6 w-6 transition-all",
                  optimisticLiked && "fill-rose-500"
                )}
              />
              {/* Kit 4.0: the count sits right beside the icon (12/semibold). */}
              {!hideCounts && likeCount > 0 && (
                <span className="text-[13px] font-semibold tabular-nums text-foreground">
                  {compactCount(likeCount)}
                </span>
              )}
            </button>
            {!commentsOff && (
              <button
                onClick={() => {
                  const el = document.getElementById(`comments-${post.id}`);
                  el?.scrollIntoView({ behavior: "smooth", block: "center" });
                  el?.focus();
                }}
                className="flex h-9 items-center justify-center gap-1 rounded-full px-1 text-foreground/90 transition-all hover:text-foreground active:scale-90"
                aria-label="Comment"
              >
                <MessageCircle className="h-6 w-6" />
                {!hideCounts && (realCommentCount ?? post.comments_count ?? 0) > 0 && (
                  <span className="text-[13px] font-semibold tabular-nums text-foreground">
                    {compactCount(realCommentCount ?? post.comments_count ?? 0)}
                  </span>
                )}
              </button>
            )}
            <button
              onClick={() => setRepostMenuOpen(true)}
              className={cn(
                "flex h-9 items-center justify-center gap-1 rounded-full px-1.5 transition-all active:scale-90",
                optimisticReposted
                  ? "text-repost"
                  : "text-foreground/90 hover:text-foreground"
              )}
              aria-label="Repost"
            >
              <Repeat2 key={repostBump} className="h-6 w-6" />
              {!hideCounts && liveRepostCount > 0 && (
                <span className="text-[13px] font-semibold tabular-nums">
                  {compactCount(liveRepostCount)}
                </span>
              )}
            </button>
            <button
              onClick={() => setShareOpen(true)}
              className="flex h-9 w-9 items-center justify-center rounded-full text-foreground/90 transition-all hover:text-foreground active:scale-90"
              aria-label="Share"
            >
              <Send className="h-6 w-6" />
            </button>
          </div>
          {/* Instagram carousel dots — centered between the action clusters */}
          {media.length > 1 && (
            <div className="pointer-events-none absolute left-1/2 top-1/2 flex -translate-x-1/2 -translate-y-1/2 items-center gap-1">
              {media.map((u, i) => (
                <span
                  key={u}
                  className={cn(
                    "rounded-full transition-all duration-200",
                    i === mediaIndex
                      ? "h-1.5 w-1.5 bg-[#3897F0]"
                      : "h-1 w-1 bg-foreground/25"
                  )}
                />
              ))}
            </div>
          )}
          <button
            onClick={() => saveMutation.mutate()}
            className={cn(
              "flex h-9 w-9 items-center justify-center rounded-full transition-all active:scale-90",
              optimisticSaved
                ? "text-foreground"
                : "text-foreground/90 hover:text-foreground"
            )}
            aria-label="Save"
          >
            <Bookmark
              className={cn("h-6 w-6", optimisticSaved && "fill-foreground")}
            />
          </button>
        </div>

        {/* Music line — IG-style "song · artist" attribution. */}
        {meta?.music && (
          <p className="mt-1 flex items-center gap-1.5 text-[12.5px] text-muted-foreground">
            <Music className="h-3.5 w-3.5 shrink-0" />
            <span className="truncate">
              <span className="font-semibold text-foreground/80">{meta.music.title}</span>
              {" · "}
              {meta.music.artist}
            </span>
          </p>
        )}

        {/* "Liked by X and others" with the likers facepile (IG kit) */}
        {!hideCounts &&
          likeCount > 0 &&
          (likers.length > 0 ? (
            <div className="mt-1.5 flex items-center gap-2">
              <div className="flex shrink-0 -space-x-1.5">
                {likers.map((l) => (
                  <Avatar
                    key={l.userId}
                    url={l.avatarUrl}
                    name={l.username}
                    size={18}
                    className="ring-2 ring-background"
                  />
                ))}
              </div>
              <p className="min-w-0 truncate text-[13.5px]">
                Liked by{" "}
                <Link
                  to={`/u/${encodeURIComponent(likers[0].username)}`}
                  className="font-bold hover:underline"
                >
                  {likers[0].username}
                </Link>
                {likeCount > 1 && (
                  <>
                    {" "}
                    and{" "}
                    <span className="font-bold">
                      {compactCount(likeCount - 1)} others
                    </span>
                  </>
                )}
              </p>
            </div>
          ) : (
            <p className="mt-1 text-[14px] font-bold">
              {compactCount(likeCount)} likes
            </p>
          ))}
        <PostCorrectionNotice postID={post.id} />
        {caption.trim() && (
          <div className="mt-1 text-[14px]">
            <div className={cn(!captionExpanded && "line-clamp-2")}>
              <Link
                to={username ? `/u/${encodeURIComponent(username)}` : "/"}
                className="mr-1.5 font-bold hover:underline"
              >
                {username || displayName}
              </Link>
              <MentionText text={caption} className="leading-snug" />
            </div>
            {!captionExpanded && caption.length > 84 && (
              <button
                onClick={() => setCaptionExpanded(true)}
                className="text-[13px] text-muted-foreground"
              >
                more
              </button>
            )}
          </div>
        )}
        {(meta?.tagged?.length ?? 0) > 0 && (
          <MentionText
            text={`with ${meta!.tagged!.map((t) => `@${t}`).join(" ")}`}
            className="mt-0.5 block text-[13px] text-muted-foreground"
          />
        )}

        {/* Inline comments */}
        <div id={`comments-${post.id}`} tabIndex={-1} className="pb-3 text-[14px]">
          <InlineComments
            postId={post.id}
            postCommentsCount={realCommentCount ?? post.comments_count ?? 0}
            createdAt={post.created_at}
            commentsOff={commentsOff}
          />
        </div>
      </div>

      {shareOpen && (
        <SharePostDialog
          post={post}
          authorUsername={username}
          open={shareOpen}
          onOpenChange={setShareOpen}
        />
      )}

      <RepostOptionsSheet
        open={repostMenuOpen}
        onOpenChange={setRepostMenuOpen}
        isReposted={optimisticReposted}
        onQuote={() => {
          setRepostMenuOpen(false);
          setQuoteOpen(true);
        }}
        onRepostOnly={() => {
          setRepostMenuOpen(false);
          repostMutation.mutate();
        }}
      />

      <ComposerModal
        open={quoteOpen}
        onOpenChange={setQuoteOpen}
        mode="thread"
        quotedPost={post}
        quotedAuthor={username}
      />

      {/* Story viewer — opened from the ringed avatar (portals to body). */}
      {storyViewerOpen && authorStoryGroup.length > 0 && (
        <StoryViewer
          groups={authorStoryGroup}
          startGroup={0}
          onClose={() => setStoryViewerOpen(false)}
          me={{
            id: user?.id,
            username: profile?.username,
            avatarUrl: profile?.profile_image_url,
          }}
        />
      )}
    </article>
  );
}

export const GridPostCard = memo(GridPostCardBase);
