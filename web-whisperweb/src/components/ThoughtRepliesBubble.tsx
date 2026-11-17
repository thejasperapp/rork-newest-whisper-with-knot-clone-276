import { memo, useMemo } from "react";
import { useQuery } from "@tanstack/react-query";

import { cn } from "@/lib/utils";
import { Avatar } from "@/components/Avatar";
import { fetchMyReplyMeta } from "@/lib/thoughtReplies";

interface ThoughtRepliesBubbleProps {
  /** The thought owner whose incoming replies we're previewing. */
  userId: string;
  onOpen: () => void;
  className?: string;
}

/**
 * Web port of the iOS `WhisperThoughtRepliesBubble` — a small row of
 * overlapping mini-avatars showing the most recent repliers to the owner's
 * thought, plus a soft pulsing dot when there's unread activity. Tapping it
 * opens the community chat. Only renders when there are replies.
 */
function ThoughtRepliesBubbleBase({
  userId,
  onOpen,
  className,
}: ThoughtRepliesBubbleProps) {
  const metaQuery = useQuery({
    queryKey: ["my-replies", userId.toLowerCase()],
    queryFn: () => fetchMyReplyMeta(userId),
    enabled: !!userId,
    refetchInterval: 15000,
  });
  const rows = metaQuery.data?.rows ?? [];
  const unread = metaQuery.data?.unread ?? 0;

  // Up to three most-recent unique repliers, newest first.
  const avatars = useMemo(() => {
    const seen = new Set<string>();
    const out: typeof rows = [];
    for (const r of rows) {
      const key = r.replier_user_id.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(r);
      if (out.length >= 3) break;
    }
    return out;
  }, [rows]);

  if (rows.length === 0) return null;

  return (
    <button
      onClick={onOpen}
      aria-label={`${rows.length} replies to your thought${unread > 0 ? ", new" : ""}`}
      className={cn(
        "relative flex items-center transition-transform active:scale-95",
        className
      )}
    >
      <div className="flex -space-x-2">
        {avatars.map((r) => (
          <div
            key={r.id}
            className="rounded-full ring-2 ring-background"
          >
            <Avatar
              name={r.replier_username}
              url={r.replier_avatar_url}
              size={22}
            />
          </div>
        ))}
      </div>
      {unread > 0 && (
        <span className="relative ml-1 flex h-2.5 w-2.5">
          <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-primary/50" />
          <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-primary ring-2 ring-background" />
        </span>
      )}
    </button>
  );
}

export const ThoughtRepliesBubble = memo(ThoughtRepliesBubbleBase);
