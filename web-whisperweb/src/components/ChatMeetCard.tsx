import { useEffect, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Video } from "lucide-react";
import { useAuth } from "@/hooks/useAuth";
import { chatMeet } from "@/lib/chatMeet";
import { fetchProfilesByIds } from "@/lib/api";
import { ParticipantStack } from "@/components/ParticipantStack";
import { cn } from "@/lib/utils";

/** Reads/RSVP are independent of explicit room Join. */
export function ChatMeetCard({ eventID }: { eventID: string }) {
  const { user } = useAuth();
  if (!user) return <p className="p-4 text-sm">Sign in to review this meeting.</p>;
  return <AccountMeetCard key={`${user.id}-${eventID}`} accountID={user.id} eventID={eventID} />;
}

function AccountMeetCard({ accountID, eventID }: { accountID: string; eventID: string }) {
  const cache = useQueryClient();
  const key = ["chat-meet", accountID, eventID];
  const [visible, setVisible] = useState<boolean>(() => document.visibilityState === "visible");
  const work = useRef<AbortController | null>(null);
  const [freshAfter, setFreshAfter] = useState<number>(0);
  const query = useQuery({ queryKey: key, queryFn: ({ signal }) => chatMeet(accountID, eventID, undefined, signal), enabled: visible, retry: false, staleTime: 0, gcTime: 0, refetchInterval: visible ? 30_000 : false });
  useEffect(() => {
    const update = (): void => {
      const active = document.visibilityState === "visible";
      setVisible(active);
      if (!active) { setFreshAfter(Date.now() + 1); work.current?.abort(); void cache.cancelQueries({ queryKey: ["chat-meet", accountID, eventID] }); }
    };
    document.addEventListener("visibilitychange", update);
    return () => { work.current?.abort(); document.removeEventListener("visibilitychange", update); };
  }, [accountID, eventID, cache]);
  const action = useMutation({
    mutationFn: async (choice: "going" | "declined" | "open") => {
      if (work.current || document.visibilityState !== "visible") throw new Error("Please wait for the current action.");
      const controller = new AbortController(); work.current = controller;
      try {
        await cache.cancelQueries({ queryKey: key });
        const next = await chatMeet(accountID, eventID, choice === "open" ? undefined : choice, controller.signal);
        if (controller.signal.aborted || document.visibilityState !== "visible") throw new Error("Action interrupted. Check the meeting again.");
        cache.setQueryData(key, next);
        if (choice === "open" && !next.cancelled) window.location.assign(`https://meet.mydailywhisper.com/meet/${next.meetingID}`);
        return next;
      } finally { if (work.current === controller) work.current = null; }
    }, retry: false,
  });
  const invitation = visible && query.dataUpdatedAt >= freshAfter && !query.isError && !action.isError ? query.data : undefined;
  const peopleIDs = invitation?.invitees.map(p => p.userID).sort() ?? [];
  const profiles = useQuery({ queryKey: ["meet-avatar-profiles", accountID, peopleIDs], queryFn: () => fetchProfilesByIds(peopleIDs), enabled: visible && peopleIDs.length > 0, staleTime: 60_000, gcTime: 0 });
  const response = invitation?.invitees.find(p => p.userID.toLowerCase() === accountID.toLowerCase())?.status;
  return <section className="w-[280px] max-w-full space-y-3 rounded-[22px] border border-border bg-background/95 p-4 text-foreground shadow-sm" aria-label="Whisper Meet invitation">
    <div className="flex items-center gap-2"><Video className="h-5 w-5" /><span className="text-sm font-semibold">Whisper Meet</span></div>
    {invitation ? <>
      <h3 className="break-words text-base font-semibold">{invitation.title}</h3>
      <p className="text-sm text-muted-foreground">{new Date(invitation.startTime).toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })}</p>
      {invitation.cancelled ? <p className="text-sm">Meeting cancelled</p> : <>
        <div className="flex gap-2">{(["going", "declined"] as const).map(status => <button type="button" key={status} disabled={action.isPending || query.isFetching} aria-pressed={response === status} onClick={() => action.mutate(status)} className={cn("min-h-11 flex-1 rounded-full border border-border px-2 text-xs font-semibold disabled:opacity-50", response === status && "bg-foreground text-background")}>{status === "going" ? "Going" : "Not going"}</button>)}</div>
        {!invitation.deliveryComplete && <p className="text-xs text-muted-foreground">Delivery is incomplete. The organizer can recover it in Meet.</p>}
        <button type="button" className="min-h-11 w-full rounded-full bg-secondary text-sm font-semibold" disabled={action.isPending || query.isFetching} onClick={() => action.mutate("open")}>{action.isPending ? "Checking…" : "Open in Meet"}</button>
      </>}
      <ParticipantStack label="Going" people={invitation.invitees.filter(p => p.status === "going").map(p => ({ id: p.userID, username: p.username, avatar: profiles.data?.[p.userID]?.profile_image_url }))} />
      <details className="text-xs text-muted-foreground"><summary className="min-h-11 cursor-pointer py-3">All responses</summary>{invitation.invitees.map(p => <p key={p.userID} className="flex justify-between gap-2 py-1"><span>{p.username}</span><span>{p.status === "going" ? "Going" : p.status === "declined" ? "Not going" : "Awaiting response"}</span></p>)}</details>
    </> : <p className="text-sm text-muted-foreground">{query.isError || action.isError ? "Unavailable or access changed. Check again before continuing." : visible ? "Checking meeting access…" : "Meeting hidden while inactive."}</p>}
    {(query.isError || action.isError) && <button type="button" className="min-h-11 text-sm font-semibold" onClick={() => { action.reset(); void query.refetch(); }}>Check again</button>}
  </section>;
}
