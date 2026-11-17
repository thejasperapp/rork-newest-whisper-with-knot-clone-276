import { createContext, useCallback, useContext, useMemo, useRef, useState } from "react";

import type { RecorderUpdate } from "@/lib/meetingRecorder";

export type MeetingSaveStatus = { ownerId: string; meetingId: string; routeId?: string; update: RecorderUpdate; inCall: boolean };

export interface ActiveMeeting {
  id: string;
  /** For 1:1 DM calls — the other side's username (drives the ringing UI). */
  callWith: string | null;
  /** Voice-only vs video for 1:1 calls — audio skips camera acquisition. */
  callMode: "audio" | "video" | null;
}

interface MeetingHostValue {
  active: ActiveMeeting | null;
  recordingStatus: MeetingSaveStatus | null;
  setRecordingStatus: (status: MeetingSaveStatus | null, routeId?: string) => void;
  /** True while the live room is shrunk to the draggable corner tile. */
  minimized: boolean;
  /** Local camera stream registered by the room for the tile preview. */
  previewStream: MediaStream | null;
  open: (id: string, callWith?: string | null, callMode?: "audio" | "video" | null) => boolean;
  close: () => boolean;
  minimize: () => void;
  restore: () => void;
  setPreviewStream: (stream: MediaStream | null) => void;
}

const MeetingHostContext = createContext<MeetingHostValue | null>(null);

/**
 * Global meeting window state. The actual room is rendered ONCE by
 * `MeetingHostSurface` outside the router's routes, so navigating around
 * the app never unmounts a live call — parity with the iOS floating
 * meeting window. `/meet/:id` becomes a thin binder that just points the
 * host at a room.
 */
export function MeetingHostProvider({ children }: { children: React.ReactNode }) {
  const [recordingStatus, updateRecordingStatus] = useState<MeetingSaveStatus | null>(null);
  const saveRef = useRef<MeetingSaveStatus | null>(null);
  const activeRef = useRef<ActiveMeeting | null>(null);
  const setRecordingStatus = useCallback((status: MeetingSaveStatus | null, routeId?: string) => {
    if (routeId && routeId !== activeRef.current?.id) return;
    if (status && (status.routeId ?? status.meetingId) !== activeRef.current?.id) return;
    saveRef.current = status; updateRecordingStatus(status);
  }, []);
  const [active, setActive] = useState<ActiveMeeting | null>(null);
  const [minimized, setMinimized] = useState<boolean>(false);
  const [previewStream, setPreviewStreamState] = useState<MediaStream | null>(null);

  const open = useCallback(
    (
      id: string,
      callWith: string | null = null,
      callMode: "audio" | "video" | null = null,
    ) => {
      if (activeRef.current?.id === id) { setMinimized(false); return true; }
      const state = saveRef.current?.update.state;
      if (state === "recording" || state === "starting" || state === "saving") { setMinimized(false); return false; }
      setRecordingStatus(null);
      activeRef.current = { id, callWith, callMode };
      setActive(activeRef.current);
      setMinimized(false);
      return true;
    },
    [setRecordingStatus],
  );

  const close = useCallback(() => {
    const state = saveRef.current?.update.state;
    if (state === "recording" || state === "starting" || state === "saving") return false;
    setRecordingStatus(null);
    activeRef.current = null;
    setActive(null);
    setMinimized(false);
    setPreviewStreamState(null);
    return true;
  }, [setRecordingStatus]);

  const minimize = useCallback(() => setMinimized(true), []);
  const restore = useCallback(() => setMinimized(false), []);
  const setPreviewStream = useCallback(
    (stream: MediaStream | null) => setPreviewStreamState(stream),
    [],
  );

  const value = useMemo<MeetingHostValue>(
    () => ({ active, recordingStatus, setRecordingStatus, minimized, previewStream, open, close, minimize, restore, setPreviewStream }),
    [active, recordingStatus, setRecordingStatus, minimized, previewStream, open, close, minimize, restore, setPreviewStream],
  );

  return <MeetingHostContext.Provider value={value}>{children}</MeetingHostContext.Provider>;
}

export function useMeetingHost(): MeetingHostValue {
  const ctx = useContext(MeetingHostContext);
  if (!ctx) throw new Error("useMeetingHost must be used within MeetingHostProvider");
  return ctx;
}
