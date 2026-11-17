import { memo, useEffect, useMemo, useRef, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Sparkles, MessageSquare, ArrowUp } from "lucide-react";

import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";
import { Avatar } from "@/components/Avatar";
import { ThoughtBubble } from "@/components/ThoughtBubble";
import {
  fetchThoughtChat,
  markRepliesRead,
  sendThoughtReply,
  snapshotFromRow,
  type ThoughtReplyRow,
  type ThoughtSnapshot,
} from "@/lib/thoughtReplies";

interface ThoughtRepliesSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Thought owner this chat belongs to. */
  ownerUserId: string;
  ownerUsername: string;
  /** When the owner is the current user, the bubbles right-align. */
  isOwner: boolean;
  /** Live snapshot of the owner's current thought (pin at top). */
  liveThought?: ThoughtSnapshot | null;
}

function ThoughtRepliesSheetBase({
  open,
  onOpenChange,
  ownerUserId,
  ownerUsername,
  isOwner,
  liveThought,
}: ThoughtRepliesSheetProps) {
  const { user, profile } = useAuth();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<string>("");
  const scrollRef = useRef<HTMLDivElement>(null);
  const myUid = (user?.id ?? "").toLowerCase();

  const queryKey = useMemo(
    () => ["thought-chat", ownerUserId.toLowerCase()],
    [ownerUserId]
  );

  const chatQuery = useQuery({
    queryKey,
    queryFn: () => fetchThoughtChat(ownerUserId),
    enabled: open && !!ownerUserId,
    refetchInterval: open ? 4000 : false,
  });
  const rows = chatQuery.data ?? [];

  // Pin the live thought if we have it, otherwise fall back to the snapshot
  // stored on the most recent reply — exactly like iOS.
  const pinned: ThoughtSnapshot | null =
    liveThought && liveThought.text
      ? liveThought
      : snapshotFromRow(rows[rows.length - 1]);

  const participantCount = useMemo(() => {
    const seen = new Set<string>();
    for (const r of rows) seen.add(r.replier_user_id.toLowerCase());
    seen.add(ownerUserId.toLowerCase());
    if (myUid) seen.add(myUid);
    return seen.size;
  }, [rows, ownerUserId, myUid]);

  // Mark incoming replies read when the owner opens their own room.
  useEffect(() => {
    if (!open || !isOwner || rows.length === 0) return;
    const unread = rows.filter((r) => !r.read_at).map((r) => r.id);
    if (unread.length === 0) return;
    void markRepliesRead(unread).then(() => {
      queryClient.invalidateQueries({ queryKey: ["my-replies", myUid] });
    });
  }, [open, isOwner, rows, queryClient, myUid]);

  // Auto-scroll to bottom as new messages arrive / sheet opens.
  useEffect(() => {
    if (!open) return;
    const el = scrollRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [open, rows.length]);

  const send = useMutation({
    mutationFn: (body: string) =>
      sendThoughtReply({
        ownerUserId,
        ownerUsername,
        meUserId: user!.id,
        meUsername: profile?.username ?? "",
        meAvatarUrl: profile?.profile_image_url ?? null,
        thought: pinned,
        body,
      }),
    onMutate: async (body: string) => {
      await queryClient.cancelQueries({ queryKey });
      const previous = queryClient.getQueryData<ThoughtReplyRow[]>(queryKey);
      const optimistic: ThoughtReplyRow = {
        id: `local-${Date.now()}`,
        thought_user_id: ownerUserId.toLowerCase(),
        replier_user_id: myUid,
        replier_username: profile?.username ?? "you",
        replier_avatar_url: profile?.profile_image_url ?? null,
        body: body.trim().slice(0, 280),
        thought_text: pinned?.text ?? "",
        thought_style: pinned?.style ?? null,
        thought_accent: pinned?.accent ?? null,
        thought_emoji: pinned?.emoji ?? null,
        thought_color_hex: pinned?.colorHex ?? null,
        thought_owner_username: ownerUsername,
        created_at: new Date().toISOString(),
        read_at: null,
      };
      queryClient.setQueryData<ThoughtReplyRow[]>(queryKey, [
        ...(previous ?? []),
        optimistic,
      ]);
      return { previous };
    },
    onError: (_e, _body, ctx) => {
      if (ctx?.previous)
        queryClient.setQueryData(queryKey, ctx.previous);
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey });
    },
  });

  const canSend = draft.trim().length > 0 && !send.isPending;

  const submit = (): void => {
    if (!canSend) return;
    const body = draft;
    setDraft("");
    send.mutate(body);
  };

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 bg-black/60 backdrop-blur-[2px] data-[state=open]:animate-in data-[state=open]:fade-in-0" />
        <Dialog.Content
          className="fixed inset-x-0 bottom-0 z-50 mx-auto flex h-[88vh] w-full max-w-[480px] flex-col rounded-t-[26px] bg-background shadow-2xl outline-none data-[state=open]:animate-in data-[state=open]:slide-in-from-bottom sm:bottom-auto sm:top-1/2 sm:h-[78vh] sm:-translate-y-1/2 sm:rounded-[26px]"
          onOpenAutoFocus={(e) => e.preventDefault()}
        >
          {/* Pinned thought header */}
          <div className="border-b border-border px-4 pb-3 pt-4">
            <div className="mb-2 flex items-center gap-1.5 text-muted-foreground">
              <Sparkles className="h-3.5 w-3.5" />
              <Dialog.Title className="text-[13px] font-semibold">
                {isOwner ? "Your thought" : `@${ownerUsername}'s thought`}
              </Dialog.Title>
              <span className="ml-auto rounded-full bg-secondary px-2 py-0.5 text-[11px] font-semibold text-muted-foreground">
                {participantCount} here
              </span>
            </div>
            {pinned && pinned.text ? (
              <div className="flex pt-1">
                <ThoughtBubble
                  text={pinned.text}
                  style={pinned.style}
                  accent={pinned.accent}
                  emoji={pinned.emoji}
                  colorHex={pinned.colorHex}
                  scale={0.78}
                />
              </div>
            ) : (
              <p className="text-sm text-muted-foreground">
                No active thought right now.
              </p>
            )}
          </div>

          {/* Chat scroll */}
          <div
            ref={scrollRef}
            className="min-h-0 flex-1 space-y-2 overflow-y-auto px-3 py-3"
          >
            {rows.length === 0 ? (
              <div className="flex h-full flex-col items-center justify-center px-8 text-center">
                <MessageSquare className="mb-3 h-10 w-10 text-muted-foreground/50" />
                <p className="font-display text-[17px] font-bold">Quiet in here</p>
                <p className="mt-1 text-sm text-muted-foreground">
                  {isOwner
                    ? "When someone replies to your thought, the conversation lives right here — not in your DMs."
                    : "Be the first to reply — the conversation lives right here, not in DMs."}
                </p>
              </div>
            ) : (
              rows.map((row) => (
                <ChatRow
                  key={row.id}
                  row={row}
                  mine={row.replier_user_id.toLowerCase() === myUid}
                />
              ))
            )}
          </div>

          {/* Composer */}
          <div className="flex items-end gap-2 border-t border-border px-3 py-3">
            <textarea
              value={draft}
              onChange={(e) => setDraft(e.target.value.slice(0, 280))}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  submit();
                }
              }}
              rows={1}
              placeholder="Reply to the room…"
              className="max-h-28 min-h-[42px] flex-1 resize-none rounded-2xl border border-border bg-card px-3.5 py-2.5 text-[15px] outline-none placeholder:text-muted-foreground focus:border-foreground/30"
            />
            <button
              onClick={submit}
              disabled={!canSend}
              aria-label="Send reply"
              className={cn(
                "flex h-10 w-10 shrink-0 items-center justify-center rounded-full transition-colors",
                canSend
                  ? "bg-primary text-primary-foreground"
                  : "bg-secondary text-muted-foreground"
              )}
            >
              <ArrowUp className="h-5 w-5" strokeWidth={2.6} />
            </button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function ChatRow({ row, mine }: { row: ThoughtReplyRow; mine: boolean }) {
  return (
    <div
      className={cn(
        "flex items-end gap-2",
        mine ? "flex-row-reverse" : "flex-row"
      )}
    >
      {!mine && (
        <Avatar
          name={row.replier_username}
          url={row.replier_avatar_url}
          size={28}
        />
      )}
      <div
        className={cn(
          "flex max-w-[72%] flex-col",
          mine ? "items-end" : "items-start"
        )}
      >
        {!mine && (
          <span className="mb-0.5 px-1 text-[11px] font-semibold text-muted-foreground">
            @{row.replier_username}
          </span>
        )}
        <div
          className={cn(
            "rounded-[18px] px-3.5 py-2.5 text-[15px] leading-snug shadow-sm",
            mine
              ? "rounded-br-md bg-primary text-primary-foreground"
              : "rounded-bl-md border border-border bg-card text-foreground"
          )}
        >
          {row.body}
        </div>
      </div>
    </div>
  );
}

export const ThoughtRepliesSheet = memo(ThoughtRepliesSheetBase);
