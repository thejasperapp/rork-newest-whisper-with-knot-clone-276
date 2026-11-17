import { useMemo, useState } from "react";
import { ProfileCover } from "@/components/ProfileCover";
import { useNavigate } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  MessageCircle,
  Lock,
  Dumbbell,
  BadgeCheck,
  CalendarCheck,
  Sparkles,
  ArrowLeft,
  Menu,
  Plus,
  UserPlus,
  Play,
  X,
  Share2,
  Link2,
  Search,
  Send,
  MoreHorizontal,
  PenLine,
  BarChart3,
  LineChart,
  Briefcase,
} from "lucide-react";
import { toast } from "sonner";

import { Avatar } from "@/components/Avatar";
import { AvatarLightbox } from "@/components/AvatarLightbox";
import { AccountSwitcherMenu } from "@/components/AccountSwitcherMenu";
import {
  insightsDoor,
  insightsDoorLabel,
  insightsDoorPath,
} from "@/lib/accountAccess";
import { HighlightsRow } from "@/components/HighlightsRow";
import { PostCard } from "@/components/PostCard";
import { GridPostCard } from "@/components/GridPostCard";
import { UserBadges } from "@/components/UserBadges";
import { ProfileBadgeRow } from "@/components/ProfileBadgeRow";
import { ThoughtBubble } from "@/components/ThoughtBubble";
import { ThoughtComposer } from "@/components/ThoughtComposer";
import { ThoughtRepliesSheet } from "@/components/ThoughtRepliesSheet";
import { EmbeddedCheckoutSheet } from "@/components/EmbeddedCheckoutSheet";
import { ThoughtRepliesBubble } from "@/components/ThoughtRepliesBubble";
import { fetchMyThought, isThoughtActive } from "@/lib/thoughts";
import { snapshotFromThought } from "@/lib/thoughtReplies";
import {
  FollowListDialog,
  type FollowTab,
} from "@/components/FollowListDialog";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  outgoingCoachStatus,
  requestCoach,
  type CoachRequestStatus,
} from "@/lib/coach";
import {
  fetchCoachRate,
  fetchHireStatus,
  formatCents,
  startEmbeddedHireCheckout,
} from "@/lib/coachPay";
import { fetchFeaturedProfileByUsername } from "@/lib/featured";
import { cn } from "@/lib/utils";
import { compactCount } from "@/lib/format";
import {
  fetchProfileBanner,
  fetchFollowCounts,
  fetchFollowers,
  fetchLiarBadges,
  fetchMyBookmarkIds,
  fetchMyLikedPostIds,
  fetchMyRepostIds,
  fetchPinnedPostIds,
  fetchPostsByUser,
  fetchRepostedPostsByUser,
  isFollowing,
  toggleFollow,
  hasPendingFollowRequest,
  createFollowRequest,
  cancelFollowRequest,
  fetchConversations,
  searchProfiles,
  sendMessage,
} from "@/lib/api";
import { useAuth } from "@/hooks/useAuth";
import type { WhisperProfile, WhisperPost } from "@/lib/types";
import { encodeSharedProfile } from "@/lib/profileShare";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

interface ProfileViewProps {
  profile: WhisperProfile;
  isMe: boolean;
  onEdit?: () => void;
}

type Tab = "whispers" | "waves" | "replies" | "media" | "reposts";

/**
 * The profile's content tabs — the EXACT iOS structure and naming: Whisps ·
 * WAVES (the 9:16 grid — the ONLY place waves render on a profile) ·
 * Replies · Reposts · Media. Text labels with an ink underline, like the
 * iPhone app; grid posts live in Whisps (as cards) and in the Media grid.
 */
const TABS: { id: Tab; label: string }[] = [
  { id: "whispers", label: "Whisps" },
  { id: "waves", label: "Waves" },
  { id: "replies", label: "Replies" },
  { id: "reposts", label: "Reposts" },
  { id: "media", label: "Media" },
];

/** Instagram-exact empty state — stroked icon circle, bold title, quiet sub,
 *  and the IG-blue action link (own profile only). */
function ProfileEmptyState({
  icon,
  title,
  sub,
  actionLabel,
  onAction,
}: {
  icon: React.ReactNode;
  title: string;
  sub?: string;
  actionLabel?: string;
  onAction?: () => void;
}) {
  return (
    <div className="flex flex-col items-center px-6 py-14 text-center">
      <div className="flex h-[62px] w-[62px] items-center justify-center rounded-full border-2 border-foreground text-foreground">
        {icon}
      </div>
      <p className="mt-4 text-[22px] font-extrabold leading-tight">{title}</p>
      {sub && (
        <p className="mt-1.5 max-w-[280px] text-[14px] leading-snug text-muted-foreground">
          {sub}
        </p>
      )}
      {actionLabel && onAction && (
        <button
          onClick={onAction}
          className="mt-3 text-[14px] font-semibold text-[#0095F6] transition-opacity hover:opacity-70"
        >
          {actionLabel}
        </button>
      )}
    </div>
  );
}

export function ProfileView({ profile, isMe, onEdit }: ProfileViewProps) {
  const { user } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [tab, setTab] = useState<Tab>("whispers");
  const [followDialog, setFollowDialog] = useState<FollowTab | null>(null);
  const [thinking, setThinking] = useState<boolean>(false);
  const [repliesOpen, setRepliesOpen] = useState<boolean>(false);
  /** The full-screen zoom stage for the profile picture. */
  const [avatarZoom, setAvatarZoom] = useState<boolean>(false);
  const [selectedGridPost, setSelectedGridPost] = useState<WhisperPost | null>(null);
  const [bioExpanded, setBioExpanded] = useState<boolean>(false);

  // The user's IG-Notes "What's on your mind?" note, shown above the avatar
  // exactly like the iOS profile. Tappable to compose/edit when it's mine.
  const thoughtQuery = useQuery({
    queryKey: ["my-thought", profile.user_id],
    queryFn: () => fetchMyThought(profile.user_id),
  });
  const thought = thoughtQuery.data ?? null;
  const noteActive = isThoughtActive(thought);

  const postsQuery = useQuery({
    queryKey: ["user-posts", profile.user_id],
    queryFn: () => fetchPostsByUser(profile.user_id),
  });
  const pinnedQuery = useQuery({
    queryKey: ["pinned-posts", profile.user_id],
    queryFn: () => fetchPinnedPostIds(profile.user_id),
  });
  const repostsPostsQuery = useQuery({
    queryKey: ["user-reposts", profile.user_id],
    queryFn: () => fetchRepostedPostsByUser(profile.user_id),
    enabled: tab === "reposts",
  });
  const countsQuery = useQuery({
    queryKey: ["follow-counts", profile.user_id],
    queryFn: () => fetchFollowCounts(profile.user_id),
  });
  // Kit 4.0 "Followed by …" facepile on other people's profiles — shares the
  // followers dialog's cache key so opening the list is instant.
  const followersPreviewQuery = useQuery({
    queryKey: ["followers", profile.user_id],
    queryFn: () => fetchFollowers(profile.user_id),
    enabled: !isMe,
    staleTime: 5 * 60 * 1000,
  });
  const followersPreview = followersPreviewQuery.data ?? [];
  const followingQuery = useQuery({
    queryKey: ["is-following", user?.id, profile.user_id],
    queryFn: () => isFollowing(user!.id, profile.user_id),
    enabled: !!user && !isMe,
  });
  const liarQuery = useQuery({
    queryKey: ["liar-badges", [profile.username]],
    queryFn: () => fetchLiarBadges([profile.username]),
  });
  const liar = liarQuery.data?.[profile.username.toLowerCase()] ?? null;

  // Reuse the viewer's interaction sets so post cards stay in sync with feed.
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

  const [optimisticFollow, setOptimisticFollow] = useState<boolean | null>(null);
  const following = optimisticFollow ?? followingQuery.data ?? false;

  // Private accounts get a request queue instead of an instant follow —
  // mirrors the iOS "Requested" flow.
  const isPrivate = !!profile.is_private;
  const requestQuery = useQuery({
    queryKey: ["follow-request", user?.id, profile.user_id],
    queryFn: () => hasPendingFollowRequest(user!.id, profile.user_id),
    enabled: !!user && !isMe && isPrivate,
  });
  const [optimisticRequested, setOptimisticRequested] = useState<
    boolean | null
  >(null);
  const requested = optimisticRequested ?? requestQuery.data ?? false;

  const bannerQuery = useQuery({ queryKey: ["profile-banner", profile.user_id], queryFn: () => fetchProfileBanner(profile.user_id) });
  const isCoach = !!profile.is_coach;
  // The grid COMPOSER + Grid tab are a verified-creator perk (one matrix,
  // `accountAccess`, mirrors iOS). The Media grid itself is for everyone.
  // The insights door top-left: Analytics (professional / One), Creator
  // Studio (verified), the Business Suite (business type) — nothing for
  // personal accounts. Never Creator Studio for a self-selected type.
  const door = isMe ? insightsDoor(profile) : null;

  // Kit 4.0 bio block — the professional category line, a clamped bio with
  // "more", and the first URL lifted out of the bio into its own link row.
  const professionalCategory = (profile.professional_category ?? "").trim();
  const bioRaw = profile.bio ?? "";
  const bioUrlMatch = bioRaw.match(/https?:\/\/\S+|www\.\S+/i);
  const bioUrl = bioUrlMatch?.[0] ?? null;
  // Kit grammar: extra bio links collapse into "and N more".
  const bioExtraLinks = Math.max(
    0,
    (bioRaw.match(/https?:\/\/\S+|www\.\S+/gi) ?? []).length - 1
  );
  const bioSansUrl = bioUrl
    ? bioRaw.replace(bioUrl, "").replace(/[ \t]{2,}/g, " ").trim()
    : bioRaw;
  const bioIsLong =
    bioSansUrl.length > 140 || bioSansUrl.split("\n").length > 2;
  const bioHref = bioUrl
    ? bioUrl.startsWith("http")
      ? bioUrl
      : `https://${bioUrl}`
    : null;
  const bioLinkLabel = bioUrl
    ? bioUrl
        .replace(/^https?:\/\//i, "")
        .replace(/^www\./i, "")
        .replace(/\/$/, "")
    : null;
  const [coachOpen, setCoachOpen] = useState<boolean>(false);
  const [coachMessage, setCoachMessage] = useState<string>("");
  const [embeddedCheckout, setEmbeddedCheckout] = useState<
    { clientSecret: string; publishableKey: string } | null
  >(null);
  const coachStatusQuery = useQuery({
    queryKey: ["coach-status", user?.id, profile.user_id],
    queryFn: () => outgoingCoachStatus(user!.id, profile.user_id),
    enabled: !!user && !isMe && isCoach,
  });
  const coachStatus: CoachRequestStatus | null = coachStatusQuery.data ?? null;
  // Payment standing with this coach — only checked once they've accepted.
  const hireStatusQuery = useQuery({
    queryKey: ["hire-status", user?.id, profile.user_id],
    queryFn: () => fetchHireStatus(profile.user_id),
    enabled: !!user && !isMe && isCoach && coachStatus === "accepted",
    retry: false,
  });
  const hireStatus = hireStatusQuery.data ?? null;
  const owesPayment =
    coachStatus === "accepted" &&
    !!hireStatus?.requiresPayment &&
    !hireStatus.paid;
  // Coach preview data for the application sheet — their public rate card
  // plus the admin-curated spotlight (if this coach is featured on the site).
  const coachRateQuery = useQuery({
    queryKey: ["coach-rate", profile.user_id],
    queryFn: () => fetchCoachRate(profile.user_id),
    enabled: !!user && !isMe && isCoach && coachOpen,
    retry: false,
  });
  const coachRate = coachRateQuery.data ?? null;
  const spotlightQuery = useQuery({
    queryKey: ["featured-by-username", profile.username],
    queryFn: () => fetchFeaturedProfileByUsername(profile.username),
    enabled: !!user && !isMe && isCoach && coachOpen,
    retry: false,
  });
  const spotlight = spotlightQuery.data ?? null;

  // Coaches who charge get a pay-to-apply flow: the application is saved,
  // then the client goes straight into checkout. Payment auto-accepts the
  // relationship (handled by the backend webhook), so coaches never review
  // dead leads.
  const coachCharges = Boolean(
    coachRate?.active && coachRate.acceptingPayments && coachRate.monthlyPriceCents
  );
  const requestCoachMutation = useMutation({
    mutationFn: async () => {
      await requestCoach({
        clientUserId: user!.id,
        clientUsername:
          (user?.user_metadata?.username as string | undefined) ??
          profile.username ??
          "client",
        coachUserId: profile.user_id,
        coachUsername: profile.username,
        message: coachMessage.trim(),
      });
      if (coachCharges) {
        // Embedded checkout — renders inline, no redirect.
        const result = await startEmbeddedHireCheckout({
          coachUserId: profile.user_id,
          userId: user!.id,
          email: user?.email ?? "",
          cancelPath: `/u/${profile.username}`,
        });
        setEmbeddedCheckout(result);
        return "paying" as const;
      }
      return "sent" as const;
    },
    onSuccess: (result) => {
      if (result === "sent") {
        toast(`Request sent to @${profile.username}`);
      }
      setCoachOpen(false);
      setCoachMessage("");
      queryClient.invalidateQueries({
        queryKey: ["coach-status", user?.id, profile.user_id],
      });
    },
    onError: (err) =>
      toast(err instanceof Error ? err.message : "Couldn't send request"),
  });

  const followMutation = useMutation({
    mutationFn: async () => {
      // Private target + not yet following → queue/cancel a follow request
      // instead of writing the follow row directly.
      if (isPrivate && !following) {
        if (requested) {
          await cancelFollowRequest(user!.id, profile.user_id);
        } else {
          await createFollowRequest({
            requesterId: user!.id,
            requesterUsername:
              (user?.user_metadata?.username as string | undefined) ?? "user",
            targetId: profile.user_id,
            targetUsername: profile.username,
          });
        }
        return;
      }
      await toggleFollow(user!.id, profile.user_id, profile.username, following);
    },
    onMutate: () => {
      if (isPrivate && !following) {
        setOptimisticRequested(!requested);
      } else {
        setOptimisticFollow(!following);
      }
    },
    onError: () => {
      setOptimisticRequested(null);
      setOptimisticFollow(null);
    },
    onSettled: () => {
      queryClient.invalidateQueries({
        queryKey: ["follow-counts", profile.user_id],
      });
      queryClient.invalidateQueries({
        queryKey: ["is-following", user?.id, profile.user_id],
      });
      queryClient.invalidateQueries({
        queryKey: ["follow-request", user?.id, profile.user_id],
      });
    },
  });

  // Waves render ONLY on the Waves tab — everything else excludes them.
  const rawPosts = useMemo(
    () => (postsQuery.data ?? []).filter((p) => p.is_reel !== true),
    [postsQuery.data]
  );
  const wavePosts = useMemo(
    () => (postsQuery.data ?? []).filter((p) => p.is_reel === true),
    [postsQuery.data]
  );
  // Float pinned posts to the top in their saved order (matches iOS).
  const pinnedIds = useMemo(
    () => pinnedQuery.data ?? [],
    [pinnedQuery.data]
  );
  const pinnedSet = useMemo(() => new Set(pinnedIds), [pinnedIds]);
  const posts = useMemo(() => {
    if (pinnedIds.length === 0) return rawPosts;
    const order = new Map(pinnedIds.map((id, i) => [id, i]));
    const pinned = rawPosts
      .filter((p) => pinnedSet.has(p.id))
      .sort((a, b) => (order.get(a.id) ?? 0) - (order.get(b.id) ?? 0));
    const rest = rawPosts.filter((p) => !pinnedSet.has(p.id));
    return [...pinned, ...rest];
  }, [rawPosts, pinnedIds, pinnedSet]);
  const mediaPosts = useMemo(
    () => posts.filter((p) => (p.media_urls ?? []).length > 0),
    [posts]
  );
  const repostedPosts = repostsPostsQuery.data ?? [];
  const counts = countsQuery.data ?? { followers: 0, following: 0 };
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

  const displayName = profile.display_name || profile.username;

  /** Copies the public profile link to clipboard. */
  const handleCopyProfileLink = async (): Promise<void> => {
    const url = `https://www.mydailywhisper.com/p/${profile.username}`;
    try {
      await navigator.clipboard.writeText(url);
      toast("Profile link copied");
    } catch {
      toast("Couldn't copy link");
    }
  };

  /** Shares the profile via the Web Share API (mobile) or copies the link. */
  const handleShareProfile = async (): Promise<void> => {
    const url = `https://www.mydailywhisper.com/p/${profile.username}`;
    try {
      if (navigator.share) {
        await navigator.share({ title: `@${profile.username} on Whisper`, url });
        return;
      }
      await navigator.clipboard.writeText(url);
      toast("Profile link copied");
    } catch {
      // user dismissed the share sheet — nothing to do
    }
  };

  /** Shares the profile to a DM — encodes a rich profile embed card. */
  const [shareProfileOpen, setShareProfileOpen] = useState<boolean>(false);
  const handleShareProfileViaDM = (): void => {
    setShareProfileOpen(true);
  };

  const profileShareEmbed = encodeSharedProfile({
    username: profile.username,
    displayName: profile.display_name,
    bio: profile.bio,
    avatarUrl: profile.profile_image_url,
    isVerified: !!profile.is_verified,
    isCoach: !!profile.is_coach,
    isAthlete: !!profile.is_athlete,
    isRecruiter: !!profile.is_recruiter,
  });

  return (
    <div className="web-profile">
      {/* Account navigation remains available independently of the profile header. */}
      <div className="profile-toolbar sticky top-0 z-30 flex h-14 items-center border-b border-border bg-background/95 px-2 backdrop-blur-sm">
        {isMe ? (
          <div className="flex items-center">
            {door && (
              <button
                onClick={() => navigate(insightsDoorPath(door))}
                aria-label={insightsDoorLabel(door)}
                title={insightsDoorLabel(door)}
                className="flex h-10 w-10 items-center justify-center transition-transform active:scale-90"
              >
                {door === "creatorStudio" ? (
                  <LineChart className="h-6 w-6" strokeWidth={2.2} />
                ) : door === "businessSuite" ? (
                  <Briefcase className="h-6 w-6" strokeWidth={2.2} />
                ) : (
                  <BarChart3 className="h-6 w-6" strokeWidth={2.2} />
                )}
              </button>
            )}
            <button
              onClick={() => navigate("/compose")}
              aria-label="New post"
              className="flex h-10 w-10 items-center justify-center transition-transform active:scale-90"
            >
              <Plus className="h-6 w-6" strokeWidth={2.2} />
            </button>
          </div>
        ) : (
          <button
            onClick={() => navigate(-1)}
            aria-label="Back"
            className="flex h-10 w-10 items-center justify-center transition-transform active:scale-90"
          >
            <ArrowLeft className="h-6 w-6" />
          </button>
        )}
        {isMe ? (
          <div className="flex min-w-0 flex-1 items-center justify-center">
            {/* The username is the ACCOUNT SWITCHER (Instagram's chevron). */}
            <AccountSwitcherMenu
              profile={profile}
              className="max-w-full gap-1.5 py-1 text-[16px] font-bold"
            >
              <span className="truncate">{profile.username}</span>
              <UserBadges profile={profile} liar={liar} size={16} />
              {profile.is_private && (
                <Lock className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
              )}
            </AccountSwitcherMenu>
          </div>
        ) : (
          <span className="flex min-w-0 flex-1 items-center justify-center gap-1.5 text-[16px] font-bold">
            <span className="truncate">{profile.username}</span>
            <UserBadges profile={profile} liar={liar} size={16} />
            {profile.is_private && (
              <Lock className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
            )}
          </span>
        )}
        {isMe ? (
          <button
            onClick={() => navigate("/settings")}
            aria-label="Settings menu"
            className="flex h-10 w-10 items-center justify-center transition-transform active:scale-90"
          >
            <Menu className="h-6 w-6" strokeWidth={2.2} />
          </button>
        ) : (
          <span className="w-10" />
        )}
      </div>

      <div className="px-0 pt-0">
        <div className="overflow-hidden bg-background sm:border-x sm:border-border/60">
          {/* Shared native cover and overlapping identity panel, within the desktop rails. */}
          <div className={cn("profile-cover relative overflow-hidden bg-secondary", !bannerQuery.data?.banner_url && "profile-cover-empty")} aria-hidden="true">
            {bannerQuery.data?.banner_url && <ProfileCover src={bannerQuery.data.banner_url} offset={bannerQuery.data.banner_offset_y} />}
          </div>
          {/* The desktop header uses a real horizontal grid, not a stretched phone card. */}
          <div className="profile-header relative bg-background px-4 pb-2 pt-5 sm:px-7">
            <div
              className={cn(
                "profile-identity flex items-center gap-5",
                noteActive || isMe ? "mt-14" : "mt-2"
              )}
            >
              <div className="profile-avatar relative shrink-0">
                {(noteActive || isMe) && (
                  <button
                    onClick={() =>
                      isMe ? setThinking(true) : setRepliesOpen(true)
                    }
                    aria-label={isMe ? "Share a note" : "Reply to note"}
                    className="profile-note absolute left-1/2 -top-1 z-10 -translate-x-1/2 -translate-y-full transition-transform active:scale-95"
                  >
                    <span className="profile-note-label hidden">{noteActive ? thought!.text : "+ Add a note"}</span>
                    <span className="profile-note-art"><ThoughtBubble
                      text={noteActive ? thought!.text : "Note..."}
                      style={noteActive ? thought!.style : "plain"}
                      accent={noteActive ? thought!.accent : ""}
                      emoji={noteActive ? thought!.emoji : ""}
                      colorHex={noteActive ? thought!.color_hex : ""}
                      scale={1.12}
                    /></span>
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => setAvatarZoom(true)}
                  aria-label="View profile picture"
                  className="rounded-full transition-transform active:scale-95"
                >
                  <Avatar
                    url={profile.profile_image_url}
                    name={profile.username}
                    size={84}
                    className="ring-4 ring-background"
                  />
                </button>
                <AvatarLightbox
                  open={avatarZoom}
                  onClose={() => setAvatarZoom(false)}
                  url={profile.profile_image_url}
                  name={profile.username}
                />
                {isMe && (
                  <ThoughtRepliesBubble
                    userId={profile.user_id}
                    onOpen={() => setRepliesOpen(true)}
                    className="profile-note-replies absolute -bottom-1 left-1/2 -translate-x-1/2"
                  />
                )}
              </div>

              <div className="profile-name min-w-0 flex-1">
                <div className="flex items-center gap-1.5">
                  <h2 className="truncate font-display text-[21px] font-bold leading-tight sm:text-[26px]">
                    {displayName}
                  </h2>
                  <ProfileBadgeRow profile={profile} liar={liar} className="profile-roles" />
                </div>

                <p className="mt-1 text-sm text-muted-foreground">@{profile.username}</p>
                <div className="profile-stats mt-3 flex gap-5">
                  <span className="flex-1 text-left">
                    <span className="block text-[17px] font-bold leading-tight tabular-nums">
                      {posts.length}
                    </span>
                    <span className="text-[12px] text-muted-foreground">
                      posts
                    </span>
                  </span>
                  <button
                    onClick={() => setFollowDialog("followers")}
                    className="flex-1 text-left transition-opacity hover:opacity-70"
                  >
                    <span className="block text-[17px] font-bold leading-tight tabular-nums">
                      {compactCount(counts.followers)}
                    </span>
                    <span className="text-[12px] text-muted-foreground">
                      followers
                    </span>
                  </button>
                  <button
                    onClick={() => setFollowDialog("following")}
                    className="flex-1 text-left transition-opacity hover:opacity-70"
                  >
                    <span className="block text-[17px] font-bold leading-tight tabular-nums">
                      {compactCount(counts.following)}
                    </span>
                    <span className="text-[12px] text-muted-foreground">
                      following
                    </span>
                  </button>
                </div>
              </div>
            </div>

            <div className="profile-bio min-w-0">
            {/* Readable profile details sit beside the avatar on desktop. */}
            {/* The creator niche / professional category — Instagram's light-gray
                line under the name ("Athlete", "Digital creator"). */}
            {bioSansUrl && (
              <div className={professionalCategory ? "mt-1" : "mt-3"}>
                <p
                  className={cn(
                    "whitespace-pre-wrap text-[14px] leading-snug text-foreground/90",
                    !bioExpanded && bioIsLong && "line-clamp-2"
                  )}
                >
                  {bioSansUrl}
                </p>
                {bioIsLong && (
                  <button
                    onClick={() => setBioExpanded((v) => !v)}
                    className="text-[14px] font-medium text-muted-foreground transition-opacity hover:opacity-70"
                  >
                    {bioExpanded ? "less" : "more"}
                  </button>
                )}
              </div>
            )}
            {bioHref && bioLinkLabel && (
              <a
                href={bioHref}
                target="_blank"
                rel="noopener noreferrer"
                className="mt-1.5 flex items-center gap-1.5 text-[13px] font-semibold text-foreground"
              >
                <Link2 className="h-3.5 w-3.5 shrink-0" />
                <span className="truncate">
                  {bioLinkLabel}
                  {bioExtraLinks > 0 ? ` and ${bioExtraLinks} more` : ""}
                </span>
              </a>
            )}
            {!isMe && followersPreview.length > 0 && (
              <button
                onClick={() => setFollowDialog("followers")}
                className="mt-2.5 flex items-center gap-2 text-left transition-opacity hover:opacity-80"
              >
                <span className="flex shrink-0 -space-x-1.5">
                  {followersPreview.slice(0, 3).map((f) => (
                    <span
                      key={f.userId}
                      className="rounded-full ring-2 ring-background"
                    >
                      <Avatar
                        name={f.username}
                        url={f.profile?.profile_image_url ?? null}
                        size={18}
                      />
                    </span>
                  ))}
                </span>
                <span className="min-w-0 truncate text-[13px] leading-tight text-foreground/90">
                  Followed by{" "}
                  <span className="font-semibold">
                    {followersPreview[0]?.username}
                  </span>
                  {followersPreview.length > 1 && (
                    <>
                      {" "}and{" "}
                      <span className="font-semibold">
                        {Math.max(
                          counts.followers - 1,
                          followersPreview.length - 1
                        )}{" "}
                        others
                      </span>
                    </>
                  )}
                </span>
              </button>
            )}

            </div>

            {/* The insights row — slim, one line, so the first post stays
                above the fold. Professional (self-selected) accounts get
                ANALYTICS; only VERIFIED creators get Creator Studio; business
                types get their own suite. Personal accounts see nothing. */}
            {isMe && door && (
              <button
                onClick={() => navigate(insightsDoorPath(door))}
                className="profile-dashboard mt-2.5 flex w-full items-center justify-between gap-3 rounded-[10px] bg-secondary/70 px-3.5 py-2 text-left transition-colors hover:bg-secondary"
              >
                <span className="text-[13px] font-semibold leading-tight">
                  {door === "analytics" ? "Analytics" : "Professional dashboard"}
                </span>
                <span className="text-[12px] text-muted-foreground">
                  {door === "analytics"
                    ? "Reach · interactions · followers"
                    : insightsDoorLabel(door)}{" "}
                  ›
                </span>
              </button>
            )}

            {/* Action row — iOS parity: Edit profile / Share profile /
                find-people for me; Follow / Message / find-people otherwise. */}
            <div className="profile-actions mb-3 mt-3 flex items-center gap-2">
              {isMe ? (
                <>
                  <button
                    onClick={onEdit}
                    className="flex-1 rounded-[10px] border border-border bg-card py-2 text-sm font-semibold transition-colors hover:bg-secondary"
                  >
                    Edit profile
                  </button>
                  <DropdownMenu>
                    <DropdownMenuTrigger className="flex-1 rounded-[10px] border border-border bg-card py-2 text-sm font-semibold transition-colors hover:bg-secondary">
                      <span className="flex items-center justify-center gap-1.5">
                        <Share2 className="h-3.5 w-3.5" />
                        Share
                      </span>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="center" className="w-48">
                      <DropdownMenuItem onClick={handleCopyProfileLink}>
                        <Link2 className="mr-2 h-4 w-4" />
                        Copy profile link
                      </DropdownMenuItem>
                      <DropdownMenuItem onClick={handleShareProfile}>
                        <Share2 className="mr-2 h-4 w-4" />
                        Share via…
                      </DropdownMenuItem>
                      <DropdownMenuItem onClick={handleShareProfileViaDM}>
                        <MessageCircle className="mr-2 h-4 w-4" />
                        Send in a DM
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </>
              ) : (
                <>
                  <button
                    onClick={() => followMutation.mutate()}
                    className={cn(
                      "flex-1 rounded-[10px] py-2 text-sm font-semibold transition-colors",
                      following || (isPrivate && requested)
                        ? "border border-border bg-card hover:bg-secondary"
                        : "bg-primary text-primary-foreground hover:opacity-90"
                    )}
                  >
                    {following
                      ? "Following"
                      : isPrivate && requested
                        ? "Requested"
                        : "Follow"}
                  </button>
                  <button
                    onClick={() => navigate("/messages")}
                    className="flex flex-1 items-center justify-center gap-1.5 rounded-[10px] border border-border bg-card py-2 text-sm font-semibold transition-colors hover:bg-secondary"
                  >
                    <MessageCircle className="h-4 w-4" />
                    Message
                  </button>
                </>
              )}
              <button
                onClick={() => navigate("/search")}
                aria-label="Find people"
                className="flex h-[38px] w-[42px] shrink-0 items-center justify-center rounded-[10px] border border-border bg-card transition-colors hover:bg-secondary"
              >
                <UserPlus className="h-4 w-4" />
              </button>
            </div>

            {/* Story highlights — the same albums curated on iOS */}
            <div className="profile-highlights min-w-0"><HighlightsRow userId={profile.user_id} isMe={isMe} /></div>

            {!isMe && isCoach && (
              <div className="profile-coaching pb-4">
                {owesPayment ? (
                  <button
                    onClick={() => navigate(`/hire/${profile.user_id}`)}
                    className="flex w-full items-center justify-center gap-2 rounded-xl bg-orange-500 py-2.5 text-sm font-bold text-white transition-transform hover:bg-orange-500/90 active:scale-[0.98]"
                  >
                    <Dumbbell className="h-4 w-4" />
                    Accepted — complete payment
                    {hireStatus?.priceCents
                      ? ` · ${formatCents(hireStatus.priceCents)}/mo`
                      : ""}
                  </button>
                ) : coachStatus === "accepted" ? (
                  <div className="flex items-center justify-center gap-2 rounded-xl bg-primary/10 py-2.5 text-sm font-semibold text-primary">
                    <Dumbbell className="h-4 w-4" />
                    {profile.username} is your coach
                  </div>
                ) : coachStatus === "pending" ? (
                  <div className="flex items-center justify-center gap-2 rounded-xl border border-border py-2.5 text-sm font-semibold text-muted-foreground">
                    <Dumbbell className="h-4 w-4" />
                    Coaching request pending
                  </div>
                ) : (
                  <button
                    onClick={() => setCoachOpen(true)}
                    className="flex w-full items-center justify-center gap-2 rounded-xl border border-primary/40 bg-primary/5 py-2.5 text-sm font-semibold text-primary transition-colors hover:bg-primary/10"
                  >
                    <Dumbbell className="h-4 w-4" />
                    Request coaching
                  </button>
                )}
              </div>
            )}
          </div>

          {/* Native profile sections in the requested sliding web selector. */}
          <div className="profile-tabs relative mx-3 mb-3 grid grid-cols-5 rounded-full bg-secondary p-1" role="tablist" aria-label="Profile posts">
            <span aria-hidden="true" className="pointer-events-none absolute bottom-1 left-1 top-1 rounded-full bg-background shadow-sm transition-transform duration-200 motion-reduce:transition-none" style={{ width: "calc((100% - 8px) / 5)", transform: `translateX(${TABS.findIndex(t => t.id === tab) * 100}%)` }} />
            {TABS.map((t) => {
              const active = tab === t.id;
              return (
                <button
                  key={t.id}
                  role="tab"
                  aria-selected={active}
                  tabIndex={active ? 0 : -1}
                  onKeyDown={event => {
                    const index = TABS.findIndex(item => item.id === tab);
                    const next = event.key === "ArrowRight" ? (index + 1) % TABS.length : event.key === "ArrowLeft" ? (index + TABS.length - 1) % TABS.length : event.key === "Home" ? 0 : event.key === "End" ? TABS.length - 1 : null;
                    if (next === null) return;
                    event.preventDefault();
                    setTab(TABS[next].id);
                    const siblings = event.currentTarget.parentElement?.querySelectorAll<HTMLButtonElement>('[role="tab"]');
                    siblings?.[next]?.focus();
                  }}
                  onClick={() => setTab(t.id)}
                  className="relative z-10 flex min-h-11 items-center justify-center rounded-full transition-colors"
                >
                  <span
                    className={cn(
                      "text-[12px] font-semibold leading-none tracking-[-0.01em] sm:text-[13.5px]",
                      active ? "text-foreground" : "text-muted-foreground"
                    )}
                  >
                    {t.label}
                  </span>

                </button>
              );
            })}
          </div>

          {/* Text stays at reading width; media uses the full profile canvas. */}
          <div className={cn("profile-content", (tab === "whispers" || tab === "reposts") && "mx-auto max-w-[680px]")}>
            {tab === "whispers" &&
              (posts.length === 0 ? (
                <ProfileEmptyState
                  icon={<PenLine className="h-7 w-7" strokeWidth={1.5} />}
                  title={isMe ? "Share your thoughts" : "No whispers yet"}
                  sub={
                    isMe
                      ? "When you share whispers, they'll appear on your profile."
                      : undefined
                  }
                  actionLabel={isMe ? "Share your first whisper" : undefined}
                  onAction={() => navigate("/compose")}
                />
              ) : (
                posts.map((p) => (
                  <PostCard
                    key={p.id}
                    post={p}
                    author={profile}
                    liked={likedSet.has(p.id)}
                    reposted={repostedSet.has(p.id)}
                    bookmarked={bookmarkedSet.has(p.id)}
                    pinned={pinnedSet.has(p.id)}
                  />
                ))
              ))}

            {/* WAVES — the only place waves render on a profile: 3-column
                9:16 tiles; tap opens the full-screen Waves player on that wave. */}
            {tab === "waves" &&
              (wavePosts.length === 0 ? (
                <ProfileEmptyState
                  icon={<Play className="h-7 w-7" strokeWidth={1.5} />}
                  title={isMe ? "Make a wave" : "No waves yet"}
                  sub={
                    isMe
                      ? "Short videos you post land here, in the Waves format — nowhere else."
                      : undefined
                  }
                  actionLabel={isMe ? "Record your first wave" : undefined}
                  onAction={() => navigate("/reels")}
                />
              ) : (
                <div className="grid grid-cols-3 gap-0.5 p-0.5">
                  {wavePosts.map((p) => {
                    const url = (p.media_urls ?? [])[0];
                    return (
                      <button
                        key={p.id}
                        onClick={() => navigate(`/reels?wave=${p.id}`)}
                        className="relative aspect-[9/16] overflow-hidden bg-black transition-transform active:scale-[0.97]"
                        aria-label="Open wave"
                      >
                        {url && (
                          <video
                            src={url}
                            muted
                            playsInline
                            preload="metadata"
                            className="h-full w-full object-cover"
                          />
                        )}
                        <span className="pointer-events-none absolute inset-x-0 bottom-0 h-12 bg-gradient-to-t from-black/60 to-transparent" />
                        <span className="absolute bottom-1.5 left-1.5 flex items-center gap-1 text-[11px] font-extrabold text-white drop-shadow">
                          <Play className="h-3 w-3 fill-white" />
                          {p.likes_count ?? 0}
                        </span>
                      </button>
                    );
                  })}
                </div>
              ))}

            {tab === "replies" && (
              <p className="px-6 py-16 text-center text-sm text-muted-foreground">
                No replies yet.
              </p>
            )}

            {tab === "media" &&
              (mediaPosts.length === 0 ? (
                <p className="px-6 py-16 text-center text-sm text-muted-foreground">
                  No media yet.
                </p>
              ) : (
                <div className="grid grid-cols-3 gap-0.5 p-0.5">
                  {mediaPosts.map((p) => {
                    const url = p.media_urls?.[0];
                    return (
                      <button
                        key={p.id}
                        type="button"
                        onClick={() => setSelectedGridPost(p)}
                        className="relative aspect-square overflow-hidden bg-secondary transition-transform active:scale-[0.97]"
                        aria-label="Open post"
                      >
                        {url && (/\.(mp4|mov|m4v|webm)(?:[?#]|$)/i.test(url) ? <video src={url} muted playsInline preload="metadata" className="h-full w-full object-cover" /> : <img src={url} alt="" loading="lazy" className="h-full w-full object-cover" />)}
                        {(p.media_urls?.length ?? 0) > 1 && <span className="absolute right-2 top-2 rounded-full bg-black/60 px-2 py-1 text-xs text-white">{p.media_urls!.length}</span>}
                      </button>
                    );
                  })}
                </div>
              ))}

            {tab === "reposts" &&
              (repostsPostsQuery.isLoading ? (
                <p className="px-6 py-16 text-center text-sm text-muted-foreground">
                  Loading reposts…
                </p>
              ) : repostedPosts.length === 0 ? (
                <p className="px-6 py-16 text-center text-sm text-muted-foreground">
                  No reposts yet.
                </p>
              ) : (
                repostedPosts.map((p) => (
                  <PostCard
                    key={p.id}
                    post={p}
                    liked={likedSet.has(p.id)}
                    reposted={repostedSet.has(p.id)}
                    bookmarked={bookmarkedSet.has(p.id)}
                  />
                ))
              ))}
          </div>
        </div>
      </div>

      {isMe && (
        <ThoughtComposer
          open={thinking}
          onOpenChange={setThinking}
          current={thought}
        />
      )}

      {(isMe || noteActive) && (
        <ThoughtRepliesSheet
          open={repliesOpen}
          onOpenChange={setRepliesOpen}
          ownerUserId={profile.user_id}
          ownerUsername={profile.username}
          isOwner={isMe}
          liveThought={noteActive ? snapshotFromThought(thought) : null}
        />
      )}

      {/* Grid post detail modal — opens a feed-style PostCard when a grid cell is tapped */}
      {selectedGridPost && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm"
          onClick={() => setSelectedGridPost(null)}
        >
          <div
            className="max-h-[88vh] w-full max-w-md overflow-y-auto rounded-[22px] bg-background shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between border-b border-border px-4 py-3">
              <button
                onClick={() => setSelectedGridPost(null)}
                className="flex h-8 w-8 items-center justify-center rounded-full transition-colors hover:bg-secondary"
              >
                <X className="h-5 w-5" />
              </button>
              <span className="text-sm font-bold">Post</span>
              <span className="w-8" />
            </div>
            {/* IG grammar: the grid detail shows the REAL photo card —
                full-bleed media, action row, and the inline comments — not a
                thread-style attachment. */}
            <GridPostCard
              post={selectedGridPost}
              author={profile}
              liked={likedSet.has(selectedGridPost.id)}
              reposted={repostedSet.has(selectedGridPost.id)}
              bookmarked={bookmarkedSet.has(selectedGridPost.id)}
            />
          </div>
        </div>
      )}

      <FollowListDialog
        open={followDialog !== null}
        onOpenChange={(o) => !o && setFollowDialog(null)}
        userId={profile.user_id}
        username={profile.username}
        initialTab={followDialog ?? "followers"}
      />

      {/* Share profile via DM — opens a dialog to pick a recipient and send the
          profile embed card (mirrors the iOS share-profile-in-DM flow). */}
      <Dialog open={shareProfileOpen} onOpenChange={setShareProfileOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Share @{profile.username}'s profile</DialogTitle>
          </DialogHeader>
          <ShareProfileToDM
            embed={profileShareEmbed}
            onClose={() => setShareProfileOpen(false)}
          />
        </DialogContent>
      </Dialog>

      {embeddedCheckout && (
        <EmbeddedCheckoutSheet
          clientSecret={embeddedCheckout.clientSecret}
          publishableKey={embeddedCheckout.publishableKey}
          onClose={() => setEmbeddedCheckout(null)}
          onComplete={() => {
            setEmbeddedCheckout(null);
            queryClient.invalidateQueries({
              queryKey: ["coach-status", user?.id, profile.user_id],
            });
            queryClient.invalidateQueries({
              queryKey: ["hire-status", profile.user_id],
            });
            toast("Payment complete — you&rsquo;re subscribed!");
          }}
        />
      )}

      <Dialog open={coachOpen} onOpenChange={setCoachOpen}>
        <DialogContent className="max-h-[88vh] max-w-md overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Request @{profile.username} as your coach</DialogTitle>
          </DialogHeader>

          {/* Coach preview — same side-photo layout as the search spotlight
              card so the photo never gets cropped awkwardly. */}
          <div className="overflow-hidden rounded-2xl border border-border bg-card">
            <div className="p-4">
              <div className="flex gap-3.5">
                <div className="h-28 w-[88px] shrink-0 overflow-hidden rounded-xl bg-secondary">
                  {spotlight?.photo_url || profile.profile_image_url ? (
                    <img
                      src={spotlight?.photo_url || profile.profile_image_url || ""}
                      alt={profile.username}
                      className="h-full w-full object-cover object-top"
                    />
                  ) : (
                    <div className="flex h-full w-full items-center justify-center">
                      <Avatar name={profile.username} size={44} />
                    </div>
                  )}
                </div>
                <div className="min-w-0 flex-1">
                  <p className="flex items-center gap-1.5 truncate text-[16px] font-extrabold">
                    {profile.display_name || profile.username}
                    <BadgeCheck className="h-4 w-4 shrink-0 text-orange-500" />
                  </p>
                  <p className="truncate text-[12.5px] text-muted-foreground">
                    Verified Coach · @{profile.username}
                  </p>
                  {coachRate?.monthlyPriceCents &&
                    coachRate.active &&
                    coachRate.acceptingPayments && (
                      <span className="mt-1.5 inline-block rounded-full bg-orange-500/10 px-2.5 py-1 text-[12px] font-extrabold text-orange-600">
                        {formatCents(coachRate.monthlyPriceCents)}/mo · cancel anytime
                      </span>
                    )}
                </div>
              </div>

              {(spotlight?.discipline ||
                spotlight?.age ||
                (spotlight?.chips.length ?? 0) > 0) && (
                <div className="mt-2.5 flex flex-wrap gap-1.5">
                  {spotlight?.tier !== null && spotlight?.tier !== undefined && (
                    <span className="rounded-full border border-border px-2.5 py-1 text-[11.5px] font-bold">
                      Tier {spotlight.tier}
                    </span>
                  )}
                  {spotlight?.discipline && (
                    <span className="rounded-full border border-border px-2.5 py-1 text-[11.5px] font-semibold">
                      {spotlight.discipline}
                    </span>
                  )}
                  {spotlight?.age && (
                    <span className="rounded-full border border-border px-2.5 py-1 text-[11.5px] font-semibold text-muted-foreground">
                      {spotlight.age}
                    </span>
                  )}
                  {(spotlight?.chips ?? []).map((chip) => (
                    <span
                      key={chip}
                      className="rounded-full border border-border px-2.5 py-1 text-[11.5px] font-semibold text-muted-foreground"
                    >
                      {chip}
                    </span>
                  ))}
                </div>
              )}

              {(spotlight?.paragraphs[0] || profile.bio) && (
                <p className="mt-3 text-[13.5px] leading-relaxed text-muted-foreground">
                  {spotlight?.paragraphs[0] ?? profile.bio}
                </p>
              )}

              {(spotlight?.highlights.length ?? 0) > 0 && (
                <div className="mt-3 space-y-1.5">
                  {(spotlight?.highlights ?? []).slice(0, 4).map((h, i) => (
                    <div
                      key={`hl-${i}`}
                      className="flex items-center gap-2 rounded-xl bg-secondary px-3 py-2 text-[12.5px] font-medium"
                    >
                      {i % 2 === 0 ? (
                        <Dumbbell className="h-3.5 w-3.5 shrink-0 text-foreground/70" />
                      ) : (
                        <CalendarCheck className="h-3.5 w-3.5 shrink-0 text-foreground/70" />
                      )}
                      {h}
                    </div>
                  ))}
                </div>
              )}

              {spotlightQuery.isPending && coachRateQuery.isPending && (
                <div className="mt-3 flex items-center gap-2 text-[12.5px] text-muted-foreground">
                  <Sparkles className="h-3.5 w-3.5 animate-pulse" />
                  Loading coach details…
                </div>
              )}
            </div>
          </div>

          <p className="text-sm text-muted-foreground">
            Tell them a bit about your goals. They'll see this with your request.
          </p>
          <textarea
            value={coachMessage}
            onChange={(e) => setCoachMessage(e.target.value)}
            rows={3}
            autoFocus
            placeholder="e.g. Cutting for summer, want a 4-day split and macro check-ins."
            className="w-full resize-none rounded-2xl border border-border bg-card px-4 py-3 text-sm outline-none focus:border-foreground/40"
          />
          <button
            onClick={() => requestCoachMutation.mutate()}
            disabled={requestCoachMutation.isPending}
            className="w-full rounded-2xl bg-primary py-3.5 text-[15px] font-bold text-primary-foreground transition-transform active:scale-[0.98] disabled:opacity-50"
          >
            {requestCoachMutation.isPending
              ? "Sending…"
              : coachCharges
                ? `Apply & subscribe · ${formatCents(coachRate!.monthlyPriceCents!)}/mo`
                : "Send request"}
          </button>
          {coachCharges && (
            <p className="text-center text-[12px] leading-snug text-muted-foreground">
              Billed monthly through Stripe. Cancel anytime in Settings — access
              runs to the end of the paid month.
            </p>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Share profile via DM — pick a recipient and send a profile card    */
/* ------------------------------------------------------------------ */
function ShareProfileToDM({
  embed,
  onClose,
}: {
  embed: string;
  onClose: () => void;
}) {
  const { user, profile: me } = useAuth();
  const [query, setQuery] = useState<string>("");
  const [sending, setSending] = useState<boolean>(false);

  const convosQuery = useQuery({
    queryKey: ["conversations", user?.id],
    queryFn: () => fetchConversations(user!.id),
    enabled: !!user,
  });

  const searchQuery = useQuery({
    queryKey: ["share-profile-search", query],
    queryFn: () => searchProfiles(query),
    enabled: query.trim().length > 0,
  });

  const recipients = useMemo(() => {
    if (query.trim()) {
      return (searchQuery.data ?? [])
        .filter((p) => p.user_id !== user?.id)
        .slice(0, 10);
    }
    return (convosQuery.data ?? []).slice(0, 12);
  }, [query, searchQuery.data, convosQuery.data, user?.id]);

  const handleSend = async (recipientId: string, recipientUsername: string): Promise<void> => {
    if (!user || !me) return;
    setSending(true);
    try {
      await sendMessage(user.id, me.username, recipientId, recipientUsername, embed);
      toast(`Profile sent to @${recipientUsername}`);
      onClose();
    } catch {
      toast("Couldn't send. Try again.");
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2 rounded-full bg-secondary px-3.5 py-2.5">
        <Search className="h-4 w-4 text-muted-foreground" />
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search people…"
          className="flex-1 bg-transparent text-[15px] outline-none placeholder:text-muted-foreground"
        />
      </div>
      <div className="max-h-[40vh] overflow-y-auto">
        {recipients.length === 0 ? (
          <p className="py-6 text-center text-sm text-muted-foreground">
            {query.trim() ? "No people found." : "Search for someone to share with."}
          </p>
        ) : (
          <div className="flex flex-col gap-1">
            {recipients.map((r) => {
              const rp = r as { user_id: string; username: string; profile_image_url: string | null; display_name?: string | null };
              return (
                <button
                  key={rp.user_id}
                  onClick={() => handleSend(rp.user_id, rp.username)}
                  disabled={sending}
                  className="flex items-center gap-3 rounded-xl px-2 py-2 text-left transition-colors hover:bg-secondary/60 disabled:opacity-50"
                >
                  <Avatar url={rp.profile_image_url} name={rp.username} size={40} />
                  <span className="min-w-0 flex-1 truncate text-sm font-semibold">
                    @{rp.username}
                  </span>
                  <Send className="h-4 w-4 text-muted-foreground" />
                </button>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
