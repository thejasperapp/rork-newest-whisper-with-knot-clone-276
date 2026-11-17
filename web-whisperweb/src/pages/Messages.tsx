import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { useConversationHistory } from "@/hooks/useConversationHistory";
import { useConversationSummaries } from "@/hooks/useConversationSummaries";
import { ConversationListEnd } from "@/components/ConversationListEnd";
import { MessageHistoryStatus } from "@/components/MessageHistoryStatus";
import { invalidateHistorySnapshot } from "@/lib/conversationHistory";
import type { MessagePage, MessageCursor } from "@/lib/messageHistory";
import type { GroupSummaryPage } from "@/lib/groupSummaries";
import type { InfiniteData } from "@tanstack/react-query";
import { keepPreviousData, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  Send,
  MessageCircle,
  Smile,
  ImageIcon,
  Heart,
  X,
  Sparkles,
  Wand2,
  Layers,
  ShieldCheck,
  MapPin,
  Loader2,
  UtensilsCrossed,
  Trash2,
  Pencil,
  CalendarDays,
  Search as SearchIcon,
  Video,
  Phone,
  FileText,
  ChevronRight,
  ArrowUp as ArrowUpIcon,
  Link2 as Link2Icon,
  Plus as PlusIcon,
  Play as PlayIcon,
  ArrowUpDown,
  Clock as ClockIcon,
  MailOpen,
  ArrowDownToLine,
  Reply,
  Copy,
  Pin,
  Undo2,
  Flag,
} from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { waveCoverUrl } from "@/lib/postMeta";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { toast } from "sonner";
import { EmberMascot } from "@/components/EmberMascot";
import { isDatingPeer, markDatingPeer, toggleDatingPeer } from "@/lib/datingInbox";
import { MatchCelebration } from "@/components/MatchCelebration";
import {
  buildMatchRequest,
  buildMatched,
  decodeMatchToken,
  markMatchCelebrationSeen,
  matchCelebrationSeen,
  matchPreviewLine,
} from "@/lib/datingMatch";
import {
  decodeSecondDate,
  encodeDateConfirm,
  isSecondDateToken,
  matchExpiryState,
  secondDatePreviewLine,
  type SecondDateInvite,
} from "@/lib/secondDate";

import { Avatar } from "@/components/Avatar";
import { LinkPreviewCard, LinkedText } from "@/components/LinkPreviewCard";
import { firstLinkUrl } from "@/lib/linkPreview";
import { NewMessageDialog } from "@/components/NewMessageDialog";
import { Stories } from "@/components/Stories";
import { FloatingHeader, FloatingButton } from "@/components/FloatingHeader";
import { JasperSpark } from "@/components/JasperSpark";
import { knotCommandPrompt } from "@/lib/knotCommand";
import { cleanPostCaption, extractSharedPost, type SharedPostPayload } from "@/lib/postShare";
import { decodeSharedCommunity, SHARED_COMMUNITY_PREFIX } from "@/lib/communityShare";
import type { Community } from "@/lib/communities";
import {
  ARTICLE_EMBED_PREFIX,
  FILM_EMBED_PREFIX,
  decodePlanQuiz,
  decodePlanQuizAnswers,
  parseContentEmbeds,
  type ArticleEmbedPayload,
  type FilmEmbedPayload,
  type PlanQuizAnswersPayload,
  type PlanQuizPayload,
} from "@/lib/contentEmbeds";
import { jasperStickerName } from "@/lib/storyStickers";
import {
  ArticleEmbedCard,
  FilmEmbedCard,
  PlanQuizAnswersCard,
  PlanQuizCard,
} from "@/components/ContentEmbedCards";
import { decodeSharedProfile, type SharedProfilePayload } from "@/lib/profileShare";
import {
  decodeCalendarEmbed,
  EVENT_TYPE_COLORS,
  EVENT_TYPE_LABELS,
  type CalendarEmbedPayload,
  type CalendarEventType,
} from "@/lib/calendar";
import { DmEmbedCard, isDmEmbed } from "@/components/DmEmbedCard";
import { JasperAnalysisDock } from "@/components/JasperAnalysisDock";
import { KnotPortrait } from "@/components/Knot";
import { ChatCreativeTool, type ChatCreativeMode } from "@/components/ChatCreativeTool";
import { ChatMeetScheduler } from "@/components/ChatMeetScheduler";
import { EmberDmCard } from "@/components/EmberDmCard";
import { GiphyPicker } from "@/components/GiphyPicker";
import { GroupChatsSection } from "@/components/GroupChats";
import { MessageActions } from "@/components/MessageActions";
import { MessageReportDialog, type ReportMessageTarget } from "@/components/MessageReportDialog";
import { ForwardMessageDialog } from "@/components/ForwardMessageDialog";
import { useMessageReactions } from "@/hooks/useMessageReactions";
import { useMessageTools } from "@/hooks/useMessageTools";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { SharedStoryCard } from "@/components/SharedStoryCard";
import { ChatMessageBoundary } from "@/components/ChatMessageBoundary";
import { sharedStoryID } from "@/lib/sharedStory";
import { buildGroupReplyBody, quoteLabelFor, quoteCardKind, splitGroupReply } from "@/lib/groupChats";
import { ChatQuoteMiniCard } from "@/components/ChatQuoteMiniCard";
import { UserBadges } from "@/components/UserBadges";
import { cn } from "@/lib/utils";
import { clockTime, timeAgo } from "@/lib/format";
import { factCheck, emberRecipe, EMBER_ENABLED, type Verdict } from "@/lib/ember";
import {
  createMeeting,
  encodeCallInvite,
  decodeCallInvite,
  isCallSignal,
  isMeetingUuid,
  meetingIdFromCode,
} from "@/lib/meetings";
import {
  buildEmberHealthContext,
  emberEngineRespond,
  type BrainChatMessage,
} from "@/lib/emberBrain";
import { decodeRecipe, encodeRecipe, type RecipePayload } from "@/lib/recipe";
import { encodeGrocery } from "@/lib/grocery";
import { RecipeCard } from "@/components/RecipeCard";
import { MeetingNotesScreen, NOTES_TRANSCRIPT_MARKER } from "@/components/MeetingNotesScreen";
import {
  buildNearbyPayload,
  decodeEmberAnswer,
  decodeFactCheck,
  decodeMap,
  encodeEmberAnswer,
  encodeFactCheck,
  encodeMap,
  isEmberEmbed,
} from "@/lib/dmEmber";
import {
  fetchFollowers,
  fetchFollowing,
  fetchLiarBadges,
  fetchProfilesByIds,
  fetchStories,
  markThreadRead,
  sendMessage,
} from "@/lib/api";
import {
  isConversationHidden,
  markConversationDeleted,
} from "@/lib/deletedConversations";
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
import { supabase } from "@/lib/supabase";
import { isDmBlocked } from "@/lib/brands";
import { fetchPresence, heartbeatPresence, isActiveNow, presenceLabel } from "@/lib/presence";
import { useAuth } from "@/hooks/useAuth";
import { ChatMeetCard } from "@/components/ChatMeetCard";
import { TeamsInvitationCard } from "@/components/TeamsInvitationCard";
import { teamsCardCandidate } from "@/lib/teamsInvitation";
import { GroupThemeSurface } from "@/components/GroupThemeSurface";
import { PersonalChatSettings } from "@/components/PersonalChatSettings";
import { ConversationDetails } from "@/components/ConversationDetails";
import { useConversationNickname } from "@/hooks/useConversationNickname";
import { usePersonalChatAppearance } from "@/hooks/usePersonalChatAppearance";
import { NotesEntry } from "@/components/NotesEntry";
import { NotesAppIcon } from "@/components/NotesAppIcon";
import { notesDocumentCardCandidate, notesMessageSummary } from "@/lib/notesDocumentCard";
import { collapseMeetMessages } from "@/lib/meetMessageIdentity";
import type { WhisperConversation, WhisperMessage } from "@/lib/types";

/**
 * The iOS inbox's filter chips, exactly: All · Primary (people you follow
 * who follow you back) · General (everyone else) · Coaches · 💘 Dating.
 * Unread is a SORT on iOS ("Unread first"), not a chip — mirrored below.
 */
type InboxFilter = "all" | "primary" | "general" | "coaches" | "dating";
type InboxSort = "recent" | "unread" | "oldest";

const INBOX_FILTERS: { id: InboxFilter; label: string }[] = [
  { id: "all", label: "All" },
  { id: "primary", label: "Primary" },
  { id: "general", label: "General" },
  { id: "coaches", label: "Coaches" },
  { id: "dating", label: "💘 Dating" },
];

const INBOX_SORTS: { id: InboxSort; label: string; icon: typeof ClockIcon }[] = [
  { id: "recent", label: "Most recent", icon: ClockIcon },
  { id: "unread", label: "Unread first", icon: MailOpen },
  { id: "oldest", label: "Oldest first", icon: ArrowDownToLine },
];

/** Cupid Knot's date tools — prefill /jasper with dating-tuned asks.
 *  Shown above the composer in chats marked 💘 (mirrors iOS). */
/**
 * Round 77 — the second-date scheduler card (mirrors iOS `WhisperSecondDateCard`):
 * slot · plan · Accept (partner) or Join on Whisper Meet once confirmed.
 */
function SecondDateCard({
  invite,
  confirm,
  mine,
  partnerName,
  onAccept,
  onJoin,
}: {
  invite: SecondDateInvite;
  confirm: boolean;
  mine: boolean;
  partnerName: string;
  onAccept: () => void;
  onJoin: (code: string) => void;
}) {
  const [accepted, setAccepted] = useState<boolean>(false);
  const when = new Date(invite.slot);
  const whenLabel = Number.isNaN(when.getTime())
    ? invite.slot
    : when.toLocaleString(undefined, { weekday: "long", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
  const confirmed = confirm || accepted;
  return (
    <div className="w-[300px] max-w-full rounded-[18px] border border-rose-400/30 bg-rose-500/10 p-3.5">
      <div className="flex items-center gap-1.5 text-[10.5px] font-extrabold uppercase tracking-[0.1em] text-rose-500">
        {confirmed ? "Second date · confirmed" : "Second date · proposed"}
      </div>
      <div className="mt-1 text-[17px] font-extrabold leading-tight text-foreground">{whenLabel}</div>
      <div className="mt-0.5 text-[13px] text-muted-foreground">{invite.title}</div>
      <div className="mt-2.5 flex flex-wrap items-center gap-2">
        {confirmed ? (
          <>
            <button
              type="button"
              onClick={() => onJoin(invite.meetCode)}
              className="rounded-full bg-rose-500 px-3 py-1.5 text-[12.5px] font-extrabold text-white transition-transform active:scale-95"
            >
              Join on Whisper Meet
            </button>
            <span className="text-[11.5px] font-semibold text-muted-foreground">On both calendars 💘</span>
          </>
        ) : !mine ? (
          <>
            <button
              type="button"
              onClick={() => {
                setAccepted(true);
                onAccept();
              }}
              className="rounded-full bg-rose-500 px-3.5 py-1.5 text-[12.5px] font-extrabold text-white transition-transform active:scale-95"
            >
              Accept 💘
            </button>
            <span className="text-[11.5px] text-muted-foreground">Adds it to both calendars</span>
          </>
        ) : (
          <span className="text-[11.5px] font-semibold text-muted-foreground">Waiting for @{partnerName} to accept…</span>
        )}
      </div>
    </div>
  );
}

const DATING_CHAT_TOOLS: { label: string; fill: string }[] = [
  { label: "💡 Date ideas", fill: "/knot give us 3 date ideas based on this chat — specific and fun, one line each" },
  { label: "🗓 Plan a date", fill: "/knot help us plan our next date — read this chat and suggest a day, a time, and the kind of place" },
  { label: "✍️ Reply coach", fill: "/knot coach my next reply in this chat — 2 options, warm and specific, no cringe" },
  { label: "🚩 Vibe check", fill: "/knot vibe check this chat — how's it going, any green or red flags? be honest and kind" },
];

import { conversationKey } from "@/lib/conversationIdentity";

export default function Messages() {
  const { user, profile } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [searchParams, setSearchParams] = useSearchParams();
  const [activeId, setActiveId] = useState<string | null>(null);
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const draftKey = `${user?.id ?? "signed-out"}:${activeId ?? "none"}`;
  const draft = drafts[draftKey] ?? "";
  const setDraft: React.Dispatch<React.SetStateAction<string>> = (value) => {
    setDrafts((previous) => ({ ...previous, [draftKey]: typeof value === "function" ? value(previous[draftKey] ?? "") : value }));
  };
  useEffect(() => { setDrafts({}); setActiveId(null); }, [user?.id]);
  const [filter, setFilter] = useState<InboxFilter>("all");
  const [sort, setSort] = useState<InboxSort>("recent");
  const [inboxQuery, setInboxQuery] = useState<string>("");
  const [newMessage, setNewMessage] = useState<boolean>(false);
  const [groupActive, setGroupActive] = useState<boolean>(false);
  const [conversationHost, setConversationHost] = useState<HTMLDivElement | null>(null);
  useEffect(() => { if (activeId || groupActive) window.scrollTo({ top: 0 }); }, [activeId, groupActive]);
  // Bumped whenever a conversation is hidden/unhidden so the inbox re-filters
  // against the latest localStorage state.
  const [deletedVersion, setDeletedVersion] = useState<number>(0);
  const [pendingDelete, setPendingDelete] =
    useState<WhisperConversation | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  // Direct/dating summaries are independent of group fan-out and the open
  // thread's 100/50 history. Never rebuild this inbox from a shared raw window.
  const convosQuery = useConversationSummaries(user?.id);

  // Notes / stories row at the top of the inbox (mirrors the iOS inbox).
  const storiesQuery = useQuery({
    queryKey: ["stories", user?.id],
    queryFn: fetchStories,
    enabled: !!user,
  });
  const stories = storiesQuery.data ?? [];
  const storyAuthorIds = stories.map((s) => s.user_id);
  const storyProfilesQuery = useQuery({
    queryKey: ["profiles", [...storyAuthorIds].sort()],
    queryFn: () => fetchProfilesByIds(storyAuthorIds),
    enabled: storyAuthorIds.length > 0,
  });
  const storyProfiles = storyProfilesQuery.data ?? {};

  // Hide locally-deleted conversations (until a newer message arrives). The
  // `deletedVersion` dependency forces a re-read after a delete.
  const conversations = convosQuery.conversations.filter(
    (c) => !isConversationHidden(conversationKey(c), c.lastDate)
  );
  void deletedVersion;
  // Primary = mutual follows (the iOS inbox's rule); General = everyone else.
  const followingQuery = useQuery({
    queryKey: ["inbox-following", user?.id],
    queryFn: () => fetchFollowing(user!.id),
    enabled: !!user,
    staleTime: 60_000,
  });
  const followersQuery = useQuery({
    queryKey: ["inbox-followers", user?.id],
    queryFn: () => fetchFollowers(user!.id),
    enabled: !!user,
    staleTime: 60_000,
  });
  const mutualIds = useMemo(() => {
    const following = new Set((followingQuery.data ?? []).map((f) => f.userId));
    const mutual = new Set<string>();
    for (const f of followersQuery.data ?? []) {
      if (following.has(f.userId)) mutual.add(f.userId);
    }
    return mutual;
  }, [followingQuery.data, followersQuery.data]);

  // Filter chips + sort + inbox search — the iOS inbox's exact buckets.
  const inboxNeedle = inboxQuery.trim().toLowerCase();
  const matchesFilter = (c: WhisperConversation, f: InboxFilter): boolean => {
    if (f === "primary") return c.kind !== "dating" && mutualIds.has(c.otherUserId);
    if (f === "general") return c.kind !== "dating" && !mutualIds.has(c.otherUserId);
    if (f === "coaches") return c.kind !== "dating" && !!c.otherProfile?.is_coach;
    if (f === "dating") return c.kind === "dating";
    return true;
  };
  const lastMs = (c: WhisperConversation): number =>
    c.lastDate ? new Date(c.lastDate).getTime() || 0 : 0;
  const visibleConversations = conversations
    .filter((c) => {
      if (!matchesFilter(c, filter)) return false;
      if (inboxNeedle.length > 0) {
        const name = (c.otherProfile?.display_name ?? "").toLowerCase();
        const uname = c.otherUsername.toLowerCase();
        const last = (c.lastMessage ?? "").toLowerCase();
        if (!name.includes(inboxNeedle) && !uname.includes(inboxNeedle) && !last.includes(inboxNeedle))
          return false;
      }
      return true;
    })
    .sort((a, b) => {
      if (sort === "oldest") return lastMs(a) - lastMs(b);
      if (sort === "unread" && (a.unread > 0) !== (b.unread > 0)) return a.unread > 0 ? -1 : 1;
      return lastMs(b) - lastMs(a);
    });
  /** Unread threads inside a chip's bucket — the iOS chips carry the same counts. */
  const unreadFor = (f: InboxFilter): number =>
    conversations.filter((c) => c.unread > 0 && matchesFilter(c, f)).length;

  const confirmDelete = (): void => {
    const target = pendingDelete;
    if (!target) return;
    markConversationDeleted(conversationKey(target), target.lastDate);
    if (activeId === conversationKey(target)) closeThread();
    setPendingDelete(null);
    setDeletedVersion((v) => v + 1);
    toast.success("Conversation deleted");
  };

  // "New message" deep-link: /messages?to=<userId>&u=<username>. Open the
  // existing thread if there is one, otherwise spin up an empty synthetic
  // conversation so the user can fire off the first message.
  const toId = searchParams.get("to");
  const toName = searchParams.get("u");
  const toKind = searchParams.get("kind") === "dating" ? "dating" : "direct";
  const toKey = toId ? conversationKey({ otherUserId: toId, kind: toKind }) : null;
  const newChatProfileQuery = useQuery({
    queryKey: ["profile-by-id", user?.id, toId],
    queryFn: () => fetchProfilesByIds([toId!]),
    enabled: !!toId && !conversations.some((c) => c.otherUserId === toId),
  });

  useEffect(() => {
    if (toKey) setActiveId(toKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [toKey]);

  const existingActive =
    conversations.find((c) => conversationKey(c) === activeId) ?? null;
  // Retain only the selected header if a refreshed page boundary moves it out
  // of the inbox. Message access/content still comes from owner-scoped history.
  const selectedHeader = useRef<{ owner: string; key: string; conversation: WhisperConversation } | null>(null);
  useEffect(() => {
    if (!user || !activeId) { selectedHeader.current = null; return; }
    if (existingActive) selectedHeader.current = { owner: user.id, key: activeId,
      conversation: { ...existingActive, messages: [], lastMessage: "", lastDate: null, unread: 0 } };
  }, [user?.id, activeId, existingActive]);
  const retainedActive = selectedHeader.current?.owner === user?.id && selectedHeader.current?.key === activeId
    ? selectedHeader.current.conversation : null;
  const pendingProfile =
    toId && activeId === toKey ? newChatProfileQuery.data?.[toId] ?? null : null;
  const syntheticActive: WhisperConversation | null =
    !existingActive && activeId && activeId === toKey
      ? {
          kind: toKind,
          otherUserId: toId!,
          otherUsername:
            pendingProfile?.username ?? toName ?? "user",
          otherProfile: pendingProfile,
          lastMessage: "",
          lastDate: null,
          lastFromMe: false,
          unread: 0,
          messages: [],
        }
      : null;
  const active = existingActive ?? syntheticActive ?? retainedActive;

  const closeThread = (): void => {
    setActiveId(null);
    if (toId) setSearchParams({}, { replace: true });
  };
  const totalUnread = conversations.filter((c) => c.unread > 0).length;

  const convoUsernames = conversations.map((c) => c.otherUsername);
  const liarQuery = useQuery({
    queryKey: ["liar-badges", [...convoUsernames].sort()],
    queryFn: () => fetchLiarBadges(convoUsernames),
    enabled: convoUsernames.length > 0,
  });
  const liarBadges = liarQuery.data ?? {};

  // Presence — green "Active now" dots in the inbox + thread header, and my
  // own heartbeat so others see me online (parity with the iOS inbox).
  const convoIds = conversations.map((c) => c.otherUserId);
  const presenceQuery = useQuery({
    queryKey: ["presence", convoIds],
    queryFn: () => fetchPresence(convoIds),
    enabled: convoIds.length > 0,
    refetchInterval: 30_000,
  });
  const presence = presenceQuery.data ?? {};

  useEffect(() => {
    if (!user) return;
    void heartbeatPresence(user.id);
    const timer = window.setInterval(() => void heartbeatPresence(user.id), 60_000);
    return () => window.clearInterval(timer);
  }, [user]);

  // Realtime: refresh threads whenever a message touching this user lands.
  useEffect(() => {
    if (!user) return;
    const channel = supabase
      .channel("whisper-dms")
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "whisper_messages" },
        (payload) => {
          const row = payload.new as { from_user_id: string; to_user_id: string };
          if (row.from_user_id === user.id || row.to_user_id === user.id) {
            invalidateHistorySnapshot();
            queryClient.invalidateQueries({ queryKey: ["conversations"] });
            void queryClient.invalidateQueries({ queryKey: ["group-wire", user.id] });
          }
        }
      )
      .on("postgres_changes", { event: "UPDATE", schema: "public", table: "whisper_messages" }, (payload) => {
        const row = payload.new as WhisperMessage;
        if (row.from_user_id === user.id || row.to_user_id === user.id) {
          invalidateHistorySnapshot();
          void queryClient.invalidateQueries({ queryKey: ["conversations", user.id] });
          void queryClient.invalidateQueries({ queryKey: ["group-wire", user.id] });
        }
      })
      .on("postgres_changes", { event: "DELETE", schema: "public", table: "whisper_messages" }, (payload) => {
        invalidateHistorySnapshot();
        const deletedID = payload.old.id as string | undefined;
        if (deletedID) queryClient.setQueriesData<InfiniteData<MessagePage, MessageCursor | null>>(
          { queryKey: ["conversations", user.id, "history"] },
          data => data ? { ...data, pages: data.pages.map(page => ({ ...page, messages: page.messages.filter(message => message.id !== deletedID) })) } : data,
        );
        if (deletedID) {
          queryClient.setQueryData<InfiniteData<GroupSummaryPage, MessageCursor | null>>(["group-wire", user.id, "summaries"], data => data ? {
            ...data, pages: data.pages.map(page => ({ ...page, groups: page.groups.filter(row => row.last_message_id !== deletedID) })),
          } : data);
          queryClient.setQueryData<WhisperMessage[]>(["group-wire", user.id], rows => rows?.filter(row => row.id !== deletedID));
          queryClient.setQueriesData<InfiniteData<MessagePage, MessageCursor | null>>(
            { queryKey: ["group-wire", user.id, "history"] },
            data => data ? { ...data, pages: data.pages.map(page => ({ ...page, messages: page.messages.filter(message => message.id !== deletedID) })) } : data,
          );
        }
        void queryClient.invalidateQueries({ queryKey: ["conversations", user.id] });
        void queryClient.invalidateQueries({ queryKey: ["group-wire", user.id] });
      })
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [user, queryClient]);

  useEffect(() => {
    if (active && user && active.unread > 0) {
      void markThreadRead(user.id, active.otherUserId, active.kind).then(() =>
        queryClient.invalidateQueries({ queryKey: ["conversations"] })
      );
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeId]);

  const beginSendOperation = useChatOperationGuard(user?.id ?? "", active ? conversationKey(active) : "");
  const sendBody = async (body: string, assertCurrent: () => void = beginSendOperation()): Promise<boolean> => {
    const trimmed = body.trim();
    if (!trimmed || !active || !user) return false;
    try {
      assertCurrent();
      // Sponsorship scam protection: a brand that denied this creator's
      // application is permanently blocked from DMing them.
      if (await isDmBlocked(user.id, active.otherUserId)) {
        toast.error("Messaging is unavailable — your brand declined this creator's sponsorship application.");
        return false;
      }
      assertCurrent();
      await sendMessage(
        user.id,
        profile?.username ?? "you",
        active.otherUserId,
        active.otherUsername,
        trimmed,
        assertCurrent,
        active.kind ?? "direct"
      );
    } catch (error) {
      try { assertCurrent(); } catch { return false; }
      const denied = typeof error === "object" && error !== null && "code" in error && error.code === "42501";
      toast.error(denied ? "Message not delivered. Contact permission, a block, or a messaging restriction may prevent this send. A previous message alone is not permission." : "Couldn't send that—please try again.");
      return false;
    }
    queryClient.invalidateQueries({ queryKey: ["conversations"] });
    return true;
  };

  const handleSend = async (e: React.FormEvent): Promise<void> => {
    e.preventDefault();
    const body = draft.trim();
    if (!body) return;
    const check = beginSendOperation();
    if (await sendBody(body, check)) {
      try { check(); setDraft(current => current.trim() === body ? "" : current); } catch { /* previous conversation */ }
    }
  };

  return (
    <div className="relative w-full min-w-0">
      <div ref={setConversationHost} />
      <div className={active || groupActive ? "hidden" : ""}>
      <FloatingHeader
        title={profile?.username ?? "you"}
        left={<FloatingButton onClick={() => navigate(-1)} label="Back"><ArrowLeft className="h-5 w-5" /></FloatingButton>}
        right={<FloatingButton onClick={() => setNewMessage(true)} label="New message"><Pencil className="h-5 w-5" /></FloatingButton>}
      />

      <Stories stories={stories} profiles={storyProfiles} />

      {/* Inbox — flat, no card wrapper (matches the clean, no-gray-box look). */}
      <div className="w-full pb-8">

      {/* Inbox search + filter chips (mirrors the iOS inbox). */}
      {!convosQuery.isLoading && (
        <div className="space-y-3 px-4 pb-3 pt-3">
          <div className="flex items-center gap-2.5 rounded-2xl bg-secondary/60 px-4 py-2.5">
            <SearchIcon className="h-[18px] w-[18px] shrink-0 text-muted-foreground" />
            <input
              value={inboxQuery}
              onChange={(e) => setInboxQuery(e.target.value)}
              placeholder="Search"
              className="min-w-0 flex-1 bg-transparent text-[15px] outline-none placeholder:text-muted-foreground"
            />
            {inboxQuery.length > 0 && (
              <button
                onClick={() => setInboxQuery("")}
                aria-label="Clear search"
                className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-muted-foreground/30 text-background transition-transform active:scale-90"
              >
                <X className="h-3 w-3" strokeWidth={3} />
              </button>
            )}
          </div>
          <div className="flex items-center gap-2">
            <div className="flex min-w-0 flex-1 gap-2 overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
              {INBOX_FILTERS.map((f) => {
                const n = f.id === "all" ? 0 : unreadFor(f.id);
                const on = filter === f.id;
                return (
                  <button
                    key={f.id}
                    onClick={() => setFilter(f.id)}
                    className={cn(
                      "flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-4 py-1.5 text-sm font-semibold transition-colors",
                      on
                        ? "bg-foreground text-background"
                        : "bg-secondary/60 text-muted-foreground hover:bg-secondary"
                    )}
                  >
                    {f.label}
                    {n > 0 && (
                      <span
                        className={cn(
                          "inline-flex min-w-[18px] justify-center rounded-full px-1.5 text-[11px] font-bold tabular-nums",
                          on ? "bg-background/25 text-background" : "bg-foreground text-background"
                        )}
                      >
                        {n}{convosQuery.hasNextPage ? "+" : ""}
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
            {/* Sort — the iOS inbox's menu: Most recent · Unread first · Oldest first. */}
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <button
                  aria-label="Sort conversations"
                  className={cn(
                    "flex h-8 w-8 shrink-0 items-center justify-center rounded-full transition-colors",
                    sort !== "recent"
                      ? "bg-foreground text-background"
                      : "bg-secondary/60 text-muted-foreground hover:bg-secondary"
                  )}
                >
                  <ArrowUpDown className="h-4 w-4" />
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-48 rounded-2xl p-1.5">
                {INBOX_SORTS.map((s) => {
                  const Icon = s.icon;
                  return (
                    <DropdownMenuItem
                      key={s.id}
                      onClick={() => setSort(s.id)}
                      className={cn("gap-2.5 rounded-xl text-[14px]", sort === s.id && "font-bold")}
                    >
                      <Icon className="h-4 w-4" />
                      {s.label}
                      {sort === s.id && <span className="ml-auto h-1.5 w-1.5 rounded-full bg-foreground" />}
                    </DropdownMenuItem>
                  );
                })}
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
      )}

      {/* The meeting-style Jasper dock — the mascot peeking from behind the
          pill; tapping runs a live read of the current chats in place. */}
      {!active && !groupActive && conversations.length > 0 && (
        <JasperAnalysisDock
          alignToContent
          pillLabel="Knot's read"
          boxTitle="Inbox analysis"
          focus="You are analyzing the user's DM inbox. Each line below is one chat: the handle, whether it's waiting on my reply, and the last message. Lead with who is WAITING ON MY REPLY and what they actually need (topic-specific), flag anything time-sensitive (invites, meetings, proposals, deadlines), then ONE suggested next move."
          buildContext={() => {
            const lines = conversations.slice(0, 10).map((c) => {
              const preview = previewText(c.lastMessage).slice(0, 90);
              return `@${c.otherUsername}: (${c.unread > 0 ? "WAITING ON MY REPLY" : "read"}) ${preview}`;
            });
            return lines.length > 0 ? lines.join("\n") : null;
          }}
          emptyText="No chats yet — once you're talking to people I'll analyze the inbox here."
        />
      )}


      {convosQuery.isLoading && (
        <div className="space-y-1 p-3">
          {[0, 1, 2, 3].map((i) => (
            <div key={i} className="flex animate-pulse items-center gap-3 p-2">
              <div className="h-12 w-12 rounded-full bg-secondary" />
              <div className="flex-1 space-y-2">
                <div className="h-3 w-28 rounded bg-secondary" />
                <div className="h-3 w-40 rounded bg-secondary" />
              </div>
            </div>
          ))}
        </div>
      )}

      {convosQuery.isError && !convosQuery.isFetchNextPageError && <div role="alert" className="p-6 text-sm text-muted-foreground">Couldn't refresh messages. <button type="button" disabled={convosQuery.isFetching} className="min-h-11 font-semibold disabled:opacity-50" onClick={() => void convosQuery.refetch()}>Retry messages</button></div>}

      {filter === "dating" && (
        <div className="mx-4 mb-1 mt-2 flex items-center gap-3 rounded-2xl border border-rose-500/30 bg-rose-500/[0.07] px-4 py-3 dark:bg-rose-500/[0.14]">
          <EmberMascot
            size={40}
            palette={{ accent: "#F5B8CC", softAccent: "#FFEDF2", deepAccent: "#E68FAD" }}
            smitten
            cyclesExpressions
          />
          <div className="min-w-0">
            <p className="text-[13px] font-extrabold text-rose-500">Dating chats</p>
            <p className="text-[11.5px] leading-snug text-muted-foreground">
              People you said hi to in the Dating hub land here — with cupid
              Knot's date tools in every chat.
            </p>
          </div>
        </div>
      )}

      {user && profile && <GroupChatsSection key={user.id}
        me={{ id: user.id, username: profile.username }} conversationHost={conversationHost} onActiveChange={setGroupActive}
        active={!active} filter={filter} search={inboxQuery} sort={sort} directLoading={convosQuery.isLoading || convosQuery.hasNextPage} directError={convosQuery.isError}
        directRows={visibleConversations.map((c) => ({ id: conversationKey(c), date: c.lastDate, unread: c.unread, node: (
          <div
            key={conversationKey(c)}
            className="group relative flex w-full items-center transition-colors hover:bg-secondary/50"
          >
          <button
            onClick={() => setActiveId(conversationKey(c))}
            className="flex min-w-0 flex-1 items-center gap-3 py-3 pl-4 pr-12 text-left"
          >
            <div className="relative shrink-0">
              <Avatar
                url={c.otherProfile?.profile_image_url}
                name={c.otherUsername}
                size={52}
              />
              {isActiveNow(presence[c.otherUserId]) && (
                <span className="absolute bottom-0.5 right-0.5 h-3 w-3 rounded-full border-2 border-background bg-[#1cd14f]" />
              )}
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex items-center justify-between gap-2">
                <span className="flex min-w-0 items-center gap-1 truncate font-semibold">
                  <span className="truncate">
                    {c.otherProfile?.display_name || c.otherUsername}
                  </span>
                  {c.kind === "dating" && <Heart className="h-3 w-3 shrink-0 text-rose-500" aria-label="Dating conversation" />}
                  <UserBadges
                    profile={c.otherProfile}
                    liar={liarBadges[c.otherUsername.toLowerCase()]}
                    size={13}
                  />
                </span>
                <span className="shrink-0 text-xs text-muted-foreground">
                  {timeAgo(c.lastDate)}
                </span>
              </div>
              <p
                className={cn(
                  "truncate text-sm",
                  c.unread > 0
                    ? "font-semibold text-foreground"
                    : "text-muted-foreground"
                )}
              >
                {c.lastFromMe ? "You: " : ""}
                {previewText(c.lastMessage)}
              </p>
            </div>
            {c.unread > 0 && (
              <span
                className="ml-1 h-2.5 w-2.5 shrink-0 rounded-full bg-[#0095f6]"
                aria-label={`${c.unread} unread`}
              />
            )}
          </button>
          <button
            onClick={() => setPendingDelete(c)}
            aria-label={`Delete conversation with ${c.otherUsername}`}
            className="absolute right-3 top-1/2 flex h-9 w-9 -translate-y-1/2 items-center justify-center rounded-full text-muted-foreground opacity-0 transition-all hover:bg-destructive/10 hover:text-destructive focus:opacity-100 group-hover:opacity-100 max-md:opacity-100"
          >
            <Trash2 className="h-[18px] w-[18px]" />
          </button>
          </div>
        ) }))} />}
      <ConversationListEnd active={!active && !groupActive} hasMore={convosQuery.hasNextPage}
        busy={convosQuery.isFetching} loading={convosQuery.isFetchingNextPage}
        failed={convosQuery.isFetchNextPageError}
        onLoad={() => convosQuery.fetchNextPage({ cancelRefetch: false })} />
      </div>

      <AlertDialog
        open={!!pendingDelete}
        onOpenChange={(open) => {
          if (!open) setPendingDelete(null);
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete conversation?</AlertDialogTitle>
            <AlertDialogDescription>
              This removes the conversation with @
              {pendingDelete?.otherUsername} from your inbox on this device.
              {" "}
              {pendingDelete?.otherUsername} will still see it, and the thread
              comes back if they send you a new message.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={confirmDelete}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      </div>
      {active && !groupActive && (
        <ChatView
          key={`${user!.id}:${conversationKey(active)}`}
          convo={active}
          meId={user!.id}
          liar={liarBadges[active.otherUsername.toLowerCase()]}
          lastSeenAt={presence[active.otherUserId] ?? null}
          draft={draft}
          setDraft={setDraft}
          onSend={handleSend}
          onSendBody={sendBody}
          onBack={closeThread}
          scrollRef={scrollRef}
        />
      )}

      <NewMessageDialog
        open={newMessage}
        onOpenChange={setNewMessage}
        onPick={(p) =>
          navigate(`/messages?to=${p.user_id}&u=${encodeURIComponent(p.username)}`)
        }
      />
    </div>
  );
}

/** Session separator label — "2:14 PM" today, "Mon 9:02 AM" this week. */
function stampLabel(iso: string): string {
  const d = new Date(iso);
  const now = new Date();
  const time = d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  if (d.toDateString() === now.toDateString()) return time;
  if (now.getTime() - d.getTime() < 6 * 86_400_000) {
    return `${d.toLocaleDateString([], { weekday: "short" })} ${time}`;
  }
  return `${d.toLocaleDateString([], { month: "short", day: "numeric" })}, ${time}`;
}

/** Human label for a thread preview when the last message is a rich embed. */
function previewText(body: string | null | undefined): string {
  const t = (body ?? "").trim();
  if (!t) return "";
  if (t.startsWith("::whisper-teams-")) return "Team invitation";
  if (sharedStoryID(t)) return "Shared a story";
  if (t.startsWith(SHARED_COMMUNITY_PREFIX)) return "Shared a community";
  const notesSummary = notesMessageSummary(t);
  if (notesSummary) return notesSummary;
  if (decodeEmberAnswer(t)) return "Knot answered";
  if (decodeFactCheck(t)) return "✅ Fact check";
  if (decodeMap(t)) return "📍 Nearby restaurants";
  if (jasperStickerName(t)) return "👻 Sticker";
  if (t.startsWith(MEETING_NOTES_DM_SIG)) return "📋 Meeting notes";
  if (decodeSharedProfile(t)) return "👤 Shared a profile";
  if (t.startsWith("::whisper-calendar")) {
    const cal = decodeCalendarEmbed(t);
    if (cal?.kind === "chat-meet") return "Meet invitation";
    if (cal?.kind === "cancelled") return "📅 Event cancelled";
    if (cal?.kind === "update") return "📅 Event updated";
    return "📅 Team calendar invite";
  }
  if (t.startsWith("::whisper-program")) return "📋 Sent a training program";
  if (t.startsWith("::whisper-coach-macros")) return "🔥 Sent nutrition goals";
  if (t.startsWith("::whisper-coach-diet-plan")) return "🍽️ Sent a diet plan";
  if (t.startsWith("::whisper-coach-targets")) return "🎯 Sent daily targets";
  if (t.startsWith("::whisper-coach-proposal")) return "📋 New coach suggestion";
  if (t.startsWith("::whisper-workout")) return "🏋️ Shared a workout";
  if (t.startsWith("::whisper-recipe")) return "🥘 Shared a recipe";
  if (t.startsWith("::whisper-grocery")) return "🛒 Shared a grocery list";
  if (t.startsWith("::whisper-checkin")) return "✅ Check-in";
  if (t.startsWith("::whisper-chart")) return "📈 Shared a chart";
  if (t.startsWith("::whisper-healthshare")) return "❤️ Shared health stats";
  if (t.startsWith("::whisper-call")) return "📞 Call";
  if (t.startsWith("::whisper-sharedpost")) return "📎 Shared a post";
  if (t.startsWith(FILM_EMBED_PREFIX)) return "🎬 Shared a film";
  if (t.startsWith(ARTICLE_EMBED_PREFIX)) return "📰 Shared an article";
  if (t.startsWith("::whisper-plan-quiz-answers")) return "📝 Questionnaire answers";
  if (t.startsWith("::whisper-plan-quiz")) return "📝 Coach questionnaire";
  if (chatVideoUrl(t)) return "Sent a video";
  const dateLine = secondDatePreviewLine(t);
  if (dateLine) return dateLine;
  const matchLine = matchPreviewLine(t);
  if (matchLine) return matchLine;
  if (t.startsWith("::whisper-")) return "📎 Shared an attachment";
  if (/^https?:\/\/\S+$/.test(t) && /(giphy\.com\/media|\.(gif|png|jpe?g|webp))/i.test(t))
    return "📷 Sent an image";
  // A share that rides along with a caption — swap the token for its label
  // so raw JSON never reaches a preview line.
  if (t.includes("::whisper-")) return stripEmbedTokens(t);
  return t;
}

/** Replaces any `::whisper-…` token embedded mid-text with its human label. */
function stripEmbedTokens(t: string): string {
  return t
    .split("\n")
    .map((line) => {
      const idx = line.indexOf("::whisper-");
      if (idx < 0) return line;
      const label = previewText(line.slice(idx));
      const before = line.slice(0, idx).trim();
      return [before, label].filter(Boolean).join(" ");
    })
    .filter((l) => l.trim().length > 0)
    .join("\n")
    .trim();
}

const DM_EMOJIS = [
  "😀", "😂", "🥹", "😍", "😎", "🥳", "😭", "🔥",
  "💪", "👏", "🙌", "💯", "✨", "❤️", "👀", "🙏",
];

/**
 * /jasper slash commands available in a DM (mirrors the iOS command menu).
 * The legacy `/ember` prefix still works when typed. `runImmediate` commands
 * fire the moment they're tapped (no extra input needed); the others fill
 * the draft and keep focus so the user can type.
 */
const JASPER_COMMANDS: {
  /** The chip's `/name` — also what the typed query filters against. */
  name: string;
  label: string;
  hint: string;
  fill: string;
  icon: React.ReactNode;
  runImmediate?: boolean;
}[] = [
  {
    name: "knot",
    label: "Ask Knot",
    hint: "Ask Knot anything",
    fill: "/knot ",
    icon: <Sparkles className="h-4 w-4" />,
  },
  {
    name: "factcheck",
    label: "Fact check",
    hint: "Verify a claim with sources",
    fill: "/knot factcheck ",
    icon: <ShieldCheck className="h-4 w-4" />,
  },
  {
    name: "nearby",
    label: "Nearby food",
    hint: "Send a map of nearby food",
    fill: "/knot nearby",
    icon: <MapPin className="h-4 w-4" />,
    runImmediate: true,
  },
  {
    name: "recipe",
    label: "Recipe",
    hint: "Send a full recipe card",
    fill: "/recipe ",
    icon: <UtensilsCrossed className="h-4 w-4" />,
  },
  {
    name: "explain",
    label: "Explain",
    hint: "Explain a workout or term",
    fill: "/knot explain ",
    icon: <Sparkles className="h-4 w-4" />,
  },
  {
    name: "summarize",
    label: "Summarize",
    hint: "Summarize this chat",
    fill: "/knot summarize this thread",
    icon: <Sparkles className="h-4 w-4" />,
  },
  {
    name: "macros",
    label: "Macros",
    hint: "Lookup macros for a food",
    fill: "/knot macros for ",
    icon: <UtensilsCrossed className="h-4 w-4" />,
  },
];

/**
 * Team calendar invite/update/cancel card rendered inline in a DM thread.
 * Mirrors the iOS `WhisperCalendarInlineCard` — sent by the organizer when
 * they tag someone on a shared-calendar event.
 */
function CalendarInviteDmCard({
  payload,
  mine,
  onOpen,
}: {
  payload: CalendarEmbedPayload;
  mine: boolean;
  /** Closes the thread first so the calendar isn't hidden behind the DM view. */
  onOpen?: () => void;
}) {
  if (payload.kind === "chat-meet") return <ChatMeetCard eventID={payload.eventID} />;
  const color = EVENT_TYPE_COLORS[(payload.eventType as CalendarEventType)] ?? "#6b7280";
  const typeLabel = EVENT_TYPE_LABELS[(payload.eventType as CalendarEventType)] ?? "Event";
  const cancelled = payload.kind === "cancelled";
  const heading = cancelled
    ? "Event cancelled"
    : payload.kind === "update"
      ? "Event updated"
      : "Team calendar invite";
  const when = new Date(payload.startTime).toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
  return (
    <div
      className={cn(
        "w-[min(280px,78vw)] space-y-2.5 rounded-[18px] border p-3.5",
        mine
          ? "border-transparent bg-primary text-primary-foreground"
          : "border-border bg-card text-foreground"
      )}
    >
      <div className="flex items-center gap-2 text-[13px] font-bold">
        <CalendarDays className="h-4 w-4" style={mine ? {} : { color }} />
        {heading}
      </div>
      <div className="h-[3px] rounded-full" style={{ backgroundColor: color }} />
      <p className={cn("text-[15px] font-bold leading-tight", cancelled && "line-through opacity-70")}>
        {payload.title}
      </p>
      <div className="space-y-1 text-[12px] font-semibold opacity-80">
        <p>🕒 {when}</p>
        <p>
          <span
            className="rounded-full px-1.5 py-0.5 text-[10px] font-bold"
            style={mine ? {} : { backgroundColor: `${color}22`, color }}
          >
            {typeLabel}
          </span>
        </p>
        {payload.location && <p>📍 {payload.location}</p>}
        {payload.meetingLink && <p>🎥 Online meeting</p>}
        {payload.taggedUsernames.length > 0 && (
          <p className="truncate">
            👥 With{" "}
            {payload.taggedUsernames.slice(0, 3).map((u) => `@${u}`).join(", ")}
            {payload.taggedUsernames.length > 3
              ? ` +${payload.taggedUsernames.length - 3}`
              : ""}
          </p>
        )}
        <p className="opacity-70">From @{payload.createdByUsername}</p>
      </div>
      {!cancelled && (
        <button
          type="button"
          onClick={onOpen}
          className={cn(
            "block w-full rounded-xl py-2 text-center text-[12px] font-bold transition-opacity hover:opacity-90",
            mine
              ? "bg-primary-foreground text-primary"
              : "bg-foreground text-background"
          )}
        >
          View in calendar
        </button>
      )}
    </div>
  );
}

/** Strips every embed token from a compact card caption — on a card the
 *  token content IS the card, so even a label would be noise. */
function cleanCardCaption(caption: string | null | undefined): string {
  const base = cleanPostCaption(caption);
  if (!base.includes("::whisper-")) return base;
  return base
    .split("\n")
    .map((line) => {
      const idx = line.indexOf("::whisper-");
      return idx < 0 ? line : line.slice(0, idx).trim();
    })
    .filter((l) => l.trim().length > 0)
    .join("\n")
    .trim();
}

/**
 * Compact card rendered inside a DM bubble for a shared post. A shared WAVE
 * opens the actual wave in the full-screen Waves player (mirrors iOS); any
 * other post opens the post itself on the feed.
 */
function SharedPostCard({
  payload: p,
  mine,
}: {
  payload: SharedPostPayload;
  mine: boolean;
}) {
  const caption = cleanCardCaption(p.caption);
  const isWave = p.isReel === true || (p.isVideo && p.kindRaw === "photo");
  const destination = isWave ? `/reels?wave=${p.postID}` : `/?post=${p.postID}`;
  if (isWave) return <SharedWaveCard payload={p} caption={caption} to={destination} />;
  return (
    <Link
      to={destination}
      className={cn(
        "block w-[min(240px,78vw)] overflow-hidden rounded-[18px] border",
        mine
          ? "border-transparent bg-primary text-primary-foreground"
          : "border-border bg-card text-foreground"
      )}
    >
      <div className="relative h-[150px] w-full bg-secondary">
        {p.mediaURL ? (
          <img src={p.mediaURL} alt="" className="h-full w-full object-cover" />
        ) : (
          <div
            className="flex h-full w-full items-center justify-center"
            style={{
              background: p.accentHex
                ? `linear-gradient(135deg, ${p.accentHex}, ${p.accentHex}cc)`
                : "linear-gradient(135deg, #8b8b96, #6b6b75)",
            }}
          >
            <MessageCircle className="h-9 w-9 text-white/90" />
          </div>
        )}
      </div>
      <div className="space-y-1.5 p-3">
        <div className="flex items-center gap-1.5">
          <Avatar name={p.username} size={20} />
          <span className="truncate text-xs font-bold">@{p.username}</span>
        </div>
        {caption && (
          <p className="line-clamp-3 text-xs opacity-90">{caption}</p>
        )}
        <div className="flex items-center gap-3 pt-0.5 text-[11px] font-semibold opacity-70">
          <span className="flex items-center gap-1">
            <Heart className="h-3 w-3" />
            {p.likes}
          </span>
          <span className="flex items-center gap-1">
            <MessageCircle className="h-3 w-3" />
            {p.comments}
          </span>
          <span className="ml-auto">{isWave ? "Watch wave" : "View post"}</span>
        </div>
      </div>
    </Link>
  );
}

/**
 * A shared WAVE is just the wave — a bare 9:16 poster with the author chip,
 * a play disc, the caption and counts laid over the footage — never boxed
 * in a card with a header and a "Watch wave" footer (the feed-card box is
 * exactly what broke the wave's proportions). Mirrors the iOS wave embed.
 */
function SharedWaveCard({
  payload: p,
  caption,
  to,
}: {
  payload: SharedPostPayload;
  caption: string;
  to: string;
}) {
  const cover = waveCoverUrl(p.caption);
  const mediaIsVideo = !!p.mediaURL && /\.(mp4|mov|webm|m4v)(\?|$)/i.test(p.mediaURL);
  return (
    <Link
      to={to}
      aria-label="Watch wave"
      className="group relative block aspect-[9/16] w-[min(200px,58vw)] overflow-hidden rounded-[18px] bg-black shadow-md ring-1 ring-black/5 dark:ring-white/10"
    >
      {cover ? (
        <img src={cover} alt="" className="absolute inset-0 h-full w-full object-cover" loading="lazy" />
      ) : p.mediaURL && mediaIsVideo ? (
        <video
          src={p.mediaURL}
          muted
          playsInline
          preload="metadata"
          className="absolute inset-0 h-full w-full object-cover"
        />
      ) : p.mediaURL ? (
        <img src={p.mediaURL} alt="" className="absolute inset-0 h-full w-full object-cover" loading="lazy" />
      ) : (
        <div
          className="absolute inset-0"
          style={{
            background: p.accentHex
              ? `linear-gradient(160deg, ${p.accentHex}, ${p.accentHex}99)`
              : "linear-gradient(160deg, #2b2b30, #0c0c0f)",
          }}
        />
      )}
      <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-black/40 via-transparent to-black/75" />
      <div className="absolute left-2.5 right-2.5 top-2.5 flex items-center gap-1.5">
        <Avatar name={p.username} size={22} className="ring-1 ring-white/70" />
        <span className="truncate text-[12px] font-bold text-white drop-shadow">{p.username}</span>
      </div>
      <div className="absolute inset-0 flex items-center justify-center">
        <span className="flex h-12 w-12 items-center justify-center rounded-full bg-white/20 ring-1 ring-white/50 backdrop-blur-md transition-transform group-hover:scale-105">
          <PlayIcon className="ml-0.5 h-5 w-5 fill-white text-white" />
        </span>
      </div>
      <div className="absolute inset-x-2.5 bottom-2.5 space-y-1.5">
        {caption && (
          <p className="line-clamp-2 text-[12px] leading-snug text-white drop-shadow">{caption}</p>
        )}
        <div className="flex items-center gap-2.5 text-[11px] font-semibold text-white/90">
          <span className="flex items-center gap-1">
            <Heart className="h-3 w-3" />
            {p.likes}
          </span>
          <span className="flex items-center gap-1">
            <MessageCircle className="h-3 w-3" />
            {p.comments}
          </span>
        </div>
      </div>
    </Link>
  );
}

/**
 * Last-resort text for a plain bubble. Any unrecognised `::whisper-…::` embed
 * (a control signal or a future embed type the web doesn't render yet) is
 * collapsed to its human label via `previewText` so raw JSON never leaks.
 */
/** Compact profile card rendered inside a DM bubble when someone shares a profile. */
function SharedProfileDmCard({
  payload,
  mine,
}: {
  payload: SharedProfilePayload;
  mine: boolean;
}) {
  return (
    <Link
      to={`/u/${payload.username}`}
      className={cn(
        "block w-[min(240px,78vw)] overflow-hidden rounded-[18px] border",
        mine
          ? "border-transparent bg-primary text-primary-foreground"
          : "border-border bg-card text-foreground"
      )}
    >
      <div className="flex items-center gap-3 p-3">
        <Avatar
          url={payload.avatarUrl}
          name={payload.username}
          size={48}
        />
        <div className="min-w-0 flex-1">
          <p className="truncate text-[14px] font-bold">
            {payload.displayName || payload.username}
          </p>
          <p className="truncate text-[12px] opacity-70">
            @{payload.username}
          </p>
        </div>
      </div>
      {payload.bio && (
        <p className="line-clamp-2 px-3 pb-2 text-[12px] opacity-80">
          {payload.bio}
        </p>
      )}
      <div className="flex items-center gap-2 px-3 pb-3 pt-1">
        {(payload.isCoach || payload.isAthlete || payload.isVerified) && (
          <span className="rounded-full bg-foreground/10 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider">
            {payload.isCoach ? "Coach" : payload.isAthlete ? "Athlete" : "Creator"}
          </span>
        )}
        <span className="ml-auto text-[11px] font-semibold opacity-60">
          View profile
        </span>
      </div>
    </Link>
  );
}

function displayBody(body: string | null | undefined): string {
  const t = (body ?? "").trim();
  if (t.startsWith("::whisper-")) return previewText(t);
  if (t.includes("::whisper-")) return stripEmbedTokens(t);
  return body ?? "";
}

import { chatVideoUrl, uploadChatMedia } from "@/lib/chatMedia";
import { ChatVideo } from "@/components/ChatVideo";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";

function mediaUrlOf(body: string | null | undefined): string | null {
  const t = (body ?? "").trim();
  if (!t) return null;
  if (/^https?:\/\/\S+$/.test(t) &&
    (/\.(gif|png|jpe?g|webp)(\?|$)/i.test(t) || t.includes("giphy.com/media")))
    return t;
  return null;
}

/**
 * Everything a bubble needs, decoded ONCE per unique body and cached.
 * The inbox poll rebuilds every message object each cycle, and re-running a
 * dozen JSON.parse attempts per bubble per poll is what made open threads
 * feel glitchy. Bodies are immutable, so the raw string is a safe cache key.
 */
type DecodedBubble =
  | { kind: "hidden" }
  | { kind: "notes"; notes: MeetingNotesDmPayload }
  | { kind: "calendar"; calendar: CalendarEmbedPayload }
  | { kind: "story"; storyID: string }
  | { kind: "ember" }
  | { kind: "dmEmbed" }
  | { kind: "recipe"; recipe: RecipePayload }
  | { kind: "film"; film: FilmEmbedPayload; caption: string }
  | { kind: "article"; article: ArticleEmbedPayload; caption: string }
  | { kind: "quiz"; quiz: PlanQuizPayload }
  | { kind: "quizAnswers"; quizAnswers: PlanQuizAnswersPayload }
  | { kind: "sharedPost"; post: SharedPostPayload; caption: string }
  | { kind: "community"; community: Community }
  | { kind: "profile"; profile: SharedProfilePayload }
  | { kind: "sticker"; sticker: string }
  | { kind: "video"; url: string }
  | { kind: "media"; url: string }
  | { kind: "text"; text: string };

const bubbleCache = new Map<string, DecodedBubble>();

function decodeBubble(body: string | null | undefined): DecodedBubble {
  const raw = typeof body === "string" ? body : "";
  const hit = bubbleCache.get(raw);
  if (hit) return hit;
  let decoded: DecodedBubble;
  try { decoded = computeBubble(raw); }
  catch { decoded = { kind: "text", text: "This attachment couldn't be displayed." }; }
  if (bubbleCache.size > 600) bubbleCache.clear();
  bubbleCache.set(raw, decoded);
  return decoded;
}

function computeBubble(raw: string): DecodedBubble {
  const t = raw.trim();
  const storyID = sharedStoryID(t);
  if (storyID) return { kind: "story", storyID };
  if (splitGroupReply(t).quote) return { kind: "text", text: t };
  // Call control signals (accept/decline/cancel/end) ride the DM channel but
  // aren't chat — never render them as bubbles.
  if (isCallSignal(t) && !decodeCallInvite(t)) return { kind: "hidden" };
  const notes = decodeMeetingNotesDm(t);
  if (notes) return { kind: "notes", notes };
  const calendar = decodeCalendarEmbed(t);
  if (calendar) return { kind: "calendar", calendar };
  if (isEmberEmbed(t)) return { kind: "ember" };
  if (isDmEmbed(t)) return { kind: "dmEmbed" };
  const recipe = decodeRecipe(t);
  if (recipe) return { kind: "recipe", recipe };
  if (t.includes(FILM_EMBED_PREFIX) || t.includes(ARTICLE_EMBED_PREFIX)) {
    const split = parseContentEmbeds(t);
    if (split.film) return { kind: "film", film: split.film, caption: split.cleaned };
    if (split.article) {
      return { kind: "article", article: split.article, caption: split.cleaned };
    }
  }
  const quizAnswers = decodePlanQuizAnswers(t);
  if (quizAnswers) return { kind: "quizAnswers", quizAnswers };
  const quiz = decodePlanQuiz(t);
  if (quiz) return { kind: "quiz", quiz };
  if (t.startsWith(SHARED_COMMUNITY_PREFIX)) {
    const community = decodeSharedCommunity(t);
    return community ? { kind: "community", community } : { kind: "text", text: "This community is unavailable." };
  }
  const post = extractSharedPost(t);
  if (post.payload) {
    return { kind: "sharedPost", post: post.payload, caption: post.rest };
  }
  const profile = decodeSharedProfile(t);
  if (profile) return { kind: "profile", profile };
  const sticker = jasperStickerName(t);
  if (sticker) return { kind: "sticker", sticker };
  const video = chatVideoUrl(t);
  if (video) return { kind: "video", url: video };
  const media = mediaUrlOf(t);
  if (media) return { kind: "media", url: media };
  return { kind: "text", text: displayBody(raw) };
}

/**
 * A locally-held Ember result shown in a dashed "only you see this" preview
 * card above the composer — mirrors the iOS `emberSharePreviewCard` /
 * `factCheckPreviewCard`. The answer renders from local state (so it is
 * guaranteed to appear regardless of the DB round-trip) and only enters the
 * thread when the user taps Share.
 */
type EmberPreview =
  | {
      kind: "answer";
      question: string;
      answer: string;
      sources: string[];
      tldr: string | null;
    }
  | {
      kind: "fact";
      claim: string;
      verdict: Verdict;
      summary: string;
      explanation: string;
      sources: string[];
    };

const VERDICT_LABEL: Record<Verdict, { label: string; color: string }> = {
  true: { label: "True", color: "#22c55e" },
  mostly_true: { label: "Mostly true", color: "#10b981" },
  misleading: { label: "Misleading", color: "#f59e0b" },
  false: { label: "False", color: "#ef4444" },
  unverified: { label: "Unverified", color: "#94a3b8" },
};

function hostOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
}

function EmberPreviewCard({
  preview,
  username,
  onShare,
  onDismiss,
}: {
  preview: EmberPreview;
  username: string;
  onShare: () => void;
  onDismiss: () => void;
}) {
  const [expanded, setExpanded] = useState<boolean>(false);
  const body =
    preview.kind === "answer"
      ? preview.answer
      : preview.summary || preview.explanation;
  const isLong = body.length > 220;
  const verdict =
    preview.kind === "fact" ? VERDICT_LABEL[preview.verdict] : null;
  return (
    /* The iOS round-83 grammar: a clean surface card, the spark + "only you
       see this", the question, the answer, then an ink Share pill and Keep
       private. The mint dashed box and the candle badge are gone. */
    <div className="my-3 mr-6 rounded-[20px] rounded-tl-md border border-border bg-background p-3.5 sm:mr-12" role="region" aria-label="Private Knot reply">
      <div className="flex items-start gap-2.5">
        <KnotPortrait size={34} />
        <div className="min-w-0 flex-1">
          <p className="flex flex-wrap items-center gap-1.5 text-[11px] font-bold text-muted-foreground">
            {preview.kind === "fact" ? (
              <>
                Fact-check · only you see this
                <span
                  className="rounded-full px-2 py-0.5 text-[10px] font-extrabold"
                  style={{ color: verdict!.color, background: `${verdict!.color}22` }}
                >
                  {verdict!.label}
                </span>
              </>
            ) : (
              "Knot · only you see this"
            )}
          </p>
          {preview.kind === "answer" && preview.question.trim() && (
            <p className="mt-0.5 line-clamp-2 text-[12.5px] font-semibold text-foreground/80">
              {preview.question}
            </p>
          )}
          {preview.kind === "fact" && (
            <p className="mt-0.5 line-clamp-2 text-xs italic text-muted-foreground">
              “{preview.claim}”
            </p>
          )}
          <p
            className={cn(
              "mt-1 whitespace-pre-wrap text-sm leading-relaxed text-foreground",
              !expanded && isLong && "line-clamp-3"
            )}
          >
            {body}
          </p>
          {preview.kind === "fact" &&
            expanded &&
            preview.explanation &&
            preview.explanation !== body && (
              <p className="mt-1 text-sm leading-relaxed text-foreground/90">
                {preview.explanation}
              </p>
            )}
          {isLong && !expanded && (
            <button
              onClick={() => setExpanded(true)}
              className="mt-1 text-xs font-bold text-foreground underline-offset-2 hover:underline"
            >
              Tell me more
            </button>
          )}
          {preview.sources.length > 0 && (
            <p className="mt-1 truncate text-[11px] text-muted-foreground">
              {preview.sources.slice(0, 2).map(hostOf).join(" · ")}
            </p>
          )}
        </div>
        <button
          onClick={onDismiss}
          aria-label="Dismiss"
          className="rounded-full p-1 text-muted-foreground transition-colors hover:bg-secondary"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
      <div className="mt-2.5 flex items-center gap-2">
        <button
          onClick={onShare}
          className="flex items-center gap-1.5 rounded-full bg-foreground px-3.5 py-1.5 text-xs font-bold text-background transition-transform active:scale-95"
        >
          <Send className="h-3.5 w-3.5" />
          Share with @{username}
        </button>
        <button
          onClick={onDismiss}
          className="rounded-full px-3 py-1.5 text-xs font-semibold text-muted-foreground transition-colors hover:bg-secondary"
        >
          Keep private
        </button>
      </div>
    </div>
  );
}

/** Notes auto-DMs keep their plain-text body ("📋 Meeting notes — Title…")
 *  so old clients still read them — this detects the signature and upgrades
 *  the message into a tappable card that opens the full-screen notes,
 *  exactly like iOS. */
const MEETING_NOTES_DM_SIG = "\u{1F4CB} Meeting notes \u{2014} ";
/** The link line the sender writes under the notes ("🔗 Full notes & transcript: …"). */
const MEETING_NOTES_LINK_RE = /^\u{1F517} Full notes & transcript:\s*(\S+)\s*$/mu;

interface MeetingNotesDmPayload {
  title: string;
  notes: string;
  /** "speaker: line" transcript that rode the message (newer senders). */
  transcript: string | null;
  /** The room link, when the sender included one. */
  link: string | null;
  /** Database id derived from the link — lets the notes screen fetch the
   *  transcript for messages that predate the inline block. */
  meetingId: string | null;
}

/** Meeting id from a /meet/<id-or-code> link (codes hash to their room id). */
function meetingIdFromLink(link: string): string | null {
  try {
    const url = new URL(link);
    const seg = url.pathname.split("/").filter(Boolean).pop() ?? "";
    if (!seg || seg.toLowerCase() === "meet") return null;
    return isMeetingUuid(seg) ? seg.toLowerCase() : meetingIdFromCode(seg);
  } catch {
    return null;
  }
}

function decodeMeetingNotesDm(body: string | null | undefined): MeetingNotesDmPayload | null {
  if (!body) return null;
  const trimmed = body.trim();
  if (!trimmed.startsWith(MEETING_NOTES_DM_SIG)) return null;
  const rest = trimmed.slice(MEETING_NOTES_DM_SIG.length);
  const nl = rest.indexOf("\n");
  if (nl < 0) return null;
  const title = rest.slice(0, nl).trim() || "Meeting";
  let notes = rest.slice(nl + 1).trim();
  // The transcript block rides last under its marker line.
  let transcript: string | null = null;
  const marker = notes.indexOf(`\n${NOTES_TRANSCRIPT_MARKER}\n`);
  if (marker >= 0) {
    transcript = notes.slice(marker + NOTES_TRANSCRIPT_MARKER.length + 2).trim() || null;
    notes = notes.slice(0, marker).trim();
  }
  // Lift the link line out of the notes body.
  let link: string | null = null;
  const linkMatch = MEETING_NOTES_LINK_RE.exec(notes);
  if (linkMatch) {
    link = linkMatch[1];
    notes = notes.replace(linkMatch[0], "").trim();
  }
  if (!notes) return null;
  return { title, notes, transcript, link, meetingId: link ? meetingIdFromLink(link) : null };
}

function MeetingNotesDmCard({
  payload,
  onOpen,
}: {
  payload: MeetingNotesDmPayload;
  onOpen: () => void;
}) {
  const preview = payload.notes.replace(/\*\*/g, "").replace(/\n+/g, " ").slice(0, 140);
  return (
    <button
      type="button"
      onClick={onOpen}
      className="w-[260px] overflow-hidden rounded-[18px] border border-emerald-500/30 bg-card text-left shadow-[0_8px_22px_rgba(16,185,129,0.14)] transition-transform active:scale-[0.98]"
    >
      <span className="flex items-center gap-2 bg-emerald-500/10 px-3 py-2">
        <JasperSpark size={13} breathing={false} />
        <span className="text-[9px] font-black uppercase tracking-[0.14em] text-emerald-700 dark:text-emerald-300">
          Meeting notes
        </span>
      </span>
      <span className="block px-3 py-2.5">
        <span className="block text-[13.5px] font-bold leading-snug">{payload.title}</span>
        <span className="mt-1 block text-[11.5px] leading-snug text-muted-foreground">{preview}</span>
        <span className="mt-1.5 flex items-center gap-1 text-[10.5px] font-bold text-emerald-700 dark:text-emerald-300">
          <FileText className="h-3 w-3" /> Tap to read
          <ChevronRight className="ml-auto h-3 w-3 text-muted-foreground" />
        </span>
      </span>
    </button>
  );
}

function ChatView({
  convo: inboxConvo,
  meId,
  liar,
  lastSeenAt,
  draft,
  setDraft,
  onSend,
  onSendBody,
  onBack,
  scrollRef,
}: {
  convo: WhisperConversation;
  meId: string;
  liar?: import("@/lib/types").WhisperLiarBadge | null;
  lastSeenAt?: string | null;
  draft: string;
  setDraft: (v: string) => void;
  onSend: (e: React.FormEvent) => void;
  onSendBody: (body: string, assertCurrent?: () => void) => void | boolean | Promise<void | boolean>;
  onBack: () => void;
  scrollRef: React.RefObject<HTMLDivElement>;
}) {
  const { user, profile } = useAuth();
  const navigate = useNavigate();
  const [showGiphy, setShowGiphy] = useState<boolean>(false);
  const [showEmoji, setShowEmoji] = useState<boolean>(false);
  const [showAttachTray, setShowAttachTray] = useState<boolean>(false);
  const [replyTo, setReplyTo] = useState<WhisperMessage | null>(null);
  const [forwardBody, setForwardBody] = useState<string | null>(null);
  const [reportTarget, setReportTarget] = useState<ReportMessageTarget | null>(null);
  const composerRef = useRef<HTMLTextAreaElement>(null);
  const threadQueryClient = useQueryClient();
  const history = useConversationHistory(meId, inboxConvo.otherUserId, inboxConvo.kind ?? "direct");
  const convo = { ...inboxConvo, messages: history.data || history.messages.length > 0 ? history.messages : inboxConvo.messages.slice(-100) };
  const prependAnchor = useRef<{ height: number; top: number } | null>(null);
  const olderRequestInFlight = useRef(false);
  const loadOlder = async () => {
    const el = scrollRef.current;
    if (!el || history.isFetching || olderRequestInFlight.current || !history.hasNextPage) return;
    olderRequestInFlight.current = true;
    followsLatest.current = false;
    prependAnchor.current = { height: el.scrollHeight, top: el.scrollTop };
    try {
      await history.fetchNextPage({ cancelRefetch: false });
    } finally {
      olderRequestInFlight.current = false;
    }
  };
  useLayoutEffect(() => {
    const el = scrollRef.current;
    const anchor = prependAnchor.current;
    if (el && anchor && !history.isFetching) {
      el.scrollTop = anchor.top + el.scrollHeight - anchor.height;
      prependAnchor.current = null;
    }
  }, [history.data, history.isFetching, scrollRef]);
  const messageTools = useMessageTools(meId, conversationKey(convo), () => { invalidateHistorySnapshot(); void threadQueryClient.invalidateQueries({ queryKey: ["conversations"] }); });
  const sharedReactions = useMessageReactions(meId, conversationKey(convo), convo.messages.map(message => message.id));
  const [notesOpen, setNotesOpen] = useState<boolean>(false);
  const [detailsOpen, setDetailsOpen] = useState<boolean>(false);
  const [creativeMode, setCreativeMode] = useState<ChatCreativeMode | null>(null);
  const [meetOpen, setMeetOpen] = useState(false);
  const messageNodes = useRef<Map<string, HTMLDivElement>>(new Map());
  const personalAppearance = usePersonalChatAppearance(meId, conversationKey(convo));
  const { nickname } = useConversationNickname(meId, conversationKey(convo));
  // Bumped when this chat is unmarked 💘 so the tools row hides instantly.
  const [, setDatingTick] = useState<number>(0);
  const [emberBusy, setEmberBusy] = useState<boolean>(false);
  // A CARD is being built (nearby map, recipe) rather than a text answer —
  // the pill says "putting that together" like iOS.
  const [emberWorking, setEmberWorking] = useState<boolean>(false);
  const [uploading, setUploading] = useState<boolean>(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  // Ember ask/fact-check results render in a local preview card above the
  // composer (like iOS) so they always appear, independent of the DB.
  const [emberPreview, setEmberPreview] = useState<EmberPreview | null>(null);
  // Optimistic messages (Ember embeds + sent text) so a reply renders the
  // instant it's ready — the DB refetch can lag behind write-visibility, which
  // is why Ember replies previously never appeared in a DM thread. Mirrors how
  // the iOS chat appends locally before the round-trip settles.
  const [pending, setPending] = useState<WhisperMessage[]>([]);
  // Tap a bubble to reveal its exact send time (parity with iOS).
  const [revealedTimeId, setRevealedTimeId] = useState<string | null>(null);
  // Full-screen notes opened from a meeting-notes DM card (parity with iOS).
  const [notesView, setNotesView] = useState<MeetingNotesDmPayload | null>(null);
  // 💘 mutual match — the full-screen linking celebration.
  const [showCelebration, setShowCelebration] = useState<boolean>(false);

  const trimmed = draft.trim();
  const showSlash = trimmed.startsWith("/");
  // THE JASPER PEEK PILL (iOS grammar): Jasper's whole presence above the
  // bar is ONE quiet pill led by the breathing spark — command chips while
  // you type "/" (filtered as you type), the send hint once "/jasper …" is
  // formed, "Knot is thinking" while he answers, "putting that together"
  // while a card builds. Never a menu docked to the keyboard.
  const slashQuery = showSlash ? trimmed.slice(1).toLowerCase().split(" ")[0] : "";
  const slashMatches = useMemo(
    () =>
      showSlash
        ? JASPER_COMMANDS.filter((c) => slashQuery === "" || c.name.includes(slashQuery))
        : [],
    [showSlash, slashQuery]
  );
  const draftLower = trimmed.toLowerCase();
  const jasperPillMode: "thinking" | "working" | "ask" | "commands" | null = emberBusy
    ? emberWorking
      ? "working"
      : "thinking"
    : knotCommandPrompt(draft) !== null
      ? "ask"
      : showSlash && slashMatches.length > 0
        ? "commands"
        : null;

  // Stable render keys: when the server copy of an optimistic row arrives it
  // gets a brand-new id — which used to remount the bubble and make it
  // visibly "re-pop". The alias map lets the server row reuse the optimistic
  // key so React treats them as the same node.
  const keyAliasRef = useRef<Map<string, string>>(new Map());

  // Drop optimistic rows once the authoritative refetch contains them.
  useEffect(() => {
    setPending((prev) =>
      prev.filter((p) => {
        const match = convo.messages.find((m) => m.body === p.body);
        if (match) {
          keyAliasRef.current.set(match.id, p.id);
          return false;
        }
        return true;
      })
    );
  }, [convo.messages]);

  /** Renders a body locally right away, then persists it to the thread. */
  const [hideDatingTools, setHideDatingTools] = useState<boolean>(false);
  const beginChatOperation = useChatOperationGuard(meId, conversationKey(convo));
  const sendWithEcho = async (body: string, assertCurrent: () => void = beginChatOperation()): Promise<boolean> => {
    try { assertCurrent(); } catch { return false; }
    const optimistic: WhisperMessage = {
      id: `pending-${crypto.randomUUID()}`,
      from_user_id: meId,
      from_username: "you",
      to_user_id: convo.otherUserId,
      to_username: convo.otherUsername,
      body,
      created_at: new Date().toISOString(),
      read_at: null,
    };
    setPending((prev) => [...prev, optimistic]);
    try {
      const result = await onSendBody(body, assertCurrent);
      if (result === false) { setPending((previous) => previous.filter((message) => message.id !== optimistic.id)); return false; }
      return true;
    } catch {
      setPending((previous) => previous.filter((message) => message.id !== optimistic.id));
      return false;
    }
  };

  // Merge the authoritative thread with any still-pending optimistic rows,
  // then dedupe by id and sort by time. Deduping guards against a realtime
  // refetch briefly showing a row twice, and the stable sort keeps the
  // thread from reordering mid-poll — both of which read as messages
  // "flickering" or "disappearing".
  const messages: WhisperMessage[] = (() => {
    const merged: WhisperMessage[] = [
      ...collapseMeetMessages(convo.messages),
      ...pending.filter(
        (p) => !convo.messages.some((m) => m.body === p.body)
      ),
    ];
    const seen = new Set<string>();
    const unique = merged.filter((m) => {
      if (seen.has(m.id) || messageTools.hidden.has(m.id)) return false;
      seen.add(m.id);
      return true;
    });
    unique.sort(
      (a, b) =>
        new Date(a.created_at ?? 0).getTime() -
        new Date(b.created_at ?? 0).getTime()
    );
    return unique;
  })();

  // Quiz cards need to know whether their answers landed anywhere in the
  // thread — computed once per render off the cached decodes.
  const answeredQuizIds = new Set<string>();
  for (const msg of messages) {
    const dec = decodeBubble(msg.body);
    if (dec.kind === "quizAnswers") answeredQuizIds.add(dec.quizAnswers.quizId);
  }

  /** Mutual-match state read straight off the thread's wire tokens —
   *  matched when a matched token exists OR both sides asked. */
  const matchState: "none" | "requested" | "theirs" | "matched" = (() => {
    let mine = false;
    let theirs = false;
    for (const m of messages) {
      const token = decodeMatchToken(m.body);
      if (!token || m.id.startsWith("pending-") || token.from.toLowerCase() !== m.from_user_id.toLowerCase()) continue;
      if (token.matched) return "matched";
      if (m.from_user_id === meId) mine = true;
      else theirs = true;
    }
    if (mine && theirs) return "matched";
    if (mine) return "requested";
    if (theirs) return "theirs";
    return "none";
  })();

  // Fire the one-time linking celebration when the thread turns matched.
  useEffect(() => {
    if (!user || matchState !== "matched") return;
    if (matchCelebrationSeen(user.id, conversationKey(convo))) return;
    markMatchCelebrationSeen(user.id, conversationKey(convo));
    markDatingPeer(user.id, convo.otherUserId);
    setDatingTick((t) => t + 1);
    setShowCelebration(true);
  }, [matchState, user, convo.otherUserId]);

  /** Match expiry — anchored on the matched token, reset by any real message (tokens don't count). */
  const matchExpiry = (() => {
    if (matchState !== "matched") return null;
    let matchedAt: Date | null = null;
    for (const m of messages) {
      if (decodeMatchToken(m.body)?.matched && m.created_at) matchedAt = new Date(m.created_at);
    }
    if (!matchedAt || Number.isNaN(matchedAt.getTime())) return null;
    let lastHuman: Date | null = null;
    for (const m of messages) {
      const body = (m.body ?? "").trim();
      if (!body || decodeMatchToken(body) || isSecondDateToken(body) || !m.created_at) continue;
      const at = new Date(m.created_at);
      if (at.getTime() > matchedAt.getTime() && (!lastHuman || at.getTime() > lastHuman.getTime())) lastHuman = at;
    }
    return matchExpiryState(matchedAt, lastHuman);
  })();

  /** The 💘 Match button — request, match back, or replay the celebration. */
  const handleMatchTap = async (): Promise<void> => {
    if (!user) return;
    const name = profile?.username ?? "you";
    if (matchState === "none") {
      if (await sendWithEcho(buildMatchRequest(user.id, name))) toast.success("Match request sent");
    } else if (matchState === "theirs") {
      if (!await sendWithEcho(buildMatched(user.id, name))) return;
      markMatchCelebrationSeen(user.id, conversationKey(convo));
      markDatingPeer(user.id, convo.otherUserId);
      setDatingTick((t) => t + 1);
      setShowCelebration(true);
    } else if (matchState === "matched") {
      setShowCelebration(true);
    } else {
      toast("Waiting for them to match back 💘");
    }
  };

  // Auto-scroll only when something genuinely NEW lands (or on first open) —
  // not on every 8s inbox poll, which used to yank the thread to the bottom
  // while scrolling back through history.
  const lastNewestRef = useRef<string | null>(null);
  const followsLatest = useRef(true);
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const newest = messages[messages.length - 1]?.id ?? null;
    if (followsLatest.current && newest !== lastNewestRef.current && !prependAnchor.current) el.scrollTop = el.scrollHeight;
    lastNewestRef.current = newest;
  }, [messages, scrollRef]);

  // "Seen" receipt — shown under my newest message once they've read it.
  const lastSeenOwnId = (() => {
    for (let i = messages.length - 1; i >= 0; i--) {
      const m = messages[i];
      if (m.from_user_id === meId) return m.read_at ? m.id : null;
    }
    return null;
  })();

  /** Runs a recognised /jasper (or legacy /ember) command and posts the
   *  result as a DM embed. */
  const runJasperCommand = async (raw: string): Promise<boolean> => {
    const text = raw.trim();
    const after = knotCommandPrompt(text);
    if (after === null) return false;
    const afterLower = after.toLowerCase();
    const check = beginChatOperation();
    setDraft("");
    setShowGiphy(false);
    setShowEmoji(false);
    setEmberPreview(null);
    setEmberBusy(true);
    setEmberWorking(afterLower.startsWith("nearby") || afterLower.startsWith("recipe"));
    try {
      if (afterLower === "nearby" || afterLower.startsWith("nearby")) {
        // Nearby sends straight into the thread (no preview), like iOS.
        const payload = await buildNearbyPayload();
        check();
        await sendWithEcho(encodeMap(payload), check);
      } else if (afterLower.startsWith("recipe")) {
        // `/ember recipe <dish>` routes to the same recipe card builder as the
        // top-level `/recipe` command — sends straight into the thread.
        const dish = after.slice("recipe".length).trim();
        await sendRecipeCard(dish, check);
      } else if (afterLower.startsWith("factcheck")) {
        const claim = after.slice("factcheck".length).trim();
        if (!claim) return true;
        const r = await factCheck(claim);
        check();
        setEmberPreview({
          kind: "fact",
          claim,
          verdict: r.verdict,
          summary: r.summary,
          explanation: r.explanation,
          sources: r.sources,
        });
      } else {
        // Route through the SAME shared brain (`/ember/chat`) that iOS uses
        // for in-DM Ember replies — not the separate web-answer proxy. This
        // gives the DM Ember access to health context, real `/interpret`
        // analysis, and block cards, exactly like the standalone Ember chat.
        const question = after || "What should I help with in this chat?";
        const ctx = await buildEmberHealthContext(profile?.display_name ?? profile?.username);
        check();
        const history: BrainChatMessage[] = messages
          .slice(-10)
          .map((m) => ({
            role: (m.from_user_id === meId ? "user" : "assistant") as "user" | "assistant",
            content: m.body ?? "",
          }))
          .filter((m) => m.content.length > 0);
        const r = await emberEngineRespond({ message: question, context: ctx, history, assertCurrent: check });
        check();
        setEmberPreview({
          kind: "answer",
          question,
          answer: r.text || "Couldn't reach Knot right now. Try again in a sec.",
          sources: [],
          tldr: null,
        });
      }
    } catch {
      try { check(); toast.error("Couldn't complete this request. Please try again."); } catch { /* Obsolete conversation. */ }
    } finally {
      try { check(); setEmberBusy(false); setEmberWorking(false); } catch { /* Obsolete conversation. */ }
    }
    return true;
  };

  /** Builds a recipe card for a dish and sends it straight into the thread. */
  const sendRecipeCard = async (dish: string, check: () => void = beginChatOperation()): Promise<void> => {
    const r = await emberRecipe(dish);
    check();
    const payload: RecipePayload = {
      id: crypto.randomUUID(),
      title: r.title,
      summary: r.summary,
      prepTime: r.prepTime,
      cookTime: r.cookTime,
      servings: r.servings,
      ingredients: r.ingredients,
      steps: r.steps,
      calories: r.calories,
      protein: r.protein,
      carbs: r.carbs,
      fat: r.fat,
    };
    await sendWithEcho(encodeRecipe(payload), check);
  };

  /** Runs a top-level `/recipe <dish>` command. */
  const runRecipeCommand = async (raw: string): Promise<void> => {
    const dish = raw.trim().slice("/recipe".length).trim();
    setDraft("");
    setShowGiphy(false);
    setShowEmoji(false);
    setEmberPreview(null);
    setEmberBusy(true);
    setEmberWorking(true);
    try {
      await sendRecipeCard(dish);
    } finally {
      setEmberBusy(false);
      setEmberWorking(false);
    }
  };

  /** Sends a recipe's ingredients into the thread as a grocery list embed. */
  const sendGroceryFromRecipe = (title: string, ingredients: string[]): void => {
    if (ingredients.length === 0) return;
    void sendWithEcho(
      encodeGrocery({
        id: crypto.randomUUID(),
        title: `Grocery: ${title}`,
        items: ingredients,
        authorUsername: "you",
      })
    );
  };

  /** Shares the current Ember preview into the thread, then clears it. */
  const shareEmberPreview = async (): Promise<void> => {
    const p = emberPreview;
    if (!p) return;
    setEmberPreview(null);
    if (p.kind === "answer") {
      await sendWithEcho(
        encodeEmberAnswer({
          id: crypto.randomUUID(),
          question: p.question,
          answer: p.answer,
          sources: p.sources,
          tldr: p.tldr,
        })
      );
    } else {
      await sendWithEcho(
        encodeFactCheck({
          id: crypto.randomUUID(),
          claim: p.claim,
          verdictRaw: p.verdict,
          summary: p.summary,
          explanation: p.explanation,
          sources: p.sources,
        })
      );
    }
  };

  /** Uploads a validated photo/video and sends it as an inline attachment. */
  const handleImagePick = async (
    e: React.ChangeEvent<HTMLInputElement>
  ): Promise<void> => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file || uploading) return;
    setShowGiphy(false);
    setShowEmoji(false);
    setUploading(true);
    const assertCurrent = beginChatOperation();
    try {
      const url = await uploadChatMedia(file, meId, assertCurrent);
      assertCurrent();
      await sendWithEcho(url, assertCurrent);
    } catch (error) {
      toast.error(error instanceof Error && !error.message.includes("{ ") ? error.message : "Couldn't send this attachment. Please try again.");
    } finally {
      setUploading(false);
    }
  };

  /** Rings the other person and jumps into the call room (voice or video).
   *  Titles match iOS ("Audio call with @x" / "Video call with @x") so both
   *  clients render the same thing, and the invite carries `mode` so iOS
   *  rings it as a voice call instead of defaulting to video. */
  const startCall = async (mode: "audio" | "video"): Promise<void> => {
    if (!profile) return;
    try {
      const meeting = await createMeeting({
        hostId: meId,
        hostUsername: profile.username ?? "you",
        title: `${mode === "audio" ? "Audio" : "Video"} call with @${convo.otherUsername}`,
      });
      // Ring them: the call card lands in the thread and their incoming-call
      // overlay picks it up in realtime. No wait room — the call connects
      // the moment they answer.
      await onSendBody(
        encodeCallInvite({
          meetingId: meeting.id,
          fromUserId: meId,
          fromUsername: profile.username ?? "you",
          toUserId: convo.otherUserId,
          mode,
        })
      );
      navigate(
        `/meet/${meeting.id}?call=${encodeURIComponent(convo.otherUsername)}${mode === "audio" ? "&mode=audio" : ""}`
      );
    } catch {
      toast.error("Couldn't start the call. Try again.");
    }
  };

  const submit = async (e: React.FormEvent): Promise<void> => {
    e.preventDefault();
    if (emberBusy) return;
    const lowerDraft = trimmed.toLowerCase();
    if (knotCommandPrompt(trimmed) !== null) {
      await runJasperCommand(trimmed);
      return;
    }
    if (lowerDraft.startsWith("/recipe")) {
      await runRecipeCommand(trimmed);
      return;
    }
    if (replyTo && trimmed) {
      const check = beginChatOperation();
      const reply = replyTo;
      const body = buildGroupReplyBody({ key: reply.id, fromUserId: reply.from_user_id, fromUsername: reply.from_username ?? convo.otherUsername, body: reply.body, createdAt: reply.created_at }, trimmed);
      if (await sendWithEcho(body, check)) { try { check(); setReplyTo(current => current?.id === reply.id ? null : current); if (composerRef.current?.value.trim() === trimmed) setDraft(""); } catch { /* Obsolete conversation. */ } }
      return;
    }
    onSend(e);
  };

  return (
    <section aria-label="Conversation" className="relative flex h-[calc(100dvh-76px-env(safe-area-inset-bottom))] min-h-0 w-full flex-col lg:h-dvh">
      {/* Full-screen meeting notes — the exact screen the Meetings page and
          ended calls show, opened from a notes DM card (parity with iOS). */}
      {notesView && (
        <div className="fixed inset-0 z-[80] overflow-y-auto bg-background">
          <MeetingNotesScreen
            title={notesView.title}
            notes={notesView.notes}
            transcript={notesView.transcript}
            meetingId={notesView.meetingId}
            onClose={() => setNotesView(null)}
          />
        </div>
      )}
      {showCelebration && (
        <MatchCelebration
          myName={profile?.username ?? "you"}
          myAvatarUrl={profile?.profile_image_url}
          otherName={convo.otherUsername}
          otherAvatarUrl={convo.otherProfile?.profile_image_url}
          onDismiss={() => setShowCelebration(false)}
        />
      )}
      <GroupThemeSurface design={personalAppearance.design} wallpaper={personalAppearance.wallpaper}
        className="flex h-full min-h-0 w-full flex-col overflow-hidden !rounded-none"
      >
      {reportTarget && <MessageReportDialog account={meId} thread={conversationKey(convo)} target={reportTarget} onClose={() => setReportTarget(null)} />}
      {forwardBody !== null && <ForwardMessageDialog account={meId} username={profile?.username ?? "you"} thread={conversationKey(convo)} body={forwardBody} onClose={() => setForwardBody(null)} />}
      {creativeMode && <ChatCreativeTool key={`${meId}:${conversationKey(convo)}:${creativeMode}`} owner={meId} thread={conversationKey(convo)} mode={creativeMode} onClose={() => setCreativeMode(null)} onSend={sendWithEcho} />}
      {meetOpen && <ChatMeetScheduler key={`${meId}:${conversationKey(convo)}`} owner={meId} thread={conversationKey(convo)} kind={convo.kind === "dating" ? "dating" : "direct"} peerID={convo.otherUserId} name={convo.otherUsername} onClose={() => setMeetOpen(false)} onScheduled={() => { void threadQueryClient.invalidateQueries({ queryKey: ["conversations"] }); }} />}
      <NotesEntry open={notesOpen} onOpenChange={setNotesOpen} />
      <ConversationDetails key={`${meId}:${conversationKey(convo)}`} convo={convo} accountID={meId} messages={messages} onBlocked={onBack} open={detailsOpen} onOpenChange={setDetailsOpen} onSelect={id => messageNodes.current.get(id)?.scrollIntoView({ block: "center", behavior: "auto" })} />
      <header className="relative z-30 flex min-h-16 shrink-0 items-center gap-2 border-b border-border bg-background/90 px-3 backdrop-blur-xl">
        <button
          onClick={onBack}
          className="flex h-9 w-9 items-center justify-center rounded-full transition-colors hover:bg-secondary"
          aria-label="Back"
        >
          <ArrowLeft className="h-5 w-5" />
        </button>
        <button type="button" aria-label="Conversation details" aria-haspopup="dialog" onClick={() => setDetailsOpen(true)} className="flex min-h-11 min-w-0 flex-1 items-center gap-2.5 text-left">
        <Avatar
          url={convo.otherProfile?.profile_image_url}
          name={convo.otherUsername}
          size={32}
        />
        <div className="min-w-0 flex-1">
          <p className="flex items-center gap-1 truncate text-[15px] font-bold">
            <span className="truncate">
              {nickname || convo.otherProfile?.display_name || convo.otherUsername}
            </span>
            <UserBadges profile={convo.otherProfile} liar={liar} size={13} />
          </p>
          {presenceLabel(lastSeenAt) ? (
            <p className="flex items-center gap-1 truncate text-[12px] text-muted-foreground">
              {isActiveNow(lastSeenAt) && (
                <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-[#1cd14f]" />
              )}
              {presenceLabel(lastSeenAt)}
            </p>
          ) : (
            <p className="truncate text-[12px] text-muted-foreground">
              @{convo.otherUsername}
            </p>
          )}
        </div><ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
        </button>
        <button
          onClick={() => void startCall("audio")}
          aria-label="Voice call"
          className="flex h-9 w-9 items-center justify-center rounded-full transition-colors hover:bg-secondary"
          title="Start voice call"
        >
          <Phone className="h-5 w-5" />
        </button>
        <button
          onClick={() => void startCall("video")}
          aria-label="Video call"
          className="flex h-9 w-9 items-center justify-center rounded-full transition-colors hover:bg-secondary"
          title="Start video call"
        >
          <Video className="h-5 w-5" />
        </button>
        <button
          onClick={onBack}
          aria-label="Close"
          className="flex h-9 w-9 items-center justify-center rounded-full transition-colors hover:bg-secondary md:flex"
        >
          <X className="h-5 w-5" />
        </button>
      </header>

      <div
        ref={scrollRef}
        className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 py-5"
        onScroll={(event) => {
          const el = event.currentTarget;
          followsLatest.current = el.scrollHeight - el.scrollTop - el.clientHeight < 100;
          if (el.scrollTop < 80 && !history.isError) void loadOlder();
        }}
      >
        <MessageHistoryStatus
          loading={history.isFetching}
          failure={history.isError ? (history.isFetchNextPageError ? "earlier" : "refresh") : null}
          onRetry={() => void (history.isFetchNextPageError ? loadOlder() : history.refetch())}
        />
        {messageTools.pinned && messages.some(message => message.id === messageTools.pinned) && <button type="button" className="mb-3 flex min-h-11 w-full items-center gap-2 rounded-xl bg-background/90 px-3 text-left text-xs" onClick={() => messageNodes.current.get(messageTools.pinned!)?.scrollIntoView({ block: "center" })}><Pin className="h-4 w-4 shrink-0" /><span className="truncate">Pinned in this browser · {quoteLabelFor(messages.find(message => message.id === messageTools.pinned)!.body)}</span></button>}
        {messages.map((m, i) => {
          const d = decodeBubble(m.body);
          // Call control signals (accept/decline/cancel/end) ride the DM
          // channel but aren't chat — never render them as bubbles.
          if (d.kind === "hidden") return null;
          // 📅 second-date wire — the rose scheduler card, never the raw token.
          const secondDate = decodeSecondDate(m.body);
          if (secondDate) {
            return (
              <div
                key={keyAliasRef.current.get(m.id) ?? m.id}
                className={cn("flex py-1.5", m.from_user_id === meId ? "justify-end" : "justify-start")}
              >
                <SecondDateCard
                  invite={secondDate.invite}
                  confirm={secondDate.confirm}
                  mine={m.from_user_id === meId}
                  partnerName={convo.otherUsername}
                  onAccept={() => void sendWithEcho(encodeDateConfirm(secondDate.invite))}
                  onJoin={(code) => navigate(`/meet/${encodeURIComponent(code)}?sd=1`)}
                />
              </div>
            );
          }
          // 💘 match wire — a quiet rose system line, never the raw token.
          const matchToken = decodeMatchToken(m.body);
          if (matchToken) {
            return (
              <div
                key={keyAliasRef.current.get(m.id) ?? m.id}
                className="flex justify-center py-1.5"
              >
                <span className="flex items-center gap-1.5 rounded-full bg-rose-500/10 px-3 py-1.5 text-[12px] font-semibold text-rose-500">
                  {matchToken.matched
                    ? `💘 It's a match! You and @${convo.otherUsername}`
                    : m.from_user_id === meId
                      ? "💘 You asked to match"
                      : `💘 @${convo.otherUsername} wants to match`}
                </span>
              </div>
            );
          }
          const mine = m.from_user_id === meId;
          const prev = i > 0 ? messages[i - 1] : null;
          const gapMs =
            prev?.created_at && m.created_at
              ? new Date(m.created_at).getTime() - new Date(prev.created_at).getTime()
              : Number.POSITIVE_INFINITY;
          // 15-minute session separators + grouped runs — parity with iOS.
          const showStamp = gapMs > 15 * 60 * 1000;
          const sameRunAsPrev = !!prev && prev.from_user_id === m.from_user_id && !showStamp;
          return (
            <div key={keyAliasRef.current.get(m.id) ?? m.id} ref={node => { if (node) messageNodes.current.set(m.id, node); else messageNodes.current.delete(m.id); }}>
              {showStamp && m.created_at && (
                <div className="flex justify-center py-2.5">
                  <span className="rounded-full bg-secondary/70 px-3 py-1 text-[10.5px] font-medium text-muted-foreground">
                    {stampLabel(m.created_at)}
                  </span>
                </div>
              )}
              <MessageActions mine={mine} insetControls disabled={m.id.startsWith("pending-")} reactions={sharedReactions.rows[m.id.toLowerCase()] ?? []} onReaction={emoji => void sharedReactions.toggle(m.id, emoji)} actions={[
                { label: "Reply", icon: <Reply className="h-4 w-4" />, run: () => { setReplyTo(m); composerRef.current?.focus(); } },
                { label: "Forward", icon: <Send className="h-4 w-4" />, run: () => setForwardBody(m.body) },
                { label: "Copy", icon: <Copy className="h-4 w-4" />, run: async () => { try { await navigator.clipboard.writeText(quoteLabelFor(m.body)); toast("Copied"); } catch { toast.error("Couldn't copy this message."); } } },
                { label: messageTools.pinned === m.id ? "Unpin" : "Pin to top", icon: <Pin className="h-4 w-4" />, run: () => messageTools.pin(m.id) },
                { label: "Show time sent", icon: <ClockIcon className="h-4 w-4" />, run: () => setRevealedTimeId(m.id) },
                ...(!mine ? [{ label: "Report message", icon: <Flag className="h-4 w-4" />, run: () => setReportTarget({ id: m.id, username: m.from_username ?? convo.otherUsername, senderID: m.from_user_id, body: m.body }) }] : []),
                { label: "Delete for you", icon: <Trash2 className="h-4 w-4" />, confirmation: { title: "Delete for you?", detail: "This hides the message in this browser only. Other people will still see it." }, run: () => messageTools.hide(m.id) },
                ...(mine ? [{ label: "Unsend", icon: <Undo2 className="h-4 w-4" />, destructive: true, confirmation: { title: "Unsend message?", detail: "Remove this message from both sides of this chat. Previously downloaded or saved copies cannot be removed." }, run: async () => { if (await messageTools.unsend([m.id])) setPending(current => current.filter(message => message.body !== m.body)); } }] : []),
              ]} className={cn("flex flex-col", mine ? "items-end" : "items-start", sameRunAsPrev ? "mt-0.5" : "mt-2")}>
              {revealedTimeId === m.id && d.kind !== "text" && <span className="mb-1 text-[10px] text-muted-foreground">{clockTime(m.created_at)}</span>}
              {teamsCardCandidate(m.body, m.id) ? <TeamsInvitationCard message={m} /> : notesDocumentCardCandidate(m.embed, m.id) ? <div className="max-w-[280px] space-y-2 rounded-2xl border border-border bg-background p-4 text-foreground"><p className="whitespace-pre-wrap break-words text-sm">{m.body}</p><p className="text-xs text-muted-foreground">Status not checked</p></div> : d.kind === "notes" ? (
                <MeetingNotesDmCard
                  payload={d.notes}
                  onOpen={() => setNotesView(d.notes)}
                />
              ) : d.kind === "story" ? (
                <SharedStoryCard storyID={d.storyID} />
              ) : d.kind === "calendar" ? (
                <CalendarInviteDmCard
                  payload={d.calendar}
                  mine={mine}
                  onOpen={() => {
                    // Close the thread BEFORE navigating so the calendar is
                    // never hidden behind the full-screen DM view.
                    onBack();
                    navigate("/calendar");
                  }}
                />
              ) : d.kind === "ember" ? (
                <EmberDmCard body={m.body} mine={mine} />
              ) : d.kind === "dmEmbed" ? (
                <ChatMessageBoundary><DmEmbedCard body={m.body} mine={mine} meId={meId} /></ChatMessageBoundary>
              ) : d.kind === "recipe" ? (
                <RecipeCard
                  payload={d.recipe}
                  mine={mine}
                  meId={meId}
                  onAddToGrocery={sendGroceryFromRecipe}
                />
              ) : d.kind === "film" || d.kind === "article" ? (
                <div
                  className={cn(
                    "flex max-w-[85%] flex-col gap-1.5",
                    mine ? "items-end" : "items-start"
                  )}
                >
                  {d.caption && (
                    <div
                      className={cn(
                        "rounded-[22px] px-3.5 py-[9px] text-[15px] leading-snug",
                        mine
                          ? "group-outgoing"
                          : "group-incoming"
                      )}
                    >
                      <p className="whitespace-pre-wrap break-words">{d.caption}</p>
                    </div>
                  )}
                  {d.kind === "film" ? (
                    <FilmEmbedCard payload={d.film} />
                  ) : (
                    <ArticleEmbedCard payload={d.article} />
                  )}
                </div>
              ) : d.kind === "quiz" ? (
                <PlanQuizCard
                  payload={d.quiz}
                  mine={mine}
                  answered={answeredQuizIds.has(d.quiz.id)}
                  toUserId={convo.otherUserId}
                  toUsername={convo.otherUsername}
                />
              ) : d.kind === "quizAnswers" ? (
                <PlanQuizAnswersCard payload={d.quizAnswers} mine={mine} />
              ) : d.kind === "sharedPost" ? (
                <div
                  className={cn(
                    "flex max-w-[85%] flex-col gap-1.5",
                    mine ? "items-end" : "items-start"
                  )}
                >
                  {d.caption && (
                    <div
                      className={cn(
                        "rounded-[22px] px-3.5 py-[9px] text-[15px] leading-snug",
                        mine
                          ? "group-outgoing"
                          : "group-incoming"
                      )}
                    >
                      <p className="whitespace-pre-wrap break-words">{d.caption}</p>
                    </div>
                  )}
                  <SharedPostCard payload={d.post} mine={mine} />
                </div>
              ) : d.kind === "community" ? (
                <Link to={`/c/${encodeURIComponent(d.community.id)}`} className="block w-[250px] max-w-full space-y-3 rounded-[22px] border border-border bg-card p-4 text-card-foreground" aria-label={`View ${d.community.name} community`}>
                  <p className="text-xs text-muted-foreground">Shared community</p>
                  <div className="flex items-center gap-3">
                    <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl text-white" style={{ background: `linear-gradient(135deg, ${d.community.gradient[0]}, ${d.community.gradient[1]})` }}><d.community.icon className="h-6 w-6" aria-hidden="true" /></span>
                    <p className="font-semibold">{d.community.name}</p>
                  </div>
                  <p className="text-sm text-muted-foreground">{d.community.tagline}</p>
                  <p className="text-xs font-semibold">View community ↗</p>
                </Link>
              ) : d.kind === "profile" ? (
                <SharedProfileDmCard payload={d.profile} mine={mine} />
              ) : d.kind === "sticker" ? (
                <img
                  src={`/stickers/${d.sticker}.png`}
                  alt="Sticker"
                  width={124}
                  height={124}
                  draggable={false}
                  loading="lazy"
                  onError={(e) => {
                    e.currentTarget.src = "/jasper-ghost.png";
                  }}
                  className="h-[124px] w-[124px] select-none object-contain drop-shadow-[0_8px_18px_rgba(0,0,0,0.18)]"
                />
              ) : d.kind === "video" ? (
                <ChatVideo url={d.url} />
              ) : d.kind === "media" ? (
                <div className="max-w-[60%]">
                  <img
                    src={d.url}
                    alt=""
                    loading="lazy"
                    className="w-full rounded-2xl border border-border"
                  />
                </div>
              ) : (
                <div className={cn("flex max-w-[78%] flex-col gap-1", mine ? "items-end" : "items-start")}>
                  {(() => {
                    // A REPLY — the quote rides the body in plain text
                    // (`↩ @name: "quote"\n\nreply`, the same grammar as
                    // groups and iOS). Render the reference look: a quiet
                    // "Replied to you" label, the quoted message as a lighter
                    // bubble with a bar on its outer edge, then the reply.
                    const split = d.kind === "text" ? splitGroupReply(d.text) : { quote: null, text: "" };
                    if (!split.quote) return null;
                    const myName = (profile?.username ?? "").toLowerCase();
                    const quotedMine = split.quote.username.toLowerCase() === myName;
                    const label = mine
                      ? quotedMine
                        ? "You replied to yourself"
                        : "You replied"
                      : quotedMine
                        ? "Replied to you"
                        : "Replied to themselves";
                    return (
                      <>
                        <span className="px-1.5 text-[12px] text-muted-foreground">{label}</span>
                        <div className={cn("flex items-stretch gap-2", mine ? "flex-row-reverse" : "flex-row")}>
                          <span className="w-[3px] shrink-0 rounded-full bg-muted-foreground/45" />
                          {(() => {
                            // A quoted CARD or photo renders as a MINI card
                            // (icon tile + its friendly line) — never the card.
                            const kind = quoteCardKind(split.quote.text);
                            return kind ? (
                              <ChatQuoteMiniCard quoteText={split.quote.text} kind={kind} quotedMine={quotedMine} />
                            ) : (
                              <p
                                className={cn(
                                  "line-clamp-3 whitespace-pre-wrap break-words rounded-2xl px-3.5 py-2 text-[15px] leading-snug",
                                  quotedMine ? "bg-foreground/40 text-background" : "bg-secondary/70 text-muted-foreground"
                                )}
                              >
                                {split.quote.text}
                              </p>
                            );
                          })()}
                        </div>
                      </>
                    );
                  })()}
                  {d.kind === "text" && chatVideoUrl(splitGroupReply(d.text).text) ? <ChatVideo url={chatVideoUrl(splitGroupReply(d.text).text)!} /> :
                  d.kind === "text" && mediaUrlOf(splitGroupReply(d.text).text) ? <img src={mediaUrlOf(splitGroupReply(d.text).text)!} alt="Photo attachment" className="max-h-[300px] max-w-[240px] rounded-2xl object-contain" /> : <>
                  <div
                    onClick={() =>
                      setRevealedTimeId((cur) => (cur === m.id ? null : m.id))
                    }
                    className={cn(
                      "rounded-[22px] px-3.5 py-[9px] text-[15px] leading-snug",
                      mine ? "group-outgoing" : "group-incoming"
                    )}
                  >
                    {d.kind === "text" && firstLinkUrl(splitGroupReply(d.text).text) ? (
                      <LinkedText text={splitGroupReply(d.text).text} />
                    ) : (
                      <p className="whitespace-pre-wrap break-words">
                        {d.kind === "text" ? splitGroupReply(d.text).text : ""}
                      </p>
                    )}
                    {revealedTimeId === m.id && (
                      <span
                        className={cn(
                          "mt-1 block text-right text-[10px]",
                          "opacity-65"
                        )}
                      >
                        {clockTime(m.created_at)}
                      </span>
                    )}
                  </div>
                  {d.kind === "text" && firstLinkUrl(splitGroupReply(d.text).text) && (
                    <LinkPreviewCard url={firstLinkUrl(splitGroupReply(d.text).text) as string} />
                  )}
                  </>}
                </div>
              )}
              </MessageActions>
              {m.id === lastSeenOwnId && (
                <p className="mt-1 pr-1 text-right text-[10.5px] font-medium text-muted-foreground">
                  Seen
                </p>
              )}
            </div>
          );
        })}
        {emberPreview && <EmberPreviewCard preview={emberPreview} username={convo.otherUsername} onShare={() => void shareEmberPreview()} onDismiss={() => setEmberPreview(null)} />}
      </div>

      <div className="relative">
        {EMBER_ENABLED && jasperPillMode && (
          /* THE JASPER PEEK PILL — one identity per pill FAMILY so the
             fade-up plays when it first appears (and changes job), not on
             every key. Left-anchored above the bar, iOS's exact grammar. */
          <div
            key={jasperPillMode}
            className="jasper-pill-in pointer-events-auto absolute bottom-full left-3 z-20 mb-2 max-w-[calc(100%-24px)]"
          >
            <div className={cn("flex gap-2 rounded-[22px] border border-border bg-background/95 p-2 shadow-lg backdrop-blur-xl", jasperPillMode === "commands" ? "w-[min(340px,calc(100vw-48px))] items-start" : "items-center")}>
              {jasperPillMode !== "commands" && <JasperSpark size={9} className="ml-0.5 shrink-0" />}
              {jasperPillMode === "commands" ? (
                <div className="max-h-[min(360px,45dvh)] w-full overflow-y-auto" aria-label="Knot commands">
                  {slashMatches.slice(0, 8).map((c) => (
                    <button
                      key={c.fill}
                      type="button"
                      onClick={() => {
                        if (c.runImmediate) {
                          void runJasperCommand(c.fill);
                        } else {
                          setDraft(c.fill);
                        }
                      }}
                      className="flex min-h-14 w-full items-center gap-3 rounded-xl px-3 py-2 text-left hover:bg-secondary focus-visible:bg-secondary"
                    >
                      <span className="text-foreground/75 [&>svg]:h-5 [&>svg]:w-5">{c.icon}</span>
                      <span className="flex flex-col leading-tight">
                        <span className="text-[13px] font-semibold text-foreground">/{c.name}</span>
                        <span className="text-xs leading-relaxed text-muted-foreground">{c.hint}</span>
                      </span>
                    </button>
                  ))}
                </div>
              ) : (
                <span className="flex items-center gap-2 whitespace-nowrap py-0.5 text-[13px] font-medium text-foreground/85">
                  {jasperPillMode === "ask"
                    ? "Ask Knot · press ↵ to send"
                    : jasperPillMode === "working"
                      ? "Knot is putting that together"
                      : "Knot is thinking"}
                  {jasperPillMode !== "ask" && (
                    <span className="ml-0.5 flex items-center gap-0.5">
                      <span className="ember-dot" />
                      <span className="ember-dot ember-dot-2" />
                      <span className="ember-dot ember-dot-3" />
                    </span>
                  )}
                </span>
              )}
            </div>
          </div>
        )}
        {showGiphy && (
          <GiphyPicker
            onSelect={(url) => {
              void onSendBody(url);
              setShowGiphy(false);
            }}
            onClose={() => setShowGiphy(false)}
          />
        )}

        {showEmoji && (
          <div className="absolute inset-x-0 bottom-full mx-2 mb-2 grid grid-cols-8 gap-1 rounded-2xl border border-border bg-popover p-2 shadow-2xl">
            {DM_EMOJIS.map((e) => (
              <button
                key={e}
                onClick={() => setDraft(draft + e)}
                className="flex h-9 items-center justify-center rounded-lg text-xl transition-colors hover:bg-secondary"
              >
                {e}
              </button>
            ))}
          </div>
        )}

        <form
          onSubmit={submit}
          className="sticky bottom-0 px-3 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]"
        >
          {/* The Whisper bar — Jasper has no button here: his presence is the
              peek pill above (spark-led, iOS grammar). No mascot ever climbs
              over the composer's edge. */}
          <div className="relative">
          {user && convo.kind === "dating" && !hideDatingTools && (
            <div className="mb-2 flex items-center gap-1.5 overflow-x-auto pb-0.5">
              <EmberMascot
                size={26}
                palette={{ accent: "#F5B8CC", softAccent: "#FFEDF2", deepAccent: "#E68FAD" }}
                smitten
                className="shrink-0"
              />
              <button
                type="button"
                onClick={handleMatchTap}
                className={cn(
                  "shrink-0 rounded-full px-3 py-1.5 text-[11.5px] font-bold transition-transform active:scale-95",
                  matchState === "none" || matchState === "theirs"
                    ? "bg-gradient-to-r from-rose-500 to-pink-500 text-white shadow-sm shadow-rose-500/30"
                    : "border border-rose-300/60 bg-rose-500/10 text-rose-500",
                  matchState === "theirs" && "animate-pulse"
                )}
              >
                {matchState === "matched"
                  ? "💘 Matched"
                  : matchState === "requested"
                    ? "💘 Requested"
                    : matchState === "theirs"
                      ? "💘 Match back!"
                      : "💘 Match"}
              </button>
              {matchExpiry?.chip ? (
                // Round 77 — matches fade after 7 quiet days; the chip nudges first.
                <span
                  className={cn(
                    "shrink-0 rounded-full px-3 py-1.5 text-[11.5px] font-bold",
                    matchExpiry.faded
                      ? "bg-zinc-500/50 text-white/85"
                      : "border border-rose-300/60 bg-rose-500/10 text-rose-500"
                  )}
                >
                  {matchExpiry.chip}
                </span>
              ) : null}
              {DATING_CHAT_TOOLS.map((t) => (
                <button
                  key={t.label}
                  type="button"
                  onClick={() => setDraft(t.fill)}
                  className="shrink-0 rounded-full border border-rose-300/50 bg-rose-500/10 px-3 py-1.5 text-[11.5px] font-bold text-rose-500 transition-transform active:scale-95"
                >
                  {t.label}
                </button>
              ))}
              <button
                type="button"
                onClick={() => setHideDatingTools(true)}
                aria-label="Hide dating tools"
                title="Hide dating tools"
                className="shrink-0 rounded-full border border-rose-300/40 px-2.5 py-1.5 text-[11.5px] font-bold text-rose-400/80 transition-transform active:scale-95"
              >
                💔
              </button>
            </div>
          )}
          {/* THE WHISPER BAR (iOS parity) — flat and quiet: a bare ink "+" opens
              the attach tray, the field is a rounded card, the quick tools sit
              OUTSIDE the field as bare glyphs and fold into a single ink send
              disc the moment you type. */}
          <input
            ref={fileInputRef}
            type="file"
            accept="image/*,video/mp4,video/quicktime,video/x-m4v,video/webm"
            className="hidden"
            onChange={(e) => void handleImagePick(e)}
          />
          {replyTo && <div className="mb-2 flex items-center gap-3 border-l-2 border-foreground/40 px-3"><div className="min-w-0 flex-1"><p className="text-xs font-semibold">Replying to @{replyTo.from_username ?? convo.otherUsername}</p><p className="truncate text-xs text-muted-foreground">{quoteLabelFor(replyTo.body)}</p></div><button type="button" aria-label="Cancel reply" className="flex h-11 w-11 items-center justify-center" onClick={() => setReplyTo(null)}><X className="h-4 w-4" /></button></div>}
          <div className="relative z-10 flex items-end gap-1">
            <Popover open={showAttachTray} onOpenChange={value => { setShowAttachTray(value); setShowGiphy(false); setShowEmoji(false); }}>
              <PopoverTrigger asChild><button type="button" aria-label="Add to conversation" className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-foreground hover:bg-secondary"><PlusIcon className="h-[22px] w-[22px]" strokeWidth={2} /></button></PopoverTrigger>
              <PopoverContent side="top" align="start" sideOffset={12} collisionPadding={12} className="chat-attachment-popover" onCloseAutoFocus={event => event.preventDefault()}>
                {[
                  { label: "Photos & videos", icon: <ImageIcon className="h-5 w-5" />, run: () => fileInputRef.current?.click() },
                  { label: "Meetings", icon: <Video className="h-5 w-5" />, run: () => setMeetOpen(true) },
                  { label: "Notes", icon: <FileText className="h-5 w-5" />, run: () => setNotesOpen(true) },
                  { label: "GIF", icon: <Layers className="h-5 w-5" />, run: () => { setShowGiphy(true); setShowEmoji(false); } },
                  { label: "Stickers", icon: <Smile className="h-5 w-5" />, run: () => setCreativeMode("stickers") },
                  { label: "Draw", icon: <Pencil className="h-5 w-5" />, run: () => setCreativeMode("draw") },
                  { label: "Imagine", icon: <Wand2 className="h-5 w-5" />, run: () => setCreativeMode("imagine") },
                  { label: "Nearby", icon: <MapPin className="h-5 w-5" />, run: () => setCreativeMode("nearby") },
                  { label: "Emoji", icon: <Smile className="h-5 w-5" />, run: () => { setShowEmoji(true); setShowGiphy(false); } },
                  { label: "Link", icon: <Link2Icon className="h-5 w-5" />, run: () => { setDraft(draft ? `${draft} https://` : "https://"); composerRef.current?.focus(); } },
                  ...(EMBER_ENABLED ? [{ label: "Ask Knot privately", icon: <Sparkles className="h-5 w-5" />, run: () => { setDraft("/knot "); composerRef.current?.focus(); } }] : []),
                  { label: "Conversation details & appearance", icon: <MessageCircle className="h-5 w-5" />, run: () => setDetailsOpen(true) },
                ].map(item => <button key={item.label} type="button" className="chat-attachment-action" onClick={() => { setShowAttachTray(false); item.run(); }}>{item.icon}<span>{item.label}</span></button>)}
              </PopoverContent>
            </Popover>
            <textarea
              ref={composerRef}
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onFocus={() => {
                setShowGiphy(false);
                setShowEmoji(false);
                setShowAttachTray(false);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
                  e.preventDefault();
                  void submit(e as unknown as React.FormEvent);
                }
              }}
              rows={1}
              placeholder={showSlash ? "Type a Knot command…" : "Message…"}
              className={cn(
                "max-h-32 min-h-[40px] min-w-0 flex-1 resize-none rounded-[21px] border bg-secondary/60 px-4 py-2.5 text-[15px] leading-snug outline-none transition-colors focus:bg-background",
                showSlash ? "border-foreground/30" : "border-border focus:border-foreground/30"
              )}
            />
            {draft.trim() ? (
              <button
                type="submit"
                disabled={emberBusy}
                aria-label="Send"
                className="group-outgoing mb-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full transition-transform active:scale-90 disabled:opacity-40"
              >
                <ArrowUpIcon className="h-4 w-4" strokeWidth={2.6} />
              </button>
            ) : (
              <>
                <button
                  type="button"
                  onClick={() => fileInputRef.current?.click()}
                  disabled={uploading}
                  aria-label="Send a photo"
                  className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-foreground/85 transition-colors hover:bg-secondary disabled:opacity-50"
                >
                  {uploading ? <Loader2 className="h-5 w-5 animate-spin" /> : <ImageIcon className="h-5 w-5" />}
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setShowEmoji((v) => !v);
                    setShowGiphy(false);
                  }}
                  aria-label="Add emoji or sticker"
                  className={cn(
                    "flex h-10 w-10 shrink-0 items-center justify-center rounded-full transition-colors hover:bg-secondary",
                    showEmoji ? "text-foreground" : "text-foreground/85"
                  )}
                >
                  <Smile className="h-5 w-5" />
                </button>
              </>
            )}
          </div>
          </div>
        </form>
      </div>
      </GroupThemeSurface>
    </section>
  );
}
