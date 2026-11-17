import { memo, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import * as Dialog from "@radix-ui/react-dialog";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Check,
  Clapperboard,
  ClipboardList,
  FileText,
  Link2,
  Play,
  Repeat2,
  Search,
  Send,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import { ArticleCover } from "@/components/ArticleCover";
import { Avatar } from "@/components/Avatar";
import { useAuth } from "@/hooks/useAuth";
import { fetchConversations, searchProfiles, sendMessage } from "@/lib/api";
import { setComposerPrefill } from "@/lib/composerDraft";
import { formatTimecode } from "@/lib/films";
import {
  PLAN_QUIZ_DISPLAY_ORDER,
  encodePlanQuizAnswers,
  planQuizLabel,
  type ArticleEmbedPayload,
  type FilmEmbedPayload,
  type PlanQuizAnswersPayload,
  type PlanQuizPayload,
} from "@/lib/contentEmbeds";

/* ------------------------------------------------------------------ */
/* Inline cards — rendered in DM bubbles and post captions              */
/* ------------------------------------------------------------------ */

/** Tappable cinema card for a shared film — opens the full film page. */
export function FilmEmbedCard({
  payload,
  className,
}: {
  payload: FilmEmbedPayload;
  className?: string;
}) {
  return (
    <Link
      to={`/films/${payload.id}`}
      className={cn(
        "block w-[min(270px,80vw)] overflow-hidden rounded-[18px] ring-1 ring-white/15",
        className
      )}
      aria-label={`Watch ${payload.title}`}
    >
      <div className="relative aspect-video w-full bg-[#121212]">
        {payload.poster ? (
          <img
            src={payload.poster}
            alt=""
            className="absolute inset-0 h-full w-full object-cover"
          />
        ) : (
          <div className="absolute inset-0 flex items-center justify-center">
            <Clapperboard className="h-8 w-8 text-white/20" />
          </div>
        )}
        <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/10 to-transparent" />
        <div className="absolute inset-x-0 bottom-0 p-3">
          <p className="flex items-center gap-1 text-[8px] font-black uppercase tracking-[0.14em] text-white/75">
            <Play className="h-2 w-2 fill-white/75" />
            Whisper Studios
            {payload.duration ? ` · ${formatTimecode(payload.duration)}` : ""}
          </p>
          <p className="mt-0.5 line-clamp-2 text-[14px] font-bold leading-snug text-white">
            {payload.title}
          </p>
          <p className="truncate text-[11px] font-semibold text-white/65">
            A {payload.director} film
          </p>
        </div>
      </div>
    </Link>
  );
}

/** Tappable journal card for a shared article — opens the reader. */
export function ArticleEmbedCard({
  payload,
  className,
}: {
  payload: ArticleEmbedPayload;
  className?: string;
}) {
  return (
    <Link
      to={`/articles/${payload.slug}`}
      className={cn(
        "block w-[min(270px,80vw)] overflow-hidden rounded-[18px] border border-border bg-card text-foreground",
        className
      )}
      aria-label={`Read ${payload.title}`}
    >
      <div className="relative h-24 w-full">
        <ArticleCover cover={payload.cover} className="absolute inset-0" />
        {payload.category && (
          <span className="absolute left-2 top-2 rounded-full bg-black/50 px-2 py-0.5 text-[8px] font-black uppercase tracking-wider text-white">
            {payload.category}
          </span>
        )}
      </div>
      <div className="space-y-1 p-3">
        <p className="line-clamp-2 text-[13.5px] font-bold leading-snug">
          {payload.title}
        </p>
        <p className="flex items-center gap-1.5 text-[11px] font-semibold text-muted-foreground">
          <FileText className="h-3 w-3" />
          <span className="truncate">By {payload.author}</span>
          <span className="ml-auto shrink-0 font-black">Read →</span>
        </p>
      </div>
    </Link>
  );
}

/* ------------------------------------------------------------------ */
/* Share dialog — DMs, wall repost, copy link                           */
/* ------------------------------------------------------------------ */

const recipientKey = (r: Recipient): string => `${r.kind ?? "direct"}:${r.userId}`;

interface Recipient {
  kind?: "direct" | "dating";
  userId: string;
  username: string;
  avatarUrl: string | null;
}

/**
 * One share surface for films and articles — mirrors iOS: send into DMs as
 * a tappable card, repost to your wall through the real composer, or copy
 * the link.
 */
function ShareContentDialogBase({
  open,
  onOpenChange,
  kicker,
  title,
  subtitle,
  imageUrl,
  embedBody,
  linkUrl,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** "WHISPER FILM" / "WHISPER JOURNAL". */
  kicker: string;
  title: string;
  subtitle: string;
  imageUrl?: string | null;
  /** The `::whisper-…::` embed line sent as the DM body / wall draft. */
  embedBody: string;
  linkUrl: string;
}) {
  const { user, profile } = useAuth();
  const navigate = useNavigate();
  const [query, setQuery] = useState<string>("");
  const [selected, setSelected] = useState<Record<string, Recipient>>({});

  const convosQuery = useQuery({
    queryKey: ["conversations", user?.id],
    queryFn: () => fetchConversations(user!.id),
    enabled: !!user && open,
  });

  const searchQuery = useQuery({
    queryKey: ["share-content-search", query],
    queryFn: () => searchProfiles(query),
    enabled: open && query.trim().length > 0,
  });

  const recipients = useMemo<Recipient[]>(() => {
    if (query.trim()) {
      return (searchQuery.data ?? [])
        .filter((p) => p.user_id !== user?.id)
        .map((p) => ({
          userId: p.user_id,
          username: p.username,
          avatarUrl: p.profile_image_url,
        }));
    }
    return (convosQuery.data ?? []).map((c) => ({
      kind: c.kind,
      userId: c.otherUserId,
      username: c.otherUsername,
      avatarUrl: c.otherProfile?.profile_image_url ?? null,
    }));
  }, [query, searchQuery.data, convosQuery.data, user?.id]);

  const selectedList = Object.values(selected);

  const toggle = (r: Recipient): void => {
    setSelected((prev) => {
      const next = { ...prev };
      if (next[recipientKey(r)]) delete next[recipientKey(r)];
      else next[recipientKey(r)] = r;
      return next;
    });
  };

  const close = (): void => {
    setQuery("");
    setSelected({});
    onOpenChange(false);
  };

  const send = useMutation({
    mutationFn: async (): Promise<void> => {
      if (!user || !profile) throw new Error("Not signed in");
      for (const r of selectedList) {
        await sendMessage(user.id, profile.username, r.userId, r.username, embedBody, undefined, r.kind);
      }
    },
    onSuccess: () => {
      toast(
        selectedList.length === 1
          ? `Sent to @${selectedList[0]!.username}`
          : `Sent to ${selectedList.length} people`
      );
      close();
    },
    onError: () => toast("Couldn't send. Try again."),
  });

  const repostToWall = (): void => {
    if (!user) {
      toast("Sign in to post this to your wall.");
      return;
    }
    setComposerPrefill({ caption: embedBody });
    close();
    navigate("/compose");
  };

  const copyLink = async (): Promise<void> => {
    try {
      await navigator.clipboard.writeText(linkUrl);
      toast.success("Link copied.");
    } catch {
      toast("Couldn't copy the link.");
    }
  };

  return (
    <Dialog.Root open={open} onOpenChange={(o) => (o ? onOpenChange(true) : close())}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 bg-black/60 backdrop-blur-[2px] data-[state=open]:animate-in data-[state=open]:fade-in-0" />
        <Dialog.Content
          className="fixed inset-x-0 bottom-0 z-50 mx-auto flex max-h-[88vh] w-full max-w-[480px] flex-col rounded-t-[26px] bg-background shadow-2xl outline-none data-[state=open]:animate-in data-[state=open]:slide-in-from-bottom sm:bottom-auto sm:top-1/2 sm:-translate-y-1/2 sm:rounded-[26px]"
          onOpenAutoFocus={(e) => e.preventDefault()}
        >
          <div className="flex items-center justify-between border-b border-border px-4 py-3.5">
            <button
              onClick={close}
              className="flex h-8 w-8 items-center justify-center rounded-full transition-colors hover:bg-secondary"
              aria-label="Cancel"
            >
              <X className="h-5 w-5" />
            </button>
            <Dialog.Title className="font-display text-[17px] font-bold">
              Share
            </Dialog.Title>
            <span className="w-8" />
          </div>

          <div className="no-scrollbar min-h-0 flex-1 overflow-y-auto">
            {/* Preview */}
            <div className="mx-4 mt-3 flex items-center gap-3 rounded-[16px] border border-border bg-card p-3">
              <div className="flex h-14 w-14 shrink-0 items-center justify-center overflow-hidden rounded-[13px] bg-secondary">
                {imageUrl ? (
                  <img src={imageUrl} alt="" className="h-full w-full object-cover" />
                ) : kicker.includes("FILM") ? (
                  <Clapperboard className="h-6 w-6 text-muted-foreground" />
                ) : (
                  <FileText className="h-6 w-6 text-muted-foreground" />
                )}
              </div>
              <div className="min-w-0">
                <p className="text-[9px] font-black uppercase tracking-[0.14em] text-muted-foreground">
                  {kicker}
                </p>
                <p className="truncate text-[14px] font-bold">{title}</p>
                <p className="truncate text-[12px] text-muted-foreground">{subtitle}</p>
              </div>
            </div>

            {/* Post to your wall */}
            <button
              type="button"
              onClick={repostToWall}
              className="mx-4 mt-2.5 flex w-[calc(100%-2rem)] items-center gap-3 rounded-[16px] border border-border bg-card p-3 text-left transition-colors hover:bg-secondary/50"
            >
              <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-[11px] bg-gradient-to-br from-orange-500 to-amber-400 text-white">
                <Repeat2 className="h-5 w-5" strokeWidth={2.6} />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-[14px] font-bold">Post to your wall</span>
                <span className="block truncate text-[11.5px] text-muted-foreground">
                  Opens the composer — add your take, it lands as a card.
                </span>
              </span>
            </button>

            {/* Copy link */}
            <button
              type="button"
              onClick={() => void copyLink()}
              className="mx-4 mt-2 flex w-[calc(100%-2rem)] items-center gap-2 rounded-full border border-border px-4 py-2.5 text-[13px] font-bold transition-colors hover:bg-secondary/50"
            >
              <Link2 className="h-4 w-4" />
              Copy link
            </button>

            {/* Search */}
            <div className="px-4 pt-3">
              <div className="flex items-center gap-2 rounded-full bg-secondary px-3.5 py-2.5">
                <Search className="h-4 w-4 text-muted-foreground" />
                <input
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder="Search people"
                  className="flex-1 bg-transparent text-[15px] outline-none placeholder:text-muted-foreground"
                />
              </div>
            </div>

            {/* Recipients */}
            <div className="px-2 py-2">
              {recipients.length === 0 ? (
                <p className="px-4 py-8 text-center text-sm text-muted-foreground">
                  {query.trim()
                    ? "No people found."
                    : "Your recent chats show up here."}
                </p>
              ) : (
                recipients.map((r) => {
                  const isSel = !!selected[recipientKey(r)];
                  return (
                    <button
                      key={recipientKey(r)}
                      onClick={() => toggle(r)}
                      className="flex w-full items-center gap-3 rounded-2xl px-3 py-2 text-left transition-colors hover:bg-secondary/60"
                    >
                      <Avatar name={r.username} url={r.avatarUrl} size={40} />
                      <span className="min-w-0 flex-1 truncate font-semibold">
                        @{r.username}{r.kind === "dating" ? " · Dating" : ""}
                      </span>
                      <span
                        className={cn(
                          "flex h-6 w-6 items-center justify-center rounded-full border-2 transition-colors",
                          isSel
                            ? "border-primary bg-primary text-primary-foreground"
                            : "border-border"
                        )}
                      >
                        {isSel && <Check className="h-3.5 w-3.5" />}
                      </span>
                    </button>
                  );
                })
              )}
            </div>
          </div>

          <div className="border-t border-border px-4 py-3">
            <button
              onClick={() => selectedList.length > 0 && send.mutate()}
              disabled={selectedList.length === 0 || send.isPending}
              className={cn(
                "flex w-full items-center justify-center gap-2 rounded-full py-3 text-[15px] font-bold transition-colors",
                selectedList.length > 0
                  ? "bg-primary text-primary-foreground"
                  : "border border-border text-muted-foreground"
              )}
            >
              <Send className="h-4 w-4" />
              {send.isPending
                ? "Sending…"
                : selectedList.length > 0
                  ? `Send (${selectedList.length})`
                  : "Select people to send"}
            </button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

export const ShareContentDialog = memo(ShareContentDialogBase);

/* ------------------------------------------------------------------ */
/* Coach plan questionnaire cards — wire-compatible with iOS           */
/* ------------------------------------------------------------------ */

const QUIZ_ACCENT = "#fa7321";

/** The questionnaire as it lands in a DM thread. Fully tappable for the
 * CLIENT (one tap per question, then send); a compact "sent" summary for
 * the coach who sent it. */
export function PlanQuizCard({
  payload,
  mine,
  answered,
  toUserId,
  toUsername,
}: {
  payload: PlanQuizPayload;
  mine: boolean;
  /** The thread already contains an answers card for this quiz. */
  answered: boolean;
  toUserId: string;
  toUsername: string;
}) {
  const { user, profile } = useAuth();
  const queryClient = useQueryClient();
  const [picks, setPicks] = useState<Record<string, string>>({});
  const [sentLocally, setSentLocally] = useState<boolean>(false);
  const allAnswered = payload.questions.every((q) => !!picks[q.id]);

  const send = useMutation({
    mutationFn: async () => {
      if (!user) throw new Error("Sign in first");
      const client = profile?.username ?? "client";
      await sendMessage(
        user.id,
        client,
        toUserId,
        toUsername,
        encodePlanQuizAnswers({ quizId: payload.id, client, answers: picks })
      );
    },
    onSuccess: () => {
      setSentLocally(true);
      void queryClient.invalidateQueries({ queryKey: ["conversations"] });
      toast("Answers sent");
    },
    onError: () => toast("Couldn't send answers — try again."),
  });

  const done = answered || sentLocally;

  return (
    <div
      className="w-[290px] max-w-[78%] rounded-[18px] border bg-card p-3"
      style={{ borderColor: `${QUIZ_ACCENT}59` }}
    >
      <div className="flex items-center gap-1.5" style={{ color: QUIZ_ACCENT }}>
        <ClipboardList className="h-3 w-3" strokeWidth={3} />
        <span className="text-[9px] font-black tracking-[0.12em]">
          PLAN QUESTIONNAIRE
        </span>
        <span className="ml-auto rounded-full bg-secondary px-1.5 py-0.5 text-[8px] font-black tracking-wide text-muted-foreground">
          {payload.questions.length} TAPS
        </span>
      </div>
      {mine ? (
        <p className="mt-2 text-[12px] leading-snug text-muted-foreground">
          Answers land here as a card for your review. Automatic plan delivery is paused;
          nutrition requires review in Jasper.
        </p>
      ) : done ? (
        <p className="mt-2 flex items-start gap-1.5 text-[12px] leading-snug text-muted-foreground">
          <Check
            className="mt-0.5 h-3.5 w-3.5 shrink-0"
            style={{ color: QUIZ_ACCENT }}
            strokeWidth={3}
          />
          Answered — @{payload.coach} got your picks for review. No plan was generated
          or activated.
        </p>
      ) : (
        <>
          <p className="mt-2 text-[12px] leading-snug text-muted-foreground">
            @{payload.coach} wants to review your training and nutrition goals.
            One tap per question; answering does not authorize plan changes.
          </p>
          <div className="mt-2.5 space-y-2.5">
            {payload.questions.map((q) => (
              <div key={q.id}>
                <p className="text-[11.5px] font-bold">{q.q}</p>
                <div className="mt-1 flex flex-wrap gap-1">
                  {q.opts.map((opt) => {
                    const on = picks[q.id] === opt;
                    return (
                      <button
                        key={opt}
                        type="button"
                        onClick={() =>
                          setPicks((p) => ({ ...p, [q.id]: opt }))
                        }
                        className={cn(
                          "rounded-full border px-2.5 py-1 text-[10.5px] font-bold transition-colors",
                          on
                            ? "border-foreground bg-foreground text-background"
                            : "border-border bg-secondary/60 text-foreground hover:bg-secondary"
                        )}
                      >
                        {opt}
                      </button>
                    );
                  })}
                </div>
              </div>
            ))}
          </div>
          <button
            type="button"
            disabled={!allAnswered || send.isPending}
            onClick={() => send.mutate()}
            className="mt-3 flex w-full items-center justify-center gap-1.5 rounded-full bg-foreground py-2 text-[12.5px] font-bold text-background transition-transform active:scale-95 disabled:opacity-45"
          >
            <Send className="h-3 w-3" strokeWidth={3} />
            {send.isPending
              ? "Sending…"
              : allAnswered
                ? "Send answers"
                : `Send answers (${Object.keys(picks).length}/${payload.questions.length})`}
          </button>
        </>
      )}
    </div>
  );
}

/** The client's answers as a compact chip card — quiz order preserved. */
export function PlanQuizAnswersCard({
  payload,
  mine,
}: {
  payload: PlanQuizAnswersPayload;
  mine: boolean;
}) {
  const ordered = useMemo(() => {
    const out: [string, string][] = [];
    for (const key of PLAN_QUIZ_DISPLAY_ORDER) {
      const v = payload.answers[key];
      if (v) out.push([key, v]);
    }
    for (const [k, v] of Object.entries(payload.answers)) {
      if (!PLAN_QUIZ_DISPLAY_ORDER.includes(k)) out.push([k, v]);
    }
    return out;
  }, [payload]);

  return (
    <div
      className="w-[290px] max-w-[78%] rounded-[18px] border bg-card p-3"
      style={{ borderColor: `${QUIZ_ACCENT}59` }}
    >
      <div className="flex items-center gap-1.5" style={{ color: QUIZ_ACCENT }}>
        <Check className="h-3 w-3" strokeWidth={3.4} />
        <span className="text-[9px] font-black tracking-[0.12em]">
          QUESTIONNAIRE ANSWERS
        </span>
      </div>
      <div className="mt-2 grid grid-cols-2 gap-1.5">
        {ordered.map(([k, v]) => (
          <div key={k} className="rounded-[9px] bg-secondary/70 px-2 py-1.5">
            <p className="text-[7.5px] font-black tracking-[0.08em] text-muted-foreground">
              {planQuizLabel(k).toUpperCase()}
            </p>
            <p className="truncate text-[11.5px] font-bold">{v}</p>
          </div>
        ))}
      </div>
      {!mine && (
        <p className="mt-2 text-[10.5px] text-muted-foreground">
          Ready for review — Coach Studio → Jasper's read → Plan questionnaire.
        </p>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Composer draft chip — the film/article card preview while drafting  */
/* ------------------------------------------------------------------ */

/** Compact preview of the card a post will carry — the composer shows this
 * removable stand-in instead of the raw embed token. */
export function EmbedDraftChip({
  kicker,
  title,
  subtitle,
  image,
  film,
  onRemove,
}: {
  kicker: string;
  title: string;
  subtitle: string;
  image: string | null;
  film?: boolean;
  onRemove: () => void;
}) {
  return (
    <div className="mb-2 mt-1 flex items-center gap-2.5 rounded-2xl border border-border bg-card p-2">
      <div className="h-12 w-12 shrink-0 overflow-hidden rounded-xl bg-zinc-900">
        {image ? (
          <img src={image} alt="" className="h-full w-full object-cover" />
        ) : (
          <div className="flex h-full w-full items-center justify-center">
            {film ? (
              <Clapperboard className="h-4 w-4 text-white/40" />
            ) : (
              <FileText className="h-4 w-4 text-white/40" />
            )}
          </div>
        )}
      </div>
      <div className="min-w-0 flex-1">
        <p className="text-[8px] font-black tracking-[0.12em] text-muted-foreground">
          {kicker}
        </p>
        <p className="truncate text-[13px] font-bold">{title}</p>
        <p className="truncate text-[11px] text-muted-foreground">{subtitle}</p>
      </div>
      <span className="shrink-0 rounded-full bg-secondary px-2 py-0.5 text-[9px] font-black tracking-wide text-muted-foreground">
        CARD
      </span>
      <button
        type="button"
        onClick={onRemove}
        aria-label="Remove attached card"
        className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-secondary text-muted-foreground transition-colors hover:text-foreground"
      >
        <X className="h-3 w-3" />
      </button>
    </div>
  );
}
