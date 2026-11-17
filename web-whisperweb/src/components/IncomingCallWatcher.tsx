import { useEffect, useRef, useState } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { PhoneCall, PhoneOff, Video } from "lucide-react";

import { Avatar } from "@/components/Avatar";
import { useAuth } from "@/hooks/useAuth";
import { decodeCallInvite, type CallInvitePayload } from "@/lib/meetings";
import { supabase } from "@/lib/supabase";
import { setHumanCallIncoming } from '@/lib/knotWelcome';

/** How long a ring stays answerable after it was placed. */
const RING_WINDOW_MS = 45_000;

/**
 * Global incoming-call overlay. The DM video button sends a
 * `::whisper-call-v1::` payload; this watcher listens for those message
 * inserts in realtime and — when a fresh ring addressed to the signed-in
 * user lands — takes over the screen with answer/decline, pulsing rings,
 * vibration, and a soft generated ringtone (no audio assets required).
 */
export function IncomingCallWatcher() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [call, setCall] = useState<CallInvitePayload | null>(null);
  const [callerAvatar, setCallerAvatar] = useState<string | null>(null);
  const dismissTimerRef = useRef<number | null>(null);

  // Realtime: watch for fresh call invites addressed to me.
  useEffect(() => {
    if (!user) return;
    const channel = supabase
      .channel(`whisper-call-ring-${user.id}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "whisper_messages",
          filter: `to_user_id=eq.${user.id}`,
        },
        (payload) => {
          const row = payload.new as { body?: string | null };
          const invite = decodeCallInvite(row.body);
          if (!invite || invite.fromUserId === user.id) return;
          if (invite.at > 0 && Date.now() - invite.at > RING_WINDOW_MS) return;
          // Already in that room — don't ring over the call itself.
          if (window.location.pathname.includes(`/meet/${invite.meetingId}`)) return;
          setCall(invite);
        }
      )
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [user]);

  // Human rings take priority over an optional AI welcome, before Answer.
  useEffect(() => { setHumanCallIncoming(call !== null); return () => setHumanCallIncoming(false); }, [call]);

  // Caller avatar lookup (best effort).
  useEffect(() => {
    if (!call) {
      setCallerAvatar(null);
      return;
    }
    let cancelled = false;
    void supabase
      .from("whisper_profiles")
      .select("profile_image_url")
      .eq("user_id", call.fromUserId)
      .maybeSingle()
      .then(({ data }) => {
        if (cancelled) return;
        setCallerAvatar(
          (data as { profile_image_url?: string | null } | null)?.profile_image_url ?? null
        );
      });
    return () => {
      cancelled = true;
    };
  }, [call]);

  // Ring loop: vibration + a soft two-tone chirp, auto-dismissed at 40s.
  useEffect(() => {
    if (!call) return;
    let ctx: AudioContext | null = null;
    const chirp = (): void => {
      try {
        ctx = ctx ?? new AudioContext();
        const play = (freq: number, at: number): void => {
          if (!ctx) return;
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.type = "sine";
          osc.frequency.value = freq;
          gain.gain.setValueAtTime(0, ctx.currentTime + at);
          gain.gain.linearRampToValueAtTime(0.08, ctx.currentTime + at + 0.03);
          gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + at + 0.5);
          osc.connect(gain).connect(ctx.destination);
          osc.start(ctx.currentTime + at);
          osc.stop(ctx.currentTime + at + 0.55);
        };
        play(880, 0);
        play(660, 0.28);
      } catch {
        /* autoplay blocked — the visual ring still shows */
      }
      try {
        navigator.vibrate?.([260, 140, 260]);
      } catch {
        /* unsupported */
      }
    };
    chirp();
    const timer = window.setInterval(chirp, 2200);
    dismissTimerRef.current = window.setTimeout(() => setCall(null), 40_000);
    return () => {
      window.clearInterval(timer);
      if (dismissTimerRef.current != null) window.clearTimeout(dismissTimerRef.current);
      try {
        void ctx?.close();
      } catch {
        /* already closed */
      }
    };
  }, [call]);

  // Landing inside the room dismisses the ring.
  useEffect(() => {
    if (call && location.pathname.includes(`/meet/${call.meetingId}`)) setCall(null);
  }, [location.pathname, call]);

  // ── Browser notifications ── prime permission on the first tap after
  // sign-in, then surface a system notification for rings that land while
  // the tab is hidden or unfocused — clicking it brings Whisper up to answer.
  useEffect(() => {
    if (!user || typeof Notification === "undefined") return;
    if (Notification.permission !== "default") return;
    const prime = (): void => {
      void Notification.requestPermission().catch(() => undefined);
    };
    window.addEventListener("pointerdown", prime, { once: true });
    return () => window.removeEventListener("pointerdown", prime);
  }, [user]);

  useEffect(() => {
    if (!call || typeof Notification === "undefined") return;
    if (Notification.permission !== "granted") return;
    if (!document.hidden && document.hasFocus()) return;
    let notification: Notification | null = null;
    try {
      notification = new Notification(
        call.mode === "audio" ? "Incoming voice call" : "Incoming video call",
        {
          body: `@${call.fromUsername} is calling you on Whisper`,
          tag: `whisper-call-${call.meetingId}`,
          icon: "/icon.png",
        }
      );
      notification.onclick = () => {
        window.focus();
        const target = `/meet/${call.meetingId}?call=${encodeURIComponent(call.fromUsername)}${call.mode === "audio" ? "&mode=audio" : ""}`;
        setCall(null);
        navigate(target);
        notification?.close();
      };
    } catch {
      /* Notification constructor can throw on some mobile browsers */
    }
    return () => notification?.close();
  }, [call, navigate]);

  if (!call) return null;

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/78 px-6 backdrop-blur-md">
      <div
        className="flex w-full max-w-xs flex-col items-center gap-5 rounded-[32px] border border-white/12 bg-zinc-950/95 px-7 py-9 text-center shadow-[0_30px_90px_rgba(0,0,0,0.7)]"
        style={{ animation: "ember-pop-in 360ms cubic-bezier(0.34, 1.45, 0.64, 1) both" }}
      >
        <div className="relative flex h-28 w-28 items-center justify-center">
          <span className="call-ring" aria-hidden />
          <span className="call-ring" style={{ animationDelay: "0.6s" }} aria-hidden />
          <span className="call-ring" style={{ animationDelay: "1.2s" }} aria-hidden />
          <Avatar
            url={callerAvatar}
            name={call.fromUsername}
            size={88}
            className="relative ring-4 ring-zinc-950"
          />
        </div>
        <div>
          <p className="text-[19px] font-extrabold text-white">@{call.fromUsername}</p>
          <p className="mt-1 flex items-center justify-center gap-1.5 text-[13px] font-medium text-emerald-300">
            {call.mode === "audio" ? (
              <PhoneCall className="h-3.5 w-3.5" />
            ) : (
              <Video className="h-3.5 w-3.5" />
            )}
            {call.mode === "audio" ? "Incoming voice call…" : "Incoming video call…"}
          </p>
        </div>
        <div className="flex w-full items-center justify-center gap-4">
          <button
            type="button"
            onClick={() => setCall(null)}
            className="flex h-16 w-16 shrink-0 items-center justify-center rounded-full bg-red-500 text-white shadow-lg transition-transform hover:bg-red-400 active:scale-95"
            aria-label="Decline call"
          >
            <PhoneOff className="h-6 w-6" />
          </button>
          <button
            type="button"
            onClick={() => {
              const target = `/meet/${call.meetingId}?call=${encodeURIComponent(call.fromUsername)}${call.mode === "audio" ? "&mode=audio" : ""}`;
              setCall(null);
              navigate(target);
            }}
            className="flex h-16 flex-1 items-center justify-center gap-2 rounded-full bg-emerald-500 text-[15px] font-bold text-white shadow-lg transition-transform hover:bg-emerald-400 active:scale-95"
            aria-label="Answer call"
          >
            <PhoneCall className="h-5 w-5" />
            Answer
          </button>
        </div>
      </div>
    </div>
  );
}
