import { useEffect, useRef, useState } from "react";
import { useLocation, useNavigate, useParams, useSearchParams } from "react-router-dom";
import { Maximize2, PhoneCall } from "lucide-react";

import MeetingRoom from "@/pages/MeetingRoom";
import { useMeetingHost } from "@/hooks/useMeetingHost";
import { MeetingSaveBanner } from "./MeetingSaveBanner";
import { useAuth } from "@/hooks/useAuth";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/lib/supabase";
import { parseMeetingInvitation } from "@/lib/meetingInvitation";

/**
 * Route binder for `/meet/:id` — the room itself is mounted globally by
 * `MeetingHostSurface`, so this component only tells the host which meeting
 * is active (and passes the `?call=` param for 1:1 DM calls).
 */
export function MeetRouteBinder({ openExternal = (url: string) => window.location.replace(url) }: { openExternal?: (url: string) => void } = {}) {
  const { id } = useParams<{ id: string }>();
  const [searchParams] = useSearchParams();
  const host = useMeetingHost();
  const navigate = useNavigate();
  const call = searchParams.get("call");
  const mode = searchParams.get("mode") === "audio" ? ("audio" as const) : null;
  const { user, loading: authLoading } = useAuth();
  const invitation = parseMeetingInvitation(`https://www.mydailywhisper.com/meet/${id ?? ""}?${searchParams}`);
  let knownDate = false;
  try { knownDate = sessionStorage.getItem(`whisper-speed-date:${id}`) === "1"; } catch { /* unavailable */ }
  const legacyOrdinary = ["www.mydailywhisper.com", "mydailywhisper.com"].includes(window.location.hostname)
    && !!invitation && !invitation.social && !knownDate && host.active?.id !== id;
  const needsMetadata = legacyOrdinary && !!user && !!id && !/^wsp-/i.test(id);
  const metadata = useQuery({
    queryKey: ["invitation-room-kind", user?.id, id],
    enabled: needsMetadata,
    retry: false,
    queryFn: async ({ signal }) => {
      // Read only: fetching the normal room registers a participant.
      const { data, error } = await supabase.from("whisper_meetings").select("title,summary").eq("id", id!).limit(1).abortSignal(signal);
      if (error) throw error;
      const row = data?.[0] as { title?: string; summary?: string } | undefined;
      return !!row && (/^(?:Audio|Video) call with @|^Group call · |^Blind date$|^Second date/.test(row.title ?? "") || row.summary?.startsWith("::whisper-group-call-v1::") === true);
    },
  });

  useEffect(() => {
    if (legacyOrdinary && invitation) {
      if (authLoading) return;
      if (needsMetadata && !metadata.isSuccess) return;
      if (!metadata.data) {
        if (host.recordingStatus && ["recording", "starting", "saving"].includes(host.recordingStatus.update.state)) {
          toast("Finish and save your recording before opening Whisper Meet.");
          return;
        }
        openExternal(invitation.href);
        return;
      }
    }
    if (id && !host.open(id, call, call ? (mode ?? "video") : null) && host.active) {
      const prior = host.active;
      navigate(`/meet/${prior.id}${prior.callWith ? `?call=${encodeURIComponent(prior.callWith)}&mode=${prior.callMode ?? "video"}` : ""}`, { replace: true });
      toast("Finish and save your current recording before opening a different meeting.");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, call, mode, legacyOrdinary, authLoading, needsMetadata, metadata.isSuccess, metadata.data, invitation?.href, host.recordingStatus?.update.state]);

  if (legacyOrdinary && needsMetadata && metadata.isError) {
    return <div className="p-6 text-center"><p>Couldn't check this invitation.</p><button type="button" className="mt-3 min-h-11 underline" onClick={() => void metadata.refetch()}>Try again</button></div>;
  }
  return null;
}

/**
 * Renders the active meeting as a floating window above the app. While
 * minimized the room stays mounted (WebRTC, transcription and audio keep
 * running) but turns invisible, and a draggable corner tile with the local
 * camera preview takes its place — tap the tile to jump back in.
 */
export function MeetingHostSurface() {
  const host = useMeetingHost();
  const { user } = useAuth();
  const location = useLocation();
  const navigate = useNavigate();

  // Route sync: leaving /meet/:id (back button, tapping a link) minimizes
  // the live room instead of killing it; landing back on it restores.
  useEffect(() => {
    if (!host.active) return;
    const onRoomRoute = location.pathname === `/meet/${host.active.id}`;
    const busy = host.recordingStatus && ["starting", "recording", "saving"].includes(host.recordingStatus.update.state);
    if (!onRoomRoute && !host.minimized && !(busy && location.pathname.startsWith("/meet/"))) host.minimize();
    if (onRoomRoute && host.minimized) host.restore();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [location.pathname, host.active?.id]);

  if (!host.active) return null;

  const restoreTarget = `/meet/${host.active.id}${
    host.active.callWith
      ? `?call=${encodeURIComponent(host.active.callWith)}${
          host.active.callMode === "audio" ? "&mode=audio" : ""
        }`
      : ""
  }`;

  return (
    <>
      <div
        className={cn(
          "fixed inset-0 z-[60] overflow-y-auto bg-background",
          host.minimized && "invisible",
        )}
        aria-hidden={host.minimized}
      >
        <MeetingRoom
          key={host.active.id}
          meetingId={host.active.id}
          callWith={host.active.callWith}
          callMode={host.active.callMode}
        />
      </div>
      {host.recordingStatus && host.recordingStatus.ownerId === user?.id && (!host.recordingStatus.inCall || host.minimized) && host.recordingStatus.update.state !== "recording" && <MeetingSaveBanner status={host.recordingStatus} onOpen={() => {
        const saved = host.recordingStatus;
        if (!saved || saved.update.state === "saving" || saved.update.state === "starting") return;
        if (saved.inCall) host.minimize(); else if (!host.close()) return;
        navigate(`/notebook?portal=workspace&meeting=${encodeURIComponent(saved.meetingId)}&recording=${encodeURIComponent(saved.update.recordingId)}`);
      }} />}
      {host.minimized && (
        <MeetingMiniTile
          stream={host.previewStream}
          onRestore={() => {
            navigate(restoreTarget);
            host.restore();
          }}
        />
      )}
    </>
  );
}

/** Draggable, side-clamped corner tile shown while the meeting is minimized. */
function MeetingMiniTile({
  stream,
  onRestore,
}: {
  stream: MediaStream | null;
  onRestore: () => void;
}) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const tileRef = useRef<HTMLDivElement | null>(null);
  const [offset, setOffset] = useState<{ x: number; y: number }>({ x: 0, y: 0 });
  const dragRef = useRef<{
    pointerId: number;
    startX: number;
    startY: number;
    baseX: number;
    baseY: number;
    moved: boolean;
  } | null>(null);

  useEffect(() => {
    const el = videoRef.current;
    if (!el) return;
    if (stream) {
      if (el.srcObject !== stream) el.srcObject = stream;
      void el.play().catch(() => undefined);
    } else {
      el.srcObject = null;
    }
  }, [stream]);

  const onPointerDown = (event: React.PointerEvent<HTMLDivElement>): void => {
    dragRef.current = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      baseX: offset.x,
      baseY: offset.y,
      moved: false,
    };
    tileRef.current?.setPointerCapture(event.pointerId);
  };

  const onPointerMove = (event: React.PointerEvent<HTMLDivElement>): void => {
    const drag = dragRef.current;
    if (!drag || drag.pointerId !== event.pointerId) return;
    const dx = event.clientX - drag.startX;
    const dy = event.clientY - drag.startY;
    if (Math.abs(dx) > 6 || Math.abs(dy) > 6) drag.moved = true;
    const width = tileRef.current?.offsetWidth ?? 124;
    const height = tileRef.current?.offsetHeight ?? 166;
    // Anchored bottom-right — offsets move it left/up, clamped on-screen.
    const minX = -(window.innerWidth - width - 16);
    const minY = -(window.innerHeight - height - 112);
    setOffset({
      x: Math.min(0, Math.max(minX, drag.baseX + dx)),
      y: Math.min(0, Math.max(minY, drag.baseY + dy)),
    });
  };

  const onPointerUp = (event: React.PointerEvent<HTMLDivElement>): void => {
    const drag = dragRef.current;
    if (!drag || drag.pointerId !== event.pointerId) return;
    dragRef.current = null;
    if (!drag.moved) onRestore();
  };

  return (
    <div
      ref={tileRef}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      className="fixed bottom-24 right-4 z-[90] w-[124px] cursor-pointer touch-none select-none overflow-hidden rounded-2xl border border-white/15 bg-zinc-950 shadow-[0_18px_54px_rgba(0,0,0,0.5)]"
      style={{ transform: `translate(${offset.x}px, ${offset.y}px)`, aspectRatio: "3 / 4" }}
      role="button"
      aria-label="Return to call"
      title="Return to call"
    >
      {stream ? (
        <video
          ref={videoRef}
          autoPlay
          playsInline
          muted
          className="h-full w-full object-cover [transform:scaleX(-1)]"
        />
      ) : (
        <div className="flex h-full w-full flex-col items-center justify-center gap-2 text-white/70">
          <PhoneCall className="h-5 w-5" />
          <span className="text-[10px] font-bold">In call</span>
        </div>
      )}
      <div className="pointer-events-none absolute inset-x-0 bottom-0 flex items-center justify-between bg-gradient-to-t from-black/75 to-transparent px-2 pb-1.5 pt-4">
        <span className="flex items-center gap-1 text-[9px] font-black uppercase tracking-wide text-white">
          <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-400" />
          Live
        </span>
        <Maximize2 className="h-3 w-3 text-white/75" />
      </div>
    </div>
  );
}
