import { memo, useEffect, useMemo, useRef, useState } from "react";
import { removePagedFeedPost } from "@/lib/feedPaging";
import { Link } from "react-router-dom";
import {
  MoreHorizontal,
  Bookmark,
  ChevronRight,
  Grip,
  Link2,
  Flag,
  Trash2,
  BadgeCheck,
  BarChart3,
  Pin,
  PinOff,
  Loader2,
  CheckCircle2,
  ShieldCheck,
  AlertTriangle,
  XCircle,
  HelpCircle,
} from "lucide-react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { PostInsightMetrics } from "@/components/PostInsightMetrics";
import { PostCorrectionNotice } from "@/components/PostCorrectionNotice";
import { WhisperHeart as Heart, WhisperComment as MessageCircle, WhisperRepost as Repeat2, WhisperShare as Send } from "@/components/WhisperGlyph";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import { playLikeSound } from "@/lib/meetSounds";
import { siteUrl } from "@/lib/site";
import { useDragScroll } from "@/hooks/useDragScroll";
import { timeAgo, compactCount } from "@/lib/format";
import { Avatar } from "@/components/Avatar";
import { EmberBadge } from "@/components/EmberBadge";
import { MentionText } from "@/components/MentionText";
import { UserBadges } from "@/components/UserBadges";
import { WorkoutCard } from "@/components/WorkoutCard";
import { GridPostCard } from "@/components/GridPostCard";
import { PostMetaView } from "@/components/PostMetaView";
import { parseWorkoutEmbed, stripWorkoutEmbed } from "@/lib/workout";
import { parsePostMeta, stripPostMeta } from "@/lib/postMeta";
import { extractSharedPost } from "@/lib/postShare";
import { parseContentEmbeds } from "@/lib/contentEmbeds";
import { communityById } from "@/lib/communities";
import { ArticleEmbedCard, FilmEmbedCard } from "@/components/ContentEmbedCards";
import { QuotedPostCard } from "@/components/QuotedPostCard";
import { RepostOptionsSheet } from "@/components/RepostOptionsSheet";
import { ComposerModal } from "@/components/ComposerModal";
import {
  addComment,
  addEmberComment,
  deletePost,
  fetchComments,
  fetchPinnedPostIds,
  fetchProfilesByUsernames,
  fetchStories,
  pinPost,
  reportPost,
  toggleBookmark,
  toggleLike,
  toggleRepost,
  unpinPost,
} from "@/lib/api";
import { loadSeenStoryIds } from "@/lib/storySeen";
import { WHISPER_STORY_RING_TW } from "@/lib/storyRing";
import { StoryViewer, type StoryGroup } from "@/components/StoryViewer";
import {
  emberCommentReply,
  shouldEmberRespond,
  factCheck,
  EMBER_ENABLED,
  type FactCheck,
  type Verdict,
} from "@/lib/ember";
import { useAuth } from "@/hooks/useAuth";
import { useMyBadge } from "@/hooks/useMyBadge";
import { SharePostDialog } from "@/components/SharePostDialog";
import {
  fetchActiveAds,
  trackAdClick,
  trackAdImpression,
  externalUrl,
  type ActiveAd,
} from "@/lib/business";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import type {
  WhisperComment,
  WhisperLiarBadge,
  WhisperPost,
  WhisperProfile,
} from "@/lib/types";

interface PostCardProps {
  post: WhisperPost;
  /** Expands only one original automatically; deeper references open explicitly. */
  quoteDepth?: number;
  author?: WhisperProfile;
  liar?: WhisperLiarBadge | null;
  liked: boolean;
  reposted?: boolean;
  repostCount?: number;
  bookmarked?: boolean;
  /** Shows a "Pinned" label above the post (used on profiles). */
  pinned?: boolean;
  /** Real like count from the engagement table (overrides post.likes_count when available). */
  realLikeCount?: number;
  /** Real comment count from the engagement table (overrides post.comments_count when available). */
  realCommentCount?: number;
  /** Community special react — when set (rendering inside a community feed),
   *  the liked heart and the double-tap burst wear THIS emoji instead
   *  (⚖️ in Whisper Law, 💪 at your gym). */
  specialReact?: string;
}

function PostMedia({
  urls,
  onDoubleTap,
}: {
  urls: string[];
  onDoubleTap: () => void;
}) {
  const [index, setIndex] = useState<number>(0);
  const lastTap = useRef<number>(0);
  const { ref, handlers, didDrag } = useDragScroll<HTMLDivElement>();

  if (urls.length === 0) return null;

  const handleTap = (): void => {
    if (didDrag()) return;
    const now = Date.now();
    if (now - lastTap.current < 280) onDoubleTap();
    lastTap.current = now;
  };

  const single = urls.length === 1;

  if (single) {
    return (
      <div
        onClick={handleTap}
        className="mt-2 cursor-pointer overflow-hidden rounded-[18px] border border-border bg-secondary"
      >
        <img src={urls[0]} alt="" className="max-h-[420px] w-full object-cover" />
      </div>
    );
  }

  return (
    <div className="mt-2">
      <div
        ref={ref}
        {...handlers}
        className="no-scrollbar flex cursor-grab snap-x snap-mandatory gap-2 overflow-x-auto scroll-smooth active:cursor-grabbing"
        style={{ WebkitOverflowScrolling: "touch" }}
        onScroll={(e) => {
          const el = e.currentTarget;
          const w = el.scrollWidth / urls.length;
          setIndex(Math.round(el.scrollLeft / w));
        }}
      >
        {urls.map((u) => (
          <img
            key={u}
            src={u}
            alt=""
            draggable={false}
            onClick={handleTap}
            className="aspect-[3/4] w-[62%] shrink-0 snap-center select-none rounded-[18px] border border-border bg-secondary object-cover"
          />
        ))}
      </div>
      <div className="mt-2 flex items-center justify-center gap-1.5">
        {urls.map((u, i) => (
          <span
            key={u}
            className={cn(
              "h-1.5 rounded-full transition-all",
              i === index ? "w-4 bg-foreground" : "w-1.5 bg-foreground/25"
            )}
          />
        ))}
      </div>
    </div>
  );
}

/**
 * Per-post throttle so a burst of `@ember` mentions only bills the AI once a
 * minute per post (mirrors the iOS `WhisperEmberMention` throttle).
 */
const emberLastReplyAt = new Map<string, number>();
const EMBER_THROTTLE_MS = 60_000;

function emberThrottled(postId: string): boolean {
  const last = emberLastReplyAt.get(postId);
  return last !== undefined && Date.now() - last < EMBER_THROTTLE_MS;
}

function markEmberReplied(postId: string): void {
  emberLastReplyAt.set(postId, Date.now());
}

type ActionAnim = "pop" | "spin" | "fly";

function ActionButton({
  icon,
  count,
  active,
  activeClass,
  onClick,
  bump = 0,
  anim = "pop",
}: {
  icon: React.ReactNode;
  count: number;
  active?: boolean;
  activeClass?: string;
  onClick?: () => void;
  bump?: number;
  anim?: ActionAnim;
}) {
  const animClass =
    anim === "spin"
      ? "animate-spin-once"
      : anim === "fly"
        ? "animate-fly"
        : "animate-pop";
  return (
    <button
      onClick={onClick}
      className="-ml-2 flex items-center gap-1.5 rounded-full px-2 py-1.5 transition-colors hover:bg-secondary active:scale-90"
    >
      <span
        key={bump}
        className={cn(
          "flex h-7 w-7 items-center justify-center transition-colors",
          active ? activeClass : "text-foreground/90",
          bump > 0 && animClass
        )}
      >
        {icon}
      </span>
      {count > 0 && (
        <span className="text-[13px] font-semibold tabular-nums text-foreground/70">
          {compactCount(count)}
        </span>
      )}
    </button>
  );
}

/**
 * A single comment in the thread. The avatar column carries a connecting line
 * — a top stub links up to the parent, and a `hasThread` line drops down to
 * its own replies, so the thread visibly connects rather than just looking it.
 */
/**
 * One quiet sponsored row inside a comment thread — the "comments" ad
 * placement from Whisper Business. Tracked like every other placement.
 */
function SponsoredCommentRow({ ad }: { ad: ActiveAd }) {
  useEffect(() => {
    if (ad.id) trackAdImpression(ad.id);
  }, [ad.id]);
  const destination =
    externalUrl(ad.cta_url) ?? externalUrl(ad.business_website);
  return (
    <div className="my-1.5 flex gap-2.5 rounded-2xl bg-muted/30 px-2.5 py-2.5">
      {ad.business_logo_url ? (
        <img
          src={ad.business_logo_url}
          alt={ad.business_name}
          className="h-8 w-8 shrink-0 rounded-full border border-border/50 object-cover"
          loading="lazy"
        />
      ) : (
        <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-secondary text-[11px] font-black">
          {ad.business_name.slice(0, 1).toUpperCase()}
        </span>
      )}
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <span className="truncate text-[13px] font-semibold">
            {ad.business_name}
          </span>
          <span className="shrink-0 rounded-full bg-secondary px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wide text-muted-foreground">
            Sponsored
          </span>
          <span className="ml-auto shrink-0 rounded-md border border-border/50 bg-background/70 px-1.5 py-0.5 text-[8.5px] font-black uppercase tracking-wide text-muted-foreground">
            Ad
          </span>
        </div>
        <p className="mt-0.5 text-[13px] leading-snug">{ad.headline}</p>
        {ad.body && (
          <p className="mt-0.5 line-clamp-2 text-[12px] leading-snug text-muted-foreground">
            {ad.body}
          </p>
        )}
        <button
          onClick={() => {
            trackAdClick(ad.id);
            if (destination)
              window.open(destination, "_blank", "noopener,noreferrer");
          }}
          className="mt-1.5 text-[12px] font-bold text-[#5A5FE8]"
        >
          {ad.cta_label || "Learn more"} ↗
        </button>
      </div>
    </div>
  );
}

function CommentRow({
  comment,
  isReply = false,
  hasThread = false,
  authorUrl,
  onReply,
}: {
  comment: WhisperComment;
  isReply?: boolean;
  hasThread?: boolean;
  authorUrl?: string | null;
  onReply: (c: WhisperComment) => void;
}) {
  const size = isReply ? 26 : 32;
  const isEmber = comment.username.toLowerCase() === "ember";
  return (
    <div className="flex gap-2.5">
      {/* Avatar column + thread rails */}
      <div className="relative flex flex-col items-center" style={{ width: size }}>
        {isReply && (
          <span className="absolute -top-2 left-1/2 h-3 w-0.5 -translate-x-1/2 bg-foreground/15" />
        )}
        {isEmber ? (
          <span className="z-10">
            <EmberBadge size={size} />
          </span>
        ) : (
          <Link to={`/u/${comment.username}`} className="z-10">
            <Avatar url={authorUrl} name={comment.username} size={size} />
          </Link>
        )}
        {hasThread && (
          <span className="mt-1 w-0.5 flex-1 rounded-full bg-foreground/15" />
        )}
      </div>

      <div className="min-w-0 flex-1 pb-2.5">
        <div className="flex items-center gap-1.5">
          {isEmber ? (
            <span className="text-[13px] font-semibold">Jasper</span>
          ) : (
            <Link
              to={`/u/${comment.username}`}
              className="text-[13px] font-semibold hover:underline"
            >
              {comment.username}
            </Link>
          )}
          <span className="text-xs text-muted-foreground">
            {timeAgo(comment.created_at)}
          </span>
        </div>
        <MentionText
          text={comment.body}
          className="mt-0.5 block text-[14px] leading-snug"
        />
        <button
          onClick={() => onReply(comment)}
          className="mt-1 text-xs font-semibold text-muted-foreground transition-colors hover:text-foreground"
        >
          Reply
        </button>
      </div>
    </div>
  );
}

function PostCardBase(props: PostCardProps) {
  // Pure dispatcher — grid posts get the Instagram card, a wave that opted
  // into the feed ("Also share to feed") gets the same card as Instagram's
  // reel-in-feed, everything else the Threads card. Splitting the components
  // keeps every hook unconditional (the old early-return-before-hooks pattern
  // violated the rules of hooks and could corrupt rendering if a post's kind
  // ever changed in place).
  if (props.post.kind === "grid" || props.post.is_reel === true) {
    return (
      <GridPostCard
        post={props.post}
        author={props.author}
        liked={props.liked}
        reposted={props.reposted ?? false}
        repostCount={props.repostCount ?? 0}
        bookmarked={props.bookmarked ?? false}
        realLikeCount={props.realLikeCount}
        realCommentCount={props.realCommentCount}
      />
    );
  }
  return <ThreadPostCard {...props} />;
}

/**
 * Threads-grammar text post — 36px avatar column with the thread rail,
 * username · 15/600 left, time · 12 gray grouped with ⋯ on the right,
 * 15px body, pill action row with counts beside the icons.
 */
function ThreadPostCard({
  post,
  author,
  liar,
  liked,
  reposted = false,
  repostCount = 0,
  bookmarked = false,
  pinned = false,
  realLikeCount,
  realCommentCount,
  specialReact,
  quoteDepth = 0,
}: PostCardProps) {
  const { user, profile } = useAuth();
  const badge = useMyBadge();
  const isVerified = badge !== "none";
  const queryClient = useQueryClient();
  const [optimisticLiked, setOptimisticLiked] = useState<boolean>(liked);
  const [likeBump, setLikeBump] = useState<number>(0);
  const [showComments, setShowComments] = useState<boolean>(false);
  const [draft, setDraft] = useState<string>("");
  const [heartBurst, setHeartBurst] = useState<number>(0);

  const [optimisticReposted, setOptimisticReposted] = useState<boolean>(reposted);
  const [repostBump, setRepostBump] = useState<number>(0);
  const [optimisticSaved, setOptimisticSaved] = useState<boolean>(bookmarked);
  const [shareBump, setShareBump] = useState<number>(0);
  const [confirmDelete, setConfirmDelete] = useState<boolean>(false);
  const [deleted, setDeleted] = useState<boolean>(false);
  const [replyTo, setReplyTo] = useState<WhisperComment | null>(null);
  const [reportOpen, setReportOpen] = useState<boolean>(false);
  const [reportReason, setReportReason] = useState<string | null>(null);
  const [reportDetails, setReportDetails] = useState<string>("");
  const [reportDone, setReportDone] = useState<boolean>(false);
  const [shareOpen, setShareOpen] = useState<boolean>(false);
  const [factOpen, setFactOpen] = useState<boolean>(false);
  const [factResult, setFactResult] = useState<FactCheck | null>(null);
  const [insightsOpen, setInsightsOpen] = useState<boolean>(false);
  const [repostMenuOpen, setRepostMenuOpen] = useState<boolean>(false);
  const [quoteOpen, setQuoteOpen] = useState<boolean>(false);
  const [captionExpanded, setCaptionExpanded] = useState<boolean>(false);
  const [storyViewerOpen, setStoryViewerOpen] = useState<boolean>(false);

  // The authoritative liked/reposted/saved sets load AFTER the feed renders
  // (separate queries), so the props flip from false → true a moment after
  // mount. Without syncing, the optimistic mirrors kept their stale initial
  // value and likes/reposts looked like they "disappeared" on every refresh.
  useEffect(() => setOptimisticLiked(liked), [liked]);
  useEffect(() => setOptimisticReposted(reposted), [reposted]);
  useEffect(() => setOptimisticSaved(bookmarked), [bookmarked]);

  const username = author?.username ?? post.username ?? "user";
  const media = post.media_urls ?? [];
  const workout = parseWorkoutEmbed(post.caption);
  const meta = parsePostMeta(post.caption);
  const captionBeforeQuote = (
    workout
      ? stripWorkoutEmbed(post.caption)
      : meta
        ? stripPostMeta(post.caption)
        : post.caption ?? ""
  ).trim();
  const { payload: quoted, rest: captionWithEmbeds } = extractSharedPost(captionBeforeQuote);
  // Film/article embed lines planted by "Post to your wall" — stripped from
  // the visible text and rendered as tappable cards below the caption.
  const {
    cleaned: caption,
    film: filmEmbed,
    article: articleEmbed,
  } = parseContentEmbeds(captionWithEmbeds);
  const isMyPost = !!user && post.user_id === user.id;
  const canPin = isMyPost && isVerified;

  const baseLikes = realLikeCount ?? post.likes_count ?? 0;
  const likeDelta = (optimisticLiked ? 1 : 0) - (liked ? 1 : 0);
  const likeCount = baseLikes + likeDelta;

  const repostDelta = (optimisticReposted ? 1 : 0) - (reposted ? 1 : 0);
  const liveRepostCount = repostCount + repostDelta;

  // Whisper story ring on the thread avatar — shares the ["stories"] cache
  // with the strip and grid cards, so long feeds never refetch.
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
  const authorStoryGroup = useMemo<StoryGroup[]>(() => {
    if (!hasStory) return [];
    return [
      {
        userId: post.user_id,
        username,
        avatarUrl: author?.profile_image_url ?? null,
        stories: authorStories,
      },
    ];
  }, [hasStory, post.user_id, username, author?.profile_image_url, authorStories]);

  const likeMutation = useMutation({
    mutationFn: () => toggleLike(post.id, user!.id, optimisticLiked),
    onMutate: () => {
      // The like FEELS like something: a soft two-note pop (never on unlike).
      if (!optimisticLiked) playLikeSound();
      setOptimisticLiked((v) => !v);
      setLikeBump((v) => v + 1);
      // Optimistically update the feed cache so the like count & state retain
      // while the server trigger updates the row.
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
    onError: () => setOptimisticLiked((v) => !v),
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ["my-likes"] });
      queryClient.invalidateQueries({ queryKey: ["feed-like-counts"] });
    },
  });

  /** Likes only on double-tap — never unlikes (matches iOS heart burst). */
  const handleDoubleTapLike = (): void => {
    setHeartBurst((v) => v + 1);
    if (!optimisticLiked) likeMutation.mutate();
  };

  const repostMutation = useMutation({
    mutationFn: () => toggleRepost(post.id, user!.id, optimisticReposted),
    onMutate: () => {
      setOptimisticReposted((v) => !v);
      setRepostBump((v) => v + 1);
    },
    onSuccess: () => {
      toast(optimisticReposted ? "Reposted" : "Removed repost");
    },
    onError: () => {
      setOptimisticReposted((v) => !v);
      toast("Couldn't repost — try again");
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ["my-reposts"] });
      queryClient.invalidateQueries({ queryKey: ["repost-counts"] });
      queryClient.invalidateQueries({ queryKey: ["user-reposts"] });
    },
  });

  const bookmarkMutation = useMutation({
    mutationFn: () => toggleBookmark(post.id, user!.id, optimisticSaved),
    onMutate: () => setOptimisticSaved((v) => !v),
    onSuccess: () => toast(optimisticSaved ? "Saved" : "Removed from saved"),
    onError: () => setOptimisticSaved((v) => !v),
    onSettled: () => queryClient.invalidateQueries({ queryKey: ["my-bookmarks"] }),
  });

  const pinnedQuery = useQuery({
    queryKey: ["my-pins", user?.id],
    queryFn: () => fetchPinnedPostIds(user!.id),
    enabled: canPin,
  });
  const isPinned = (pinnedQuery.data ?? []).includes(post.id);

  const pinMutation = useMutation({
    mutationFn: () =>
      isPinned ? unpinPost(user!.id, post.id) : pinPost(user!.id, post.id),
    onSuccess: () => {
      toast(isPinned ? "Unpinned from profile" : "Pinned to profile");
      queryClient.invalidateQueries({ queryKey: ["my-pins", user?.id] });
      queryClient.invalidateQueries({ queryKey: ["pinned-posts", post.user_id] });
    },
    onError: (e) =>
      toast(e instanceof Error ? e.message : "Couldn't update pin"),
  });

  const deleteMutation = useMutation({
    mutationFn: () => deletePost(post.id),
    onSuccess: () => {
      setDeleted(true);
      removePagedFeedPost(queryClient, post.id);
      toast("Post deleted");
      queryClient.invalidateQueries({ queryKey: ["feed"] });
    },
    onError: () => toast("Couldn't delete post"),
  });

  const commentsQuery = useQuery({
    queryKey: ["comments", post.id],
    queryFn: () => fetchComments(post.id),
    enabled: showComments,
  });

  // The "comments" ad placement — one quiet sponsored row per opened
  // thread, resolved from the same full-funnel rotation as the feed.
  const commentAdQuery = useQuery({
    queryKey: ["business-active-ads", "comments", post.id],
    queryFn: () => fetchActiveAds("comments", 1),
    enabled: showComments,
    staleTime: 5 * 60 * 1000,
  });
  const commentAd = (commentAdQuery.data ?? [])[0] ?? null;

  const commentMutation = useMutation({
    mutationFn: async (body: string): Promise<void> => {
      const parentId = replyTo?.id ?? null;
      await addComment(
        post.id,
        user!.id,
        profile?.username ?? "you",
        body,
        parentId
      );
      // If the comment tagged @ember, fire Ember's reply as a comment so the
      // AI joins the thread inline — exactly like the iOS comment behaviour.
      if (shouldEmberRespond(body) && !emberThrottled(post.id)) {
        markEmberReplied(post.id);
        try {
          const answer = await emberCommentReply(body, post.caption ?? "");
          if (answer.trim()) {
            await addEmberComment(post.id, user!.id, answer.trim(), parentId);
          }
        } catch {
          /* best-effort — a failed AI reply shouldn't block the comment */
        }
      }
    },
    onSuccess: () => {
      setDraft("");
      setReplyTo(null);
      queryClient.invalidateQueries({ queryKey: ["comments", post.id] });
    },
  });

  const reportMutation = useMutation({
    mutationFn: () =>
      reportPost({
        reporterId: user!.id,
        reporterUsername: profile?.username ?? "you",
        postId: post.id,
        targetUserId: post.user_id,
        targetUsername: username,
        reason: reportReason ?? "other",
        details: reportDetails.trim() || undefined,
      }),
    onSuccess: () => {
      setReportDone(true);
      window.setTimeout(() => {
        setReportOpen(false);
        setReportDone(false);
        setReportReason(null);
        setReportDetails("");
      }, 1500);
    },
    onError: () => toast("Couldn't submit report"),
  });

  const factMutation = useMutation({
    mutationFn: () => factCheck(caption || post.caption || ""),
    onMutate: () => {
      setFactResult(null);
      setFactOpen(true);
    },
    onSuccess: (result) => setFactResult(result),
    onError: () => toast("Jasper couldn't fact-check that right now"),
  });

  const handleShare = (): void => {
    setShareBump((v) => v + 1);
    setShareOpen(true);
  };

  const handleCopyLink = (): void => {
    // Public /p/ route on the canonical domain so the link works for
    // recipients who aren't signed in (and never leaks a preview URL).
    void navigator.clipboard.writeText(siteUrl(`/p/${username}`));
    toast("Link copied");
  };

  const comments = commentsQuery.data ?? [];
  const commentCount = (post.comments_count ?? 0) + comments.length;

  // Profile pictures for everyone in the thread so comment avatars load.
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
    queryKey: ["comment-profiles", post.id, commentUsernames],
    queryFn: () => fetchProfilesByUsernames(commentUsernames),
    enabled: showComments && commentUsernames.length > 0,
  });
  const commentProfiles = commentProfilesQuery.data ?? {};
  const avatarFor = (username: string): string | null =>
    commentProfiles[username.toLowerCase()]?.profile_image_url ?? null;

  /** Build a 2-level thread: top-level comments each with their replies. */
  const commentTree = useMemo(() => {
    const tops = comments.filter((c) => !c.parent_comment_id);
    const repliesByParent = new Map<string, WhisperComment[]>();
    for (const c of comments) {
      if (!c.parent_comment_id) continue;
      const list = repliesByParent.get(c.parent_comment_id) ?? [];
      list.push(c);
      repliesByParent.set(c.parent_comment_id, list);
    }
    return tops.map((comment) => ({
      comment,
      replies: repliesByParent.get(comment.id) ?? [],
    }));
  }, [comments]);

  if (deleted) return null;

  return (
    <article className="animate-rise border-b border-border px-4 py-3">
      <div className="flex gap-3">
        {/* Avatar column with the Threads thread rail (36px avatar, kit size) */}
        <div className="flex w-9 flex-col items-center">
          {hasStory ? (
            <button
              onClick={() => setStoryViewerOpen(true)}
              aria-label={`View ${username}'s story`}
              className={cn(
                "rounded-full p-[2.5px] transition-transform active:scale-95",
                hasUnseenStory ? WHISPER_STORY_RING_TW : "bg-border"
              )}
            >
              <span className="block rounded-full bg-background p-[2px]">
                <Avatar
                  url={author?.profile_image_url}
                  name={username}
                  size={28}
                />
              </span>
            </button>
          ) : (
            <Link to={`/u/${username}`}>
              <Avatar url={author?.profile_image_url} name={username} size={36} />
            </Link>
          )}
          {showComments && comments.length > 0 && (
            <div className="mt-1.5 w-0.5 flex-1 rounded-full bg-foreground/15" />
          )}
        </div>

        {/* Content column */}
        <div className="min-w-0 flex-1">
          {pinned && (
            <div className="mb-1 flex items-center gap-1.5 text-xs font-semibold text-muted-foreground">
              <Pin className="h-3.5 w-3.5" />
              Pinned
            </div>
          )}
          <header className="flex items-center gap-1.5">
            {/* Threads grammar: username (no display name) 15/600 on the left… */}
            <Link
              to={`/u/${username}`}
              className="truncate text-[15px] font-semibold hover:underline"
            >
              {username}
            </Link>
            <UserBadges profile={author} liar={liar} size={14} />
            {post.community_id && (
              /* iOS grammar: `username › ⬡ Community` — chevron + dot-cluster
                 glyph + the name in semibold ink, tap opens the hub. */
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
            {/* …time · 12 gray grouped with ⋯ on the right (Threads header). */}
            <span className="ml-auto shrink-0 text-[12px] text-muted-foreground">
              {timeAgo(post.created_at)}
            </span>
            <DropdownMenu>
              <DropdownMenuTrigger className="-mr-1 rounded-full p-1 text-muted-foreground outline-none transition-colors hover:bg-secondary">
                <MoreHorizontal className="h-5 w-5" />
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-52">
                <DropdownMenuItem onClick={() => bookmarkMutation.mutate()}>
                  <Bookmark
                    className={cn("mr-2 h-4 w-4", optimisticSaved && "fill-foreground")}
                  />
                  {optimisticSaved ? "Unsave" : "Save"}
                </DropdownMenuItem>
                <DropdownMenuItem onClick={handleCopyLink}>
                  <Link2 className="mr-2 h-4 w-4" />
                  Copy link
                </DropdownMenuItem>
                {EMBER_ENABLED && (
                  <DropdownMenuItem onClick={() => factMutation.mutate()}>
                    <BadgeCheck className="mr-2 h-4 w-4" />
                    AI analysis · not moderation
                  </DropdownMenuItem>
                )}
                {canPin && (
                  <DropdownMenuItem onClick={() => pinMutation.mutate()}>
                    {isPinned ? (
                      <PinOff className="mr-2 h-4 w-4" />
                    ) : (
                      <Pin className="mr-2 h-4 w-4" />
                    )}
                    {isPinned ? "Unpin from profile" : "Pin to profile"}
                  </DropdownMenuItem>
                )}
                {isMyPost && (
                  <DropdownMenuItem onClick={() => setInsightsOpen(true)}>
                    <BarChart3 className="mr-2 h-4 w-4" />
                    View insights
                  </DropdownMenuItem>
                )}
                <DropdownMenuSeparator />
                {isMyPost ? (
                  <DropdownMenuItem
                    onClick={() => setConfirmDelete(true)}
                    className="text-destructive focus:text-destructive"
                  >
                    <Trash2 className="mr-2 h-4 w-4" />
                    Delete
                  </DropdownMenuItem>
                ) : (
                  <DropdownMenuItem
                    onClick={() => setReportOpen(true)}
                    className="text-destructive focus:text-destructive"
                  >
                    <Flag className="mr-2 h-4 w-4" />
                    Report
                  </DropdownMenuItem>
                )}
              </DropdownMenuContent>
            </DropdownMenu>
          </header>

          {caption && (
            <>
              <MentionText
                text={caption}
                className={cn(
                  "mt-0.5 block text-[15px] leading-snug",
                  caption.length > 420 &&
                    !captionExpanded &&
                    "line-clamp-[8]"
                )}
              />
              {caption.length > 420 && (
                <button
                  onClick={() => setCaptionExpanded((v) => !v)}
                  className="mt-0.5 text-[13px] font-medium text-muted-foreground transition-colors hover:text-foreground"
                >
                  {captionExpanded ? "Show less" : "Show more"}
                </button>
              )}
            </>
          )}

          {quoted && quoted.postID !== post.id && <QuotedPostCard payload={quoted} depth={quoteDepth} />}

          {filmEmbed && (
            <div className="mt-2">
              <FilmEmbedCard payload={filmEmbed} />
            </div>
          )}
          {articleEmbed && (
            <div className="mt-2">
              <ArticleEmbedCard payload={articleEmbed} />
            </div>
          )}

          {workout && (
            <WorkoutCard
              payload={workout}
              accentHex={post.accent_hex}
              author={author}
              authorUsername={username}
            />
          )}

          {meta && <PostMetaView postId={post.id} meta={meta} />}

          {media.length > 0 && (
            <div className="relative">
              <PostMedia urls={media} onDoubleTap={handleDoubleTapLike} />
              {heartBurst > 0 && (
                <span
                  key={heartBurst}
                  className="animate-heart-burst pointer-events-none absolute inset-0 flex items-center justify-center"
                >
                  {specialReact ? (
                    <span className="text-7xl drop-shadow-lg">{specialReact}</span>
                  ) : (
                    <Heart className="h-24 w-24 fill-white text-white drop-shadow-lg" />
                  )}
                </span>
              )}
            </div>
          )}

          <PostCorrectionNotice postID={post.id} />

          {/* Threads-style action row */}
          <div className="mt-1.5 flex items-center gap-3">
            <ActionButton
              icon={
                optimisticLiked && specialReact ? (
                  <span className="text-[19px] leading-none">{specialReact}</span>
                ) : (
                  <Heart
                    className={cn("h-[22px] w-[22px]", optimisticLiked && "fill-like")}
                  />
                )
              }
              count={likeCount}
              active={optimisticLiked}
              activeClass="text-like"
              bump={likeBump}
              onClick={() => likeMutation.mutate()}
            />
            <ActionButton
              icon={<MessageCircle className="h-[22px] w-[22px]" />}
              count={commentCount}
              onClick={() => setShowComments((v) => !v)}
            />
            <ActionButton
              icon={<Repeat2 className="h-[22px] w-[22px]" />}
              count={liveRepostCount}
              active={optimisticReposted}
              activeClass="text-repost"
              bump={repostBump}
              anim="spin"
              onClick={() => setRepostMenuOpen(true)}
            />
            <ActionButton
              icon={<Send className="h-[20px] w-[20px]" />}
              count={0}
              bump={shareBump}
              anim="fly"
              onClick={handleShare}
            />
          </div>

          <SharePostDialog
            open={shareOpen}
            onOpenChange={setShareOpen}
            post={post}
            authorUsername={username}
          />

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

          {/* Inline threaded comments */}
          {showComments && (
            <div className="mt-2">
              {commentsQuery.isLoading && (
                <p className="py-3 text-sm text-muted-foreground">
                  Loading comments…
                </p>
              )}

              {commentTree.map(({ comment, replies }, i) => (
                <div key={comment.id}>
                  <CommentRow
                    comment={comment}
                    hasThread={replies.length > 0}
                    authorUrl={avatarFor(comment.username)}
                    onReply={(c) => setReplyTo(c)}
                  />
                  {replies.length > 0 && (
                    <div className="pl-[42px]">
                      {replies.map((r) => (
                        <CommentRow
                          key={r.id}
                          comment={r}
                          isReply
                          authorUrl={avatarFor(r.username)}
                          onReply={() => setReplyTo(comment)}
                        />
                      ))}
                    </div>
                  )}
                  {i < commentTree.length - 1 && (
                    <div className="h-px bg-border/50" />
                  )}
                </div>
              ))}

              {commentAd && comments.length > 0 && (
                <SponsoredCommentRow ad={commentAd} />
              )}

              {!commentsQuery.isLoading && comments.length === 0 && (
                <p className="py-3 text-sm text-muted-foreground">
                  Be the first to comment.
                </p>
              )}

              {replyTo && (
                <div className="mt-1 flex items-center gap-2 rounded-full bg-secondary px-3 py-1.5 text-xs text-muted-foreground">
                  <span className="truncate">
                    Replying to{" "}
                    <span className="font-semibold text-foreground">
                      @{replyTo.username}
                    </span>
                  </span>
                  <button
                    onClick={() => setReplyTo(null)}
                    className="ml-auto font-semibold text-foreground"
                  >
                    Cancel
                  </button>
                </div>
              )}

              <form
                onSubmit={(e) => {
                  e.preventDefault();
                  const body = draft.trim();
                  if (body) commentMutation.mutate(body);
                }}
                className="mt-1 flex items-center gap-2 py-3"
              >
                <Avatar
                  url={profile?.profile_image_url}
                  name={profile?.username ?? "you"}
                  size={28}
                />
                <input
                  value={draft}
                  onChange={(e) => setDraft(e.target.value)}
                  placeholder={
                    replyTo ? `Reply to @${replyTo.username}…` : "Add a comment…"
                  }
                  className="flex-1 rounded-full border border-border bg-card px-4 py-2 text-sm outline-none focus:border-foreground/40"
                />
                <button
                  type="submit"
                  disabled={!draft.trim() || commentMutation.isPending}
                  className="text-sm font-semibold text-foreground disabled:opacity-40"
                >
                  Post
                </button>
              </form>
            </div>
          )}
        </div>
      </div>

      <AlertDialog open={confirmDelete} onOpenChange={setConfirmDelete}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete this post?</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently remove your post for everyone. This can't be
              undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => deleteMutation.mutate()}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <AlertDialog
        open={reportOpen}
        onOpenChange={(o) => {
          setReportOpen(o);
          if (!o) {
            setReportReason(null);
            setReportDetails("");
            setReportDone(false);
          }
        }}
      >
        <AlertDialogContent>
          {reportDone ? (
            <div className="flex flex-col items-center gap-3 py-4 text-center">
              <BadgeCheck className="h-12 w-12 text-foreground" />
              <AlertDialogTitle>Thanks for letting us know</AlertDialogTitle>
              <AlertDialogDescription>
                Your report was received for review. Review times vary.
              </AlertDialogDescription>
            </div>
          ) : (
            <>
              <AlertDialogHeader>
                <AlertDialogTitle>What's wrong with this post?</AlertDialogTitle>
                <AlertDialogDescription>
                  Your report is private to you and authorized reviewers, not anonymous
                  to the moderation team. Add context or source links to help review.
                </AlertDialogDescription>
              </AlertDialogHeader>
              <div className="flex max-h-[40vh] flex-col gap-1 overflow-y-auto">
                {REPORT_REASONS.map((reason) => (
                  <button
                    key={reason.id}
                    onClick={() => setReportReason(reason.id)}
                    className={cn(
                      "flex items-center justify-between rounded-xl border px-4 py-2.5 text-left text-sm font-medium transition-colors",
                      reportReason === reason.id
                        ? "border-foreground bg-secondary"
                        : "border-border hover:bg-secondary/60"
                    )}
                  >
                    {reason.label}
                    {reportReason === reason.id && (
                      <CheckCircle2 className="h-4 w-4" />
                    )}
                  </button>
                ))}
              </div>
              {reportReason && (
                <textarea
                  value={reportDetails}
                  onChange={(e) => setReportDetails(e.target.value)}
                  placeholder="Add context (optional)"
                  rows={3}
                  className="w-full resize-none rounded-xl border border-border bg-card px-3 py-2 text-sm outline-none focus:border-foreground/40"
                />
              )}
              <AlertDialogFooter>
                <AlertDialogCancel>Cancel</AlertDialogCancel>
                <AlertDialogAction
                  onClick={(e) => {
                    e.preventDefault();
                    reportMutation.mutate();
                  }}
                  disabled={!reportReason || reportMutation.isPending}
                >
                  {reportMutation.isPending ? "Submitting…" : "Submit report"}
                </AlertDialogAction>
              </AlertDialogFooter>
            </>
          )}
        </AlertDialogContent>
      </AlertDialog>

      <AlertDialog open={factOpen} onOpenChange={setFactOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle className="flex items-center gap-2">
              <BadgeCheck className="h-5 w-5 text-[#f4511e]" />
              Ember fact-check
            </AlertDialogTitle>
            <AlertDialogDescription className="line-clamp-2 italic">
              “{caption || post.caption}”
            </AlertDialogDescription>
          </AlertDialogHeader>
          {!factResult ? (
            <div className="flex items-center gap-2 py-6 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" />
              Jasper is checking the research…
            </div>
          ) : (
            <div className="space-y-3">
              <span
                className="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-sm font-bold"
                style={{
                  color: VERDICT_META[factResult.verdict].color,
                  background: VERDICT_META[factResult.verdict].bg,
                }}
              >
                {VERDICT_META[factResult.verdict].icon}
                {VERDICT_META[factResult.verdict].label}
              </span>
              {factResult.summary && (
                <p className="text-sm font-semibold">{factResult.summary}</p>
              )}
              {factResult.explanation && (
                <p className="text-sm leading-relaxed text-muted-foreground">
                  {factResult.explanation}
                </p>
              )}
              {factResult.sources.length > 0 && (
                <div className="space-y-1 border-t border-border/60 pt-2">
                  {factResult.sources.map((s) => (
                    <a
                      key={s}
                      href={s}
                      target="_blank"
                      rel="noreferrer"
                      className="block truncate text-xs font-medium text-[#f4511e] hover:underline"
                    >
                      {s}
                    </a>
                  ))}
                </div>
              )}
            </div>
          )}
          <AlertDialogFooter>
            <AlertDialogCancel>Done</AlertDialogCancel>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <AlertDialog open={insightsOpen} onOpenChange={setInsightsOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Post insights</AlertDialogTitle>
            <AlertDialogDescription>
              How this post is performing.
            </AlertDialogDescription>
          </AlertDialogHeader>
          {insightsOpen && isMyPost && user && <PostInsightMetrics key={`${user.id}:${post.id}`} postID={post.id} accountID={user.id} />}
          <AlertDialogFooter>
            <AlertDialogCancel>Done</AlertDialogCancel>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

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

const VERDICT_META: Record<
  Verdict,
  { label: string; icon: React.ReactNode; color: string; bg: string }
> = {
  true: {
    label: "True",
    icon: <CheckCircle2 className="h-4 w-4" />,
    color: "#22c55e",
    bg: "rgba(34,197,94,0.14)",
  },
  mostly_true: {
    label: "Mostly true",
    icon: <ShieldCheck className="h-4 w-4" />,
    color: "#10b981",
    bg: "rgba(16,185,129,0.14)",
  },
  misleading: {
    label: "Misleading",
    icon: <AlertTriangle className="h-4 w-4" />,
    color: "#f59e0b",
    bg: "rgba(245,158,11,0.14)",
  },
  false: {
    label: "False",
    icon: <XCircle className="h-4 w-4" />,
    color: "#ef4444",
    bg: "rgba(239,68,68,0.14)",
  },
  unverified: {
    label: "Unverified",
    icon: <HelpCircle className="h-4 w-4" />,
    color: "#94a3b8",
    bg: "rgba(148,163,184,0.16)",
  },
};

const REPORT_REASONS: { id: string; label: string }[] = [
  { id: "spam", label: "Spam or misleading" },
  { id: "harassment", label: "Harassment or bullying" },
  { id: "hate", label: "Hate speech or symbols" },
  { id: "sexual", label: "Nudity or sexual content" },
  { id: "violence", label: "Violence or threats" },
  { id: "selfHarm", label: "Self-harm or suicide" },
  { id: "minorSafety", label: "Endangering a minor" },
  { id: "impersonation", label: "Impersonation" },
  { id: "scam", label: "Scam or fraud" },
  { id: "misinformation", label: "False information" },
  { id: "other", label: "Something else" },
];

export const PostCard = memo(PostCardBase);
