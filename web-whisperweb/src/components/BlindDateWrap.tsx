import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Check, Copy, Loader2, MessageCircle, ShieldHalf, Sparkles } from "lucide-react";
import { toast } from "sonner";

import { EmberMascot } from "@/components/EmberMascot";
import { MatchCelebration } from "@/components/MatchCelebration";
import { sendMessage } from "@/lib/api";
import {
  BLIND_DECISION_META,
  decideBlindDate,
  blindDateHistory,
  blindRecordKey,
  finishBlindDate,
  generateBlindRecap,
  type BlindDecision,
} from "@/lib/blindDate";
import { loadDatingCardLocal, type DatingCardWire, type DatingVerdict } from "@/lib/datingCards";
import { markDatingPeer } from "@/lib/datingInbox";
import { buildMatched, markMatchCelebrationSeen } from "@/lib/datingMatch";
import { supabase } from "@/lib/supabase";

/** Round 77 — the wrap's Report writes a real report AND blocks in one move (whisper_dating_report). */
async function reportDatingPartner(username: string, reason: string, roomCode: string | null): Promise<boolean> {
  const { error } = await supabase.rpc("whisper_dating_report", {
    p_reported_username: username,
    p_reason: reason,
    p_details: null,
    p_room_code: roomCode,
    p_block: true,
  });
  return !error;
}
import { cn } from "@/lib/utils";

const CUPID = { accent: "#F5B8CC", softAccent: "#FFEDF2", deepAccent: "#E68FAD" };

/**
 * What a blind date looks like when it ENDS — not a meeting recap. The
 * wrap asks for your private decision (see them again · friends · pass),
 * reveals the partner's answer only once both are in (mutual 💘 → the
 * linking celebration + a DM), offers Jasper's read of the date on tap,
 * and keeps the safety exits one tap away. Mirrors iOS
 * `WhisperBlindDateWrapView`.
 */
export function BlindDateWrap({
  roomKey,
  userId,
  myName,
  myAvatarUrl,
  partnerUserId,
  partnerName,
  partnerAvatarUrl,
  transcript,
  theirCard,
  revealed,
  partnerLeft,
  elapsedSec,
  onClose,
}: {
  roomKey: string;
  userId: string;
  myName: string;
  myAvatarUrl: string | null | undefined;
  partnerUserId: string;
  partnerName: string;
  partnerAvatarUrl: string | null | undefined;
  transcript: string;
  theirCard: DatingCardWire | null;
  revealed: boolean;
  partnerLeft: boolean;
  elapsedSec: number;
  onClose: () => void;
}) {
  const navigate = useNavigate();
  const [decision, setDecision] = useState<BlindDecision | null>(null);
  const [theirDecision, setTheirDecision] = useState<BlindDecision | null>(null);
  const [waiting, setWaiting] = useState<boolean>(false);
  const [timedOut, setTimedOut] = useState<boolean>(false);
  const [mutual, setMutual] = useState<boolean>(false);
  // Round 77 — report + block in one move (RPC), replacing the mailto.
  const [reporting, setReporting] = useState<boolean>(false);
  const [reportDone, setReportDone] = useState<boolean>(false);
  const reportAndBlock = async (reason: string): Promise<void> => {
    setReporting(true);
    const ok = await reportDatingPartner(partnerName, reason, roomKey);
    setReporting(false);
    if (ok) {
      setReportDone(true);
      toast.success(`Reported and blocked @${partnerName}`);
    } else {
      toast.error("Couldn't send the report. Check your connection and try again.");
    }
  };
  const [celebrate, setCelebrate] = useState<boolean>(false);
  const [recap, setRecap] = useState<DatingVerdict | null>(null);
  const [recapBusy, setRecapBusy] = useState<boolean>(false);
  const [recapFailed, setRecapFailed] = useState<boolean>(false);
  const [copied, setCopied] = useState<boolean>(false);
  const cancelledRef = useRef<boolean>(false);

  useEffect(() => {
    cancelledRef.current = false;
    void finishBlindDate(roomKey, revealed, null);
    return () => {
      cancelledRef.current = true;
    };
  }, [roomKey, revealed]);

  const openDm = (): void => {
    markDatingPeer(userId, partnerUserId);
    navigate(`/messages?to=${partnerUserId}&u=${encodeURIComponent(partnerName)}&kind=dating`);
  };

  const landTheirs = (d: BlindDecision, mine: BlindDecision): void => {
    setTheirDecision(d);
    setWaiting(false);
    const isMutual = d === "again" && mine === "again";
    setMutual(isMutual);
    if (!isMutual) return;
    // Seal the match on the DM rails exactly like the Match-back button.
    void sendMessage(userId, myName, partnerUserId, partnerName, buildMatched(userId, myName), () => { if (cancelledRef.current) throw new Error("Date closed"); }, "dating").catch(() => undefined);
    markMatchCelebrationSeen(userId, partnerUserId);
    markDatingPeer(userId, partnerUserId);
    setCelebrate(true);
  };

  /** Watches for the partner's answer — the date record first, then the DM wire. */
  const pollForTheirs = async (mine: BlindDecision): Promise<void> => {
    for (let i = 0; i < 40; i += 1) {
      if (cancelledRef.current) return;
      const result = (await blindDateHistory()).find((row) => blindRecordKey(row.room_code) === blindRecordKey(roomKey));
      if (cancelledRef.current) return;
      if (result?.their_decision === "again" || result?.their_decision === "friends" || result?.their_decision === "pass") {
        landTheirs(result.their_decision, mine);
        return;
      }
      await new Promise((r) => setTimeout(r, 3000));
    }
    if (!cancelledRef.current) {
      setWaiting(false);
      setTimedOut(true);
    }
  };

  const decide = (d: BlindDecision): void => {
    setDecision(d);
    if (d !== "pass") markDatingPeer(userId, partnerUserId);
    if (d === "again") {
      // The 💘 request rides the DM wire — they get the push, and the
      // Messages thread turns into a match the moment they say yes too.
      setWaiting(true);
      void decideBlindDate(roomKey, d).then((result) => {
        if (cancelledRef.current) return;
        if (!result) { setWaiting(false); setDecision(null); toast.error("Your decision couldn't be saved. Please retry."); return; }
        if (result.theirs === "again" || result.theirs === "friends" || result.theirs === "pass") landTheirs(result.theirs, d);
        else void pollForTheirs(d);
      });
    } else {
      void decideBlindDate(roomKey, d);
    }
  };

  const runRecap = async (): Promise<void> => {
    if (recapBusy) return;
    setRecapBusy(true);
    setRecapFailed(false);
    const result = await generateBlindRecap({
      myName,
      myCard: loadDatingCardLocal(userId),
      theirCard,
      transcript,
    });
    setRecapBusy(false);
    if (!result) {
      setRecapFailed(true);
      return;
    }
    setRecap(result);
    void finishBlindDate(roomKey, revealed, result);
  };

  const mutualLine = (): string => {
    if (mutual) return "You both want to see each other again 💘 — the chat is open.";
    if (theirDecision) return `@${partnerName} chose differently this time — it happens. Your yes stays private.`;
    if (timedOut) return `Sent 💘 If @${partnerName} feels the same, you'll match in Messages and get a notification.`;
    return `Sent 💘 If @${partnerName} feels the same, it's a match.`;
  };

  const avatar = (url: string | null | undefined, name: string, offset: string): React.ReactNode => (
    <span
      className={cn(
        "absolute top-0 flex h-[76px] w-[76px] items-center justify-center overflow-hidden rounded-full border-[3px] border-white/85 bg-rose-500/35 text-[26px] font-black shadow-xl shadow-rose-500/40",
        offset
      )}
    >
      {url ? <img src={url} alt="" className="h-full w-full object-cover" /> : name.slice(0, 1).toUpperCase()}
    </span>
  );

  return (
    <div className="fixed inset-0 z-[90] overflow-y-auto bg-gradient-to-b from-[#240510] via-[#470F24] to-[#1F0512] text-white">
      <div className="mx-auto w-full max-w-md px-5 pb-10 pt-8">
        {/* Header */}
        <div className="flex flex-col items-center text-center">
          <div className="relative h-24 w-[160px]">
            {avatar(myAvatarUrl, myName, "left-[12px]")}
            {avatar(partnerAvatarUrl, partnerName, "right-[12px]")}
            <span className="absolute bottom-0 left-1/2 flex h-10 w-10 -translate-x-1/2 items-center justify-center rounded-full bg-[#33081F] text-[22px]">
              💘
            </span>
          </div>
          <p className="mt-3 text-[10.5px] font-black uppercase tracking-[0.22em] text-rose-300">Date over</p>
          <h1 className="mt-1 text-[24px] font-black leading-tight">
            {partnerLeft ? `@${partnerName} left the date` : `Your date with @${partnerName}`}
          </h1>
          <p className="mt-1 text-[12.5px] font-semibold text-white/60">
            {Math.max(1, Math.floor(elapsedSec / 60))} min · {revealed ? "you revealed 👀" : "stayed blind 🙈"}
          </p>
        </div>

        {/* Decision */}
        <div className="mt-5 rounded-[20px] border border-rose-500/35 bg-white/[0.07] p-4">
          {decision == null ? (
            <>
              <p className="text-[17px] font-extrabold">Would you see @{partnerName} again?</p>
              <p className="mt-1 text-[12px] leading-snug text-white/60">
                Your answer stays private. They only find out if you BOTH say yes.
              </p>
              <div className="mt-3 space-y-2">
                <button
                  type="button"
                  onClick={() => decide("again")}
                  className="flex w-full items-center justify-center gap-1.5 rounded-full bg-gradient-to-r from-rose-500 to-pink-500 py-3.5 text-[15px] font-black shadow-xl shadow-rose-500/30 transition-transform active:scale-95"
                >
                  {BLIND_DECISION_META.again.emoji} {BLIND_DECISION_META.again.label}
                </button>
                <div className="flex gap-2">
                  {(["friends", "pass"] as BlindDecision[]).map((d) => (
                    <button
                      key={d}
                      type="button"
                      onClick={() => decide(d)}
                      className="flex flex-1 items-center justify-center gap-1.5 rounded-full border border-white/20 bg-white/[0.12] py-2.5 text-[13px] font-black transition-transform active:scale-95"
                    >
                      {BLIND_DECISION_META[d].emoji} {BLIND_DECISION_META[d].label}
                    </button>
                  ))}
                </div>
              </div>
            </>
          ) : decision === "again" ? (
            <>
              <div className="flex items-start gap-2.5">
                <span className="text-[22px]">💘</span>
                <div>
                  <p className="text-[17px] font-extrabold">{mutual ? "It's a match!" : "You said yes"}</p>
                  <p className="mt-0.5 text-[12px] leading-snug text-white/65">{mutualLine()}</p>
                </div>
              </div>
              {waiting && !mutual && !theirDecision && (
                <p className="mt-2 flex items-center gap-2 text-[12px] font-semibold text-rose-300">
                  <Loader2 className="h-3.5 w-3.5 animate-spin" /> Waiting for @{partnerName}'s answer…
                </p>
              )}
              {mutual && (
                <div className="mt-3 flex gap-2">
                  <button
                    type="button"
                    onClick={openDm}
                    className="flex flex-1 items-center justify-center gap-1.5 rounded-full bg-rose-500 py-2.5 text-[13px] font-bold transition-transform active:scale-95"
                  >
                    <MessageCircle className="h-3.5 w-3.5" /> Say hi 💬
                  </button>
                  <button
                    type="button"
                    onClick={() => setCelebrate(true)}
                    className="rounded-full bg-white/[0.12] px-4 py-2.5 text-[13px] font-bold text-rose-300 transition-transform active:scale-95"
                  >
                    Replay 💘
                  </button>
                </div>
              )}
            </>
          ) : decision === "friends" ? (
            <>
              <div className="flex items-start gap-2.5">
                <span className="text-[22px]">🤝</span>
                <div>
                  <p className="text-[17px] font-extrabold">Friends it is</p>
                  <p className="mt-0.5 text-[12px] leading-snug text-white/65">
                    @{partnerName} is in your 💘 inbox — send a friendly note whenever.
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={openDm}
                className="mt-3 flex w-full items-center justify-center gap-1.5 rounded-full bg-white/[0.14] py-2.5 text-[13px] font-bold transition-transform active:scale-95"
              >
                <MessageCircle className="h-3.5 w-3.5" /> Send a friendly note
              </button>
            </>
          ) : (
            <div className="flex items-start gap-2.5">
              <span className="text-[22px]">👋</span>
              <div>
                <p className="text-[17px] font-extrabold">Not this time</p>
                <p className="mt-0.5 text-[12px] leading-snug text-white/65">
                  Got it. @{partnerName} will never know — on to the next one.
                </p>
              </div>
            </div>
          )}
        </div>

        {/* Jasper's recap */}
        <div className="mt-4 rounded-[20px] border border-white/[0.12] bg-white/[0.07] p-4">
          <div className="flex items-center gap-2">
            <EmberMascot size={30} palette={CUPID} smitten isActive={recapBusy} expression={recap ? "delighted" : "calm"} cyclesExpressions={!recapBusy} />
            <div>
              <p className="text-[14px] font-extrabold">Jasper's read of the date</p>
              <p className="text-[10.5px] text-white/60">Both cards + what you actually said</p>
            </div>
          </div>
          {recap ? (
            <div className="mt-3 space-y-2">
              <div className="flex items-baseline gap-2">
                <span className="text-[34px] font-black leading-none text-rose-300">{recap.score}%</span>
                <span className="text-[9px] font-black uppercase tracking-[0.12em] text-white/55">compatible</span>
              </div>
              <div className="h-1.5 overflow-hidden rounded-full bg-white/10">
                <div
                  className="h-full rounded-full bg-gradient-to-r from-rose-500 to-rose-300 transition-[width] duration-700"
                  style={{ width: `${recap.score}%` }}
                />
              </div>
              {recap.verdict && <p className="text-[13px] font-semibold leading-snug">{recap.verdict}</p>}
              {recap.sparks.map((s) => (
                <p key={s} className="text-[12px] leading-snug text-white/85">💘 {s}</p>
              ))}
              {recap.flag && <p className="text-[12px] leading-snug text-white/75">🚩 {recap.flag}</p>}
              {recap.opener && (
                <div className="rounded-[14px] bg-white/[0.07] p-2.5">
                  <p className="text-[9px] font-black uppercase tracking-[0.14em] text-rose-300">Your opener</p>
                  <p className="mt-1 text-[13px] font-semibold italic leading-snug">“{recap.opener}”</p>
                  <button
                    type="button"
                    onClick={() => {
                      void navigator.clipboard?.writeText(recap.opener ?? "").catch(() => undefined);
                      setCopied(true);
                      toast.success("Opener copied — paste it in the chat");
                      openDm();
                    }}
                    className="mt-2 flex items-center gap-1.5 rounded-full bg-rose-500 px-3 py-1.5 text-[11.5px] font-bold transition-transform active:scale-95"
                  >
                    {copied ? <Check className="h-3 w-3" /> : <Copy className="h-3 w-3" />}
                    {copied ? "Copied — paste it in the chat" : "Copy & open the chat"}
                  </button>
                </div>
              )}
              {recap.askNext && <p className="text-[11.5px] leading-snug text-white/65">Next time, ask: {recap.askNext}</p>}
            </div>
          ) : (
            <div className="mt-3">
              <p className="text-[12px] leading-snug text-white/65">
                {transcript.trim()
                  ? "One quiet read — score, what clicked, one honest flag, and the first message to send."
                  : "No transcript landed from this date, so Jasper will read the two cards."}
              </p>
              {recapFailed && (
                <p className="mt-1.5 text-[11.5px] font-semibold text-rose-300">Jasper couldn't read that — try again in a moment.</p>
              )}
              <button
                type="button"
                onClick={() => void runRecap()}
                disabled={recapBusy}
                className="mt-3 flex w-full items-center justify-center gap-1.5 rounded-full bg-rose-500 py-2.5 text-[12.5px] font-bold transition-transform active:scale-95 disabled:opacity-60"
              >
                {recapBusy ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Sparkles className="h-3.5 w-3.5" />}
                {recapBusy ? "Jasper is reading…" : "Read the date"}
              </button>
            </div>
          )}
        </div>

        {/* Safety */}
        <div className="mt-4 flex items-center gap-2 rounded-[16px] bg-white/[0.05] px-3 py-2.5">
          <ShieldHalf className="h-4 w-4 shrink-0 text-emerald-300" />
          <p className="flex-1 text-[12px] font-semibold text-white/75">Something felt off?</p>
          {reportDone ? (
            <span className="rounded-full bg-emerald-500/20 px-3 py-1.5 text-[12px] font-bold text-emerald-200">Reported & blocked ✓</span>
          ) : (
            <select
              aria-label={`Report @${partnerName}`}
              defaultValue=""
              disabled={reporting}
              onChange={(e) => {
                const reason = e.target.value;
                if (!reason) return;
                void reportAndBlock(reason);
              }}
              className="rounded-full bg-white/[0.12] px-3 py-1.5 text-[12px] font-bold text-white outline-none"
            >
              <option value="" className="text-black">Report @{partnerName}…</option>
              <option value="fake" className="text-black">Fake profile or photos</option>
              <option value="harassment" className="text-black">Harassment or hate</option>
              <option value="inappropriate" className="text-black">Inappropriate behavior</option>
              <option value="underage" className="text-black">Seems underage</option>
              <option value="scam" className="text-black">Scam or spam</option>
              <option value="other" className="text-black">Something else</option>
            </select>
          )}
        </div>

        <button
          type="button"
          onClick={onClose}
          className="mt-5 w-full rounded-full border border-white/[0.18] bg-white/[0.10] py-3 text-[14px] font-bold text-white/85 transition-transform active:scale-95"
        >
          Back to Dating
        </button>
      </div>

      {celebrate && (
        <MatchCelebration
          myName={myName}
          myAvatarUrl={myAvatarUrl}
          otherName={partnerName}
          otherAvatarUrl={partnerAvatarUrl}
          onDismiss={() => setCelebrate(false)}
        />
      )}
    </div>
  );
}
