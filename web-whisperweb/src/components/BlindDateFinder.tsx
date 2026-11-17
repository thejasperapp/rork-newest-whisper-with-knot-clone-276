import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Link2, Loader2, PenLine, SlidersHorizontal, Sparkles } from "lucide-react";

import { EmberMascot } from "@/components/EmberMascot";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import {
  blindDateHistory,
  blindOutcomeLabel,
  blindQueueCount,
  joinBlindQueue,
  leaveBlindQueue,
  markBlindPaired,
  pollBlindQueue,
  queueIsPaired,
  type BlindHistoryRow,
} from "@/lib/blindDate";
import { DATING_CARD_QUESTIONS, loadDatingCardLocal, markSpeedDateRoom } from "@/lib/datingCards";
import { loadDatingPrefs, prefsIsConfigured, prefsSummaryLine, syncDatingPrefsFromCloud } from "@/lib/datingPrefs";
import { cn } from "@/lib/utils";

const CUPID = { accent: "#F5B8CC", softAccent: "#FFEDF2", deepAccent: "#E68FAD" };

type Mode =
  | { kind: "idle"; error?: string }
  | { kind: "searching"; since: number }
  | { kind: "paired"; name: string; code: string };

/**
 * The dialog behind the Dating hub's video circle — the front door of the
 * blind-date service: FIND ME A BLIND DATE (the queue, with a live radar
 * while it searches and a matched moment), INVITE SOMEONE (the link lobby),
 * preferences + card at a glance, and past dates. Mirrors iOS
 * `WhisperBlindDateFinderView`.
 */
export function BlindDateFinder({
  open,
  onOpenChange,
  userId,
  username,
  onInvite,
  onOpenPrefs,
  onOpenCard,
  prefsTick = 0,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  userId: string;
  username: string;
  onInvite: () => void;
  onOpenPrefs: () => void;
  onOpenCard: () => void;
  /** Bumps when prefs/card save so the chips recompute. */
  prefsTick?: number;
}) {
  const navigate = useNavigate();
  const [mode, setMode] = useState<Mode>({ kind: "idle" });
  const [waiting, setWaiting] = useState<number>(0);
  const [history, setHistory] = useState<BlindHistoryRow[]>([]);
  const [now, setNow] = useState<number>(() => Date.now());
  const cancelledRef = useRef<boolean>(false);
  const prefs = loadDatingPrefs(userId);
  const cardCount = DATING_CARD_QUESTIONS.filter((q) => (loadDatingCardLocal(userId)[q.id] ?? "").trim()).length;
  void prefsTick;

  useEffect(() => {
    if (!open) return;
    void syncDatingPrefsFromCloud(userId);
    void blindQueueCount().then(setWaiting);
    void blindDateHistory().then(setHistory);
  }, [open, userId]);

  useEffect(() => {
    if (mode.kind !== "searching") return;
    const t = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(t);
  }, [mode.kind]);

  // Leaving the dialog mid-search leaves the queue too.
  useEffect(() => {
    if (open) return;
    cancelledRef.current = true;
    if (mode.kind === "searching") {
      setMode({ kind: "idle" });
      void leaveBlindQueue();
    }
  }, [open, mode.kind]);

  const startSearch = async (): Promise<void> => {
    cancelledRef.current = false;
    setMode({ kind: "searching", since: Date.now() });
    try {
      let result = await joinBlindQueue(userId, username);
      while (!cancelledRef.current && !queueIsPaired(result)) {
        setWaiting(result.waiting ?? 0);
        await new Promise((r) => setTimeout(r, 3000));
        if (cancelledRef.current) return;
        result = await pollBlindQueue();
        if (result.status === "none") result = await joinBlindQueue(userId, username);
      }
      if (cancelledRef.current || !result.room_code) return;
      const partnerName = result.partner_username ?? "someone";
      setMode({ kind: "paired", name: partnerName, code: result.room_code });
      // Prime the room for blind-date mode, remember who we're meeting, go.
      markSpeedDateRoom(result.room_code);
      markBlindPaired(result.room_code, partnerName);
      await leaveBlindQueue();
      window.setTimeout(() => {
        onOpenChange(false);
        navigate(`/meet/${result.room_code}`);
      }, 1200);
    } catch {
      if (cancelledRef.current) return;
      setMode({
        kind: "idle",
        error: "Matchmaking isn't switched on for this account yet — invite someone with a link meanwhile.",
      });
    }
  };

  const cancelSearch = (): void => {
    cancelledRef.current = true;
    setMode({ kind: "idle" });
    void leaveBlindQueue();
  };

  const elapsed = mode.kind === "searching" ? Math.max(0, Math.floor((now - mode.since) / 1000)) : 0;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[92vh] max-w-md overflow-y-auto rounded-[26px] border-rose-300/50 bg-gradient-to-b from-[#FCD4DF] via-rose-50 to-pink-100 p-0 dark:border-rose-500/30 dark:from-rose-950 dark:via-[#2a0d1a] dark:to-rose-950">
        <div className="space-y-3.5 px-5 pb-6 pt-7">
          <div className="text-center">
            <div className="flex justify-center">
              <EmberMascot size={84} palette={CUPID} smitten expression="delighted" />
            </div>
            <p className="mt-2 text-[11px] font-black uppercase tracking-[0.28em] text-rose-500">Blind dates</p>
            <h2 className="mt-1 text-[26px] font-black leading-tight">
              Hear them first.
              <br />
              See them at the reveal.
            </h2>
            <p className="mx-auto mt-2 max-w-[330px] text-[13px] leading-snug text-muted-foreground">
              Five minutes with someone compatible nearby — cameras stay behind a curtain until you both
              reveal. Jasper hosts with prompts built from both your cards.
            </p>
          </div>

          {mode.kind === "searching" ? (
            <div className="rounded-[18px] border border-rose-300/40 bg-white/75 p-4 text-center dark:bg-rose-950/40">
              <div className="relative mx-auto flex h-44 w-44 items-center justify-center">
                {[0, 1, 2].map((i) => (
                  <span
                    key={i}
                    className="absolute rounded-full border border-rose-400/40"
                    style={{
                      width: 90 + i * 46,
                      height: 90 + i * 46,
                      animation: `blind-radar 1.8s ease-in-out ${i * 0.25}s infinite`,
                    }}
                  />
                ))}
                <EmberMascot size={64} palette={CUPID} smitten expression="curious" isActive />
              </div>
              <p className="text-[16px] font-extrabold">Looking for someone compatible…</p>
              <p className="mt-1 text-[11.5px] font-semibold tabular-nums text-muted-foreground">
                {Math.floor(elapsed / 60)}:{String(elapsed % 60).padStart(2, "0")} · {waiting} waiting ·{" "}
                {prefsSummaryLine(prefs)}
              </p>
              <p className="mt-1 text-[12px] text-muted-foreground">
                Keep this open — the moment someone fits, you both drop into the room.
              </p>
              <button
                type="button"
                onClick={cancelSearch}
                className="mt-3 rounded-full border border-rose-300/60 bg-white/70 px-5 py-2 text-[13px] font-bold text-rose-600 transition-transform active:scale-95 dark:bg-rose-950/40 dark:text-rose-300"
              >
                Cancel
              </button>
              <style>{`@keyframes blind-radar { 0%, 100% { transform: scale(0.94); opacity: 0.35; } 50% { transform: scale(1.08); opacity: 0.85; } }`}</style>
            </div>
          ) : mode.kind === "paired" ? (
            <div className="rounded-[18px] border border-rose-300/50 bg-white/80 p-5 text-center dark:bg-rose-950/40">
              <p className="text-[44px] leading-none">💘</p>
              <p className="mt-2 text-[22px] font-black">It's a date!</p>
              <p className="mt-1 text-[13px] font-semibold text-muted-foreground">
                You're meeting @{mode.name}. Opening the room…
              </p>
              <Loader2 className="mx-auto mt-3 h-5 w-5 animate-spin text-rose-500" />
            </div>
          ) : (
            <div className="rounded-[18px] border border-rose-300/40 bg-white/75 p-4 dark:bg-rose-950/40">
              <div className="flex items-center justify-between">
                <p className="text-[10px] font-black uppercase tracking-[0.16em] text-rose-500">Find me a date</p>
                <span className="flex items-center gap-1.5 text-[10.5px] font-semibold text-muted-foreground">
                  <span className={cn("h-1.5 w-1.5 rounded-full", waiting > 0 ? "bg-emerald-500" : "bg-foreground/30")} />
                  {waiting > 0 ? `${waiting} waiting right now` : "Nobody waiting yet"}
                </span>
              </div>
              <p className="mt-1.5 text-[12.5px] leading-snug text-muted-foreground">
                Get paired with a stranger who fits your preferences — matched on your private icebreaker
                answers, distance, and what you're both looking for.
              </p>
              {mode.error && <p className="mt-2 text-[11.5px] font-semibold text-rose-500">{mode.error}</p>}
              <button
                type="button"
                onClick={() => void startSearch()}
                className="mt-3 flex w-full items-center justify-center gap-2 rounded-full bg-gradient-to-r from-rose-500 to-pink-500 py-3.5 text-[15.5px] font-black text-white shadow-lg shadow-rose-500/30 transition-transform active:scale-95"
              >
                <Sparkles className="h-4 w-4" />
                Find me a blind date 💘
              </button>
            </div>
          )}

          <div className="flex gap-2">
            <button
              type="button"
              onClick={onOpenPrefs}
              className={cn(
                "flex min-w-0 flex-1 items-center justify-center gap-1.5 rounded-full border px-3 py-2.5 text-[11.5px] font-bold transition-transform active:scale-95",
                prefsIsConfigured(prefs)
                  ? "border-transparent bg-rose-500 text-white"
                  : "border-rose-300/60 bg-white/70 text-rose-600 dark:bg-rose-950/40 dark:text-rose-300"
              )}
            >
              <SlidersHorizontal className="h-3 w-3 shrink-0" />
              <span className="truncate">{prefsIsConfigured(prefs) ? prefsSummaryLine(prefs) : "Set who you want to meet"}</span>
            </button>
            <button
              type="button"
              onClick={onOpenCard}
              className={cn(
                "flex shrink-0 items-center gap-1.5 rounded-full border px-3 py-2.5 text-[11.5px] font-bold transition-transform active:scale-95",
                cardCount > 0
                  ? "border-transparent bg-rose-500 text-white"
                  : "border-rose-300/60 bg-white/70 text-rose-600 dark:bg-rose-950/40 dark:text-rose-300"
              )}
            >
              <PenLine className="h-3 w-3" />
              {cardCount > 0 ? `Card ${cardCount}/${DATING_CARD_QUESTIONS.length}` : "Fill your card"}
            </button>
          </div>

          <div className="flex items-center gap-3 rounded-[18px] border border-rose-300/30 bg-white/60 p-3 dark:bg-rose-950/30">
            <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-rose-500/10">
              <Link2 className="h-4 w-4 text-rose-500" />
            </span>
            <div className="min-w-0 flex-1">
              <p className="text-[13.5px] font-extrabold">Invite someone instead</p>
              <p className="text-[11.5px] text-muted-foreground">Send a link — same blind-date room, your pick of person.</p>
            </div>
            <button
              type="button"
              onClick={() => {
                cancelSearch();
                onOpenChange(false);
                window.setTimeout(onInvite, 320);
              }}
              className="shrink-0 rounded-full bg-rose-500 px-3.5 py-2 text-[12.5px] font-bold text-white transition-transform active:scale-95"
            >
              Invite
            </button>
          </div>

          {history.length > 0 && (
            <div className="rounded-[18px] border border-rose-300/30 bg-white/60 p-3 dark:bg-rose-950/30">
              <p className="text-[10px] font-black uppercase tracking-[0.16em] text-rose-500">Your past dates</p>
              <div className="mt-2 space-y-2">
                {history.slice(0, 8).map((row) => (
                  <button
                    key={row.room_code}
                    type="button"
                    disabled={!row.partner_id}
                    onClick={() => {
                      if (!row.partner_id) return;
                      onOpenChange(false);
                      navigate(`/messages?to=${row.partner_id}&u=${encodeURIComponent(row.partner_username ?? "someone")}&kind=dating`);
                    }}
                    className="flex w-full items-center gap-2.5 text-left"
                  >
                    <span className="flex h-[34px] w-[34px] shrink-0 items-center justify-center rounded-full bg-rose-500/80 text-[14px] font-black text-white">
                      {(row.partner_username ?? "?").slice(0, 1).toUpperCase()}
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-[13.5px] font-bold">@{row.partner_username ?? "someone"}</span>
                      <span className="block text-[10.5px] text-muted-foreground">
                        {row.started_at ? new Date(row.started_at).toLocaleDateString() : ""} ·{" "}
                        {row.source === "queue" ? "blind match" : "invited"}
                        {row.revealed ? " · revealed" : ""}
                      </span>
                    </span>
                    <span
                      className={cn(
                        "shrink-0 rounded-full px-2.5 py-1 text-[10.5px] font-bold",
                        row.mutual ? "bg-rose-500 text-white" : "bg-rose-500/10 text-rose-600 dark:text-rose-300"
                      )}
                    >
                      {blindOutcomeLabel(row)}
                    </span>
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
