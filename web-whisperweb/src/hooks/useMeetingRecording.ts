import { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "@/lib/supabase";
import { MeetingRecordingSession, type RecordingSessionState } from "@/lib/meetingRecordingSession";
import type { WhisperLiveRTC } from "@/lib/whisperLiveRTC";

/** Owns the recording session independently of room re-renders and invalidates account changes immediately. */
export function useMeetingRecording(ownerId: string, meetingId: string | null, title: string, hostId: string | null, rtcRef: { current: WhisperLiveRTC | null }, enabled: boolean, onLifecycle?: (state: RecordingSessionState) => void): { session: MeetingRecordingSession; state: RecordingSessionState } {
  const latest = useRef({ title, hostId, enabled, ownerId, onLifecycle }); latest.current = { title, hostId, enabled, ownerId, onLifecycle };
  const [value, setValue] = useState<{ session: MeetingRecordingSession; state: RecordingSessionState } | null>(null);
  const session = useMemo(() => {
    const created = new MeetingRecordingSession(ownerId, meetingId, () => rtcRef.current, () => latest.current.hostId, () => latest.current.title, (state) => setValue({ session: created, state }), (state) => { if (latest.current.ownerId === ownerId) latest.current.onLifecycle?.(state); });
    return created;
  }, [ownerId, meetingId, rtcRef]);
  useEffect(() => {
    session.activate();
    const subscription = supabase.auth.onAuthStateChange((_event, auth) => { if (ownerId && auth?.user.id !== ownerId) session.dispose(); });
    const hidden = (): void => { if (document.hidden && session.state.request) void session.stop(false, "Recording stopped because this tab became hidden. Keep it visible when recording."); };
    const unload = (event: BeforeUnloadEvent): void => { if (session.state.request || session.state.update?.state === "saving" || session.state.update?.transcriptionPending) { event.preventDefault(); event.returnValue = ""; } };
    const pagehide = (): void => session.dispose();
    const pageshow = (event: PageTransitionEvent): void => { if (event.persisted) { session.activate(); session.setEnabled(latest.current.enabled); } };
    document.addEventListener("visibilitychange", hidden); window.addEventListener("beforeunload", unload); window.addEventListener("pagehide", pagehide); window.addEventListener("pageshow", pageshow);
    return () => { session.dispose(latest.current.ownerId !== ownerId); void session.whenSettled().finally(() => subscription.data.subscription.unsubscribe()); document.removeEventListener("visibilitychange", hidden); window.removeEventListener("beforeunload", unload); window.removeEventListener("pagehide", pagehide); window.removeEventListener("pageshow", pageshow); };
  }, [session, ownerId]);
  useEffect(() => { session.setEnabled(enabled); }, [session, enabled]);
  return { session, state: value?.session === session ? value.state : session.state };
}
