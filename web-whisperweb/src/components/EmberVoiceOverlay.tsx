import { memo, useCallback, useEffect, useRef, useState } from "react";
import { Mic, MicOff, X } from "lucide-react";

import { EmberMascot } from "@/components/EmberMascot";
import type {
  EmberBlock,
  EmberCoachMode,
  EmberExpression,
} from "@/lib/emberBrain";
import { coachModeInfo } from "@/lib/emberBrain";
import { KnotVoiceSession, type KnotVoiceContext } from "@/lib/knotVoiceSession";
import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";

/** Knot's shared Rork answering model, with maintained ElevenLabs speech transport.
 * Voice-only: no independent browser tools or execution permission. */

type VoicePhase = "connecting" | "live" | "error";

function EmberVoiceOverlayBase({
  open,
  coachMode,
  context,
  onExchange,
  onClose,
}: {
  open: boolean;
  coachMode: EmberCoachMode;
  context?: KnotVoiceContext;
  /** Records each spoken exchange (plus any card) into the chat transcript. */
  onExchange: (
    userText: string,
    replyText: string,
    block: EmberBlock | null,
  ) => void;
  onClose: () => void;
}) {
  const { user } = useAuth();
  const accountID = user?.id;
  const [phase, setPhase] = useState<VoicePhase>("connecting");
  const [hearing, setHearing] = useState<boolean>(false);
  const [thinking, setThinking] = useState<boolean>(false);
  const [speaking, setSpeaking] = useState<boolean>(false);
  const [micMuted, setMicMuted] = useState<boolean>(false);
  const [userLine, setUserLine] = useState<string>("");
  const [replyText, setReplyText] = useState<string>("");
  const [statusMessage, setStatusMessage] = useState<string | null>(null);

  const sessionRef = useRef<KnotVoiceSession | null>(null);
  const contextRef = useRef(context); contextRef.current = context;
  const userTurnRef = useRef<string>("");
  const exchangeRef = useRef(onExchange);
  exchangeRef.current = onExchange;

  const endSession = useCallback((): void => {
    const session = sessionRef.current;
    sessionRef.current = null;
    session?.close();
  }, []);

  // One live session per open. Everything resets when the overlay opens and
  // the session dies with the overlay — never in the background.
  useEffect(() => {
    if (!open || !accountID) return;
    setPhase("connecting");
    setHearing(false);
    setThinking(false);
    setSpeaking(false);
    setMicMuted(false);
    setUserLine("");
    setReplyText("");
    setStatusMessage(null);
    userTurnRef.current = "";

    const session = new KnotVoiceSession({
      owner: accountID, context: contextRef.current,
      callbacks: {
        onState: (state) => {
          if (sessionRef.current !== session) return;
          if (state === "error" || state === "closed") {
            sessionRef.current = null;
            session.close();
            setPhase("error");
            setStatusMessage(
              "Knot's live voice couldn't connect. You can keep typing in the chat.",
            );
          }
        },
        onUserSpeech: (active) => {
          if (sessionRef.current === session) setHearing(active);
        },
        onUserTranscript: (text, final) => {
          if (sessionRef.current !== session) return;
          setUserLine(text);
          if (final) { userTurnRef.current = text; setThinking(true); }
        },
        onAssistantDone: (full) => {
          if (sessionRef.current !== session) return;
          setThinking(false);
          setReplyText(full);
          const userText = userTurnRef.current.trim();
          if (userText || full.trim()) {
            exchangeRef.current(userText, full, null);
          }
          userTurnRef.current = "";
        },
        onSpeaking: (isSpeaking) => {
          if (sessionRef.current === session) setSpeaking(isSpeaking);
        },
      },
    });
    sessionRef.current = session;
    void session
      .connect()
      .then(() => {
        if (sessionRef.current === session) setPhase("live");
      })
      .catch(() => {
        if (sessionRef.current !== session) return;
        sessionRef.current = null;
        session.close();
        setPhase("error");
        setStatusMessage(
          "Knot's live voice couldn't connect. You can keep typing in the chat.",
        );
      });
    const stopWhenHidden = (): void => {
      if (document.visibilityState !== "hidden") return;
      if (sessionRef.current === session) sessionRef.current = null;
      session.close();
      setPhase("error");
      setHearing(false); setThinking(false); setSpeaking(false);
      setStatusMessage("Voice paused when you left the page. Close and reopen voice to reconnect.");
    };
    document.addEventListener("visibilitychange", stopWhenHidden);
    return () => {
      document.removeEventListener("visibilitychange", stopWhenHidden);
      if (sessionRef.current === session) sessionRef.current = null;
      session.close();
    };
  }, [open, accountID]);

  if (!open) return null;

  const info = coachModeInfo(coachMode);
  const expression: EmberExpression = thinking
    ? "thinking"
    : hearing
      ? "attentive"
      : speaking
        ? "happy"
        : phase === "error"
          ? "concerned"
          : info.signatureExpression;

  const statusLine =
    statusMessage ??
    (phase === "connecting"
      ? "Warming up Knot's voice…"
      : speaking
        ? "Knot is talking — jump in any time"
        : hearing
          ? "Listening…"
          : micMuted
            ? "Mic muted"
            : "Just talk — Knot's listening");

  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-background">
      <div className="flex items-center justify-between px-5 pt-[max(1rem,env(safe-area-inset-top))]">
        <span className="flex items-center gap-1.5 rounded-full border border-border/60 bg-card px-3 py-1.5">
          <span
            className={cn(
              "h-1.5 w-1.5 rounded-full",
              phase === "live"
                ? "animate-pulse bg-emerald-400"
                : phase === "connecting"
                  ? "animate-pulse bg-amber-400"
                  : "bg-muted-foreground/40",
            )}
          />
          <span className="text-[10px] font-black uppercase tracking-[0.14em] text-muted-foreground">
            {phase === "live"
              ? "Live voice"
              : phase === "connecting"
                ? "Connecting…"
                : "Voice offline"}
          </span>
        </span>
        <button
          type="button"
          aria-label="Close voice mode"
          onClick={() => {
            endSession();
            onClose();
          }}
          className="flex h-10 w-10 items-center justify-center rounded-full bg-card"
        >
          <X className="h-4.5 w-4.5" strokeWidth={2.6} />
        </button>
      </div>

      <div className="flex flex-col items-center gap-4 px-6 pt-6">
        <div className="relative">
          {(thinking || phase === "connecting") && (
            <span className="ember-rgb-halo" aria-hidden />
          )}
          {(hearing || speaking) && (
            <span
              className="absolute inset-0 animate-ping rounded-full bg-foreground/10"
              aria-hidden
            />
          )}
          <EmberMascot
            size={132}
            isActive={hearing || speaking}
            expression={expression}
            coachMode={coachMode}
            palette={{ accent: "#F6F8FB", softAccent: "#FFFFFF", deepAccent: "#EDF1F6" }}
            cyclesExpressions={false}
          />
        </div>
        <p className="text-center text-sm font-semibold">
          {thinking ? (
            <span className="ember-rgb-text">Knot is thinking…</span>
          ) : (
            statusLine
          )}
        </p>
        {userLine && (
          <p className="line-clamp-2 max-w-sm text-center text-[13px] italic text-muted-foreground">
            “{userLine}”
          </p>
        )}
      </div>

      <div className="mt-4 min-h-0 flex-1 overflow-y-auto px-5 pb-4">
        <div className="mx-auto flex w-full max-w-md flex-col gap-3">
          {replyText && (
            <div
              className={cn(
                "ember-glow-shell",
                !(thinking || speaking) && "ember-glow-quiet",
              )}
              style={{
                animation: "ember-pop-in 320ms cubic-bezier(0.34, 1.45, 0.64, 1) both",
              }}
            >
              <div className="rounded-[26px] border border-border/60 bg-card/95 px-4 py-3 backdrop-blur-xl">
                <p className="text-[13.5px] leading-relaxed">{replyText}</p>
              </div>
            </div>
          )}
        </div>
      </div>

      <div className="flex items-center justify-center gap-4 pb-[max(2rem,env(safe-area-inset-bottom))] pt-2">
        {phase === "error" ? (
          <button
            type="button"
            onClick={() => {
              endSession();
              onClose();
            }}
            className="w-full max-w-xs rounded-2xl bg-foreground py-4 text-base font-bold text-background"
          >
            Back to typing
          </button>
        ) : (
          <>
            <button
              type="button"
              onClick={() => {
                const next = !micMuted;
                setMicMuted(next);
                sessionRef.current?.setMicEnabled(!next);
              }}
              disabled={phase !== "live"}
              aria-label={micMuted ? "Unmute microphone" : "Mute microphone"}
              className={cn(
                "flex h-16 w-16 items-center justify-center rounded-full border-2 transition-colors disabled:opacity-50",
                micMuted
                  ? "border-foreground bg-foreground text-background"
                  : "border-foreground/60 bg-card text-foreground",
              )}
            >
              {micMuted ? <MicOff className="h-6 w-6" /> : <Mic className="h-6 w-6" />}
            </button>
            <button
              type="button"
              onClick={() => {
                endSession();
                onClose();
              }}
              className="flex h-16 items-center gap-2 rounded-full bg-foreground px-8 text-base font-bold text-background transition-transform active:scale-95"
            >
              <X className="h-5 w-5" />
              End
            </button>
          </>
        )}
      </div>
    </div>
  );
}

export const EmberVoiceOverlay = memo(EmberVoiceOverlayBase);
