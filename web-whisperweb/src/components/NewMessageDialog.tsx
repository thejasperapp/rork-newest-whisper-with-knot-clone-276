import { memo, useEffect, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { Search, X, PenSquare } from "lucide-react";

import { Avatar } from "@/components/Avatar";
import { UserBadges } from "@/components/UserBadges";
import { useProfileSearch } from "@/hooks/useProfileSearch";
import { useAuth } from "@/hooks/useAuth";
import type { WhisperProfile } from "@/lib/types";

interface NewMessageDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Called with the chosen recipient once a person is picked. */
  onPick: (profile: WhisperProfile) => void;
}

/**
 * "New message" recipient picker (mirrors the iOS compose-DM sheet). Search a
 * username, tap a person, and the parent opens a fresh thread with them.
 */
function NewMessageDialogBase({ open, onOpenChange, onPick }: NewMessageDialogProps) {
  const { user } = useAuth();
  const [query, setQuery] = useState<string>("");

  useEffect(() => {
    if (!open) setQuery("");
  }, [open]);

  const results = useProfileSearch(user?.id, query, open);

  const people = (results.data ?? []).filter((p) => p.user_id !== user?.id);

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-[60] bg-black/60 backdrop-blur-[2px] data-[state=open]:animate-in data-[state=open]:fade-in-0" />
        <Dialog.Content
          className="fixed inset-x-0 bottom-0 z-[60] mx-auto flex h-[72vh] w-full max-w-[480px] flex-col rounded-t-[26px] bg-background shadow-2xl outline-none data-[state=open]:animate-in data-[state=open]:slide-in-from-bottom sm:bottom-auto sm:top-1/2 sm:h-[64vh] sm:-translate-y-1/2 sm:rounded-[26px]"
          onOpenAutoFocus={(e) => e.preventDefault()}
        >
          <div className="flex items-center justify-between px-5 pb-3 pt-4">
            <Dialog.Title className="flex items-center gap-2 font-display text-xl font-bold">
              <PenSquare className="h-5 w-5" />
              New message
            </Dialog.Title>
            <button
              onClick={() => onOpenChange(false)}
              className="flex h-8 w-8 items-center justify-center rounded-full bg-secondary text-muted-foreground transition-colors hover:text-foreground"
              aria-label="Close"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          <div className="px-4 pb-2">
            <div className="flex items-center gap-2 rounded-full border border-border bg-secondary px-4 py-2.5">
              <Search className="h-4 w-4 text-muted-foreground" />
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search people"
                autoFocus
                className="flex-1 bg-transparent text-[15px] outline-none placeholder:text-muted-foreground"
              />
              {query && (
                <button
                  onClick={() => setQuery("")}
                  className="text-muted-foreground"
                  aria-label="Clear"
                >
                  <X className="h-4 w-4" />
                </button>
              )}
            </div>
          </div>

          <div className="min-h-0 flex-1 space-y-0.5 overflow-y-auto px-3 pb-6 pt-1">
            {results.isSearching && (
              <div className="space-y-2 p-1">
                {[0, 1, 2, 3].map((i) => (
                  <div
                    key={i}
                    className="flex animate-pulse items-center gap-3 rounded-2xl p-2.5"
                  >
                    <div className="h-11 w-11 rounded-full bg-secondary" />
                    <div className="flex-1 space-y-2">
                      <div className="h-3 w-28 rounded bg-secondary" />
                      <div className="h-3 w-20 rounded bg-secondary" />
                    </div>
                  </div>
                ))}
              </div>
            )}

            {!query.trim() && (
              <p className="px-4 py-12 text-center text-sm text-muted-foreground">
                Search for someone to start a conversation.
              </p>
            )}

            {results.isError && (
              <div role="status" className="px-4 py-8 text-center text-sm text-muted-foreground">
                <p>Search is unavailable for a moment.</p>
                <button type="button" onClick={() => void results.refetch()} className="mt-2 min-h-11 rounded-full bg-secondary px-5 font-semibold text-foreground transition-colors hover:bg-secondary/70">Try again</button>
              </div>
            )}
            {query.trim() && !results.isSearching && !results.isError && people.length === 0 && (
              <p className="px-4 py-12 text-center text-sm text-muted-foreground">
                No people found.
              </p>
            )}

            {people.map((p) => (
              <button
                key={p.user_id}
                onClick={() => {
                  onPick(p);
                  onOpenChange(false);
                }}
                className="flex w-full items-center gap-3 rounded-2xl p-2.5 text-left transition-colors hover:bg-secondary/60"
              >
                <Avatar url={p.profile_image_url} name={p.username} size={44} />
                <div className="min-w-0 flex-1">
                  <span className="flex items-center gap-1 truncate font-semibold">
                    <span className="truncate">{p.display_name || p.username}</span>
                    <UserBadges profile={p} size={13} />
                  </span>
                  <p className="truncate text-sm text-muted-foreground">
                    @{p.username}
                  </p>
                </div>
              </button>
            ))}
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

export const NewMessageDialog = memo(NewMessageDialogBase);
