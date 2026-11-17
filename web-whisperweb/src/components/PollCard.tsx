import { memo, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check } from "lucide-react";

import { cn } from "@/lib/utils";
import { castPollVote, fetchMyPollVote, fetchPollVotes } from "@/lib/api";
import { useAuth } from "@/hooks/useAuth";
import type { PostPoll } from "@/lib/postMeta";

interface PollCardProps {
  postId: string;
  poll: PostPoll;
}

/**
 * Votable poll rendered inside a post. Counts come from `whisper_poll_votes`
 * (best-effort) and the user's own choice is reflected optimistically so the
 * bar fills the instant they tap, even before the round-trip settles.
 */
function PollCardBase({ postId, poll }: PollCardProps) {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [localChoice, setLocalChoice] = useState<number | null>(null);

  const votesQuery = useQuery({
    queryKey: ["poll-votes", postId],
    queryFn: () => fetchPollVotes(postId),
  });
  const myVoteQuery = useQuery({
    queryKey: ["poll-my-vote", postId, user?.id],
    queryFn: () => fetchMyPollVote(postId, user!.id),
    enabled: !!user,
  });

  const serverChoice = myVoteQuery.data ?? null;
  const choice = localChoice ?? serverChoice;
  const hasVoted = choice !== null;

  const vote = useMutation({
    mutationFn: (index: number) => castPollVote(postId, user!.id, index),
    onMutate: (index: number) => setLocalChoice(index),
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ["poll-votes", postId] });
      queryClient.invalidateQueries({ queryKey: ["poll-my-vote", postId] });
    },
  });

  const counts = votesQuery.data ?? {};
  const tally = useMemo(() => {
    const base = poll.options.map((_, i) => counts[i] ?? 0);
    // Reflect the optimistic local vote when the server count hasn't caught up.
    if (
      localChoice !== null &&
      serverChoice !== localChoice &&
      base[localChoice] !== undefined
    ) {
      base[localChoice] = (base[localChoice] ?? 0) + 1;
    }
    return base;
  }, [counts, poll.options, localChoice, serverChoice]);

  const total = tally.reduce((a, b) => a + b, 0);

  return (
    <div className="mt-2 space-y-1.5">
      {poll.question && (
        <p className="text-[15px] font-semibold leading-snug">{poll.question}</p>
      )}
      {poll.options.map((option, i) => {
        const count = tally[i] ?? 0;
        const pct = total > 0 ? Math.round((count / total) * 100) : 0;
        const mine = choice === i;
        return (
          <button
            key={option + i}
            disabled={!user || vote.isPending}
            onClick={() => user && vote.mutate(i)}
            className={cn(
              "relative w-full overflow-hidden rounded-xl border px-3 py-2.5 text-left transition-colors",
              mine ? "border-primary" : "border-border hover:bg-secondary/50"
            )}
          >
            {hasVoted && (
              <span
                className={cn(
                  "absolute inset-y-0 left-0 transition-all duration-500",
                  mine ? "bg-primary/20" : "bg-secondary"
                )}
                style={{ width: `${pct}%` }}
              />
            )}
            <span className="relative flex items-center justify-between gap-2">
              <span className="flex items-center gap-1.5 text-[14px] font-medium">
                {mine && <Check className="h-4 w-4 text-primary" />}
                {option}
              </span>
              {hasVoted && (
                <span className="text-[13px] font-semibold tabular-nums text-muted-foreground">
                  {pct}%
                </span>
              )}
            </span>
          </button>
        );
      })}
      {hasVoted && (
        <p className="pt-0.5 text-[12px] text-muted-foreground">
          {total} {total === 1 ? "vote" : "votes"}
        </p>
      )}
    </div>
  );
}

export const PollCard = memo(PollCardBase);
