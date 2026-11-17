import { useSyncExternalStore } from "react";

/** Stage layouts — Google Meet's "Adjust view" set. */
export type MeetLayout = "auto" | "tiled" | "spotlight" | "sidebar";

/** Max-tile stops for the tiles slider (Meet's slider has the same stops). */
export const MEET_MAX_TILE_STOPS: readonly number[] = [6, 9, 16, 25, 49];

export interface MeetPrefs {
  /** Preferred microphone deviceId ("" = system default). */
  micId: string;
  /** Preferred camera deviceId ("" = system default). */
  camId: string;
  /** Preferred speaker deviceId ("" = system default). */
  speakerId: string;
  /** Join meetings with the mic on. */
  joinMic: boolean;
  /** Join meetings with the camera on. */
  joinCam: boolean;
  /** Show captions when a meeting starts. */
  captions: boolean;
  layout: MeetLayout;
  maxTiles: number;
  /** Hide participants whose camera is off from the stage grid. */
  hideNoVideo: boolean;
  /** Play the join / leave / meeting-ended chimes. */
  sounds: boolean;
}

const KEY = "whisper.meet.prefs.v1";

const DEFAULTS: MeetPrefs = {
  micId: "",
  camId: "",
  speakerId: "",
  joinMic: true,
  joinCam: true,
  captions: true,
  layout: "auto",
  maxTiles: 16,
  hideNoVideo: false,
  sounds: true,
};

let cache: MeetPrefs | null = null;
const listeners = new Set<() => void>();

function sanitize(raw: unknown): MeetPrefs {
  const r = (raw ?? {}) as Partial<Record<keyof MeetPrefs, unknown>>;
  const layout: MeetLayout =
    r.layout === "tiled" || r.layout === "spotlight" || r.layout === "sidebar"
      ? r.layout
      : "auto";
  const maxTiles =
    typeof r.maxTiles === "number" && MEET_MAX_TILE_STOPS.includes(r.maxTiles)
      ? r.maxTiles
      : DEFAULTS.maxTiles;
  return {
    micId: typeof r.micId === "string" ? r.micId : "",
    camId: typeof r.camId === "string" ? r.camId : "",
    speakerId: typeof r.speakerId === "string" ? r.speakerId : "",
    joinMic: typeof r.joinMic === "boolean" ? r.joinMic : DEFAULTS.joinMic,
    joinCam: typeof r.joinCam === "boolean" ? r.joinCam : DEFAULTS.joinCam,
    captions: typeof r.captions === "boolean" ? r.captions : DEFAULTS.captions,
    layout,
    maxTiles,
    hideNoVideo:
      typeof r.hideNoVideo === "boolean" ? r.hideNoVideo : DEFAULTS.hideNoVideo,
    sounds: typeof r.sounds === "boolean" ? r.sounds : DEFAULTS.sounds,
  };
}

/** Read the saved meeting preferences (cached after the first read). */
export function readMeetPrefs(): MeetPrefs {
  if (cache) return cache;
  try {
    const raw =
      typeof window !== "undefined" ? window.localStorage.getItem(KEY) : null;
    cache = raw ? sanitize(JSON.parse(raw)) : { ...DEFAULTS };
  } catch {
    cache = { ...DEFAULTS };
  }
  return cache;
}

/** Merge a patch into the saved preferences and notify subscribers. */
export function writeMeetPrefs(patch: Partial<MeetPrefs>): MeetPrefs {
  const next = sanitize({ ...readMeetPrefs(), ...patch });
  cache = next;
  try {
    window.localStorage.setItem(KEY, JSON.stringify(next));
  } catch {
    // Private mode / quota — the in-memory copy still drives this session.
  }
  listeners.forEach((fn) => fn());
  return next;
}

function subscribe(fn: () => void): () => void {
  listeners.add(fn);
  return () => {
    listeners.delete(fn);
  };
}

/** React hook — the live preferences plus a setter. */
export function useMeetPrefs(): [MeetPrefs, (patch: Partial<MeetPrefs>) => void] {
  const prefs = useSyncExternalStore(subscribe, readMeetPrefs, readMeetPrefs);
  return [prefs, writeMeetPrefs];
}

/**
 * Audio constraints honoring the preferred microphone. `ideal` never fails
 * acquisition — an unplugged device simply falls back to the default.
 */
export function preferredAudioConstraints(): MediaTrackConstraints | true {
  const { micId } = readMeetPrefs();
  // The voice processing is asked for EXPLICITLY — "true" left it to each
  // browser's defaults, and a desktop mic without automatic gain control
  // picks a quiet speaker up at a whisper (the "voices aren't getting picked
  // up" complaint). Mirrors the iOS voice-processing audio unit.
  const processing: MediaTrackConstraints = {
    echoCancellation: true,
    noiseSuppression: true,
    autoGainControl: true,
    channelCount: { ideal: 1 },
  };
  return micId ? { ...processing, deviceId: { ideal: micId } } : processing;
}

/** Video constraints honoring the preferred camera on top of a base set. */
export function preferredVideoConstraints(
  base: MediaTrackConstraints | true
): MediaTrackConstraints | true {
  const { camId } = readMeetPrefs();
  if (!camId) return base;
  const baseObj: MediaTrackConstraints = base === true ? {} : base;
  return { ...baseObj, deviceId: { ideal: camId } };
}
