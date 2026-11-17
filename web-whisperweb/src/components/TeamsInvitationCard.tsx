import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { UsersRound } from "lucide-react";
import { useAuth } from "@/hooks/useAuth";
import { Button } from "@/components/ui/button";
import { loadTeamsCard, teamsStatusLabel, type TeamsMessageBinding } from "@/lib/teamsInvitation";

/** Uses the existing inbox. No client-generated card, roster or accept action. */
export function TeamsInvitationCard({ message }: { message: TeamsMessageBinding }) {
  const { user } = useAuth();
  return user ? <AccountCard key={`${user.id}:${message.id}`} account={user.id} message={message} /> : <p className="p-4 text-sm">Sign in to review this invitation.</p>;
}
function AccountCard({ account, message }: { account: string; message: TeamsMessageBinding }) {
  const cache = useQueryClient();
  const [visible, setVisible] = useState<boolean>(() => document.visibilityState === "visible");
  const [freshAfter, setFreshAfter] = useState<number>(0);
  const query = useQuery({ queryKey: ["social-teams-card", account, message.id],
    queryFn: ({ signal }) => loadTeamsCard(account, message, signal), enabled: visible,
    retry: false, staleTime: 0, gcTime: 0, refetchInterval: visible ? 30_000 : false });
  useEffect(() => {
    const update = (): void => {
      const active = document.visibilityState === "visible"; setVisible(active);
      if (!active) { setFreshAfter(Date.now() + 1); void cache.cancelQueries({ queryKey: ["social-teams-card", account, message.id] }); }
    };
    document.addEventListener("visibilitychange", update);
    return () => { document.removeEventListener("visibilitychange", update); void cache.cancelQueries({ queryKey: ["social-teams-card", account, message.id] }); };
  }, [account, message.id, cache]);
  const card = visible && query.dataUpdatedAt >= freshAfter && !query.isError ? query.data : undefined;
  const status = card?.status === "pending" && card.expiresAt <= Date.now() ? "expired" : card?.status;
  return <section className="w-[280px] max-w-full space-y-3 rounded-[20px] border border-border bg-background p-4 text-foreground shadow-sm" aria-label="Team invitation">
    <div className="flex items-center gap-2 text-sm font-semibold"><UsersRound className="h-5 w-5" aria-hidden />Whisper Teams</div>
    {card ? <>
      <h3 className="break-words text-base font-semibold">{card.teamName}</h3>
      <p className="text-sm text-muted-foreground">{status ? teamsStatusLabel[status] : "Status unavailable"}</p>
      <p className="text-xs text-muted-foreground">Reported by Teams · {new Date(card.occurredAt).toLocaleString()}</p>
      {status === "pending" && card.canOpen && <p className="text-xs text-muted-foreground">Review this invitation in Whisper Teams → All teams. A browser return link isn't available yet. Nothing is accepted here.</p>}
    </> : <p className="text-sm text-muted-foreground" role="status">{query.isError ? "This invitation couldn't be confirmed. It may be unavailable or access may have changed." : visible ? "Checking invitation…" : "Invitation hidden while inactive."}</p>}
    <Button type="button" variant="outline" className="min-h-11 w-full rounded-full" disabled={!visible || query.isFetching} onClick={() => { void query.refetch(); }}>Refresh status</Button>
  </section>;
}
