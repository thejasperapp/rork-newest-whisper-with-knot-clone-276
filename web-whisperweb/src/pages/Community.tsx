import { useEffect, useMemo, useState } from "react";
import { ConversationListEnd } from "@/components/ConversationListEnd";
import { useParams, Navigate, Link, useNavigate } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  MoreHorizontal,
  ChevronDown,
  LogOut,
  Check,
  Info,
  Lock,
  Heart,
  ShieldCheck,
  Sparkles,
  UserPlus,
  Loader2,
  Hand,
  PenLine,
} from "lucide-react";
import { toast } from "sonner";

import { Header } from "@/components/Header";
import { PostCard } from "@/components/PostCard";
import { Avatar } from "@/components/Avatar";
import { ComposerModal } from "@/components/ComposerModal";
import {
  fetchMyBookmarkIds,
  fetchMyLikedPostIds,
  fetchMyRepostIds,
  fetchProfilesByIds,
  updateInterests,
} from "@/lib/api";
import {
  communityById,
  communityMatchesPost,
  communityReact,
  fetchCustomCommunity,
  datingIcebreakerForHour,
  minutesUntilNextIcebreaker,
  DATING_SAFETY_TIPS,
  fetchGroupMembers,
  inviteToGroup,
  acceptGroupInvite,
  removeGroupRow,
  type CommunityMemberRow,
} from "@/lib/communities";
import { setComposerPrefill } from "@/lib/composerDraft";
import { Input } from "@/components/ui/input";
import { loadCachedNearby } from "@/lib/nearbyCommunities";
import { useRankedFeed } from "@/hooks/useRankedFeed";
import { jasperHasLocalToken } from "@/lib/jasperConnect";
import { ChevronRight, Link2, MapPin, Shuffle, SlidersHorizontal, Video, Wand2 } from "lucide-react";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { DATING_ICEBREAKERS } from "@/lib/communities";
import { datingAnswerFromCaption, personScore, sharedThemes, type DatingAnswer } from "@/lib/datingEngine";
import { BlindDateFinder } from "@/components/BlindDateFinder";
import { DatingPrefsDialog } from "@/components/DatingPrefsDialog";
import { MatchmakerCards } from "@/components/MatchmakerCards";
import { MATCHMAKER_FORMAT, parseMatchmakerReply } from "@/lib/matchmakerReply";
import { blindQueueCount, markBlindReady } from "@/lib/blindDate";
import {
  DEFAULT_DATING_PREFS,
  fetchNearbyDaters,
  intentLabel,
  loadDatingPrefs,
  loadNearbyOnly,
  nearbyDistanceLabel,
  prefsHasLocation,
  prefsIsConfigured,
  prefsSummaryLine,
  saveNearbyOnly,
  syncDatingPrefsFromCloud,
  type DatingPrefs,
  type NearbyPerson,
} from "@/lib/datingPrefs";
import { JasperAnalysisDock, type JasperDockCostume } from "@/components/JasperAnalysisDock";
import { DatingCardEditor } from "@/components/DatingCardEditor";
import {
  DATING_CARD_QUESTIONS,
  hasDatingCard,
  loadDatingCardLocal,
  markSpeedDateRoom,
  mintSpeedDateCode,
} from "@/lib/datingCards";
import { datingAnswerFor, loadDatingAnswers, saveDatingAnswer } from "@/lib/datingAnswers";
import { markDatingPeer } from "@/lib/datingInbox";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useAuth } from "@/hooks/useAuth";
import { compactCount } from "@/lib/format";
import { cn } from "@/lib/utils";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import type { WhisperPost } from "@/lib/types";

type SortMode = "match" | "top" | "newest" | "oldest";

const SORT_LABELS: Record<SortMode, string> = {
  match: "For you",
  top: "Top posts",
  newest: "Newest",
  oldest: "Oldest",
};

/** The matchmaker brain v2 — preferences + private answers + distance in
 *  the context, a STRUCTURED response (READ / MATCH / MOVE) rendered as
 *  cards. Grounded ONLY in the hub's real posts (mirrors iOS). */
const DATING_MATCH_FOCUS = `You are Jasper, Whisper's MATCHMAKER in the Dating hub — think like a sharp, kind friend who reads people well, not a horoscope. In the context: this hour's icebreaker, MY preferences, my dating card, my private icebreaker answers, and other members' latest answers (with distance and intent when known). Rank my 2-3 most compatible people from what they ACTUALLY wrote — shared themes, matching intent, real chemistry signals, distance inside my radius — and give me an opener I'd genuinely send. Never invent people or details, zero clichés, zero cringe, no flattery. If I haven't answered anything yet, READ the room honestly and make my MOVE answering the icebreaker.
${MATCHMAKER_FORMAT}`;

const DATING_OPENERS_FOCUS = `From the dating hub context, pick my top 2 matches and write ONE opener for each that I'd actually send — warm, playful, specific to their exact words, first person, one line. READ = one line on my opener style. MOVE = when and how to send it.
${MATCHMAKER_FORMAT}`;

const DATING_VIBE_FOCUS = `Read MY dating card, preferences, and private answers like a matchmaker would: what I actually signal (one honest line), what might be scaring good matches off, and the single edit that would sharpen how I come across. Put the signal in READ, skip MATCH lines unless someone in the hub clearly fits me, and make MOVE the one edit.
${MATCHMAKER_FORMAT}`;

const DATING_COACH_FOCUS = `Help ME answer this hour's icebreaker (in the context) in a way that attracts the people I say I want. Draft 2 short answers in a natural first-person voice — specific, warm, a little playful, no clichés — one line each, then one line on why they'd stand out in a dating feed.`;

/** Cupid Jasper behind the cream "matched" pill — mirrors iOS `.datingMatchmaker`. */
const DATING_DOCK_COSTUME: JasperDockCostume = {
  accent: "#E8477D",
  softAccent: "#FAB3C9",
  pillFill: "#FCF6F1",
  pillRim: "#F2A8C2",
  ink: "#1F0D14",
  chipLabel: "MATCHMAKER",
  pillIconSrc: "/dating/whisper-dating-logo.png",
  mascotPalette: { accent: "#F5B8CC", softAccent: "#FFEDF2", deepAccent: "#E68FAD" },
  mascotSmitten: true,
};

/** Short chip labels for the five dating-card prompts (lobby status). */
const SD_SHORT_LABELS: Record<string, string> = {
  looking: "Looking for",
  interests: "Interests",
  dealbreakers: "Non-negotiables",
  firstDate: "First date",
  funFact: "Fun fact",
};

export default function Community() {
  const { id = "" } = useParams<{ id: string }>();
  const { user, profile, refreshProfile } = useAuth();
  const queryClient = useQueryClient();
  const catalogCommunity = communityById(id);

  // Geo hubs (campus pack + campus/gym crews) live in this account's
  // nearby cache — resolve them locally so /c/geo-law etc. open after a
  // Near-you visit.
  const geoCommunity = useMemo(
    () => loadCachedNearby(user?.id)?.find((c) => c.id === id),
    [id, user?.id]
  );

  // User-created communities live in the DB — fall back when the catalog
  // doesn't know this id.
  const customQuery = useQuery({
    queryKey: ["custom-community", user?.id, id],
    queryFn: () => fetchCustomCommunity(id),
    enabled: !catalogCommunity && !geoCommunity && !!id,
  });
  const community = catalogCommunity ?? geoCommunity ?? customQuery.data ?? undefined;

  const navigate = useNavigate();
  const [sortMode, setSortMode] = useState<SortMode>(() => (id === "dating" ? "match" : "top"));
  const [cardEditorOpen, setCardEditorOpen] = useState<boolean>(false);
  const [composing, setComposing] = useState<boolean>(false);
  /** Icebreaker roulette — a shuffled prompt overrides the hourly pick. */
  const [shuffledPrompt, setShuffledPrompt] = useState<string | null>(null);
  /** 30s ticker — keeps the hourly icebreaker + its countdown live. */
  const [icebreakerTick, setIcebreakerTick] = useState<number>(() => Date.now());
  const shownPrompt = shuffledPrompt ?? datingIcebreakerForHour(new Date(icebreakerTick));
  useEffect(() => {
    if (id !== "dating") return;
    const t = window.setInterval(() => setIcebreakerTick(Date.now()), 30_000);
    return () => window.clearInterval(t);
  }, [id]);
  /** The structured icebreaker ANSWER dialog (private by default). */
  const [answerOpen, setAnswerOpen] = useState<boolean>(false);
  const [answerDraft, setAnswerDraft] = useState<string>("");
  const [answerShare, setAnswerShare] = useState<boolean>(false);
  /** Bumps when a private answer saves so the For-you sort recomputes. */
  const [answersTick, setAnswersTick] = useState<number>(0);
  /** The custom speed-date LOBBY — the starter's join screen. */
  const [sdLobbyOpen, setSdLobbyOpen] = useState<boolean>(false);
  const [sdCode, setSdCode] = useState<string>("");
  const [sdCopied, setSdCopied] = useState<boolean>(false);
  const [sdCardTick, setSdCardTick] = useState<number>(0);
  /** Lobby card status — recomputes when the editor saves. */
  const sdCard = useMemo<Record<string, string>>(() => {
    void sdCardTick;
    if (!user || !sdLobbyOpen) return {};
    return loadDatingCardLocal(user.id);
  }, [user, sdLobbyOpen, sdCardTick]);
  const sdAnswered = DATING_CARD_QUESTIONS.filter((q) => (sdCard[q.id] ?? "").trim()).length;
  /** Blind dating — the finder behind the header's video circle, the
   *  preferences dialog, and the nearby set that filters the hub by radius. */
  const [finderOpen, setFinderOpen] = useState<boolean>(false);
  /** The community's tool drawer — every dating special in one sheet. */
  const [toolsOpen, setToolsOpen] = useState<boolean>(false);
  const [prefsOpen, setPrefsOpen] = useState<boolean>(false);
  const [prefsTick, setPrefsTick] = useState<number>(0);
  const [nearby, setNearby] = useState<NearbyPerson[]>([]);
  const [nearbyOnly, setNearbyOnly] = useState<boolean>(() => (user ? loadNearbyOnly(user.id) : true));
  const [queueCount, setQueueCount] = useState<number>(0);
  const datingPrefs = useMemo<DatingPrefs>(() => {
    void prefsTick;
    return user ? loadDatingPrefs(user.id) : { ...DEFAULT_DATING_PREFS };
  }, [user, prefsTick]);
  useEffect(() => {
    if (id !== "dating" || !user) return;
    // Preferences (cloud wins over an empty device), the nearby set that
    // drives the radius filter, and the live queue count for the circle.
    void syncDatingPrefsFromCloud(user.id).then(() => setPrefsTick((t) => t + 1));
    void fetchNearbyDaters().then(setNearby);
    void blindQueueCount().then(setQueueCount);
    const t = window.setInterval(() => void blindQueueCount().then(setQueueCount), 30_000);
    return () => window.clearInterval(t);
  }, [id, user]);
  const [infoOpen, setInfoOpen] = useState<boolean>(false);
  const [inviteOpen, setInviteOpen] = useState<boolean>(false);
  const [inviteName, setInviteName] = useState<string>("");

  // Private groups run on real membership rows (not interests).
  const isPrivate = community?.visibility === "private";
  const membersQuery = useQuery({
    queryKey: ["group-members", user?.id, id],
    queryFn: () => fetchGroupMembers(id),
    enabled: isPrivate,
  });
  const members = useMemo(
    () => (membersQuery.data ?? []).filter((m) => m.status === "member"),
    [membersQuery.data]
  );
  const myRow: CommunityMemberRow | undefined = (membersQuery.data ?? []).find(
    (m) => m.user_id === user?.id
  );
  const isGroupOwner =
    !!user && (community?.creatorId === user.id || myRow?.role === "owner");
  const isGroupMember = isGroupOwner || myRow?.status === "member";
  const isInvited = myRow?.status === "invited" && !isGroupOwner;

  const feedQuery = useRankedFeed(user?.id, { kind: "community", id },
    !!community && (!isPrivate || isGroupMember) && (!community.requiresJasperLink || jasperHasLocalToken()));
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

  const allPosts = feedQuery.data ?? [];
  const matching = useMemo(
    () =>
      community
        ? allPosts.filter((p) => communityMatchesPost(community, p))
        : [],
    [allPosts, community]
  );

  /** My dating answers, newest first (up to 8) — anchors for "For you".
   *  Every answer is another signal: people are scored by their BEST
   *  resonance with ANY of my answers, so the hourly prompts genuinely
   *  dial matches in over time. */
  const myDatingAnswers = useMemo<DatingAnswer[]>(() => {
    if (id !== "dating" || !user) return [];
    void answersTick;
    // Private answers lead — answering is private by default, and the
    // sort reads them straight off the device (no post required).
    const answers: DatingAnswer[] = loadDatingAnswers(user.id).map((a) => ({
      prompt: a.prompt,
      text: a.answer,
    }));
    const mine = matching
      .filter((p) => p.user_id === user.id)
      .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
    for (const p of mine) {
      if (answers.length >= 8) break;
      const parsed = datingAnswerFromCaption(p.caption);
      if (parsed.text) answers.push(parsed);
    }
    return answers.slice(0, 8);
  }, [id, matching, user, answersTick]);

  /** Newest answer — what the matchmaker context leads with. */
  const myDatingAnswer: DatingAnswer | null = myDatingAnswers[0] ?? null;

  /** Nearby daters keyed by user id (radius filter + score boost). */
  const nearbyById = useMemo(() => {
    const m = new Map<string, NearbyPerson>();
    nearby.forEach((n) => m.set(n.user_id, n));
    return m;
  }, [nearby]);
  const radiusOn = id === "dating" && nearbyOnly && prefsHasLocation(datingPrefs) && nearby.length > 0;

  const posts = useMemo(() => {
    // Dating: the RADIUS filter — with a saved location and "Nearby only"
    // on, people outside my radius (or without a location) drop out.
    const list: WhisperPost[] = radiusOn
      ? matching.filter((p) => p.user_id === user?.id || nearbyById.has(p.user_id.toLowerCase()))
      : [...matching];
    if (sortMode === "match") {
      // Dating's match sort (engine v2) — themes + literal overlap + a
      // same-prompt bonus against ALL my answers, boosted by distance inside
      // my radius and a shared intent; newest until I've answered.
      if (myDatingAnswers.length > 0) {
        const scored = list.map((p) => ({
          p,
          s: personScore(myDatingAnswers, p.caption, nearbyById.get(p.user_id.toLowerCase()), datingPrefs),
        }));
        scored.sort((a, b) =>
          Math.abs(b.s - a.s) > 0.0001
            ? b.s - a.s
            : new Date(b.p.created_at).getTime() - new Date(a.p.created_at).getTime()
        );
        return scored.map((x) => x.p);
      }
      list.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
      return list;
    }
    if (sortMode === "top") {
      list.sort(
        (a, b) =>
          (b.likes_count ?? 0) + (b.comments_count ?? 0) -
          ((a.likes_count ?? 0) + (a.comments_count ?? 0))
      );
    } else {
      list.sort((a, b) => {
        const da = new Date(a.created_at).getTime();
        const db = new Date(b.created_at).getTime();
        return sortMode === "newest" ? db - da : da - db;
      });
    }
    return list;
  }, [matching, sortMode, myDatingAnswers, radiusOn, nearbyById, datingPrefs, user?.id]);

  /** Live context for the matchmaker — tonight's prompt, my answer, and the
   *  hub's latest answers (captions meta-stripped and truncated). */
  /** Mints a wsp room primed for speed-date mode, copies the invite link,
   *  and opens the custom speed-date LOBBY — the starter's join screen. */
  const startSpeedDate = (): void => {
    if (!user) {
      toast.error("Sign in to start a speed date.");
      return;
    }
    const code = mintSpeedDateCode();
    markSpeedDateRoom(code);
    setSdCode(code);
    let copied = false;
    try {
      // ?sd=1 lets the guest see the speed-date welcome instantly.
      void navigator.clipboard.writeText(`https://mydailywhisper.com/meet/${code}?sd=1`);
      copied = true;
    } catch {
      copied = false;
    }
    setSdCopied(copied);
    if (copied) toast.success("Speed date link copied — send it to your date 💘");
    setSdLobbyOpen(true);
  };

  /** Saves the private icebreaker answer; opens the composer only when sharing. */
  const saveIcebreakerAnswer = (): void => {
    if (!user) return;
    const text = answerDraft.trim();
    if (!text) return;
    saveDatingAnswer(user.id, shownPrompt, text);
    setAnswersTick((t) => t + 1);
    setAnswerOpen(false);
    if (answerShare) {
      setComposerPrefill({ caption: `${shownPrompt}\n${text}` });
      setComposing(true);
    } else {
      toast.success("Answer saved — it sharpens your matches 💘");
    }
  };

  /** Enter the date from the lobby — marks me ready and joins the room. */
  const enterSpeedDate = (): void => {
    // Entering from the lobby IS saying "I'm ready" — the room skips the
    // welcome takeover and starts the clock once the guest is ready too.
    markBlindReady(sdCode);
    try {
      sessionStorage.setItem(`whisper-sd-ready:${sdCode}`, "1");
    } catch {
      // Best-effort — worst case the welcome shows once.
    }
    setSdLobbyOpen(false);
    navigate(`/meet/${sdCode}`);
  };

  /** Live context for the matchmaker v2 — this hour's prompt, my prefs +
   *  card + private answers, and the hub's people with distance/intent when
   *  known (out-of-radius people drop out when the Nearby filter is on). */
  const buildDatingContext = (): string | null => {
    const lines: string[] = [];
    lines.push(`THIS HOUR'S ICEBREAKER: ${shownPrompt}`);
    let prefsLine = `MY PREFERENCES: ${prefsSummaryLine(datingPrefs)}`;
    if (datingPrefs.cityLabel) prefsLine += ` · near ${datingPrefs.cityLabel}`;
    if (datingPrefs.age != null) prefsLine += ` · I'm ${datingPrefs.age}`;
    lines.push(prefsLine);
    if (user) {
      const card = loadDatingCardLocal(user.id);
      const cardLines = DATING_CARD_QUESTIONS.filter((q) => (card[q.id] ?? "").trim()).map(
        (q) => `- ${q.label} ${card[q.id]}`
      );
      if (cardLines.length > 0) lines.push(`MY DATING CARD:\n${cardLines.join("\n")}`);
    }
    if (myDatingAnswers.length === 0) {
      lines.push("I HAVEN'T ANSWERED ANY ICEBREAKER YET.");
    } else {
      lines.push(
        `MY ANSWERS (newest first):\n${myDatingAnswers
          .slice(0, 5)
          .map((a) => (a.prompt ? `- "${a.prompt.slice(0, 70)}" → ${a.text.slice(0, 160)}` : `- ${a.text.slice(0, 160)}`))
          .join("\n")}`
      );
    }
    const people: string[] = [];
    const rows = [...matching]
      .filter((p) => p.user_id !== user?.id)
      .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
    for (const row of rows.slice(0, 16)) {
      const near = nearbyById.get(row.user_id.toLowerCase());
      if (radiusOn && !near) continue;
      const parsed = datingAnswerFromCaption(row.caption);
      if (!parsed.text) continue;
      const handle = row.username ?? "member";
      const meta: string[] = [];
      if (near) {
        const d = nearbyDistanceLabel(near);
        if (d) meta.push(d);
        if (near.age != null) meta.push(String(near.age));
        const intent = intentLabel(near.intent);
        if (intent) meta.push(`wants ${intent.toLowerCase()}`);
      }
      const shared = myDatingAnswers.length > 0 ? sharedThemes(myDatingAnswers, parsed.text) : [];
      if (shared.length > 0) meta.push(`shared: ${shared.join(", ")}`);
      const metaText = meta.length > 0 ? ` [${meta.join(" · ")}]` : "";
      people.push(
        parsed.prompt
          ? `@${handle}${metaText} — answered "${parsed.prompt.slice(0, 60)}": ${parsed.text.slice(0, 140)}`
          : `@${handle}${metaText}: ${parsed.text.slice(0, 140)}`
      );
    }
    if (people.length > 0) {
      lines.push(`PEOPLE IN THE DATING HUB (newest first):\n${people.join("\n")}`);
    }
    return people.length === 0 && myDatingAnswers.length === 0 ? null : lines.join("\n\n");
  };

  /** "You both: Outdoors · Food · 12 km away" — why this person ranks in For you. */
  const matchWhyLine = (post: WhisperPost): string | null => {
    if (sortMode !== "match" || !user || post.user_id === user.id) return null;
    const parts: string[] = [];
    if (myDatingAnswers.length > 0) {
      const shared = sharedThemes(myDatingAnswers, datingAnswerFromCaption(post.caption).text);
      if (shared.length > 0) parts.push(`You both: ${shared.join(" · ")}`);
    }
    const near = nearbyById.get(post.user_id.toLowerCase());
    if (near) {
      const d = nearbyDistanceLabel(near);
      if (d) parts.push(d);
      const intent = intentLabel(near.intent);
      if (intent && near.intent === datingPrefs.intent) parts.push(`both want ${intent.toLowerCase()}`);
    }
    return parts.length > 0 ? parts.join(" · ") : null;
  };

  /** A hub member's DM target by @handle — the matchmaker cards use it. */
  const memberByHandle = (handle: string): { userId: string; username: string } | null => {
    const needle = handle.toLowerCase().replace(/@/g, "");
    const row = matching.find((p) => (p.username ?? "").toLowerCase() === needle && p.user_id !== user?.id);
    return row ? { userId: row.user_id, username: row.username ?? needle } : null;
  };

  const derivedMemberCount = useMemo(
    () => new Set(matching.map((p) => p.user_id)).size,
    [matching]
  );
  const memberCount = isPrivate ? members.length : derivedMemberCount;

  const authorIds = useMemo(() => posts.map((p) => p.user_id), [posts]);
  const profilesQuery = useQuery({
    queryKey: ["profiles", authorIds],
    queryFn: () => fetchProfilesByIds(authorIds),
    enabled: authorIds.length > 0,
  });

  const profiles = profilesQuery.data ?? {};
  const likedSet = useMemo(() => new Set(likesQuery.data ?? []), [likesQuery.data]);
  const repostedSet = useMemo(
    () => new Set(repostsQuery.data ?? []),
    [repostsQuery.data]
  );
  const bookmarkedSet = useMemo(
    () => new Set(bookmarksQuery.data ?? []),
    [bookmarksQuery.data]
  );

  const interests = profile?.interests ?? [];
  const isJoined = community
    ? interests.some((i) => i.toLowerCase() === community.name.toLowerCase())
    : false;

  const joinMutation = useMutation({
    mutationFn: async (): Promise<void> => {
      if (!user || !community) throw new Error("Not signed in");
      const key = community.name.toLowerCase();
      const next = isJoined
        ? interests.filter((i) => i.toLowerCase() !== key)
        : [...interests, community.name];
      await updateInterests(user.id, next);
    },
    onSuccess: async () => {
      await refreshProfile();
      queryClient.invalidateQueries({ queryKey: ["my-verification-badge"] });
      toast(isJoined ? "Left community" : "Joined community");
    },
    onError: () => toast("Couldn't update membership"),
  });

  const inviteMutation = useMutation({
    mutationFn: () =>
      inviteToGroup({
        slug: id,
        username: inviteName,
        invitedBy: profile?.username ?? "someone",
      }),
    onSuccess: () => {
      toast(`Invited @${inviteName.trim().replace(/^@/, "")}`);
      setInviteName("");
      void queryClient.invalidateQueries({ queryKey: ["group-members", user?.id, id] });
    },
    onError: (err: Error) => toast(err.message),
  });

  const acceptInvite = useMutation({
    mutationFn: () => acceptGroupInvite(id, user!.id),
    onSuccess: () => {
      toast(`Welcome to ${community?.name ?? "the group"}`);
      void queryClient.invalidateQueries({ queryKey: ["group-members", user?.id, id] });
    },
    onError: (err: Error) => toast(err.message),
  });

  const leaveGroup = useMutation({
    mutationFn: () => removeGroupRow(id, user!.id),
    onSuccess: () => {
      toast(isInvited ? "Invite declined" : "Left the group");
      void queryClient.invalidateQueries({ queryKey: ["group-members", user?.id, id] });
    },
  });

  if (!catalogCommunity && customQuery.isLoading) {
    return (
      <div>
        <Header title="Community" />
        <p className="px-6 py-16 text-center text-sm text-muted-foreground">
          Loading…
        </p>
      </div>
    );
  }
  if (!community) return <Navigate to="/communities" replace />;

  const Icon = community.icon;
  // Jasper Circle: viewable only with a linked Jasper account. Once open,
  // its posts stay white but wear the ember glow shell.
  const jasperLocked = community.requiresJasperLink === true && !jasperHasLocalToken();
  const jasperGlow = community.requiresJasperLink === true && !jasperLocked;

  return (
    <div>
      <Header title={community.name} />

      <div className="px-0 pt-0 sm:px-0 sm:pt-2">
        <div className="overflow-hidden border-b border-border bg-background sm:rounded-[22px] sm:border sm:shadow-sm">
          {/* Hero */}
          <div
            className="flex items-center gap-3 px-5 py-5"
            style={{
              backgroundImage: `linear-gradient(135deg, ${community.gradient[0]}, ${community.gradient[1]})`,
            }}
          >
            <span className="flex h-12 w-12 items-center justify-center rounded-2xl bg-white/25 text-white backdrop-blur">
              <Icon className="h-6 w-6" />
            </span>
            <div className="min-w-0 flex-1">
              <h2 className="flex items-center gap-1.5 font-display text-[20px] font-extrabold text-white">
                {community.name}
                {communityReact(community) && (
                  <span className="text-[17px]">{communityReact(community)}</span>
                )}
              </h2>
              <p className="truncate text-[13px] text-white/85">
                {community.tagline}
              </p>
              {community.origin && (
                <p className="mt-0.5 flex items-center gap-1 text-[11.5px] font-semibold text-white/80">
                  <MapPin className="h-3 w-3" />
                  {community.origin}
                </p>
              )}
            </div>
            {isPrivate ? (
              isGroupOwner ? (
                <button
                  onClick={() => setInviteOpen(true)}
                  className="flex shrink-0 items-center gap-1.5 rounded-full bg-white px-4 py-1.5 text-sm font-bold text-foreground transition-transform active:scale-95"
                >
                  <UserPlus className="h-4 w-4" />
                  Invite
                </button>
              ) : isGroupMember ? (
                <span className="shrink-0 rounded-full bg-white/20 px-4 py-1.5 text-sm font-bold text-white backdrop-blur">
                  Member
                </span>
              ) : (
                <span className="flex shrink-0 items-center gap-1 rounded-full bg-white/20 px-3.5 py-1.5 text-[12.5px] font-bold text-white backdrop-blur">
                  <Lock className="h-3.5 w-3.5" />
                  Invite only
                </span>
              )
            ) : (
              <button
                onClick={() => joinMutation.mutate()}
                disabled={joinMutation.isPending}
                className={cn(
                  "shrink-0 rounded-full px-4 py-1.5 text-sm font-bold transition-colors disabled:opacity-50",
                  isJoined
                    ? "bg-white/20 text-white backdrop-blur"
                    : "bg-white text-foreground"
                )}
              >
                {isJoined ? "Joined" : "Join"}
              </button>
            )}
            <button
              onClick={() => setInfoOpen(true)}
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-white/20 text-white outline-none backdrop-blur transition-colors hover:bg-white/30"
              aria-label="About this community"
            >
              <Info className="h-4 w-4" />
            </button>
            <DropdownMenu>
              <DropdownMenuTrigger className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-white/20 text-white outline-none backdrop-blur transition-colors hover:bg-white/30">
                <MoreHorizontal className="h-5 w-5" />
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-44">
                {isPrivate ? (
                  <>
                    {isGroupOwner && (
                      <DropdownMenuItem onClick={() => setInviteOpen(true)}>
                        <UserPlus className="mr-2 h-4 w-4" />
                        Invite people
                      </DropdownMenuItem>
                    )}
                    {isGroupMember && !isGroupOwner && (
                      <DropdownMenuItem
                        onClick={() => leaveGroup.mutate()}
                        className="text-destructive focus:text-destructive"
                      >
                        <LogOut className="mr-2 h-4 w-4" />
                        Leave group
                      </DropdownMenuItem>
                    )}
                  </>
                ) : (
                  <>
                    {isJoined && (
                      <DropdownMenuItem
                        onClick={() => joinMutation.mutate()}
                        className="text-destructive focus:text-destructive"
                      >
                        <LogOut className="mr-2 h-4 w-4" />
                        Leave community
                      </DropdownMenuItem>
                    )}
                    {!isJoined && (
                      <DropdownMenuItem onClick={() => joinMutation.mutate()}>
                        <Check className="mr-2 h-4 w-4" />
                        Join community
                      </DropdownMenuItem>
                    )}
                  </>
                )}
              </DropdownMenuContent>
            </DropdownMenu>
          </div>

          {/* About sheet — provenance (campus/gym + street address), the
              signature react, and the caption keywords that file posts in. */}
          <Dialog open={infoOpen} onOpenChange={setInfoOpen}>
            <DialogContent className="max-w-[420px] rounded-[24px]">
              <DialogHeader>
                <DialogTitle className="flex items-center gap-2.5 text-left">
                  <span
                    className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl text-white"
                    style={{
                      backgroundImage: `linear-gradient(135deg, ${community.gradient[0]}, ${community.gradient[1]})`,
                    }}
                  >
                    <Icon className="h-5 w-5" />
                  </span>
                  <span className="min-w-0 truncate">About {community.name}</span>
                  {communityReact(community) && (
                    <span className="text-[18px]">{communityReact(community)}</span>
                  )}
                </DialogTitle>
              </DialogHeader>
              <div className="space-y-3">
                <p className="text-[13.5px] text-muted-foreground">{community.tagline}</p>
                <p className="text-[12.5px] font-semibold">
                  {compactCount(memberCount)} {memberCount === 1 ? "member" : "members"}
                  {matching.length > 0 && (
                    <>
                      {" · "}
                      {compactCount(matching.length)}{" "}
                      {matching.length === 1 ? "post" : "posts"}
                    </>
                  )}
                </p>
                {(community.origin || community.originAddress) && (
                  <div className="rounded-2xl border border-border bg-card p-3.5">
                    <p className="text-[10px] font-black uppercase tracking-[0.16em] text-muted-foreground">
                      Where it comes from
                    </p>
                    {community.origin && (
                      <p className="mt-1.5 flex items-center gap-1.5 text-[13.5px] font-semibold">
                        <MapPin className="h-3.5 w-3.5 text-muted-foreground" />
                        {community.origin}
                      </p>
                    )}
                    {community.originAddress && (
                      <p className="mt-0.5 pl-5 text-[12.5px] text-muted-foreground">
                        {community.originAddress}
                      </p>
                    )}
                    <p className="mt-1.5 text-[11px] text-muted-foreground/80">
                      Detected on this device — Whisper only keeps the place
                      name, never your coordinates.
                    </p>
                  </div>
                )}
                {communityReact(community) && (
                  <div className="flex items-center gap-3 rounded-2xl border border-border bg-card p-3.5">
                    <span className="text-[26px]">{communityReact(community)}</span>
                    <p className="text-[12.5px] leading-snug text-muted-foreground">
                      <span className="font-bold text-foreground">Signature react</span>{" "}
                      — liking a post inside this community bursts{" "}
                      {communityReact(community)} instead of the heart.
                    </p>
                  </div>
                )}
                <div className="rounded-2xl border border-border bg-card p-3.5">
                  <p className="text-[10px] font-black uppercase tracking-[0.16em] text-muted-foreground">
                    How posts land here
                  </p>
                  <p className="mt-1.5 text-[12.5px] leading-snug text-muted-foreground">
                    {isPrivate
                      ? "Members pick this group in the composer — posts filed here never appear anywhere else."
                      : "Pick the community in the composer when you post — that's the only way a post lands here. Captions and hashtags never auto-file anything."}
                  </p>
                </div>
                <p className="text-[11.5px] text-muted-foreground">
                  {community.id.startsWith("geo-")
                    ? "Location community — it appears while you're nearby. Joining keeps it in Your communities."
                    : "Part of the Whisper catalog — the same community on every account."}
                </p>
              </div>
            </DialogContent>
          </Dialog>

          {isPrivate && !isGroupMember ? (
            <div className="px-5 py-10">
              {membersQuery.isLoading ? (
                <p className="py-6 text-center text-sm text-muted-foreground">Loading…</p>
              ) : isInvited ? (
                <div className="mx-auto max-w-sm rounded-[24px] border border-border bg-card p-6 text-center shadow-sm">
                  <span
                    className="mx-auto flex h-12 w-12 items-center justify-center rounded-full text-white"
                    style={{
                      backgroundImage: `linear-gradient(135deg, ${community.gradient[0]}, ${community.gradient[1]})`,
                    }}
                  >
                    <UserPlus className="h-5 w-5" />
                  </span>
                  <p className="mt-3 text-[16px] font-extrabold">You're invited</p>
                  <p className="mt-1.5 text-[12.5px] leading-relaxed text-muted-foreground">
                    {myRow?.invited_by ? `@${myRow.invited_by}` : "The owner"} invited you
                    to {community.name} — a private group. Only members see what's inside.
                  </p>
                  <div className="mt-4 flex items-center justify-center gap-2">
                    <button
                      onClick={() => acceptInvite.mutate()}
                      disabled={acceptInvite.isPending}
                      className="rounded-full bg-foreground px-5 py-2.5 text-[13px] font-bold text-background transition-transform active:scale-95 disabled:opacity-50"
                    >
                      {acceptInvite.isPending ? "Joining…" : "Join the group"}
                    </button>
                    <button
                      onClick={() => leaveGroup.mutate()}
                      className="rounded-full border border-border px-4 py-2.5 text-[13px] font-bold text-muted-foreground transition-colors hover:text-foreground"
                    >
                      Decline
                    </button>
                  </div>
                </div>
              ) : (
                <div className="mx-auto max-w-sm rounded-[24px] border border-border bg-card p-6 text-center shadow-sm">
                  <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-secondary text-muted-foreground">
                    <Lock className="h-5 w-5" />
                  </span>
                  <p className="mt-3 text-[16px] font-extrabold">This group is private</p>
                  <p className="mt-1.5 text-[12.5px] leading-relaxed text-muted-foreground">
                    {community.name} is invite-only—
                    {community.creatorUsername
                      ? ` ask @${community.creatorUsername} for an invite.`
                      : " ask the owner for an invite."}
                    {members.length > 0 &&
                      ` ${members.length} ${members.length === 1 ? "person is" : "people are"} inside.`}
                  </p>
                </div>
              )}
            </div>
          ) : jasperLocked ? (
            <div className="px-5 py-10">
              <div className="mx-auto max-w-sm rounded-[24px] border border-orange-400/40 bg-card p-6 text-center shadow-[0_16px_44px_rgba(249,115,22,0.16),0_4px_14px_rgba(249,115,22,0.10)]">
                <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-orange-500/10 text-orange-500">
                  <Lock className="h-5 w-5" />
                </span>
                <p className="mt-3 text-[16px] font-extrabold">Linked accounts only</p>
                <p className="mt-1.5 text-[12.5px] leading-relaxed text-muted-foreground">
                  Jasper Circle opens once your Jasper account is linked — one
                  tap in Settings, no codes. Members’ posts glow in here.
                </p>
                <Link
                  to="/settings"
                  className="mt-4 inline-flex items-center justify-center rounded-full bg-foreground px-5 py-2.5 text-[13px] font-bold text-background transition-transform active:scale-95"
                >
                  Connect Jasper
                </Link>
              </div>
            </div>
          ) : (
          <>
          {/* Dating hub extras — tonight's icebreaker + the safety card. */}
          {community.id === "dating" && (
            <div className="space-y-3 px-4 pt-4">
              {/* The Whisper Dating mark on a living pink field — the logo
                  with its background removed over slow-drifting rose blooms. */}
              <div
                className="relative flex h-32 items-center justify-center overflow-hidden rounded-[20px] border border-rose-500/25"
                style={{ background: "#FCD4DF" }}
              >
                <span
                  aria-hidden
                  className="dating-bloom-a absolute -left-10 -top-12 h-56 w-56 rounded-full"
                  style={{ background: "#FF9FBF", filter: "blur(46px)", opacity: 0.6 }}
                />
                <span
                  aria-hidden
                  className="dating-bloom-b absolute -bottom-14 -right-8 h-48 w-48 rounded-full"
                  style={{ background: "#ED5C94", filter: "blur(52px)", opacity: 0.35 }}
                />
                <span
                  aria-hidden
                  className="dating-bloom-c absolute left-1/3 top-1/4 h-40 w-40 rounded-full"
                  style={{ background: "#FFFFFF", filter: "blur(48px)", opacity: 0.55 }}
                />
                <img
                  src="/dating/whisper-dating-logo.png"
                  alt="Whisper Dating"
                  className="relative h-16 w-auto"
                />
                <style>{`
                  @keyframes dating-bloom-a { 0%, 100% { transform: translate(0, 0); } 50% { transform: translate(56px, 30px); } }
                  @keyframes dating-bloom-b { 0%, 100% { transform: translate(0, 0); } 50% { transform: translate(-48px, -26px); } }
                  @keyframes dating-bloom-c { 0%, 100% { transform: translate(0, 0); } 50% { transform: translate(24px, -32px); } }
                  .dating-bloom-a { animation: dating-bloom-a 7s ease-in-out infinite; }
                  .dating-bloom-b { animation: dating-bloom-b 8s ease-in-out infinite; }
                  .dating-bloom-c { animation: dating-bloom-c 9s ease-in-out infinite; }
                `}</style>
              </div>
              {/* The community's TOOL DRAWER door — every dating special
                  (blind dates, preferences, your card, nearby) lives in one
                  sheet instead of a button riding the masthead. */}
              <button
                type="button"
                onClick={() => setToolsOpen(true)}
                className="flex w-full items-center gap-3 rounded-[18px] border border-rose-500/[0.28] bg-rose-500/[0.08] px-3 py-2.5 text-left transition-transform active:scale-[0.99] dark:bg-rose-500/[0.16]"
              >
                <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-rose-500 to-pink-500 text-white">
                  <Wand2 className="h-4 w-4" strokeWidth={2.4} />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-[14px] font-extrabold">Dating tools</span>
                  <span className="block truncate text-[11.5px] text-muted-foreground">
                    Blind dates · preferences · your card
                  </span>
                </span>
                {queueCount > 0 && (
                  <span className="shrink-0 whitespace-nowrap rounded-full bg-emerald-500 px-2 py-0.5 text-[10.5px] font-black text-white">
                    {Math.min(queueCount, 99)} waiting
                  </span>
                )}
                <ChevronRight className="h-4 w-4 shrink-0 text-rose-500" />
              </button>
              <Sheet open={toolsOpen} onOpenChange={setToolsOpen}>
                <SheetContent
                  side="bottom"
                  className="rounded-t-[24px] px-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-5 sm:mx-auto sm:max-w-md"
                >
                  <SheetHeader className="text-left">
                    <SheetTitle className="flex items-center gap-2 text-[17px] font-extrabold">
                      <Wand2 className="h-4 w-4 text-rose-500" />
                      Dating tools
                    </SheetTitle>
                    <SheetDescription className="text-[12.5px]">
                      Every dating special in one place.
                    </SheetDescription>
                  </SheetHeader>
                  <div className="mt-4 space-y-2.5">
                    {(
                      [
                        {
                          id: "blind",
                          icon: <Video className="h-4 w-4" />,
                          title: "Find me a blind date",
                          sub:
                            queueCount > 0
                              ? `${queueCount} waiting right now · five minutes, cameras behind the curtain`
                              : "Get paired with a compatible stranger · five minutes, cameras behind the curtain",
                          badge: queueCount > 0 ? String(Math.min(queueCount, 99)) : null,
                          gate: "Sign in to go on a blind date.",
                          open: () => setFinderOpen(true),
                        },
                        {
                          id: "prefs",
                          icon: <SlidersHorizontal className="h-4 w-4" />,
                          title: "Dating preferences",
                          sub: prefsIsConfigured(datingPrefs)
                            ? prefsSummaryLine(datingPrefs)
                            : "Who you want to meet, how far, what you're looking for",
                          badge: null,
                          gate: "Sign in to set your preferences.",
                          open: () => setPrefsOpen(true),
                        },
                        {
                          id: "card",
                          icon: <PenLine className="h-4 w-4" />,
                          title:
                            user && hasDatingCard(loadDatingCardLocal(user.id))
                              ? "My dating card ✓"
                              : "My dating card",
                          sub: "Five prompts Jasper builds every date from",
                          badge: null,
                          gate: "Sign in to fill your dating card.",
                          open: () => setCardEditorOpen(true),
                        },
                      ] as {
                        id: string;
                        icon: JSX.Element;
                        title: string;
                        sub: string;
                        badge: string | null;
                        gate: string;
                        open: () => void;
                      }[]
                    ).map((tool) => (
                      <button
                        key={tool.id}
                        type="button"
                        onClick={() => {
                          if (!user) {
                            toast.error(tool.gate);
                            return;
                          }
                          setToolsOpen(false);
                          // Let the sheet finish closing before the next surface opens.
                          window.setTimeout(tool.open, 260);
                        }}
                        className="flex w-full items-center gap-3 rounded-2xl border border-border bg-card px-3 py-2.5 text-left transition-colors hover:bg-accent"
                      >
                        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-rose-500/12 text-rose-500">
                          {tool.icon}
                        </span>
                        <span className="min-w-0 flex-1">
                          <span className="block truncate text-[14px] font-bold">{tool.title}</span>
                          <span className="line-clamp-2 block text-[11.5px] leading-snug text-muted-foreground">
                            {tool.sub}
                          </span>
                        </span>
                        {tool.badge && (
                          <span className="shrink-0 whitespace-nowrap rounded-full bg-emerald-500 px-1.5 py-0.5 text-[10.5px] font-black text-white">
                            {tool.badge}
                          </span>
                        )}
                        <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
                      </button>
                    ))}
                    {prefsHasLocation(datingPrefs) && (
                      <div className="flex w-full items-center gap-3 rounded-2xl border border-border bg-card px-3 py-2.5">
                        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-emerald-500/12 text-emerald-600 dark:text-emerald-400">
                          <MapPin className="h-4 w-4" />
                        </span>
                        <span className="min-w-0 flex-1">
                          <span className="block truncate text-[14px] font-bold">Nearby only</span>
                          <span className="block truncate text-[11.5px] text-muted-foreground">
                            {nearbyOnly
                              ? nearby.length === 0
                                ? "Nobody in range yet"
                                : `${nearby.length} people inside your radius`
                              : "Everyone, anywhere"}
                          </span>
                        </span>
                        <button
                          type="button"
                          role="switch"
                          aria-checked={nearbyOnly}
                          onClick={() => {
                            const next = !nearbyOnly;
                            setNearbyOnly(next);
                            if (user) saveNearbyOnly(user.id, next);
                          }}
                          className={cn(
                            "relative h-7 w-12 shrink-0 rounded-full transition-colors",
                            nearbyOnly ? "bg-rose-500" : "bg-muted",
                          )}
                        >
                          <span
                            className={cn(
                              "absolute top-0.5 h-6 w-6 rounded-full bg-white shadow transition-transform",
                              nearbyOnly ? "translate-x-[22px]" : "translate-x-0.5",
                            )}
                          />
                        </button>
                      </div>
                    )}
                    <p className="px-1 pt-1 text-center text-[11px] leading-snug text-muted-foreground">
                      Blind dates run five minutes with cameras behind the curtain until you both reveal.
                      Preferences and your card stay private — other people only ever see a rounded distance.
                    </p>
                  </div>
                </SheetContent>
              </Sheet>
              {/* Who you want to meet + how far — the radius chips under the masthead. */}
              <div className="scrollbar-none flex gap-2 overflow-x-auto">
                <button
                  type="button"
                  onClick={() => {
                    if (!user) {
                      toast.error("Sign in to set your preferences.");
                      return;
                    }
                    setPrefsOpen(true);
                  }}
                  className={cn(
                    "flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border px-3 py-2 text-[11.5px] font-bold transition-transform active:scale-95",
                    prefsIsConfigured(datingPrefs)
                      ? "border-transparent bg-rose-500 text-white"
                      : "border-rose-300/60 bg-rose-500/10 text-rose-600 dark:text-rose-300"
                  )}
                >
                  <SlidersHorizontal className="h-3 w-3" />
                  {prefsIsConfigured(datingPrefs) ? prefsSummaryLine(datingPrefs) : "Who do you want to meet?"}
                </button>
                {prefsHasLocation(datingPrefs) && (
                  <button
                    type="button"
                    onClick={() => {
                      const next = !nearbyOnly;
                      setNearbyOnly(next);
                      if (user) saveNearbyOnly(user.id, next);
                    }}
                    className={cn(
                      "flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border px-3 py-2 text-[11.5px] font-bold transition-transform active:scale-95",
                      nearbyOnly
                        ? "border-transparent bg-rose-500 text-white"
                        : "border-rose-300/60 bg-rose-500/10 text-rose-600 dark:text-rose-300"
                    )}
                  >
                    <MapPin className="h-3 w-3" />
                    {nearbyOnly
                      ? nearby.length === 0
                        ? "Nearby · nobody in range yet"
                        : `Nearby only · ${nearby.length}`
                      : "Everyone, anywhere"}
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => setCardEditorOpen(true)}
                  className="flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border border-rose-300/60 bg-rose-500/10 px-3 py-2 text-[11.5px] font-bold text-rose-600 transition-transform active:scale-95 dark:text-rose-300"
                >
                  <PenLine className="h-3 w-3" />
                  {user && hasDatingCard(loadDatingCardLocal(user.id)) ? "Dating card ✓" : "Your dating card"}
                </button>
              </div>
              {/* iOS tokens exactly: rose tint fill (7% light · 14% dark) under a
                  30% rose hairline, the prompt in INK so it reads in both modes. */}
              <div className="overflow-hidden rounded-[20px] border border-rose-500/30 bg-rose-500/[0.07] p-4 dark:bg-rose-500/[0.14]">
                <p className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.16em] text-rose-500">
                  <Sparkles className="h-3.5 w-3.5" />
                  This hour's icebreaker
                </p>
                <p className="mt-1.5 text-[16.5px] font-extrabold leading-snug text-foreground">
                  {shownPrompt}
                </p>
                <div className="mt-3 flex flex-wrap items-center gap-2">
                  <button
                    onClick={() => {
                      if (!user) {
                        toast.error("Sign in to answer.");
                        return;
                      }
                      setAnswerDraft(datingAnswerFor(user.id, shownPrompt) ?? "");
                      setAnswerShare(false);
                      setAnswerOpen(true);
                    }}
                    className="flex items-center gap-1.5 rounded-full bg-rose-500 px-4 py-2 text-[12.5px] font-bold text-white transition-transform active:scale-95"
                  >
                    <Heart className="h-3.5 w-3.5" />
                    {user && datingAnswerFor(user.id, shownPrompt) ? "Edit answer" : "Answer it"}
                  </button>
                  <button
                    onClick={() => {
                      const pool = DATING_ICEBREAKERS.filter((p) => p !== shownPrompt);
                      setShuffledPrompt(pool[Math.floor(Math.random() * pool.length)] ?? null);
                    }}
                    className="flex items-center gap-1.5 rounded-full border border-rose-500/35 bg-rose-500/10 px-3.5 py-2 text-[12px] font-bold text-rose-600 transition-transform active:scale-95 dark:text-rose-300"
                    aria-label="Shuffle the icebreaker"
                  >
                    <Shuffle className="h-3.5 w-3.5" />
                    Shuffle
                  </button>
                  <span className="text-[11px] font-medium tabular-nums text-rose-500/80">
                    New prompt in {minutesUntilNextIcebreaker(new Date(icebreakerTick))}m
                  </span>
                </div>
                {user && !!datingAnswerFor(user.id, shownPrompt) && (
                  <p className="mt-2 flex items-center gap-1.5 text-[11px] font-semibold text-rose-500/90">
                    <Check className="h-3 w-3" />
                    Answered privately — every answer sharpens your matches
                  </p>
                )}
              </div>
              <details className="group rounded-[20px] border border-border px-4 py-3">
                <summary className="flex cursor-pointer list-none items-center gap-2 text-[13px] font-bold [&::-webkit-details-marker]:hidden">
                  <ShieldCheck className="h-4 w-4 text-emerald-600" />
                  Date safe on Whisper
                  <ChevronDown className="ml-auto h-4 w-4 text-muted-foreground transition-transform group-open:rotate-180" />
                </summary>
                <ul className="mt-2.5 space-y-1.5 border-t border-border pt-2.5">
                  {DATING_SAFETY_TIPS.map((tip) => (
                    <li key={tip} className="flex items-start gap-2 text-[12.5px] leading-snug text-muted-foreground">
                      <Check className="mt-0.5 h-3.5 w-3.5 shrink-0 text-emerald-600" />
                      {tip}
                    </li>
                  ))}
                </ul>
              </details>
            </div>
          )}

          {/* Cupid Jasper — the dating-tuned matchmaker dock behind the
              "matched" pill (pink smitten mascot, heart eyes, lifted brows). */}
          {community.id === "dating" && (
            <JasperAnalysisDock
              pillLabel="matched"
              boxTitle="Jasper Matchmaker"
              focus={DATING_MATCH_FOCUS}
              buildContext={buildDatingContext}
              emptyText="Nothing to read yet — answer this hour's icebreaker and give me some signal."
              actions={[
                { id: "openers", label: "Openers", icon: Hand, kind: "lens", focus: DATING_OPENERS_FOCUS },
                { id: "vibe", label: "My vibe", icon: Sparkles, kind: "lens", focus: DATING_VIBE_FOCUS },
                { id: "coach", label: "Answer coach", icon: PenLine, kind: "lens", focus: DATING_COACH_FOCUS },
                {
                  id: "answer",
                  label: "Answer it",
                  icon: Heart,
                  kind: "perform",
                  onPerform: () => {
                    if (!user) return;
                    setAnswerDraft(datingAnswerFor(user.id, shownPrompt) ?? "");
                    setAnswerShare(false);
                    setAnswerOpen(true);
                  },
                },
              ]}
              costume={DATING_DOCK_COSTUME}
              renderReply={(text) => {
                const parsed = parseMatchmakerReply(text);
                if (!parsed) return null;
                return (
                  <MatchmakerCards
                    parsed={parsed}
                    accent={DATING_DOCK_COSTUME.accent}
                    softAccent={DATING_DOCK_COSTUME.softAccent}
                    avatarFor={(handle) => {
                      const member = memberByHandle(handle);
                      return member ? profiles[member.userId]?.profile_image_url ?? null : null;
                    }}
                    onSayHi={(match) => {
                      const member = memberByHandle(match.username);
                      if (!member || !user) {
                        toast("Couldn't find that member in the hub right now.");
                        return;
                      }
                      markDatingPeer(user.id, member.userId);
                      navigate(`/messages?to=${member.userId}&u=${encodeURIComponent(member.username)}&kind=dating`);
                    }}
                  />
                );
              }}
            />
          )}

          {user && (
            <DatingCardEditor
              open={cardEditorOpen}
              onOpenChange={setCardEditorOpen}
              userId={user.id}
              onSaved={() => {
                setSdCardTick((t) => t + 1);
                setPrefsTick((t) => t + 1);
              }}
            />
          )}
          {user && (
            <BlindDateFinder
              open={finderOpen}
              onOpenChange={setFinderOpen}
              userId={user.id}
              username={profile?.username ?? "someone"}
              prefsTick={prefsTick + sdCardTick}
              onInvite={startSpeedDate}
              onOpenPrefs={() => setPrefsOpen(true)}
              onOpenCard={() => setCardEditorOpen(true)}
            />
          )}
          {user && (
            <DatingPrefsDialog
              open={prefsOpen}
              onOpenChange={setPrefsOpen}
              userId={user.id}
              username={profile?.username ?? null}
              onSaved={() => {
                setPrefsTick((t) => t + 1);
                void fetchNearbyDaters().then(setNearby);
              }}
            />
          )}

          {/* The structured icebreaker ANSWER — private by default; sharing is explicit. */}
          <Dialog open={answerOpen} onOpenChange={setAnswerOpen}>
            <DialogContent className="max-w-md rounded-[24px]">
              <DialogHeader>
                <DialogTitle className="text-[15px] font-extrabold">
                  Answer the icebreaker
                </DialogTitle>
              </DialogHeader>
              <div className="rounded-[18px] border border-rose-500/30 bg-rose-500/[0.07] p-3.5 dark:bg-rose-500/[0.14]">
                <p className="text-[10px] font-black uppercase tracking-[0.16em] text-rose-500">
                  This hour's icebreaker
                </p>
                <p className="mt-1 text-[15.5px] font-extrabold leading-snug">{shownPrompt}</p>
                <div className="my-2.5 h-px bg-rose-300/40" />
                <p className="text-[10px] font-black uppercase tracking-[0.16em] text-rose-500/80">
                  Your answer
                </p>
                <textarea
                  value={answerDraft}
                  onChange={(e) => setAnswerDraft(e.target.value)}
                  rows={4}
                  maxLength={280}
                  placeholder="Say it like you'd say it on a good first date…"
                  className="mt-1.5 w-full resize-none rounded-xl border border-rose-300/40 bg-white/80 p-2.5 text-[13.5px] outline-none focus:border-rose-400 dark:bg-rose-950/30"
                />
              </div>
              <div className="flex items-start gap-2.5">
                <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-rose-500/10">
                  <Lock className="h-3.5 w-3.5 text-rose-500" />
                </span>
                <p className="text-[11.5px] leading-snug text-muted-foreground">
                  <span className="font-bold text-foreground">Private by default.</span> Saved on
                  your device to sharpen who you see first — nothing posts unless you flip the
                  share toggle.
                </p>
              </div>
              <label className="flex cursor-pointer items-center justify-between rounded-xl border border-border bg-card px-3 py-2.5">
                <span>
                  <span className="block text-[12.5px] font-bold">Also share to the Dating hub</span>
                  <span className="block text-[11px] text-muted-foreground">
                    Posts your answer as a Q&A card.
                  </span>
                </span>
                <input
                  type="checkbox"
                  checked={answerShare}
                  onChange={(e) => setAnswerShare(e.target.checked)}
                  className="h-4 w-4 accent-rose-500"
                />
              </label>
              <button
                onClick={saveIcebreakerAnswer}
                disabled={!answerDraft.trim()}
                className="flex w-full items-center justify-center gap-1.5 rounded-full bg-rose-500 py-2.5 text-[13px] font-bold text-white transition-transform active:scale-95 disabled:opacity-40"
              >
                <Heart className="h-3.5 w-3.5" />
                {answerShare ? "Save & share" : "Save answer"}
              </button>
            </DialogContent>
          </Dialog>

          {/* The custom speed-date LOBBY — the starter's join screen. */}
          <Dialog open={sdLobbyOpen} onOpenChange={setSdLobbyOpen}>
            <DialogContent className="max-w-md overflow-hidden rounded-[26px] border-rose-300/50 bg-gradient-to-b from-[#FCD4DF] via-rose-50 to-pink-100 p-0 dark:border-rose-500/30 dark:from-rose-950 dark:via-[#2a0d1a] dark:to-rose-950">
              <div className="px-6 pb-6 pt-7 text-center">
                <img
                  src="/dating/whisper-dating-logo.png"
                  alt="Whisper Dating"
                  className="mx-auto h-12 w-auto"
                />
                <p className="mt-3 text-[10px] font-black uppercase tracking-[0.24em] text-rose-500">
                  Speed date
                </p>
                <h2 className="mt-1 text-[26px] font-black leading-tight">
                  Five minutes,
                  <br />
                  face to face.
                </h2>
                <p className="mx-auto mt-1.5 max-w-[300px] text-[12.5px] leading-snug text-muted-foreground">
                  Send the link to your date — Jasper listens in and judges your compatibility
                  from both dating cards and the conversation.
                </p>
                <div className="mt-4 rounded-2xl border border-rose-300/50 bg-white/75 p-3 text-left dark:bg-rose-950/40">
                  <div className="flex items-center gap-2">
                    <Link2 className="h-3.5 w-3.5 shrink-0 text-rose-500" />
                    <span className="min-w-0 flex-1 truncate text-[12px] font-semibold">
                      mydailywhisper.com/meet/{sdCode}
                    </span>
                    <button
                      onClick={() => {
                        try {
                          void navigator.clipboard.writeText(
                            `https://mydailywhisper.com/meet/${sdCode}?sd=1`
                          );
                          setSdCopied(true);
                        } catch {
                          setSdCopied(false);
                        }
                      }}
                      className="shrink-0 rounded-full bg-rose-500 px-2.5 py-1 text-[11px] font-bold text-white active:scale-95"
                    >
                      {sdCopied ? "Copied ✓" : "Copy"}
                    </button>
                  </div>
                  <p className="mt-1.5 text-[10.5px] text-muted-foreground">
                    They'll get the speed-date welcome the moment they open it.
                  </p>
                </div>
                <div className="mt-3 rounded-2xl border border-rose-300/40 bg-white/55 p-3 text-left dark:bg-rose-950/30">
                  <div className="flex items-center justify-between">
                    <p className="text-[9.5px] font-black uppercase tracking-[0.16em] text-rose-500">
                      Your dating card
                    </p>
                    <p className="text-[10.5px] font-semibold text-muted-foreground">
                      {sdAnswered} of {DATING_CARD_QUESTIONS.length} answered
                    </p>
                  </div>
                  <div className="mt-2 flex flex-wrap gap-1.5">
                    {DATING_CARD_QUESTIONS.map((q) => {
                      const done = !!(sdCard[q.id] ?? "").trim();
                      return (
                        <span
                          key={q.id}
                          className={
                            done
                              ? "rounded-full bg-rose-500 px-2.5 py-1 text-[10.5px] font-bold text-white"
                              : "rounded-full border border-rose-300/50 bg-white/60 px-2.5 py-1 text-[10.5px] font-bold text-rose-500 dark:bg-rose-950/40"
                          }
                        >
                          {done ? "✓ " : ""}
                          {SD_SHORT_LABELS[q.id] ?? q.label}
                        </span>
                      );
                    })}
                  </div>
                  <button
                    onClick={() => setCardEditorOpen(true)}
                    className="mt-2.5 flex items-center gap-1.5 rounded-full border border-rose-500/35 bg-rose-500/10 px-3 py-1.5 text-[11.5px] font-bold text-rose-600 active:scale-95 dark:text-rose-300"
                  >
                    <PenLine className="h-3 w-3" />
                    {sdAnswered > 0 ? "Edit my card" : "Fill my card"}
                  </button>
                </div>
                <button
                  onClick={enterSpeedDate}
                  className="mt-4 flex w-full items-center justify-center gap-2 rounded-full bg-gradient-to-r from-rose-500 to-pink-500 py-3 text-[15px] font-black text-white shadow-lg shadow-rose-500/30 transition-transform active:scale-95"
                >
                  <Video className="h-4 w-4" />
                  Enter the date 💘
                </button>
              </div>
            </DialogContent>
          </Dialog>

          {/* Member / post counts */}
          <div className="flex items-center gap-2 px-5 py-3 text-sm font-semibold">
            <span>{compactCount(memberCount)} {memberCount === 1 ? "member" : "members"}</span>
            {matching.length > 0 && (
              <>
                <span className="text-muted-foreground">·</span>
                <span>
                  {compactCount(matching.length)}{" "}
                  {matching.length === 1 ? "post" : "posts"}
                </span>
              </>
            )}
          </div>

          {/* Post-to-community pill */}
          <button
            onClick={() => setComposing(true)}
            className="flex w-full items-center gap-3 border-t border-border px-5 py-3.5 text-left transition-colors hover:bg-secondary/40"
          >
            <Avatar
              url={profile?.profile_image_url}
              name={profile?.username ?? "you"}
              size={36}
            />
            <span className="text-sm text-muted-foreground">
              Post to {community.name}…
            </span>
          </button>

          {/* Sort row */}
          <div className="flex items-center border-t border-border px-5 py-2.5">
            <DropdownMenu>
              <DropdownMenuTrigger className="flex items-center gap-1 text-sm font-semibold outline-none">
                {SORT_LABELS[sortMode]}
                <ChevronDown className="h-3.5 w-3.5 text-muted-foreground" />
              </DropdownMenuTrigger>
              <DropdownMenuContent align="start" className="w-40">
                {(Object.keys(SORT_LABELS) as SortMode[])
                  .filter((mode) => mode !== "match" || community.id === "dating")
                  .map((mode) => (
                    <DropdownMenuItem key={mode} onClick={() => setSortMode(mode)}>
                      {SORT_LABELS[mode]}
                      {sortMode === mode && <Check className="ml-auto h-4 w-4" />}
                    </DropdownMenuItem>
                  ))}
              </DropdownMenuContent>
            </DropdownMenu>
          </div>

          {community.id === "dating" && sortMode === "match" && (
            <div className="px-5 pb-2.5">
              <p className="flex items-center gap-1.5 rounded-xl bg-rose-500/10 px-3 py-2 text-[11.5px] font-semibold text-rose-500">
                {myDatingAnswers.length > 0 ? (
                  <Heart className="h-3 w-3 shrink-0 fill-current" />
                ) : (
                  <Sparkles className="h-3 w-3 shrink-0" />
                )}
                {/* One line, always — shorter copy + truncate instead of wrapping. */}
                <span className="min-w-0 truncate">
                  {myDatingAnswers.length > 0
                    ? "Sorted for you · closest answers first"
                    : "Answer the icebreaker to sort by closeness"}
                </span>
              </p>
            </div>
          )}

          <div className="border-t border-border">
            {feedQuery.isLoading && (
              <p className="px-6 py-16 text-center text-sm text-muted-foreground">
                Loading…
              </p>
            )}

            {!feedQuery.isLoading && !feedQuery.isError && !feedQuery.hasNextPage && posts.length === 0 && (
              <p className="px-6 py-16 text-center text-sm text-muted-foreground">
                {community.id === "dating"
                  ? "Nobody's made the first move yet — answer this hour's icebreaker and break the ice."
                  : `Be the first — tap “Post to ${community.name}” above to start the conversation.`}
              </p>
            )}

            {posts.map((post) => {
              const authorHandle =
                profiles[post.user_id]?.username ?? post.username ?? "";
              const sayHi =
                community.id === "dating" &&
                !!user &&
                post.user_id !== user.id &&
                !!authorHandle;
              // Icebreaker Q&A treatment — when a dating post ANSWERS a known
              // prompt (prefilled by "Answer it"), the prompt lifts out of the
              // caption into a styled rose question card above the post.
              const promptSplit = (() => {
                if (community.id !== "dating") return null;
                const cap = post.caption ?? "";
                const nl = cap.indexOf("\n");
                if (nl <= 0) return null;
                const firstLine = cap.slice(0, nl).trim();
                if (!DATING_ICEBREAKERS.includes(firstLine)) return null;
                const rest = cap.slice(nl + 1).trim();
                if (!rest) return null;
                return { prompt: firstLine, post: { ...post, caption: rest } };
              })();
              const shownPost = promptSplit?.post ?? post;
              const promptBanner = promptSplit ? (
                <div className="px-4 pt-3">
                  <div className="rounded-2xl border border-rose-500/30 bg-rose-500/[0.07] px-3.5 py-2.5 dark:bg-rose-500/[0.14]">
                    <p className="flex items-center gap-1.5 text-[9.5px] font-black uppercase tracking-[0.14em] text-rose-500">
                      <Sparkles className="h-3 w-3" />
                      Icebreaker answer
                    </p>
                    <p className="mt-0.5 text-[13px] font-bold leading-snug">
                      {promptSplit.prompt}
                    </p>
                  </div>
                </div>
              ) : null;
              const whyLine = community.id === "dating" ? matchWhyLine(post) : null;
              return jasperGlow ? (
                // White post, Jasper glow — the ember aura wraps each post
                // inside the Circle without repainting the card itself.
                <div key={post.id} className="px-3 py-2.5 first:pt-3 last:pb-4">
                  <div className="overflow-hidden rounded-[22px] border border-orange-400/35 bg-background shadow-[0_14px_38px_rgba(249,115,22,0.18),0_3px_12px_rgba(249,115,22,0.10)]">
                    {promptBanner}
                    <PostCard
                      post={shownPost}
                      author={profiles[post.user_id]}
                      liked={likedSet.has(post.id)}
                      reposted={repostedSet.has(post.id)}
                      bookmarked={bookmarkedSet.has(post.id)}
                      specialReact={communityReact(community)}
                    />
                  </div>
                </div>
              ) : (
                <div key={post.id}>
                  {promptBanner}
                  <PostCard
                    post={shownPost}
                    author={profiles[post.user_id]}
                    liked={likedSet.has(post.id)}
                    reposted={repostedSet.has(post.id)}
                    bookmarked={bookmarkedSet.has(post.id)}
                    specialReact={communityReact(community)}
                  />
                  {whyLine && (
                    <p className="flex items-center gap-1.5 px-4 pb-1.5 text-[11px] font-semibold text-rose-500">
                      <Heart className="h-3 w-3 fill-current" />
                      <span className="truncate">{whyLine}</span>
                    </p>
                  )}
                  {sayHi && (
                    <div className="flex justify-end border-b border-border px-4 py-2">
                      <Link
                        to={`/messages?to=${post.user_id}&u=${authorHandle}&kind=dating`}
                        onClick={() => {
                          // Say-hi chats land in the 💘 Dating inbox filter.
                          if (user) markDatingPeer(user.id, post.user_id);
                        }}
                        className="flex items-center gap-1.5 rounded-full border border-rose-500/35 bg-rose-500/10 px-3 py-1.5 text-[12px] font-bold text-rose-600 transition-transform active:scale-95 dark:text-rose-300"
                      >
                        <Hand className="h-3.5 w-3.5" />
                        Say hi to @{authorHandle}
                      </Link>
                    </div>
                  )}
                </div>
              );
            })}
            <ConversationListEnd content="posts" active={feedQuery.visible} hasMore={feedQuery.hasNextPage}
              busy={feedQuery.isFetching} loading={feedQuery.isFetchingNextPage} failed={feedQuery.isError}
              onLoad={() => feedQuery.isFetchNextPageError || !feedQuery.isError ? feedQuery.fetchNextPage({ cancelRefetch: false }) : feedQuery.refetch()} />
          </div>
          </>
          )}
        </div>
      </div>

      <ComposerModal
        open={composing}
        onOpenChange={setComposing}
        mode="thread"
        initialTopic={community.id}
      />

      {/* Owner invite sheet — private groups only. */}
      <Dialog open={inviteOpen} onOpenChange={setInviteOpen}>
        <DialogContent className="max-w-[400px] rounded-[24px]">
          <DialogHeader>
            <DialogTitle>Invite to {community.name}</DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <div className="flex items-center gap-2">
              <Input
                value={inviteName}
                onChange={(e) => setInviteName(e.target.value)}
                placeholder="@username"
                onKeyDown={(e) => {
                  if (e.key === "Enter" && inviteName.trim()) inviteMutation.mutate();
                }}
              />
              <button
                onClick={() => inviteMutation.mutate()}
                disabled={inviteMutation.isPending || !inviteName.trim()}
                className="flex h-10 shrink-0 items-center gap-1.5 rounded-full bg-foreground px-4 text-[13px] font-bold text-background transition-transform active:scale-95 disabled:opacity-50"
              >
                {inviteMutation.isPending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <UserPlus className="h-4 w-4" />
                )}
                Invite
              </button>
            </div>
            <div className="max-h-56 space-y-1 overflow-y-auto">
              {(membersQuery.data ?? []).map((m) => (
                <div
                  key={m.user_id}
                  className="flex items-center gap-2.5 rounded-xl px-2 py-1.5"
                >
                  <Avatar name={m.username} size={30} />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[13px] font-semibold">
                      @{m.username}
                    </span>
                    <span className="block text-[11px] text-muted-foreground">
                      {m.role === "owner"
                        ? "Owner"
                        : m.status === "invited"
                          ? "Invited — waiting"
                          : "Member"}
                    </span>
                  </span>
                  {isGroupOwner && m.user_id !== user?.id && (
                    <button
                      onClick={() => {
                        void removeGroupRow(id, m.user_id).then(() =>
                          queryClient.invalidateQueries({ queryKey: ["group-members", user?.id, id] })
                        );
                      }}
                      className="rounded-full px-2.5 py-1 text-[11.5px] font-bold text-destructive transition-colors hover:bg-destructive/10"
                    >
                      Remove
                    </button>
                  )}
                </div>
              ))}
              {(membersQuery.data ?? []).length === 0 && (
                <p className="py-4 text-center text-[12.5px] text-muted-foreground">
                  Nobody here yet — invite your first member.
                </p>
              )}
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
