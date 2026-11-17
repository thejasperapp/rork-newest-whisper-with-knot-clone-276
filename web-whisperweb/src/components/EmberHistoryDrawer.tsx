import { memo, useMemo, useState } from "react";
import { Search, SquarePen, Trash2, X } from "lucide-react";

import { KnotMascot } from "@/components/Knot";
import type { EmberConversation } from "@/lib/emberBrain";
import { cn } from "@/lib/utils";

/**
 * THE CHAT HISTORY DRAWER — Whisper's design language (mirrors the iOS
 * `WhisperEmberHistoryDrawer`): surface + hairlines, the Jasper icon in the
 * header, an ink "New chat" pill, conversations grouped under quiet uppercase
 * kickers (TODAY · YESTERDAY · THIS WEEK · EARLIER), the current chat marked
 * with an ink dot, search once the list grows, delete on hover.
 */

function relativeTime(ts: number): string {
  const diff = Date.now() - ts;
  const min = Math.floor(diff / 60_000);
  if (min < 1) return "just now";
  if (min < 60) return `${min}m`;
  const hr = Math.floor(min / 60);
  if (hr < 24) return `${hr}h`;
  const day = Math.floor(hr / 24);
  if (day < 7) return `${day}d`;
  return new Date(ts).toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

interface Group {
  id: string;
  title: string;
  items: EmberConversation[];
}

function groupConversations(list: EmberConversation[]): Group[] {
  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const startOfYesterday = startOfToday - 86_400_000;
  const weekAgo = now.getTime() - 7 * 86_400_000;
  const groups: Group[] = [
    { id: "today", title: "Today", items: [] },
    { id: "yesterday", title: "Yesterday", items: [] },
    { id: "week", title: "This week", items: [] },
    { id: "earlier", title: "Earlier", items: [] },
  ];
  for (const c of list) {
    if (c.updatedAt >= startOfToday) groups[0].items.push(c);
    else if (c.updatedAt >= startOfYesterday) groups[1].items.push(c);
    else if (c.updatedAt >= weekAgo) groups[2].items.push(c);
    else groups[3].items.push(c);
  }
  return groups.filter((g) => g.items.length > 0);
}

function EmberHistoryDrawerBase({
  open,
  conversations,
  currentId,
  onNewChat,
  onSelect,
  onDelete,
  onClose,
}: {
  open: boolean;
  conversations: EmberConversation[];
  currentId: string;
  onNewChat: () => void;
  onSelect: (convo: EmberConversation) => void;
  onDelete: (id: string) => void;
  onClose: () => void;
}) {
  const [query, setQuery] = useState<string>("");
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return conversations;
    return conversations.filter(
      (c) =>
        c.title.toLowerCase().includes(q) ||
        c.messages.some((m) => m.text.toLowerCase().includes(q))
    );
  }, [conversations, query]);
  const groups = useMemo(() => groupConversations(filtered), [filtered]);

  return (
    <div
      className={cn(
        "fixed inset-0 z-50 transition-[visibility]",
        open ? "visible" : "invisible delay-300"
      )}
      aria-hidden={!open}
    >
      <button
        type="button"
        aria-label="Close history"
        onClick={onClose}
        className={cn(
          "absolute inset-0 bg-black/30 transition-opacity duration-300",
          open ? "opacity-100" : "opacity-0"
        )}
      />
      <div
        className={cn(
          "absolute inset-y-0 left-0 flex w-[304px] max-w-[86vw] flex-col border-r border-border bg-background shadow-2xl transition-transform duration-300 ease-[cubic-bezier(0.32,0.72,0,1)]",
          open ? "translate-x-0" : "-translate-x-full"
        )}
      >
        <div className="flex items-center gap-2.5 border-b border-border px-4 pb-3 pt-[max(1.1rem,env(safe-area-inset-top))]">
          <KnotMascot size={28} />
          <div className="min-w-0 flex-1">
            <p className="text-[15px] font-bold leading-tight">Your chats</p>
            <p className="text-[12px] text-muted-foreground">
              {conversations.length === 0 ? "Knot" : `${conversations.length} with Knot`}
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="flex h-8 w-8 items-center justify-center rounded-full bg-secondary text-foreground"
          >
            <X className="h-4 w-4" strokeWidth={2.6} />
          </button>
        </div>

        <div className="px-3.5 pb-1.5 pt-3">
          <button
            type="button"
            onClick={onNewChat}
            className="flex h-11 w-full items-center gap-2.5 rounded-full bg-foreground px-4 text-[14px] font-bold text-background transition-transform active:scale-[0.98]"
          >
            <SquarePen className="h-4 w-4" />
            New chat
          </button>
        </div>

        {conversations.length > 4 && (
          <div className="px-3.5 pb-1 pt-1">
            <label className="flex h-9 items-center gap-2 rounded-full border border-border bg-secondary/60 px-3">
              <Search className="h-3.5 w-3.5 text-muted-foreground" />
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search chats"
                className="min-w-0 flex-1 bg-transparent text-[13.5px] outline-none placeholder:text-muted-foreground"
              />
              {query && (
                <button type="button" onClick={() => setQuery("")} aria-label="Clear search" className="text-muted-foreground">
                  <X className="h-3.5 w-3.5" />
                </button>
              )}
            </label>
          </div>
        )}

        {conversations.length === 0 ? (
          <div className="px-7 pt-12 text-center">
            <p className="text-sm font-semibold">No chats yet</p>
            <p className="mt-1 text-xs text-muted-foreground">
              Your conversations with Knot will show up here.
            </p>
          </div>
        ) : filtered.length === 0 ? (
          <p className="pt-8 text-center text-[13px] text-muted-foreground">No chats match “{query}”</p>
        ) : (
          <div className="flex-1 space-y-4 overflow-y-auto px-2 pb-6 pt-2">
            {groups.map((group) => (
              <div key={group.id}>
                <p className="px-3 pb-1 text-[11px] font-black uppercase tracking-[0.12em] text-muted-foreground">
                  {group.title}
                </p>
                {group.items.map((convo) => {
                  const isCurrent = convo.id === currentId;
                  const preview = convo.messages
                    .slice()
                    .reverse()
                    .find((m) => m.role !== "user")
                    ?.text.replace(/\s+/g, " ")
                    .trim();
                  return (
                    <div
                      key={convo.id}
                      className={cn(
                        "group flex items-start gap-1 rounded-xl",
                        isCurrent && "bg-secondary"
                      )}
                    >
                      <button
                        type="button"
                        onClick={() => onSelect(convo)}
                        className="flex min-w-0 flex-1 items-start gap-2.5 px-2.5 py-2.5 text-left"
                      >
                        <span
                          className={cn(
                            "mt-[7px] h-1.5 w-1.5 shrink-0 rounded-full",
                            isCurrent ? "bg-foreground" : "bg-transparent"
                          )}
                        />
                        <span className="min-w-0 flex-1">
                          <span className={cn("block truncate text-[14px]", isCurrent ? "font-bold" : "font-semibold")}>
                            {convo.title}
                          </span>
                          {preview && (
                            <span className="block truncate text-[12px] text-muted-foreground">{preview}</span>
                          )}
                        </span>
                        <span className="shrink-0 pt-0.5 text-[11px] text-muted-foreground">
                          {relativeTime(convo.updatedAt)}
                        </span>
                      </button>
                      <button
                        type="button"
                        aria-label="Delete chat"
                        onClick={() => onDelete(convo.id)}
                        className="mr-1.5 mt-2 flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-muted-foreground opacity-0 transition-opacity hover:bg-background hover:text-foreground group-hover:opacity-100"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </div>
                  );
                })}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

export const EmberHistoryDrawer = memo(EmberHistoryDrawerBase);
