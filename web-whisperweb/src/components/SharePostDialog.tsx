import { memo, useMemo, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { useMutation, useQuery } from "@tanstack/react-query";
import { X, Search, Check, Send } from "lucide-react";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import { Avatar } from "@/components/Avatar";
import { useAuth } from "@/hooks/useAuth";
import {
  fetchConversations,
  searchProfiles,
  sendMessage,
} from "@/lib/api";
import { encodeSharedPost, payloadFromPost } from "@/lib/postShare";
import type { WhisperPost } from "@/lib/types";

const recipientKey = (r: Recipient): string => `${r.kind ?? "direct"}:${r.userId}`;

interface Recipient {
  kind?: "direct" | "dating";
  userId: string;
  username: string;
  avatarUrl: string | null;
}

interface SharePostDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  post: WhisperPost;
  authorUsername: string;
}

function SharePostDialogBase({
  open,
  onOpenChange,
  post,
  authorUsername,
}: SharePostDialogProps) {
  const { user, profile } = useAuth();
  const [query, setQuery] = useState<string>("");
  const [note, setNote] = useState<string>("");
  const [selected, setSelected] = useState<Record<string, Recipient>>({});

  // Existing conversations make the fastest "send to" list.
  const convosQuery = useQuery({
    queryKey: ["conversations", user?.id],
    queryFn: () => fetchConversations(user!.id),
    enabled: !!user && open,
  });

  const searchQuery = useQuery({
    queryKey: ["share-search", query],
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

  const send = useMutation({
    mutationFn: async (): Promise<void> => {
      if (!user || !profile) throw new Error("Not signed in");
      const embed = encodeSharedPost(payloadFromPost(post, authorUsername));
      for (const r of selectedList) {
        await sendMessage(
          user.id,
          profile.username,
          r.userId,
          r.username,
          embed, undefined, r.kind
        );
        if (note.trim()) {
          await sendMessage(
            user.id,
            profile.username,
            r.userId,
            r.username,
            note.trim(), undefined, r.kind
          );
        }
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

  const close = (): void => {
    setQuery("");
    setNote("");
    setSelected({});
    onOpenChange(false);
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

          {/* Recipient list */}
          <div className="min-h-0 flex-1 overflow-y-auto px-2 py-2">
            {recipients.length === 0 ? (
              <p className="px-4 py-10 text-center text-sm text-muted-foreground">
                {query.trim()
                  ? "No people found."
                  : "Search for someone to share this with."}
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
                    <Avatar name={r.username} url={r.avatarUrl} size={42} />
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

          {/* Note + send */}
          <div className="border-t border-border px-4 py-3">
            <input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Add a message…"
              className="mb-3 w-full rounded-full border border-border bg-card px-4 py-2.5 text-[15px] outline-none focus:border-foreground/40"
            />
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

export const SharePostDialog = memo(SharePostDialogBase);
