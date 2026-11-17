import { useEffect, useState } from "react";
import { ChevronLeft, ChevronRight, Eye, EyeOff, Hourglass, Plus } from "lucide-react";

import { EmberMascot } from "@/components/EmberMascot";
import { BLIND_STAGE_META, formatBlindClock, type BlindDateSession } from "@/lib/blindDate";
import { cn } from "@/lib/utils";

const CUPID = { accent: "#F5B8CC", softAccent: "#FFEDF2", deepAccent: "#E68FAD" };

/**
 * The blind-date STAGE — what a dating room looks like instead of a
 * meeting. Before the reveal a rose curtain covers the video: two blurred
 * silhouettes, the shared timer ring counting down to the reveal, and
 * Jasper's prompt card. After the reveal it parts into a slim HUD floating
 * over the live video. Mirrors iOS `WhisperBlindDateStageView`.
 */
export function BlindDateStage({
  session,
  tick,
  myName,
  myAvatarUrl,
  partnerName,
  partnerAvatarUrl,
  onReveal,
  onExtend,
  onPrompt,
}: {
  session: BlindDateSession;
  /** Bumps when the room mutates the session so React re-renders promptly. */
  tick: number;
  myName: string;
  myAvatarUrl: string | null | undefined;
  partnerName: string;
  partnerAvatarUrl: string | null | undefined;
  onReveal: () => void;
  onExtend: () => void;
  onPrompt: (delta: number) => void;
}) {
  const [, setClock] = useState<number>(0);
  const [flash, setFlash] = useState<boolean>(false);
  void tick;

  // The half-second clock — the timer ring, last-call pulse, stage nudges.
  useEffect(() => {
    const t = window.setInterval(() => setClock((c) => c + 1), 500);
    return () => window.clearInterval(t);
  }, []);

  // The reveal moment — a bright flash + "Reveal!" as the curtain parts.
  useEffect(() => {
    if (!session.revealed) return;
    setFlash(true);
    const t = window.setTimeout(() => setFlash(false), 1700);
    return () => window.clearTimeout(t);
  }, [session.revealed]);

  const total = Math.max(1, session.durationSec);
  const progress = session.startedAt == null ? 0 : Math.min(1, session.elapsed / total);
  const lastCall = session.isLastCall;
  const prompt = session.currentPrompt;
  const stage = prompt?.stage ?? session.clockStage;
  const stageMeta = BLIND_STAGE_META[stage];

  const ring = (size: number, stroke: number, big: boolean): React.ReactNode => {
    const r = (size - stroke) / 2;
    const c = 2 * Math.PI * r;
    return (
      <div className={cn("relative shrink-0", lastCall && "blind-lastcall")} style={{ width: size, height: size }}>
        <svg width={size} height={size} className="-rotate-90">
          <circle cx={size / 2} cy={size / 2} r={r} stroke="rgba(255,255,255,0.12)" strokeWidth={stroke} fill="none" />
          <circle
            cx={size / 2}
            cy={size / 2}
            r={r}
            stroke="url(#blind-ring-grad)"
            strokeWidth={stroke}
            strokeLinecap="round"
            fill="none"
            strokeDasharray={c}
            strokeDashoffset={c * (1 - progress)}
            style={{ transition: "stroke-dashoffset 0.5s linear" }}
          />
          <defs>
            <linearGradient id="blind-ring-grad" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stopColor="#E8477D" />
              <stop offset="100%" stopColor="#FF9FBF" />
            </linearGradient>
          </defs>
        </svg>
        {big && (
          <div className="absolute inset-0 flex flex-col items-center justify-center">
            {session.startedAt == null ? (
              <>
                <span className="text-[22px] font-black text-white">Waiting</span>
                <span className="text-[10.5px] font-semibold text-white/60">
                  {session.theirReady ? "starting…" : `for @${partnerName}`}
                </span>
              </>
            ) : (
              <>
                <span className={cn("text-[34px] font-black tabular-nums leading-none", lastCall ? "text-rose-300" : "text-white")}>
                  {formatBlindClock(session.remaining)}
                </span>
                <span className={cn("mt-1 text-[10.5px] font-bold", lastCall ? "text-rose-300" : "text-white/65")}>
                  {lastCall ? "Last call 💘" : `Reveal in ${formatBlindClock(session.untilReveal)}`}
                </span>
              </>
            )}
          </div>
        )}
      </div>
    );
  };

  const silhouette = (name: string, url: string | null | undefined, ready: boolean, isMe: boolean): React.ReactNode => (
    <div className="flex w-[124px] flex-col items-center gap-1.5">
      <div className="relative h-[92px] w-[92px]">
        <div
          className={cn(
            "h-full w-full overflow-hidden rounded-full border-2",
            ready ? "border-rose-300" : "border-white/25",
            !isMe && "bg-black/40"
          )}
        >
          {url ? (
            <img
              src={url}
              alt=""
              className="h-full w-full object-cover"
              style={isMe ? undefined : { filter: "blur(16px) brightness(0.65)", transform: "scale(1.2)" }}
            />
          ) : (
            <span
              className={cn(
                "flex h-full w-full items-center justify-center bg-rose-500/35 text-[34px] font-black",
                isMe ? "text-white/90" : "text-white/25"
              )}
              style={isMe ? undefined : { filter: "blur(6px)" }}
            >
              {name.slice(0, 1).toUpperCase()}
            </span>
          )}
        </div>
        {!isMe && (
          <EyeOff className="absolute left-1/2 top-1/2 h-5 w-5 -translate-x-1/2 -translate-y-1/2 text-white/85" />
        )}
        {ready && (
          <span className="absolute -right-0.5 -top-0.5 flex h-6 w-6 items-center justify-center rounded-full bg-emerald-500 text-[12px] font-black text-white ring-2 ring-[#2a0d1a]">
            ✓
          </span>
        )}
      </div>
      <p className="truncate text-[12.5px] font-bold text-white/90">{isMe ? "You" : `@${name}`}</p>
      <p className={cn("text-[10px] font-semibold", ready ? "text-rose-300" : "text-white/50")}>
        {ready ? "Ready to reveal" : isMe ? "Blind" : "Hidden until the reveal"}
      </p>
    </div>
  );

  const nudge = (): string => {
    if (!prompt) return "";
    const clock = session.clockStage;
    if (prompt.stage === "WARM" && clock !== "WARM") return "Ready to go deeper →";
    if (prompt.stage === "DEEPER" && clock === "SPARK") return "Time for a spark →";
    return "Ask each other";
  };

  const promptCard = (compact: boolean): React.ReactNode => (
    <div
      className={cn(
        "w-full rounded-[18px] border border-rose-500/40 text-left",
        compact ? "bg-[#33081F]/92 p-3" : "bg-[#33081F]/70 p-3.5"
      )}
    >
      <div className="flex items-center gap-1.5">
        <span className="text-[9.5px] font-black uppercase tracking-[0.14em] text-rose-300">
          {stageMeta.emoji} {stageMeta.label}
        </span>
        {session.deck.length > 0 && (
          <span className="text-[9.5px] font-bold text-white/50">
            · {Math.min(session.promptIndex + 1, session.deck.length)}/{session.deck.length}
          </span>
        )}
        <span className="ml-auto flex items-center gap-1 text-[9.5px] font-bold text-white/60">
          <EmberMascot size={18} palette={CUPID} smitten expression="happy" />
          Jasper's prompt
        </span>
      </div>
      <p
        key={prompt?.text ?? "loading"}
        className={cn("blind-prompt-in mt-1.5 font-bold leading-snug text-white", compact ? "text-[14px]" : "text-[17px]")}
      >
        {prompt ? prompt.text : "Jasper is writing prompts from both of your cards…"}
      </p>
      {session.deck.length > 0 && (
        <div className="mt-2 flex items-center gap-2">
          <button
            type="button"
            onClick={() => onPrompt(-1)}
            disabled={session.promptIndex <= 0}
            className="flex h-[30px] w-[30px] items-center justify-center rounded-full bg-white/15 text-white disabled:opacity-40"
            aria-label="Previous prompt"
          >
            <ChevronLeft className="h-3.5 w-3.5" strokeWidth={3} />
          </button>
          <button
            type="button"
            onClick={() => onPrompt(1)}
            disabled={session.promptIndex >= session.deck.length - 1}
            className="flex h-[30px] w-[30px] items-center justify-center rounded-full bg-white/15 text-white disabled:opacity-40"
            aria-label="Next prompt"
          >
            <ChevronRight className="h-3.5 w-3.5" strokeWidth={3} />
          </button>
          <span className="ml-auto truncate text-[10px] font-semibold text-white/45">{nudge()}</span>
        </div>
      )}
    </div>
  );

  const theyAskedExtend = session.theirExtendRound > session.myExtendRound;
  const iAskedExtend = session.myExtendRound > session.theirExtendRound;
  const extendButton = (
    <button
      type="button"
      onClick={onExtend}
      disabled={iAskedExtend}
      className={cn(
        "pointer-events-auto flex shrink-0 items-center gap-1 rounded-full border border-rose-300/50 px-3.5 py-3 text-[13px] font-black transition-transform active:scale-95",
        theyAskedExtend ? "blind-pulse bg-rose-500 text-white" : "bg-white/12 text-rose-300",
        iAskedExtend && "opacity-70"
      )}
    >
      <Plus className="h-3 w-3" strokeWidth={3} />
      {iAskedExtend ? "Asked" : "2 min"}
    </button>
  );

  const revealLabel = session.myRevealTapped
    ? `Waiting for @${partnerName}…`
    : session.theirRevealTapped
      ? `@${partnerName} is ready — reveal 💘`
      : "Reveal now 💘";

  return (
    <>
      <style>{`
        @keyframes blind-pulse { 0%, 100% { transform: scale(1); } 50% { transform: scale(1.04); } }
        .blind-pulse { animation: blind-pulse 1.1s ease-in-out infinite; }
        .blind-lastcall { animation: blind-pulse 1.1s ease-in-out infinite; }
        @keyframes blind-drift-a { 0%, 100% { transform: translate(0, 0); } 50% { transform: translate(90px, 60px); } }
        @keyframes blind-drift-b { 0%, 100% { transform: translate(0, 0); } 50% { transform: translate(-80px, -50px); } }
        @keyframes blind-prompt-in { from { opacity: 0; transform: translateX(10px); } to { opacity: 1; transform: none; } }
        .blind-prompt-in { animation: blind-prompt-in 0.35s ease-out; }
        @keyframes blind-flash { 0% { opacity: 0; } 15% { opacity: 1; } 100% { opacity: 0; } }
        @keyframes blind-curtain-out { to { opacity: 0; transform: scale(1.12); } }
      `}</style>

      {!session.revealed ? (
        <div className="absolute inset-0 z-20 overflow-hidden bg-gradient-to-br from-[#290611] via-[#4C0F26] to-[#210409] text-white">
          <span
            aria-hidden
            className="absolute -left-24 -top-32 h-80 w-80 rounded-full"
            style={{ background: "#E8477D", filter: "blur(70px)", opacity: 0.35, animation: "blind-drift-a 7s ease-in-out infinite" }}
          />
          <span
            aria-hidden
            className="absolute -bottom-24 -right-16 h-64 w-64 rounded-full"
            style={{ background: "#FF9FBF", filter: "blur(66px)", opacity: 0.22, animation: "blind-drift-b 8s ease-in-out infinite" }}
          />
          <div className="relative flex h-full flex-col items-center gap-3.5 overflow-y-auto px-4 pb-32 pt-16 sm:pt-20">
            <div className="flex items-start gap-5">
              {silhouette(myName, myAvatarUrl, session.myRevealTapped, true)}
              <span className="blind-pulse mt-7 text-[26px]">💘</span>
              {silhouette(partnerName, partnerAvatarUrl, session.theirRevealTapped, false)}
            </div>
            {ring(150, 8, true)}
            <div className="w-full max-w-[420px]">{promptCard(false)}</div>
            <div className="mt-auto flex w-full max-w-[420px] items-center gap-2.5">
              <button
                type="button"
                onClick={onReveal}
                disabled={session.myRevealTapped || session.startedAt == null}
                className={cn(
                  "flex flex-1 items-center justify-center gap-1.5 rounded-full py-3.5 text-[14px] font-black text-white transition-transform active:scale-95",
                  session.myRevealTapped
                    ? "border border-white/25 bg-white/15"
                    : "bg-gradient-to-r from-rose-500 to-pink-500 shadow-xl shadow-rose-500/30",
                  session.theirRevealTapped && !session.myRevealTapped && "blind-pulse",
                  session.startedAt == null && "opacity-60"
                )}
              >
                {session.myRevealTapped ? <Hourglass className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                <span className="truncate">{revealLabel}</span>
              </button>
              {session.canExtend && extendButton}
            </div>
          </div>
        </div>
      ) : (
        <div className="pointer-events-none absolute inset-0 z-20 flex flex-col items-center px-3.5 pb-32 pt-16 text-white sm:pt-20">
          <div className="pointer-events-auto flex items-center gap-2.5 rounded-full border border-rose-500/40 bg-[#2a0d1a]/85 px-3 py-2 backdrop-blur">
            {ring(44, 5, false)}
            <div className="leading-tight">
              <p className={cn("text-[12.5px] font-black", lastCall ? "text-rose-300" : "text-white")}>
                {lastCall ? "Last call 💘" : "Revealed 💘"}
              </p>
              <p className="text-[10.5px] font-semibold tabular-nums text-white/65">
                {BLIND_STAGE_META[session.clockStage].emoji} {BLIND_STAGE_META[session.clockStage].label} ·{" "}
                {formatBlindClock(session.remaining)} left
              </p>
            </div>
            {session.canExtend && <span className="scale-[0.85]">{extendButton}</span>}
          </div>
          <div className="pointer-events-auto mt-auto w-full max-w-[420px]">{promptCard(true)}</div>
        </div>
      )}

      {flash && (
        <div
          className="pointer-events-none absolute inset-0 z-[26] flex flex-col items-center justify-center bg-white/35"
          style={{ animation: "blind-flash 1.7s ease-out forwards" }}
        >
          <span className="text-[64px] leading-none">💘</span>
          <span className="mt-2 text-[30px] font-black text-white drop-shadow-[0_0_14px_rgba(232,71,125,0.7)]">Reveal!</span>
        </div>
      )}
    </>
  );
}
