/**
 * WhisperLiveRTC — mesh WebRTC for live audio/video rooms.
 *
 * No external API (no LiveKit). Signaling runs over Supabase Realtime
 * broadcast channels. ICE servers (STUN/TURN) come from the Rork toolkit.
 * Media flows peer-to-peer via RTCPeerConnection.
 *
 * Topology: selective mesh.
 *  - Speakers connect to all other peers and publish audio + video.
 *  - Listeners connect only to speakers and receive media.
 *  - When a listener is promoted to speaker, new connections are created
 *    and existing ones are renegotiated to carry the new media tracks.
 */

import { supabase } from "@/lib/supabase";
import type { RealtimeChannel } from "@supabase/supabase-js";
import { videoFx } from "@/lib/videoEffects";
import { backendFetch } from "@/lib/billing";
import {
  preferredAudioConstraints,
  preferredVideoConstraints,
} from "@/lib/meetPrefs";

// ─── ICE servers ──────────────────────────────────────────────────────────────

interface IceServersResponse {
  iceServers: RTCIceServer[];
  ttlSeconds: number;
}

interface IceFetchResult {
  servers: RTCIceServer[];
  /** How long these credentials can be trusted before a refresh. */
  ttlMs: number;
  /** True when this is the STUN-only fallback (toolkit unreachable). */
  degraded: boolean;
}

/** Minimal Network Information API surface (not yet in the TS dom lib). */
interface NetworkInformationLike {
  type?: string;
  effectiveType?: string;
  addEventListener?: (type: "change", listener: () => void) => void;
  removeEventListener?: (type: "change", listener: () => void) => void;
}

const STUN_FALLBACK: RTCIceServer[] = [{ urls: ["stun:stun.cloudflare.com:3478"] }];
/** Short fallback ttl so the health sweep quickly retries the toolkit and
 *  upgrades the meeting back to full TURN instead of staying relay-less. */
const STUN_FALLBACK_TTL_MS = 45_000;

async function fetchIceServers(): Promise<IceFetchResult> {
  // Vite exposes both VITE_* and EXPO_PUBLIC_* prefixes (see vite.config.ts).
  const toolkitUrl =
    (import.meta.env.VITE_TOOLKIT_URL as string | undefined) ||
    (import.meta.env.EXPO_PUBLIC_TOOLKIT_URL as string | undefined) ||
    "https://toolkit.rork.com";
  const secretKey =
    (import.meta.env.VITE_RORK_TOOLKIT_SECRET_KEY as string | undefined) ||
    (import.meta.env.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY as string | undefined);
  const url = toolkitUrl.replace(/\/+$/, "");

  // 1. Try the Rork toolkit (best path — includes TURN for NAT traversal).
  //    TURN is what makes calls work across symmetric NATs / strict firewalls,
  //    so a hard timeout + one retry keeps a transient hiccup from silently
  //    downgrading the whole meeting to STUN-only.
  if (secretKey && url && /^https?:\/\//.test(url)) {
    for (let attempt = 1; attempt <= 2; attempt++) {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 8000);
      try {
        const res = await fetch(`${url}/v2/webrtc/ice-servers`, {
          headers: { Authorization: `Bearer ${secretKey}` },
          signal: ctrl.signal,
        });
        if (res.ok) {
          const data = (await res.json()) as IceServersResponse;
          if (data.iceServers?.length > 0) {
            const ttlSeconds =
              typeof data.ttlSeconds === "number" && data.ttlSeconds > 0
                ? data.ttlSeconds
                : 300;
            return {
              servers: data.iceServers,
              // Clamp to sane bounds — refresh scheduling works off this.
              ttlMs: Math.min(Math.max(ttlSeconds * 1000, 60_000), 30 * 60_000),
              degraded: false,
            };
          }
        }
        console.warn(
          `[WhisperLiveRTC] Toolkit ICE fetch attempt ${attempt} returned ${res.status}`,
        );
        // A rejected key (rotated / missing) can't succeed on retry — go
        // straight to the backend proxy instead of burning 600 ms.
        if (res.status === 401 || res.status === 403) break;
      } catch (err) {
        console.warn(`[WhisperLiveRTC] Toolkit ICE fetch attempt ${attempt} failed:`, err);
      } finally {
        clearTimeout(timer);
      }
      if (attempt === 1) await new Promise((resolve) => setTimeout(resolve, 600));
    }
  } else {
    console.warn("[WhisperLiveRTC] Toolkit secret not configured — using STUN-only fallback");
  }

  // 2. Backend proxy — the Cloudflare backend holds the toolkit key
  //    server-side, so client bundles that shipped WITHOUT the baked key
  //    (e.g. a third-party host build) still get real TURN credentials.
  //    Without TURN, anyone behind a strict/symmetric NAT connects but
  //    sends no audio/video — the exact "others can't hear me" failure.
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 8000);
    try {
      const res = await backendFetch("/webrtc/ice-servers", { signal: ctrl.signal });
      if (res.ok) {
        const data = (await res.json()) as IceServersResponse;
        if (data.iceServers?.length > 0) {
          const ttlSeconds =
            typeof data.ttlSeconds === "number" && data.ttlSeconds > 0
              ? data.ttlSeconds
              : 300;
          console.info("[WhisperLiveRTC] ICE servers via backend proxy");
          return {
            servers: data.iceServers,
            ttlMs: Math.min(Math.max(ttlSeconds * 1000, 60_000), 30 * 60_000),
            degraded: false,
          };
        }
      } else {
        console.warn(`[WhisperLiveRTC] Backend ICE proxy returned ${res.status}`);
      }
    } finally {
      clearTimeout(timer);
    }
  } catch (err) {
    console.warn("[WhisperLiveRTC] Backend ICE proxy failed:", err);
  }

  // 3. Fallback: Cloudflare STUN (same STUN server the toolkit returns, just
  //    without TURN credentials). Basic connectivity works for most users;
  //    the SHORT ttl makes the engine retry the toolkit soon and push real
  //    TURN credentials into live connections via setConfiguration.
  return { servers: STUN_FALLBACK, ttlMs: STUN_FALLBACK_TTL_MS, degraded: true };
}

// ─── Local media acquisition ─────────────────────────────────────────────────

/** Why a device could not be opened, mapped from getUserMedia DOMExceptions. */
export type MediaBlockReason =
  | "denied"
  | "no-device"
  | "in-use"
  | "insecure"
  | "unknown";

export interface LocalMediaState {
  hasAudio: boolean;
  hasVideo: boolean;
  audioError: MediaBlockReason | null;
  videoError: MediaBlockReason | null;
}

function classifyMediaError(err: unknown): MediaBlockReason {
  const name =
    err instanceof DOMException || err instanceof Error ? err.name : "";
  switch (name) {
    case "NotAllowedError":
    case "PermissionDeniedError":
      return "denied";
    case "SecurityError":
      return "insecure";
    case "NotFoundError":
    case "DevicesNotFoundError":
    case "OverconstrainedError":
      return "no-device";
    case "NotReadableError":
    case "TrackStartError":
    case "AbortError":
      return "in-use";
    default:
      return "unknown";
  }
}

/** Human-readable, truthful description of a device block for toasts/banners. */
export function describeMediaBlock(
  reason: MediaBlockReason | null,
  device: "camera" | "microphone"
): string {
  switch (reason) {
    case "denied":
      return device === "camera"
        ? "Camera access is blocked. Allow the camera in your browser's site settings, then retry."
        : "Microphone access is blocked. Allow the mic in your browser's site settings, then retry.";
    case "insecure":
      return `This window isn't allowed to use the ${device} — open the meeting in a full browser tab.`;
    case "no-device":
      return device === "camera"
        ? "No camera was found on this device."
        : "No microphone was found on this device.";
    case "in-use":
      return `Your ${device} is busy in another app or tab. Close it there, then retry.`;
    case "unknown":
      return `Couldn't start your ${device}. Retry, or check your browser settings.`;
    default:
      return "";
  }
}

const VIDEO_CONSTRAINTS: MediaTrackConstraints = {
  width: { ideal: 1280 },
  height: { ideal: 720 },
};

/**
 * iPhone / iPad browsers (every one of them is WebKit). Mobile WebKit runs
 * ONE media capture session: a second getUserMedia while a capture is live
 * tears the first one down, and an instant re-grab right after stopping a
 * stream races the hardware teardown. The join path treats these devices
 * gently — combined requests, a breath between stop and reacquire, and no
 * automatic mic re-grabs mid-call (that's what killed the camera on phones).
 */
export function isMobileWebKit(): boolean {
  if (typeof navigator === "undefined") return false;
  const ua = navigator.userAgent;
  const touchMac = navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1;
  return /iPhone|iPad|iPod/i.test(ua) || touchMac;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ─── Safari workaround helpers ───────────────────────────────────────────────

/**
 * Create a silent audio track so Safari generates ICE candidates on
 * receive-only peer connections (WebKit bug 236357). Without a local track,
 * Safari refuses to fire ICE candidates and no media is received.
 */
function createSilentAudioTrack(): MediaStreamTrack | null {
  try {
    const audioCtx = new (window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext)();
    const oscillator = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
    gain.gain.value = 0; // Silent
    oscillator.connect(gain);
    const dest = audioCtx.createMediaStreamDestination();
    gain.connect(dest);
    oscillator.start();
    const track = dest.stream.getAudioTracks()[0];
    if (track) track.enabled = false; // Don't actually send audio
    return track ?? null;
  } catch {
    return null;
  }
}

// ─── Signaling protocol ───────────────────────────────────────────────────────

type SignalMessage =
  | { type: "join"; peerId: string; userId: string; name: string; isSpeaker: boolean }
  | {
      type: "peer-presence";
      peerId: string;
      userId: string;
      name: string;
      isSpeaker: boolean;
      targetPeerId: string;
    }
  | { type: "offer"; from: string; to: string; sdp: RTCSessionDescriptionInit }
  | { type: "answer"; from: string; to: string; sdp: RTCSessionDescriptionInit }
  | { type: "ice"; from: string; to: string; candidate: RTCIceCandidateInit }
  | { type: "leave"; peerId: string }
  | {
      type: "became-speaker";
      peerId: string;
      userId: string;
      name: string;
    }
  | { type: "track-update"; from: string; hasAudio: boolean; hasVideo: boolean }
  | { type: "mic-toggle"; from: string; isOn: boolean }
  | { type: "screen-share"; from: string; isOn: boolean }
  | { type: "reaction"; from: string; emoji: string }
  /** Connection healing — "reneg" asks the other side for a fresh offer
   *  (ICE restart); "reset" tears the pair down and rebuilds it from
   *  scratch. Older builds ignore unknown types, so both degrade safely. */
  | { type: "reneg"; from: string; to: string }
  | { type: "reset"; from: string; to: string }
  /** Free-form room-scoped app messages (e.g. "present this client to
   *  everyone"). Platforms that don't understand an event ignore it. */
  | { type: "app-event"; from: string; event: string; data: unknown };

// ─── Types ────────────────────────────────────────────────────────────────────

interface PeerEntry {
  pc: RTCPeerConnection;
  peerId: string;
  userId: string;
  name: string;
  isSpeaker: boolean;
  isOfferer: boolean;
  remoteStream: MediaStream;
  /** Remote state comes from explicit signaling; track.enabled is local-only. */
  micOn: boolean;
  hasVideo: boolean;
  /** Keep the focus frame steady between 400 ms stats samples. */
  speakingUntil: number;
  isSpeaking: boolean;
  /** Perfect-negotiation bookkeeping — one offer in flight at a time. */
  makingOffer: boolean;
  /** A renegotiation was requested while unstable — drained once stable. */
  queuedNegotiation: boolean;
  /** First negotiation completed — gates automatic renegotiation. */
  negotiationReady: boolean;
  /** Recovery-ladder position; resets to 0 whenever the pair connects. */
  attempts: number;
  /** Last time negotiation/ICE made progress — stuck-pair watchdog input. */
  lastProgressAt: number;
  /** The pair reached "connected" at least once — shortens the stall window. */
  everConnected: boolean;
  /** Built with iceTransportPolicy "relay" (TURN-only) after direct pairs failed. */
  relayOnly: boolean;
  /** Selected candidate path once connected (diagnostics + UI). */
  via: "relay" | "direct" | null;
}

interface KnownPeer {
  peerId: string;
  userId: string;
  name: string;
  isSpeaker: boolean;
}

export interface LiveParticipantInfo {
  peerId: string;
  userId: string;
  name: string;
  isSpeaker: boolean;
  hasAudio: boolean;
  hasVideo: boolean;
  micOn: boolean;
  /** True while this participant broadcasts their screen instead of camera. */
  isScreenSharing: boolean;
  /** Smoothed remote audio activity used for the speaker focus frame. */
  isSpeaking: boolean;
  /** Truthful transport state — tiles show "Connecting…"/"Reconnecting…". */
  connectionState: "connecting" | "connected" | "reconnecting";
  remoteStream: MediaStream | null;
}

// ─── Manager ──────────────────────────────────────────────────────────────────

export class WhisperLiveRTC {
  private peers = new Map<string, PeerEntry>();
  private readonly recoveringPeers = new Set<PeerEntry>();
  private hasLeft = false;
  private iceRefresh: Promise<void> | null = null;
  private assertActive(): void {
    if (this.hasLeft) throw new DOMException("Meeting connection was closed", "AbortError");
  }
  private async acquireMedia(constraints: MediaStreamConstraints): Promise<MediaStream> {
    this.assertActive();
    const stream = await navigator.mediaDevices.getUserMedia(constraints);
    if (this.hasLeft) { stream.getTracks().forEach((track) => track.stop()); this.assertActive(); }
    return stream;
  }
  private knownPeers = new Map<string, KnownPeer>();
  private retiredPeerIds = new Set<string>();
  /** ICE candidates that arrived before the PC existed or before
   *  setRemoteDescription — buffered and flushed once the PC is ready. */
  private pendingIce = new Map<string, RTCIceCandidateInit[]>();
  /** Reconnect grace timers — Chrome fires "disconnected" on brief ICE
   *  blips; we wait 8s before removing the peer (mirrors iOS). */
  private disconnectTimers = new Map<string, ReturnType<typeof setTimeout>>();
  private localStream: MediaStream | null = null;
  private channel: RealtimeChannel | null = null;
  private myPeerId: string;
  private userId: string;
  private name: string;
  private roomId = "";
  private isSpeaker = false;
  private micOn = false;
  private cameraOn = false;
  private iceServers: RTCIceServer[] = [];
  /** Silent dummy audio track for Safari receive-only workaround. */
  private dummyAudioTrack: MediaStreamTrack | null = null;
  /** Screen-share state — my display stream + peers currently sharing. */
  private screenStream: MediaStream | null = null;
  private screenSharing = false;
  private screenShareGeneration = 0;
  private videoPublishQueue: Promise<void> = Promise.resolve();
  private screenShareTransition: "starting" | "stopping" | null = null;
  /** Camera state when the share began — restored when it ends. */
  private cameraOnBeforeShare = false;
  private screenSharingPeers = new Set<string>();
  /** Auxiliary audio mix (Ember narration) — mic + aux blended via WebAudio
   *  into one outgoing track so every peer hears the narration. */
  private auxCtx: AudioContext | null = null;
  private auxDest: MediaStreamAudioDestinationNode | null = null;
  private auxMicGain: GainNode | null = null;
  private auxMicTrack: MediaStreamTrack | null = null;
  private auxMixTrack: MediaStreamTrack | null = null;
  private auxSources: MediaStreamAudioSourceNode[] = [];
  private speakerMonitor: ReturnType<typeof setInterval> | null = null;
  private speakerStatsInFlight = false;
  /** Health sweep — finds missing/stuck connections and heals them. */
  private healthMonitor: ReturnType<typeof setInterval> | null = null;
  private visibilityHandler: (() => void) | null = null;
  private reannounceTimer: ReturnType<typeof setTimeout> | null = null;
  private joinedOnce = false;
  /** TURN credentials are short-lived — refetch before late reconnects. */
  private iceFetchedAt = 0;
  /** Trusted lifetime of the current ICE server list (from ttlSeconds). */
  private iceTtlMs = 5 * 60_000;
  /** OS-level network-switch detection ("online" event + Network Information
   *  API) — restart ICE the moment the path changes instead of waiting for
   *  WebRTC's own failure timers to notice. */
  private onlineHandler: (() => void) | null = null;
  private netInfoCleanup: (() => void) | null = null;
  private lastNetworkRestartAt = 0;
  /** Truthful per-device acquisition state, refreshed on every attempt. */
  private mediaState: LocalMediaState = {
    hasAudio: false,
    hasVideo: false,
    audioError: null,
    videoError: null,
  };
  /** One-shot honest notice when the meeting runs without TURN relay. */
  private iceDegradedWarned = false;
  /** Outgoing-mic silence watchdog (media-source audioLevel via getStats). */
  private micSilentSamples = 0;
  private micRecoveryAttempted = false;
  private micSilenceWarned = false;
  private micRecoveryInFlight = false;

  get isScreenSharing(): boolean {
    return this.screenSharing;
  }

  get isStartingScreenShare(): boolean { return this.screenShareTransition === "starting"; }
  get isChangingScreenShare(): boolean { return this.screenShareTransition !== null; }

  /** True while an auxiliary audio mix (Ember's voice) is being broadcast. */
  get auxAudioActive(): boolean {
    return this.auxMixTrack != null;
  }

  /** Current publisher role — meetings join everyone as speaker; live rooms promote. */
  get isSpeakerRole(): boolean {
    return this.isSpeaker;
  }

  /** Snapshot of the real device state (what was acquired, what failed, why). */
  get localMediaState(): LocalMediaState {
    return { ...this.mediaState };
  }

  /** Stable ID so views never have to infer "self" from a display name. */
  get localPeerId(): string {
    return this.myPeerId;
  }

  /** A local-audio-only stream for progressive caption fallbacks. */
  get localAudioStream(): MediaStream | null {
    const track = this.auxMicTrack?.readyState === 'live' ? this.auxMicTrack : this.localStream?.getAudioTracks().find((item) => item.readyState === "live");
    return track ? new MediaStream([track]) : null;
  }

  /** The current outgoing camera track (may be an effects-processed track). */
  get localVideoTrack(): MediaStreamTrack | null {
    return this.liveTrack("video");
  }

  /**
   * Swap the outgoing camera feed on every peer connection — used when a
   * background effect is toggled mid-call. Mirrors the screen-share swap:
   * replaceTrack only, no renegotiation, localStream updated so the local
   * self-view and late joiners see the same feed.
   */
  async swapOutgoingVideoTrack(next: MediaStreamTrack, stopOld = false): Promise<void> {
    if (this.screenSharing || this.screenShareTransition || !this.channel) return;
    const generation = this.screenShareGeneration;
    const old = this.liveTrack("video");
    if (old === next) return;
    if (!this.localStream) this.localStream = new MediaStream();
    if (old) {
      this.localStream.removeTrack(old);
      if (stopOld) old.stop();
    }
    this.localStream.addTrack(next);
    next.enabled = this.cameraOn;
    await this.publishTrack(next);
    if (generation !== this.screenShareGeneration || !this.channel) return;
    this.notifyParticipants();
  }

  /** Callbacks */
  onParticipantUpdate?: (participants: LiveParticipantInfo[]) => void;
  onRemoteStream?: (peerId: string, stream: MediaStream) => void;
  onError?: (error: string) => void;
  /** Our own share started/stopped — including the browser's "Stop sharing" bar. */
  onScreenShareChange?: (sharing: boolean) => void;
  /** Called with an emoji whenever anyone sends a floating reaction. */
  onReaction?: (emoji: string) => void;
  /** Room-scoped app messages from other participants (see sendAppEvent). */
  onAppEvent?: (event: string, data: unknown, fromPeerId: string) => void;

  constructor(myPeerId: string, userId: string, name: string) {
    this.myPeerId = myPeerId;
    this.userId = userId;
    this.name = name;
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  private liveTrack(kind: "audio" | "video"): MediaStreamTrack | null {
    const tracks =
      kind === "audio"
        ? this.localStream?.getAudioTracks()
        : this.localStream?.getVideoTracks();
    return tracks?.find((t) => t.readyState === "live") ?? null;
  }

  /** Merge freshly acquired tracks into localStream, evicting dead ones.
   *  Camera tracks route through the background-effects engine when an
   *  effect is active, so peers always receive the processed feed. */
  private adoptTracks(rawTracks: MediaStreamTrack[]): void {
    if (!this.localStream) this.localStream = new MediaStream();
    const tracks = rawTracks.map((t) =>
      t.kind === "video" && !this.screenSharing && videoFx.active ? videoFx.wrap(t) : t,
    );
    for (const track of tracks) {
      if (track.kind === "audio") {
        // Self-heal when the DEVICE ends the track (unplugged, revoked,
        // stolen by another app) — our own stop() never fires "ended".
        track.addEventListener("ended", () => {
          this.handleAudioTrackEnded(track);
        });
      }
      // While the aux mix owns the outgoing audio, fresh mic tracks feed the
      // mix instead of localStream — the mixed track stays the only audio
      // track peers ever see.
      if (track.kind === "audio" && this.auxMixTrack) {
        this.attachMicToAuxMix(track);
        continue;
      }
      for (const old of this.localStream.getTracks()) {
        if (old.kind === track.kind && old.readyState !== "live") {
          this.localStream.removeTrack(old);
          old.stop();
        }
      }
      this.localStream.addTrack(track);
    }
  }

  /**
   * Acquire the local camera and microphone with per-device fallbacks.
   * Call this from the Join click so the permission prompt happens on a
   * user gesture, BEFORE signaling setup competes for attention. Partial
   * grants are kept: mic-only or camera-only both produce a usable call.
   * Never throws — failures land in the returned LocalMediaState.
   */
  async prepareLocalMedia(
    opts: { video?: boolean } = {}
  ): Promise<LocalMediaState> {
    this.assertActive();
    const wantVideo = opts.video !== false;
    const hadAudio = !!this.liveTrack("audio");
    const hadVideo = !!this.liveTrack("video");
    const state: LocalMediaState = {
      hasAudio: hadAudio,
      hasVideo: hadVideo,
      audioError: null,
      videoError: null,
    };

    if (!navigator.mediaDevices?.getUserMedia) {
      if (!state.hasAudio) state.audioError = "insecure";
      if (!state.hasVideo && wantVideo) state.videoError = "insecure";
      this.mediaState = state;
      return { ...state };
    }

    // One combined request first — a single permission prompt when possible.
    // On mobile WebKit the combined request is ALSO the only safe shape (one
    // capture session), so it gets a second try after a breath: the lobby
    // preview was stopped a moment ago and the camera can still be tearing
    // down when the first request lands ("in use" / AbortError on phones).
    if (!state.hasAudio && !state.hasVideo && wantVideo) {
      const attempts = isMobileWebKit() ? 3 : 1;
      for (let attempt = 1; attempt <= attempts; attempt++) {
        try {
          const combined = await this.acquireMedia({
            audio: preferredAudioConstraints(),
            video: preferredVideoConstraints(
              attempt === attempts && attempts > 1 ? true : VIDEO_CONSTRAINTS
            ),
          });
          this.adoptTracks(combined.getTracks());
          state.hasAudio = true;
          state.hasVideo = true;
          break;
        } catch (err) {
          const reason = classifyMediaError(err);
          // A denial is final — retrying only re-prompts nothing.
          if (reason === "denied" || reason === "insecure" || attempt === attempts) break;
          await sleep(350 * attempt);
        }
      }
    }

    if (!state.hasAudio) {
      try {
        const mic = await this.acquireMedia({ audio: preferredAudioConstraints() });
        this.adoptTracks(mic.getTracks());
        state.hasAudio = true;
      } catch (err) {
        state.audioError = classifyMediaError(err);
      }
    }

    if (!state.hasVideo && wantVideo) {
      try {
        const cam = await this.acquireMedia({
          video: preferredVideoConstraints(VIDEO_CONSTRAINTS),
        });
        this.adoptTracks(cam.getTracks());
        state.hasVideo = true;
      } catch (firstErr) {
        // Some webcams reject the 720p ideal — retry once unconstrained.
        try {
          const cam = await this.acquireMedia({ video: true });
          this.adoptTracks(cam.getTracks());
          state.hasVideo = true;
        } catch {
          state.videoError = classifyMediaError(firstErr);
        }
      }
    }

    this.assertActive();
    // Newly acquired devices start enabled; existing mute states are kept.
    if (!hadAudio && state.hasAudio) this.micOn = true;
    if (!hadVideo && state.hasVideo) this.cameraOn = true;
    if (!state.hasAudio) this.micOn = false;
    if (!state.hasVideo && !this.screenSharing) this.cameraOn = false;

    this.mediaState = state;
    return { ...state };
  }

  async join(roomId: string, asListener: boolean): Promise<void> {
    this.assertActive();
    this.roomId = roomId;
    this.isSpeaker = !asListener;

    // 1. Fresh ICE servers from the Rork toolkit (short-lived TURN creds).
    const ice = await fetchIceServers();
    this.assertActive();
    this.iceServers = ice.servers;
    this.iceTtlMs = ice.ttlMs;
    this.iceFetchedAt = Date.now();
    if (ice.degraded && !this.iceDegradedWarned) {
      // Both the toolkit AND the backend proxy were unreachable — rare, and
      // worth saying out loud: without TURN, strict-NAT participants connect
      // but their audio/video never arrives.
      this.iceDegradedWarned = true;
      console.warn("[WhisperLiveRTC] running STUN-only — TURN relay unavailable");
      this.onError?.(
        "Limited connectivity mode — the relay service couldn't be reached. If others can't hear or see you, leave and rejoin in a moment.",
      );
    }

    // 2. Signaling channel FIRST — set up and subscribe BEFORE acquiring
    //    local media. If getUserMedia fails (permission denied, iframe
    //    allow attribute missing, etc.), the peer still joins the signaling
    //    channel so other peers know they're in the room. Without this
    //    ordering, a getUserMedia rejection throws before the channel is
    //    subscribed, so the other platform never sees the peer join — the
    //    exact "iOS can't see web / web can't see iOS" bug.
    //
    //    Leave→rejoin safety: supabase keys channels by topic, and the old
    //    session's channel may still be mid-teardown. Purge any lingering
    //    channel for this room first, otherwise the fresh subscribe can
    //    attach to a dying channel and signaling silently never comes up —
    //    the exact "rejoined but nobody gets my video/audio" bug.
    const topic = `live-signal:${roomId}`;
    for (const existing of supabase.getChannels()) {
      this.assertActive();
      if (existing.topic === topic || existing.topic === `realtime:${topic}`) {
        try {
          await supabase.removeChannel(existing);
        } catch {
          /* already gone */
        }
      }
    }

    // ack:true makes channel.send() resolve with real server confirmation,
    // so critical signaling (offers/answers/ICE) can be retried instead of
    // silently vanishing — a dropped offer used to deadlock the pair until
    // someone manually left and rejoined.
    this.assertActive();
    this.channel = supabase.channel(topic, {
      config: { broadcast: { self: false, ack: true } },
    });

    this.channel.on("broadcast", { event: "signal" }, ({ payload }) => {
      if (this.hasLeft) return;
      void this.handleSignal(payload as SignalMessage);
    });

    // subscribe() returns immediately — wait for the REAL outcome so the
    // "join" announcement below is never dropped on a half-open channel.
    await new Promise<void>((resolve, reject) => {
      let settled = false;
      const finish = (error?: Error): void => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        if (error) reject(error);
        else resolve();
      };
      const timer = setTimeout(
        () => finish(new Error("Signaling connection timed out")),
        12000,
      );
      this.channel?.subscribe((status: string) => {
        if (this.hasLeft) { finish(new DOMException("Meeting connection was closed", "AbortError")); return; }
        if (status === "SUBSCRIBED") {
          // Supabase auto-rejoins after network blips; signaling sent while
          // offline is gone forever. Re-announce presence and sweep for
          // broken pairs on every re-subscribe — self-heals "joined but
          // nobody can see or hear me".
          if (this.joinedOnce) {
            void this.reannouncePresence();
            this.sweepConnections();
          }
          finish();
        } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
          finish(new Error("Couldn't reach the meeting signaling service"));
        }
      });
    });

    this.assertActive();
    // 3. Local media — speakers publish audio + video; listeners subscribe only.
    //    If the caller already ran prepareLocalMedia() (meetings do this on the
    //    Join click), the acquired tracks are reused; otherwise acquisition
    //    happens here with per-device fallbacks. A speaker whose devices all
    //    failed STAYS a speaker: recvonly transceivers make the wire behave
    //    like a listener while the UI offers device retry in-call.
    if (!asListener) {
      const preAcquired = this.localStream != null;
      const media = preAcquired
        ? this.localMediaState
        : await this.prepareLocalMedia();
      if (!preAcquired) {
        if (!media.hasAudio && media.audioError) {
          this.onError?.(describeMediaBlock(media.audioError, "microphone"));
        }
        if (!media.hasVideo && media.videoError) {
          this.onError?.(describeMediaBlock(media.videoError, "camera"));
        }
      }
      if (!media.hasAudio && !media.hasVideo) {
        // Safari needs SOME local track to generate ICE candidates.
        this.dummyAudioTrack = createSilentAudioTrack();
      }
    } else {
      // Silent dummy audio for Safari receive-only workaround.
      this.dummyAudioTrack = createSilentAudioTrack();
    }

    this.assertActive();
    // 4. Announce join so existing peers can create offers. Two peers
    //    subscribing at the same moment can miss each other's announcement,
    //    so re-announce once shortly after — receivers treat duplicates
    //    idempotently.
    this.joinedOnce = true;
    await this.sendSignal({
      type: "join",
      peerId: this.myPeerId,
      userId: this.userId,
      name: this.name,
      isSpeaker: this.isSpeaker,
    });
    this.assertActive();
    this.reannounceTimer = setTimeout(() => {
      void this.reannouncePresence();
    }, 2000);

    // Background tabs throttle timers — sweep the moment the user returns so
    // stuck pairs recover as soon as the tab is visible again.
    this.visibilityHandler = (): void => {
      if (typeof document !== "undefined" && !document.hidden) {
        this.sweepConnections();
      }
    };
    if (typeof document !== "undefined") {
      document.addEventListener("visibilitychange", this.visibilityHandler);
    }

    // OS-level network-switch detection: "online" fires on reconnect, the
    // Network Information API on wifi↔cellular/VPN changes. Restarting ICE
    // immediately (with fresh TURN creds) beats waiting out failure timers.
    if (typeof window !== "undefined") {
      this.onlineHandler = (): void => {
        void this.handleNetworkChange("online");
      };
      window.addEventListener("online", this.onlineHandler);
      const netInfo = (
        navigator as Navigator & { connection?: NetworkInformationLike }
      ).connection;
      if (netInfo?.addEventListener) {
        let lastKind = `${netInfo.type ?? ""}/${netInfo.effectiveType ?? ""}`;
        const onNetChange = (): void => {
          const kind = `${netInfo.type ?? ""}/${netInfo.effectiveType ?? ""}`;
          if (kind === lastKind) return; // signal-strength noise, not a switch
          lastKind = kind;
          void this.handleNetworkChange(`netinfo ${kind}`);
        };
        netInfo.addEventListener("change", onNetChange);
        this.netInfoCleanup = (): void => {
          netInfo.removeEventListener?.("change", onNetChange);
        };
      }
    }

    this.notifyParticipants();
    this.startSpeakerMonitor();
    this.startHealthMonitor();
  }

  /** Re-broadcast presence — duplicate-safe on every receiver. */
  private async reannouncePresence(): Promise<void> {
    if (!this.channel) return;
    await this.sendSignal({
      type: "join",
      peerId: this.myPeerId,
      userId: this.userId,
      name: this.name,
      isSpeaker: this.isSpeaker,
    });
  }

  /**
   * Publish a local track to every peer connection, reusing existing senders
   * or recvonly transceivers when possible (no renegotiation), and falling
   * back to addTrack + renegotiation. Either side may renegotiate — the glare
   * rollback in handleOffer keeps simultaneous offers safe.
   */
  private publishTrack(track: MediaStreamTrack): Promise<void> {
    if (track.kind !== "video") return this.publishTrackNow(track);
    const generation = this.screenShareGeneration;
    const operation = this.videoPublishQueue.then(async () => {
      if (generation !== this.screenShareGeneration || !this.channel || track.readyState !== "live") return;
      await this.publishTrackNow(track, generation);
    });
    this.videoPublishQueue = operation.catch(() => undefined);
    return operation;
  }

  private async publishTrackNow(track: MediaStreamTrack, generation?: number): Promise<void> {
    // The aux mix owns the outgoing audio sender — route raw mics into the
    // mix rather than replacing the mixed track on the wire.
    if (
      track.kind === "audio" &&
      this.auxMixTrack &&
      track !== this.auxMixTrack
    ) {
      this.attachMicToAuxMix(track);
      return;
    }
    const stream = this.localStream ?? new MediaStream([track]);
    for (const peer of this.peers.values()) {
      if (generation !== undefined && (generation !== this.screenShareGeneration || !this.channel || track.readyState !== "live")) return;
      const sender = peer.pc
        .getSenders()
        .find((s) => s.track?.kind === track.kind);
      if (sender) {
        if (sender.track !== track) {
          await sender.replaceTrack(track).catch(() => undefined);
        }
        continue;
      }
      const transceiver = peer.pc
        .getTransceivers()
        .find(
          (t) =>
            t.currentDirection !== "stopped" &&
            t.receiver.track?.kind === track.kind &&
            !t.sender.track,
        );
      if (transceiver) {
        await transceiver.sender.replaceTrack(track).catch(() => undefined);
        if (generation !== undefined && (generation !== this.screenShareGeneration || !this.channel)) return;
        try {
          transceiver.sender.setStreams?.(stream);
          transceiver.direction = "sendrecv";
        } catch {
          /* older browsers */
        }
        this.requestNegotiation(peer);
      } else {
        try {
          peer.pc.addTrack(track, stream);
        } catch {
          continue;
        }
        this.requestNegotiation(peer);
      }
    }
  }

  /**
   * Enable/disable the microphone. When enabling without a live audio track,
   * the mic is (re)acquired and published on the spot. Returns the state that
   * actually applies so the UI never shows an "on" mic that produces nothing.
   */
  async setMicEnabled(enabled: boolean): Promise<boolean> {
    if (this.hasLeft) return false;
    // Mix mode: the outgoing track is mic+Ember blended — mute by silencing
    // the mic branch's gain so Ember's narration keeps flowing.
    if (this.auxMixTrack) {
      if (!enabled) {
        if (this.auxMicGain) this.auxMicGain.gain.value = 0;
        if (this.auxMicTrack) this.auxMicTrack.enabled = false;
        this.micOn = false;
      } else {
        if (!this.auxMicTrack || this.auxMicTrack.readyState !== "live") {
          try {
            const mic = await this.acquireMedia({ audio: preferredAudioConstraints() });
            const fresh = mic.getAudioTracks()[0] ?? null;
            if (fresh) {
              this.attachMicToAuxMix(fresh);
              this.mediaState = { ...this.mediaState, hasAudio: true, audioError: null };
            }
          } catch (err) {
            this.mediaState = { ...this.mediaState, hasAudio: false, audioError: classifyMediaError(err) };
          }
        }
        if (!this.auxMicTrack || this.auxMicTrack.readyState !== "live") {
          this.micOn = false;
          this.notifyParticipants();
          return false;
        }
        this.auxMicTrack.enabled = true;
        if (this.auxMicGain) this.auxMicGain.gain.value = 1;
        this.micOn = true;
      }
      await this.broadcast({
        type: "mic-toggle",
        from: this.myPeerId,
        isOn: this.micOn,
      });
      if (this.hasLeft) return false;
      this.notifyParticipants();
      return this.micOn;
    }
    if (!enabled) {
      for (const track of this.localStream?.getAudioTracks() ?? []) {
        track.enabled = false;
      }
      this.micOn = false;
    } else {
      let track = this.liveTrack("audio");
      if (!track) {
        try {
          const mic = await this.acquireMedia({ audio: preferredAudioConstraints() });
          const fresh = mic.getAudioTracks()[0] ?? null;
          if (fresh) {
            this.adoptTracks([fresh]);
            await this.publishTrack(fresh);
            if (this.hasLeft) return false;
            track = fresh;
            this.mediaState = { ...this.mediaState, hasAudio: true, audioError: null };
          }
        } catch (err) {
          this.mediaState = { ...this.mediaState, hasAudio: false, audioError: classifyMediaError(err) };
        }
      }
      if (this.hasLeft) return false;
      if (!track || track.readyState !== "live") {
        this.micOn = false;
        this.notifyParticipants();
        return false;
      }
      track.enabled = true;
      this.micOn = true;
      this.micSilentSamples = 0;
    }
    await this.broadcast({
      type: "mic-toggle",
      from: this.myPeerId,
      isOn: this.micOn,
    });
    if (this.hasLeft) return false;
    this.notifyParticipants();
    return this.micOn;
  }

  /**
   * Enable/disable the camera. When enabling without a live video track, the
   * camera is (re)acquired and published. Returns the state that actually
   * applies. While screen sharing, the share owns the video sender and the
   * toggle is a no-op.
   */
  async setCameraEnabled(enabled: boolean): Promise<boolean> {
    if (this.hasLeft) return false;
    if (this.screenSharing) {
      this.cameraOn = true;
      return true;
    }
    if (this.screenShareTransition || !this.channel) return this.cameraOn;
    const generation = this.screenShareGeneration;
    if (!enabled) {
      for (const track of this.localStream?.getVideoTracks() ?? []) {
        track.enabled = false;
      }
      this.cameraOn = false;
    } else {
      let track = this.liveTrack("video");
      if (!track) {
        try {
          const cam = await this.acquireMedia({
            video: preferredVideoConstraints(VIDEO_CONSTRAINTS),
          });
          if (generation !== this.screenShareGeneration || !this.channel || this.screenSharing || this.screenShareTransition) {
            cam.getTracks().forEach((item) => item.stop());
            return this.cameraOn;
          }
          const fresh = cam.getVideoTracks()[0] ?? null;
          if (fresh) {
            this.adoptTracks([fresh]);
            // Publish what adoptTracks put on localStream — possibly the
            // effects-processed track rather than the raw camera.
            const outgoing = this.liveTrack("video") ?? fresh;
            await this.publishTrack(outgoing);
            if (generation !== this.screenShareGeneration || !this.channel) return this.cameraOn;
            track = outgoing;
            this.mediaState = { ...this.mediaState, hasVideo: true, videoError: null };
          }
        } catch (err) {
          if (generation !== this.screenShareGeneration || !this.channel) return this.cameraOn;
          this.mediaState = { ...this.mediaState, hasVideo: false, videoError: classifyMediaError(err) };
        }
      }
      if (!track) {
        this.cameraOn = false;
        await this.broadcast({
          type: "track-update",
          from: this.myPeerId,
          hasAudio: this.micOn,
          hasVideo: false,
        });
        this.notifyParticipants();
        return false;
      }
      track.enabled = true;
      this.cameraOn = true;
    }
    await this.broadcast({
      type: "track-update",
      from: this.myPeerId,
      hasAudio: this.micOn,
      hasVideo: this.cameraOn,
    });
    if (this.hasLeft) return false;
    this.notifyParticipants();
    return this.cameraOn;
  }

  /**
   * Re-attempt acquisition of any missing device and publish what came back.
   * Used by the in-call "Retry devices" action after a block is resolved.
   */
  async retryLocalMedia(): Promise<LocalMediaState> {
    const state = await this.prepareLocalMedia();
    const audio = this.liveTrack("audio");
    const video = this.liveTrack("video");
    if (audio) {
      audio.enabled = this.micOn;
      await this.publishTrack(audio);
    }
    if (video && !this.screenSharing) {
      video.enabled = this.cameraOn;
      await this.publishTrack(video);
    }
    await this.broadcast({
      type: "track-update",
      from: this.myPeerId,
      hasAudio: this.micOn,
      hasVideo: this.cameraOn || this.screenSharing,
    });
    this.notifyParticipants();
    return state;
  }

  /**
   * Promote a listener to a speaker — starts publishing audio + video.
   * Returns false (with onError feedback) when no device could be opened,
   * leaving the listener connection fully intact.
   */
  async becomeSpeaker(): Promise<boolean> {
    if (this.isSpeaker) return true;

    // Stop the dummy audio track before acquiring real media — Safari can
    // invalidate the first stream's tracks when a second getUserMedia call
    // happens (SO, Apr 2023).
    if (this.dummyAudioTrack) {
      this.dummyAudioTrack.stop();
      this.dummyAudioTrack = null;
    }

    const media = await this.prepareLocalMedia();
    if (!media.hasAudio && !media.hasVideo) {
      // Nothing usable — stay a listener and restore the Safari dummy track.
      this.dummyAudioTrack = createSilentAudioTrack();
      this.onError?.(
        describeMediaBlock(media.audioError ?? "unknown", "microphone")
      );
      return false;
    }

    this.isSpeaker = true;

    // Publish tracks to existing PCs — publishTrack reuses the dummy-audio
    // sender / recvonly transceivers and renegotiates only when needed.
    for (const track of this.localStream?.getTracks() ?? []) {
      if (track.readyState === "live") await this.publishTrack(track);
    }

    // Broadcast promotion so listeners can create new PCs with us.
    await this.broadcast({
      type: "became-speaker",
      peerId: this.myPeerId,
      userId: this.userId,
      name: this.name,
    });

    // Create offers to known peers we don't have a PC with yet (other listeners).
    for (const [peerId, known] of this.knownPeers) {
      if (this.peers.has(peerId)) continue;
      if (known.isSpeaker) continue; // speaker-speaker: handled by peerId rule
      // I'm now a speaker connecting to a listener — I'm the offerer.
      await this.createPeerConnection(
        peerId,
        known.userId,
        known.name,
        known.isSpeaker,
        true,
      );
    }

    this.notifyParticipants();
    return true;
  }

  /**
   * Start broadcasting the screen into the live. The display track replaces
   * the outgoing camera track on every peer connection (no renegotiation
   * needed), and the shared screen takes the large tile automatically.
   */
  async startScreenShare(): Promise<boolean> {
    if (!this.isSpeaker || !this.channel || this.screenSharing || this.screenShareTransition) return false;
    const generation = ++this.screenShareGeneration;
    this.screenShareTransition = "starting";
    let display: MediaStream;
    try {
      display = await navigator.mediaDevices.getDisplayMedia({
        video: { frameRate: { ideal: 30 } },
        audio: false,
      });
    } catch {
      if (generation === this.screenShareGeneration) this.screenShareTransition = null;
      return false;
    }
    const screenTrack = display.getVideoTracks()[0];
    if (generation !== this.screenShareGeneration || !this.channel || !screenTrack || screenTrack.readyState !== "live") {
      display.getTracks().forEach((track) => track.stop());
      if (generation === this.screenShareGeneration) this.screenShareTransition = null;
      return false;
    }
    this.screenStream = display;
    // Remember how the camera was BEFORE the share so ending it restores
    // that state — a camera the user had off must not switch itself on.
    this.cameraOnBeforeShare = this.cameraOn && this.liveTrack("video") != null;

    // Screen shares bypass the effects pipeline — release the camera fully
    // (it's re-acquired and re-wrapped when the share ends).
    if (videoFx.outputTrack) videoFx.release({ stopSource: true });

    // Local preview: swap the track inside localStream first so publishTrack
    // attaches the share to the same stream id peers already know.
    if (!this.localStream) this.localStream = new MediaStream();
    for (const camTrack of this.localStream.getVideoTracks()) {
      this.localStream.removeTrack(camTrack);
      camTrack.stop();
    }
    this.localStream.addTrack(screenTrack);

    // Put the share on the wire. publishTrack swaps an existing video sender
    // in place (no renegotiation) and — the case the old per-sender loop
    // silently skipped — ADDS a video sender + renegotiates for peers that
    // never received our camera (camera off or blocked when we joined).
    this.screenSharing = true;
    screenTrack.onended = () => {
      if (this.screenStream === display) void this.stopScreenShare();
    };
    await this.publishTrack(screenTrack);
    if (generation !== this.screenShareGeneration || !this.channel || screenTrack.readyState !== "live") return false;
    this.screenShareTransition = null;
    this.cameraOn = true;
    this.onScreenShareChange?.(true);
    await this.broadcast({ type: "screen-share", from: this.myPeerId, isOn: true }).catch(() => undefined);
    if (generation !== this.screenShareGeneration || !this.channel) return false;
    // Remotes gate the tile on hasVideo — a sharer whose camera was off
    // still had hasVideo=false on their side, which drew an avatar over
    // the incoming screen. Say plainly that video is flowing now.
    await this.broadcast({
      type: "track-update",
      from: this.myPeerId,
      hasAudio: this.micOn,
      hasVideo: true,
    }).catch(() => undefined);
    if (generation !== this.screenShareGeneration || !this.channel) return false;
    this.notifyParticipants();
    return true;
  }

  /** Stop sharing the screen and hand the video track back to the camera. */
  async stopScreenShare(): Promise<void> {
    if (this.screenShareTransition === "stopping") return;
    const generation = ++this.screenShareGeneration;
    if (!this.screenSharing) { this.screenShareTransition = null; return; }
    this.screenShareTransition = "stopping";
    this.screenSharing = false;
    const display = this.screenStream;
    this.screenStream = null;
    const screenTrack = display?.getVideoTracks()[0] ?? null;
    const restoreCamera = this.cameraOnBeforeShare;
    this.cameraOnBeforeShare = false;
    // Stop capture before any permission dialog or sender operation can suspend us.
    for (const track of display?.getTracks() ?? []) {
      track.onended = null;
      this.localStream?.removeTrack(track);
      track.stop();
    }
    this.cameraOn = false;
    this.mediaState = { ...this.mediaState, hasVideo: false };
    this.onScreenShareChange?.(false);
    this.notifyParticipants();
    void this.broadcast({ type: "screen-share", from: this.myPeerId, isOn: false }).catch(() => undefined);
    void this.broadcast({ type: "track-update", from: this.myPeerId, hasAudio: this.micOn, hasVideo: false }).catch(() => undefined);

    // Re-acquire the camera ONLY if it was on before the share — otherwise
    // the camera light would come on for a user who had switched it off.
    let camTrack: MediaStreamTrack | null = null;
    if (restoreCamera) {
      try {
        const cam = await this.acquireMedia({
          video: preferredVideoConstraints(VIDEO_CONSTRAINTS),
        });
        if (generation !== this.screenShareGeneration || !this.channel) {
          cam.getTracks().forEach((track) => track.stop());
          return;
        }
        camTrack = cam.getVideoTracks()[0] ?? null;
      } catch {
        camTrack = null;
      }
    }

    if (generation !== this.screenShareGeneration || !this.channel) { camTrack?.stop(); return; }
    if (this.localStream) {
      if (screenTrack) this.localStream.removeTrack(screenTrack);
      if (camTrack) this.adoptTracks([camTrack]);
    }
    // Hand the wire back to whatever adoptTracks produced (processed track
    // when a background effect is active, the raw camera otherwise) — or
    // to nothing, which mutes the remote receiver cleanly.
    const outgoingCam = camTrack ? (this.liveTrack("video") ?? camTrack) : null;

    const restoreOperation = this.videoPublishQueue.then(async () => {
      if (generation !== this.screenShareGeneration || !this.channel) return;
      if (outgoingCam) { await this.publishTrackNow(outgoingCam, generation); return; }
      for (const peer of this.peers.values()) {
        if (generation !== this.screenShareGeneration || !this.channel) return;
        const sender = peer.pc.getSenders().find((sender) => sender.track === screenTrack || sender.track?.kind === "video");
        if (sender) await sender.replaceTrack(null).catch(() => undefined);
      }
    });
    this.videoPublishQueue = restoreOperation.catch(() => undefined);
    await restoreOperation;
    if (generation !== this.screenShareGeneration || !this.channel) { camTrack?.stop(); return; }
    this.cameraOn = camTrack != null;
    this.mediaState = { ...this.mediaState, hasVideo: camTrack != null };

    await this.broadcast({ type: "screen-share", from: this.myPeerId, isOn: false }).catch(() => undefined);
    if (generation !== this.screenShareGeneration || !this.channel) return;
    await this.broadcast({
      type: "track-update",
      from: this.myPeerId,
      hasAudio: this.micOn,
      hasVideo: this.cameraOn,
    }).catch(() => undefined);
    if (generation !== this.screenShareGeneration || !this.channel) return;
    this.screenShareTransition = null;
    this.notifyParticipants();
    this.onScreenShareChange?.(false);
  }

  /**
   * Broadcast an auxiliary audio stream (Ember's live narration) to everyone
   * in the room by blending it with the microphone into a single outgoing
   * track. The mic keeps working — mute toggles silence only the mic branch.
   * Call stopAuxAudioMix() to hand the wire back to the raw microphone.
   */
  async startAuxAudioMix(aux: MediaStream): Promise<boolean> {
    if (this.auxMixTrack) await this.stopAuxAudioMix();
    try {
      const ctx = new AudioContext();
      if (ctx.state === "suspended") void ctx.resume().catch(() => undefined);
      const dest = ctx.createMediaStreamDestination();

      const micTrack = this.liveTrack("audio");
      if (micTrack) {
        const micSource = ctx.createMediaStreamSource(new MediaStream([micTrack]));
        const micGain = ctx.createGain();
        micGain.gain.value = this.micOn ? 1 : 0;
        micSource.connect(micGain);
        micGain.connect(dest);
        this.auxSources.push(micSource);
        this.auxMicGain = micGain;
        this.auxMicTrack = micTrack;
      }

      const auxSource = ctx.createMediaStreamSource(aux);
      const auxGain = ctx.createGain();
      auxGain.gain.value = 1;
      auxSource.connect(auxGain);
      auxGain.connect(dest);
      this.auxSources.push(auxSource);

      const mixed = dest.stream.getAudioTracks()[0] ?? null;
      if (!mixed) {
        void ctx.close().catch(() => undefined);
        this.auxSources = [];
        this.auxMicGain = null;
        this.auxMicTrack = null;
        return false;
      }
      this.auxCtx = ctx;
      this.auxDest = dest;
      this.auxMixTrack = mixed;

      // Swap the outgoing audio on every live peer connection.
      for (const peer of this.peers.values()) {
        const sender = peer.pc.getSenders().find((s) => s.track?.kind === "audio");
        if (sender) await sender.replaceTrack(mixed).catch(() => undefined);
      }
      // Swap inside localStream too so NEW peers connect straight to the mix.
      if (!this.localStream) this.localStream = new MediaStream();
      if (this.auxMicTrack) this.localStream.removeTrack(this.auxMicTrack);
      this.localStream.addTrack(mixed);
      this.notifyParticipants();
      return true;
    } catch (err) {
      console.warn("[WhisperLiveRTC] aux audio mix failed", err);
      this.teardownAuxMix();
      return false;
    }
  }

  /** Stop broadcasting the aux mix and restore the raw microphone track. */
  async stopAuxAudioMix(): Promise<void> {
    if (!this.auxMixTrack) return;
    const mixed = this.auxMixTrack;
    const mic = this.auxMicTrack;
    this.auxMixTrack = null;
    this.auxMicTrack = null;
    this.auxMicGain = null;
    for (const source of this.auxSources) {
      try {
        source.disconnect();
      } catch {
        /* already gone */
      }
    }
    this.auxSources = [];
    const liveMic = mic && mic.readyState === "live" ? mic : null;
    if (this.localStream) {
      this.localStream.removeTrack(mixed);
      if (liveMic && !this.localStream.getAudioTracks().includes(liveMic)) {
        this.localStream.addTrack(liveMic);
      }
    }
    mixed.stop();
    if (liveMic) liveMic.enabled = this.micOn;
    for (const peer of this.peers.values()) {
      const sender = peer.pc.getSenders().find((s) => s.track?.kind === "audio");
      if (sender) await sender.replaceTrack(liveMic).catch(() => undefined);
    }
    const ctx = this.auxCtx;
    this.auxCtx = null;
    this.auxDest = null;
    if (ctx) void ctx.close().catch(() => undefined);
    this.notifyParticipants();
  }

  /** Route a (fresh) mic track into the running aux mix. */
  private attachMicToAuxMix(track: MediaStreamTrack): void {
    if (!this.auxCtx || !this.auxDest) return;
    try {
      const source = this.auxCtx.createMediaStreamSource(new MediaStream([track]));
      const gain = this.auxCtx.createGain();
      gain.gain.value = this.micOn ? 1 : 0;
      source.connect(gain);
      gain.connect(this.auxDest);
      this.auxSources.push(source);
      this.auxMicGain = gain;
      this.auxMicTrack = track;
    } catch (err) {
      console.warn("[WhisperLiveRTC] mic → mix attach failed", err);
    }
  }

  /** Synchronous best-effort teardown of the mix (leave/cleanup paths). */
  private teardownAuxMix(): void {
    const mixed = this.auxMixTrack;
    this.auxMixTrack = null;
    this.auxMicTrack?.stop();
    this.auxMicTrack = null;
    this.auxMicGain = null;
    for (const source of this.auxSources) {
      try {
        source.disconnect();
      } catch {
        /* already gone */
      }
    }
    this.auxSources = [];
    if (mixed) {
      if (this.localStream) this.localStream.removeTrack(mixed);
      mixed.stop();
    }
    const ctx = this.auxCtx;
    this.auxCtx = null;
    this.auxDest = null;
    if (ctx) void ctx.close().catch(() => undefined);
  }

  /** Send a floating emoji reaction to everyone in the room (iOS + web share the signaling channel). */
  sendReaction(emoji: string): void {
    this.onReaction?.(emoji);
    void this.broadcast({ type: "reaction", from: this.myPeerId, emoji });
  }

  /** Broadcast a room-scoped app message (presentations, etc.) to everyone. */
  sendAppEvent(event: string, data: unknown): void {
    void this.broadcast({ type: "app-event", from: this.myPeerId, event, data });
  }

  leave(): void {
    if (this.hasLeft) return;
    this.hasLeft = true;
    this.micOn = false;
    this.cameraOn = false;
    ++this.screenShareGeneration;
    this.screenShareTransition = null;
    this.screenSharing = false;
    this.cameraOnBeforeShare = false;
    if (this.screenStream) this.screenStream.getTracks().forEach((track) => { track.onended = null; });
    if (videoFx.outputTrack && this.localStream?.getTracks().includes(videoFx.outputTrack)) videoFx.release({ stopSource: true });
    this.stopSpeakerMonitor();
    this.stopHealthMonitor();
    this.joinedOnce = false;
    if (this.reannounceTimer) {
      clearTimeout(this.reannounceTimer);
      this.reannounceTimer = null;
    }
    if (this.visibilityHandler && typeof document !== "undefined") {
      document.removeEventListener("visibilitychange", this.visibilityHandler);
      this.visibilityHandler = null;
    }
    if (this.onlineHandler && typeof window !== "undefined") {
      window.removeEventListener("online", this.onlineHandler);
      this.onlineHandler = null;
    }
    this.netInfoCleanup?.();
    this.netInfoCleanup = null;
    // Flush the goodbye BEFORE tearing the channel down. The old
    // fire-and-forget send raced removeChannel and usually never left the
    // socket, so other peers kept a ghost tile until ICE timed out.
    const channel = this.channel;
    this.channel = null;
    if (channel) {
      const goodbye: SignalMessage = { type: "leave", peerId: this.myPeerId };
      void (async () => {
        try {
          await channel.send({ type: "broadcast", event: "signal", payload: goodbye });
        } catch {
          /* best effort */
        }
        try {
          await supabase.removeChannel(channel);
        } catch {
          /* already gone */
        }
      })();
    }
    if (this.screenStream) {
      this.screenStream.getTracks().forEach((t) => t.stop());
      this.screenStream = null;
      this.screenSharing = false;
    }
    this.teardownAuxMix();
    for (const timer of this.disconnectTimers.values()) clearTimeout(timer);
    this.disconnectTimers.clear();
    for (const peer of this.peers.values()) {
      try {
        peer.pc.close();
      } catch {
        /* ignore */
      }
    }
    this.peers.clear();
    this.knownPeers.clear();
    this.pendingIce.clear();
    this.screenSharingPeers.clear();
    if (this.localStream) {
      for (const track of this.localStream.getTracks()) track.stop();
      this.localStream = null;
    }
    if (this.dummyAudioTrack) {
      this.dummyAudioTrack.stop();
      this.dummyAudioTrack = null;
    }
    this.onScreenShareChange?.(false);
  }

  // ─── Signaling ──────────────────────────────────────────────────────────────

  private async broadcast(msg: SignalMessage): Promise<void> {
    if (!this.channel) return;
    await this.channel.send({ type: "broadcast", event: "signal", payload: msg });
  }

  /**
   * Send a signaling message with delivery confirmation + retries. A silently
   * dropped offer/answer/ICE used to deadlock the pair until someone manually
   * left and rejoined — retrying here is the core cross-browser join fix.
   */
  private async sendSignal(msg: SignalMessage, attempts = 3): Promise<boolean> {
    for (let attempt = 1; attempt <= attempts; attempt++) {
      const channel = this.channel;
      if (!channel) return false;
      try {
        const result = await channel.send({
          type: "broadcast",
          event: "signal",
          payload: msg,
        });
        if (result === "ok") return true;
      } catch {
        /* retry below */
      }
      if (attempt < attempts) {
        await new Promise((resolve) => setTimeout(resolve, 350 * attempt));
      }
    }
    console.warn(`[WhisperLiveRTC] signaling send failed after retries: ${msg.type}`);
    return false;
  }

  /**
   * Refresh short-lived TURN credentials and push them into every LIVE
   * connection. Without setConfiguration, existing RTCPeerConnections keep
   * the credentials they were created with — an ICE restart minutes into a
   * meeting would gather with EXPIRED TURN creds and never get a relay,
   * exactly on the hostile networks that need one.
   */
  private async ensureIceServers(maxAgeMs?: number): Promise<void> {
    if (this.hasLeft) return;
    if (this.iceRefresh) return this.iceRefresh;
    const limit = maxAgeMs ?? Math.min(this.iceTtlMs * 0.75, 10 * 60_000);
    if (Date.now() - this.iceFetchedAt < limit) return;
    const refresh = this.refreshIceServers();
    this.iceRefresh = refresh;
    try { await refresh; } finally { if (this.iceRefresh === refresh) this.iceRefresh = null; }
  }

  private async refreshIceServers(): Promise<void> {
    try {
      const ice = await fetchIceServers();
      if (this.hasLeft) return;
      if (ice.degraded && this.iceServers.length > 0) {
        // Toolkit hiccup — keep the previous (likely still valid) TURN list
        // and retry soon rather than downgrading live pairs to STUN-only.
        this.iceTtlMs = ice.ttlMs;
        return;
      }
      this.iceServers = ice.servers;
      this.iceTtlMs = ice.ttlMs;
      this.iceFetchedAt = Date.now();
      for (const entry of this.peers.values()) {
        try {
          entry.pc.setConfiguration({ iceServers: this.iceServers });
        } catch {
          // Some browsers restrict setConfiguration — rebuilt pairs still
          // pick up the fresh list from this.iceServers.
        }
      }
    } catch {
      /* keep the previous list */
    }
  }

  private async handleSignal(msg: SignalMessage): Promise<void> {
    if (this.hasLeft) return;
    // Drop messages not addressed to me (to-field) or from myself.
    if ("to" in msg && msg.to !== this.myPeerId) return;
    if ("from" in msg && msg.from === this.myPeerId) return;
    const senderId = "from" in msg ? msg.from : "peerId" in msg ? msg.peerId : "";
    if (this.retiredPeerIds.has(senderId)) return;

    switch (msg.type) {
      case "join": {
        // A rejoining user arrives under a fresh peerId — evict any session
        // they left behind so the dead tile can't linger or steal focus.
        this.evictStaleSessions(msg.userId, msg.peerId);
        // Record the new peer.
        this.knownPeers.set(msg.peerId, {
          peerId: msg.peerId,
          userId: msg.userId,
          name: msg.name,
          isSpeaker: msg.isSpeaker,
        });
        // Duplicate announce for a pair we already track — refresh identity.
        const existingJoin = this.peers.get(msg.peerId);
        if (existingJoin) {
          existingJoin.userId = msg.userId || existingJoin.userId;
          existingJoin.name = msg.name || existingJoin.name;
          existingJoin.isSpeaker = msg.isSpeaker;
        }
        // Respond with my presence so the new peer knows about me.
        await this.sendSignal({
          type: "peer-presence",
          peerId: this.myPeerId,
          userId: this.userId,
          name: this.name,
          isSpeaker: this.isSpeaker,
          targetPeerId: msg.peerId,
        });
        await this.broadcastMediaState();
        // If I'm a speaker, create a PC to the new peer. CRITICAL: when the
        // new peer is ALSO a speaker (meetings — everyone publishes), both
        // sides would create offers simultaneously (glare) and negotiation
        // deadlocks — the exact "black screen / no audio" bug. The offerer
        // is always the smaller peerId.
        if (this.isSpeaker && msg.isSpeaker) {
          await this.createPeerConnection(
            msg.peerId,
            msg.userId,
            msg.name,
            msg.isSpeaker,
            this.myPeerId < msg.peerId,
          );
        } else if (this.isSpeaker) {
          await this.createPeerConnection(
            msg.peerId,
            msg.userId,
            msg.name,
            msg.isSpeaker,
            true,
          );
        } else if (msg.isSpeaker) {
          // New peer is a speaker, I'm a listener — create PC as answerer,
          // wait for their offer.
          await this.createPeerConnection(
            msg.peerId,
            msg.userId,
            msg.name,
            msg.isSpeaker,
            false,
          );
        }
        break;
      }
      case "peer-presence": {
        if (msg.targetPeerId !== this.myPeerId) return;
        this.evictStaleSessions(msg.userId, msg.peerId);
        this.knownPeers.set(msg.peerId, {
          peerId: msg.peerId,
          userId: msg.userId,
          name: msg.name,
          isSpeaker: msg.isSpeaker,
        });
        const existingPresence = this.peers.get(msg.peerId);
        if (existingPresence) {
          existingPresence.userId = msg.userId || existingPresence.userId;
          existingPresence.name = msg.name || existingPresence.name;
          existingPresence.isSpeaker = msg.isSpeaker;
        }
        await this.broadcastMediaState();
        // If both are speakers, offerer = smaller peerId.
        if (this.isSpeaker && msg.isSpeaker) {
          const iAmOfferer = this.myPeerId < msg.peerId;
          if (!this.peers.has(msg.peerId)) {
            await this.createPeerConnection(
              msg.peerId,
              msg.userId,
              msg.name,
              msg.isSpeaker,
              iAmOfferer,
            );
          }
        } else if (this.isSpeaker && !msg.isSpeaker) {
          // I'm a speaker, they're a listener — I must create a PC and send
          // an offer so they can receive my audio/video. Without this, the
          // listener creates a PC in their 'join' handler but never receives
          // an offer because I never created a PC to send one from.
          if (!this.peers.has(msg.peerId)) {
            await this.createPeerConnection(
              msg.peerId,
              msg.userId,
              msg.name,
              msg.isSpeaker,
              true, // I'm the offerer (speaker → listener)
            );
          }
        }
        // If I'm a listener and they're a speaker, the 'join' handler already
        // created a PC as answerer — no action needed here.
        break;
      }
      case "offer": {
        await this.handleOffer(msg.from, msg.sdp);
        break;
      }
      case "answer": {
        await this.handleAnswer(msg.from, msg.sdp);
        break;
      }
      case "ice": {
        await this.handleIce(msg.from, msg.candidate);
        break;
      }
      case "leave": {
        this.forgetParticipant(msg.peerId);
        break;
      }
      case "became-speaker": {
        this.evictStaleSessions(msg.userId, msg.peerId);
        // Update known peer status.
        const known = this.knownPeers.get(msg.peerId);
        if (known) known.isSpeaker = true;
        else
          this.knownPeers.set(msg.peerId, {
            peerId: msg.peerId,
            userId: msg.userId,
            name: msg.name,
            isSpeaker: true,
          });

        const peer = this.peers.get(msg.peerId);
        if (peer) {
          // Existing PC — renegotiate. Either side may offer; glare handling
          // keeps simultaneous offers safe, so promotion never hinges on one
          // fragile message.
          peer.isSpeaker = true;
          this.requestNegotiation(peer);
        } else if (this.isSpeaker) {
          // I'm a speaker, no PC yet — create one (offerer = smaller peerId).
          const iAmOfferer = this.myPeerId < msg.peerId;
          await this.createPeerConnection(
            msg.peerId,
            msg.userId,
            msg.name,
            true,
            iAmOfferer,
          );
        } else {
          // I'm a listener, no PC yet — create one as answerer, wait for offer.
          await this.createPeerConnection(
            msg.peerId,
            msg.userId,
            msg.name,
            true,
            false,
          );
        }
        break;
      }
      case "reneg": {
        // The other side's negotiation stalled — send a fresh ICE-restart
        // offer. If we somehow have no connection for them, build one.
        const peer = this.peers.get(msg.from);
        if (peer) {
          await this.createOffer(peer, { iceRestart: true });
        } else {
          const known = this.knownPeers.get(msg.from);
          if (known && (this.isSpeaker || known.isSpeaker)) {
            await this.createPeerConnection(
              msg.from,
              known.userId,
              known.name,
              known.isSpeaker,
              true,
            );
          }
        }
        break;
      }
      case "reset": {
        // The other side rebuilt our pair from scratch — mirror it so both
        // ends restart negotiation cleanly.
        const known = this.knownPeers.get(msg.from);
        const old = this.peers.get(msg.from);
        const theirIsSpeaker = old?.isSpeaker ?? known?.isSpeaker ?? true;
        const resetUserId = old?.userId ?? known?.userId ?? "";
        const resetName = old?.name ?? known?.name ?? "";
        // Keep a relay-only choice across the other side's reset — they're
        // resetting because the pair is broken, not because relay worked.
        const keepRelay = old?.relayOnly ?? false;
        this.removePeer(msg.from);
        if (this.isSpeaker || theirIsSpeaker) {
          await this.createPeerConnection(
            msg.from,
            resetUserId,
            resetName,
            theirIsSpeaker,
            this.amOffererTo(msg.from, theirIsSpeaker),
            { relayOnly: keepRelay },
          );
        }
        break;
      }
      case "track-update": {
        const peer = this.peers.get(msg.from);
        if (peer) {
          peer.micOn = msg.hasAudio;
          peer.hasVideo = msg.hasVideo;
          if (!msg.hasAudio) {
            peer.speakingUntil = 0;
            peer.isSpeaking = false;
          }
        }
        this.notifyParticipants();
        break;
      }
      case "mic-toggle": {
        const peer = this.peers.get(msg.from);
        if (peer) {
          peer.micOn = msg.isOn;
          if (!msg.isOn) {
            peer.speakingUntil = 0;
            peer.isSpeaking = false;
          }
        }
        this.notifyParticipants();
        break;
      }
      case "screen-share": {
        if (msg.isOn) this.screenSharingPeers.add(msg.from);
        else this.screenSharingPeers.delete(msg.from);
        this.notifyParticipants();
        break;
      }
      case "reaction": {
        // Reactions arrive via the signaling channel so iOS and web share
        // the same reaction stream (no separate channel needed).
        this.onReaction?.(msg.emoji);
        break;
      }
      case "app-event": {
        this.onAppEvent?.(msg.event, msg.data, msg.from);
        break;
      }
    }
  }

  /**
   * Drop any lingering session for a user who just (re)announced themselves
   * under a new peerId. Without this, a refresh/rejoin leaves the old dead
   * connection on everyone's stage for up to ~20s (missed "leave" + ICE
   * grace), which reads as "they rejoined but have no video/audio".
   */
  private evictStaleSessions(userId: string, freshPeerId: string): void {
    if (!userId) return;
    for (const [peerId, known] of Array.from(this.knownPeers.entries())) {
      if (peerId !== freshPeerId && known.userId === userId) {
        this.forgetParticipant(peerId);
      }
    }
    for (const [peerId, peer] of Array.from(this.peers.entries())) {
      if (peerId !== freshPeerId && peer.userId === userId) {
        this.removePeer(peerId);
      }
    }
  }

  // ─── Peer connection management ─────────────────────────────────────────────

  private async createPeerConnection(
    peerId: string,
    userId: string,
    name: string,
    isSpeaker: boolean,
    iAmOfferer: boolean,
    opts: { relayOnly?: boolean } = {},
  ): Promise<void> {
    if (this.hasLeft || this.peers.has(peerId)) return;

    const relayOnly = opts.relayOnly === true && this.hasTurn();
    const pc = this.newPeerConnection(relayOnly);
    const remoteStream = new MediaStream();

    // Add my local tracks if I'm a speaker, then fill the gaps: any kind we
    // don't send becomes a recvonly transceiver so we still RECEIVE it and
    // Safari still generates ICE candidates. This keeps a mic-only or
    // camera-only speaker fully functional (the old all-or-nothing path
    // produced offers with missing m-lines when a device failed).
    const sendingKinds = new Set<string>();
    if (this.isSpeaker && this.localStream) {
      for (const track of this.localStream.getTracks()) {
        if (track.readyState !== "live") continue;
        pc.addTrack(track, this.localStream);
        sendingKinds.add(track.kind);
      }
    }
    if (this.dummyAudioTrack && !sendingKinds.has("audio")) {
      // Silent dummy audio (Safari receive-only workaround).
      pc.addTrack(this.dummyAudioTrack, new MediaStream([this.dummyAudioTrack]));
      sendingKinds.add("audio");
    }
    for (const kind of ["audio", "video"] as const) {
      if (sendingKinds.has(kind)) continue;
      try {
        pc.addTransceiver(kind, { direction: "recvonly" });
      } catch {
        // Some browsers may not support addTransceiver — the legacy
        // offerToReceive fallback in createOffer handles those.
      }
    }

    // Remote tracks → remote stream.
    pc.ontrack = (event) => {
      if (this.hasLeft || this.peers.get(peerId) !== entry) return;
      if (!remoteStream.getTracks().includes(event.track)) remoteStream.addTrack(event.track);
      const stream = event.streams[0] ?? remoteStream;
      for (const track of stream.getTracks()) {
        if (!remoteStream.getTracks().includes(track)) {
          remoteStream.addTrack(track);
        }
      }
      // Create a fresh MediaStream with all current tracks so the React
      // side sees a new object reference and re-attaches the video element.
      // Without this, renegotiation (e.g. listener→speaker) adds tracks to
      // the existing stream but the useEffect dependency doesn't change,
      // so the video never shows.
      const freshStream = new MediaStream(remoteStream.getTracks());
      entry.remoteStream = freshStream;
      this.onRemoteStream?.(peerId, freshStream);
      this.notifyParticipants();
    };

    // Trickle ICE (confirmed sends — lost candidates stall connectivity).
    pc.onicecandidate = (event) => {
      if (event.candidate) {
        void this.sendSignal(
          {
            type: "ice",
            from: this.myPeerId,
            to: peerId,
            candidate: event.candidate.toJSON(),
          },
          2,
        );
      }
    };

    const entry: PeerEntry = {
      pc,
      peerId,
      userId,
      name,
      isSpeaker,
      isOfferer: iAmOfferer,
      remoteStream,
      micOn: isSpeaker,
      hasVideo: isSpeaker,
      speakingUntil: 0,
      isSpeaking: false,
      makingOffer: false,
      queuedNegotiation: false,
      negotiationReady: false,
      attempts: 0,
      lastProgressAt: Date.now(),
      everConnected: false,
      relayOnly,
      via: null,
    };
    this.wirePeerHealing(entry);
    this.peers.set(peerId, entry);
    this.notifyParticipants();

    if (iAmOfferer) {
      await this.createOffer(entry);
    }
  }

  /** True when the current ICE list carries TURN relay servers. */
  private hasTurn(): boolean {
    return this.iceServers.some((server) => {
      const urls = Array.isArray(server.urls) ? server.urls : [server.urls];
      return urls.some((u) => /^turns?:/i.test(u));
    });
  }

  /**
   * One place that builds RTCPeerConnections. `relayOnly` forces every
   * candidate through TURN — the escape hatch for the phone-on-cellular ↔
   * desktop pairs whose host/STUN candidates never complete a check.
   */
  private newPeerConnection(relayOnly: boolean): RTCPeerConnection {
    const config: RTCConfiguration = { iceServers: this.iceServers };
    if (relayOnly) config.iceTransportPolicy = "relay";
    return new RTCPeerConnection(config);
  }

  /** Read the selected candidate pair once and remember relay vs direct. */
  private async recordConnectionPath(entry: PeerEntry): Promise<void> {
    try {
      const stats = await entry.pc.getStats();
      let selected: RTCIceCandidatePairStats | null = null;
      const locals = new Map<string, { candidateType?: string }>();
      stats.forEach((report) => {
        const r = report as RTCStats & Record<string, unknown>;
        if (r.type === "candidate-pair") {
          const pair = r as unknown as RTCIceCandidatePairStats & { selected?: boolean };
          if (pair.state === "succeeded" && (pair.nominated || pair.selected)) selected = pair;
        } else if (r.type === "local-candidate") {
          locals.set(r.id, { candidateType: r.candidateType as string | undefined });
        }
      });
      const pair = selected as (RTCIceCandidatePairStats & { localCandidateId: string }) | null;
      if (!pair) return;
      const local = locals.get(pair.localCandidateId);
      const via: "relay" | "direct" = local?.candidateType === "relay" ? "relay" : "direct";
      if (entry.via !== via) {
        entry.via = via;
        console.info(
          `[WhisperLiveRTC] ${entry.name || entry.peerId} connected via ${via}${entry.relayOnly ? " (relay-only pair)" : ""}`,
        );
        this.notifyParticipants();
      }
    } catch {
      /* stats unavailable — diagnostics only */
    }
  }

  private async createOffer(
    peer: PeerEntry,
    opts: { iceRestart?: boolean } = {},
  ): Promise<void> {
    if (peer.makingOffer) {
      peer.queuedNegotiation = true;
      return;
    }
    if (peer.pc.signalingState !== "stable" && !opts.iceRestart) {
      peer.queuedNegotiation = true;
      return;
    }
    peer.makingOffer = true;
    try {
      // Use empty constraints — addTransceiver (added in
      // createPeerConnection) handles recvonly direction for listeners.
      // The legacy offerToReceiveAudio/Video options break Safari's m-sections
      // (WebKit bug 230000) so we avoid them entirely.
      const offer = await peer.pc.createOffer(
        opts.iceRestart ? { iceRestart: true } : undefined,
      );
      // A remote offer can land between createOffer and setLocalDescription —
      // let the glare handling in handleOffer win and re-queue ours.
      if (
        peer.pc.signalingState !== "stable" &&
        peer.pc.signalingState !== "have-local-offer"
      ) {
        peer.queuedNegotiation = true;
        return;
      }
      await peer.pc.setLocalDescription(offer);
      peer.lastProgressAt = Date.now();
      const delivered = await this.sendSignal({
        type: "offer",
        from: this.myPeerId,
        to: peer.peerId,
        sdp: offer,
      });
      if (!delivered) peer.queuedNegotiation = true;
    } catch (err) {
      console.warn("[WhisperLiveRTC] createOffer failed:", err);
    } finally {
      peer.makingOffer = false;
    }
  }

  private async handleOffer(fromPeerId: string, sdp: RTCSessionDescriptionInit): Promise<void> {
    if (this.hasLeft) return;
    let peer = this.peers.get(fromPeerId);
    if (!peer) {
      // Create PC as answerer.
      const pc = this.newPeerConnection(false);
      const remoteStream = new MediaStream();

      if (this.isSpeaker && this.localStream) {
        for (const track of this.localStream.getTracks()) {
          pc.addTrack(track, this.localStream);
        }
      } else {
        // Listener receiving an offer — DON'T add recvonly transceivers here.
        // The offer's m-lines already define the transceivers; adding extra
        // ones before setRemoteDescription creates duplicate m-lines that
        // break SDP negotiation on Safari/Firefox. The dummy audio track
        // (Safari workaround) is added AFTER setRemoteDescription below so
        // it associates with the transceiver created by the offer.
      }

      pc.ontrack = (event) => {
        if (this.hasLeft || this.peers.get(fromPeerId) !== peer) return;
        if (!remoteStream.getTracks().includes(event.track)) remoteStream.addTrack(event.track);
        const stream = event.streams[0] ?? remoteStream;
        for (const track of stream.getTracks()) {
          if (!remoteStream.getTracks().includes(track)) {
            remoteStream.addTrack(track);
          }
        }
        // Fresh stream reference so React re-attaches the video element.
        const freshStream = new MediaStream(remoteStream.getTracks());
        peer.remoteStream = freshStream;
        this.onRemoteStream?.(fromPeerId, freshStream);
        this.notifyParticipants();
      };

      pc.onicecandidate = (event) => {
        if (event.candidate) {
          void this.sendSignal(
            {
              type: "ice",
              from: this.myPeerId,
              to: fromPeerId,
              candidate: event.candidate.toJSON(),
            },
            2,
          );
        }
      };

      const known = this.knownPeers.get(fromPeerId);
      peer = {
        pc,
        peerId: fromPeerId,
        userId: known?.userId ?? "",
        name: known?.name ?? "",
        isSpeaker: true,
        isOfferer: false,
        remoteStream,
        micOn: true,
        hasVideo: true,
        speakingUntil: 0,
        isSpeaking: false,
        makingOffer: false,
        queuedNegotiation: false,
        negotiationReady: false,
        attempts: 0,
        lastProgressAt: Date.now(),
        everConnected: false,
        relayOnly: false,
        via: null,
      };
      this.wirePeerHealing(peer);
      this.peers.set(fromPeerId, peer);
      this.notifyParticipants();
    }

    try {
      // Glare protection (perfect negotiation): if we already sent our own
      // offer, the rightful offerer is the smaller peerId. The rightful
      // offerer IGNORES the incoming offer (the other side answers ours);
      // the polite side ROLLS BACK its local offer and answers instead.
      if (peer.pc.signalingState === "have-local-offer") {
        if (this.myPeerId < fromPeerId) {
          return; // impolite — our offer wins, drop theirs
        }
        try {
          await peer.pc.setLocalDescription({ type: "rollback" });
        } catch {
          if (this.hasLeft || this.peers.get(fromPeerId) !== peer) return;
          // Rollback unsupported (legacy engines) — rebuild as answerer and
          // apply the offer on a fresh connection instead of deadlocking.
          this.removePeer(fromPeerId);
          await this.handleOffer(fromPeerId, sdp);
          return;
        }
      }
      if (this.hasLeft || this.peers.get(fromPeerId) !== peer) return;
      await peer.pc.setRemoteDescription(new RTCSessionDescription(sdp));
      if (this.hasLeft || this.peers.get(fromPeerId) !== peer) return;
      // Safari workaround: add the silent dummy audio track AFTER
      // setRemoteDescription so it fills the audio transceiver created by
      // the offer (no extra m-line).
      if (!this.isSpeaker && this.dummyAudioTrack) {
        try { peer.pc.addTrack(this.dummyAudioTrack, new MediaStream([this.dummyAudioTrack])); } catch { /* ignore */ }
      }
      // Flush any ICE candidates that were buffered before the PC existed.
      await this.flushPendingIce(fromPeerId);
      // Create answer — no legacy offerToReceive options. Transceivers
      // are already set by setRemoteDescription.
      if (this.hasLeft || this.peers.get(fromPeerId) !== peer) return;
      const answer = await peer.pc.createAnswer();
      if (this.hasLeft || this.peers.get(fromPeerId) !== peer) return;
      await peer.pc.setLocalDescription(answer);
      if (this.hasLeft || this.peers.get(fromPeerId) !== peer) return;
      peer.negotiationReady = true;
      peer.lastProgressAt = Date.now();
      await this.sendSignal({
        type: "answer",
        from: this.myPeerId,
        to: fromPeerId,
        sdp: answer,
      });
      // A glare rollback can orphan local tracks that were mid-renegotiation
      // (the exact "I could see them but couldn't hear them" bug) — verify
      // everything local is on the wire and follow up with an offer if not.
      this.ensureLocalTracksSent(peer);
    } catch (err) {
      console.warn("[WhisperLiveRTC] handleOffer failed:", err);
    }
  }

  private async handleAnswer(fromPeerId: string, sdp: RTCSessionDescriptionInit): Promise<void> {
    const peer = this.peers.get(fromPeerId);
    if (!peer) return;
    // Stale/duplicate answer (e.g. the pair was rebuilt while it was in
    // flight) — applying it in the wrong state throws. Ignore it; the health
    // sweep re-offers when negotiation is genuinely stuck.
    if (peer.pc.signalingState !== "have-local-offer") return;
    try {
      await peer.pc.setRemoteDescription(new RTCSessionDescription(sdp));
      peer.negotiationReady = true;
      peer.lastProgressAt = Date.now();
      // Flush buffered ICE candidates now that remote description is set.
      await this.flushPendingIce(fromPeerId);
      this.ensureLocalTracksSent(peer);
    } catch (err) {
      console.warn("[WhisperLiveRTC] handleAnswer failed:", err);
    }
  }

  private async handleIce(fromPeerId: string, candidate: RTCIceCandidateInit): Promise<void> {
    const peer = this.peers.get(fromPeerId);
    // PC doesn't exist yet — buffer the candidate. This happens when ICE
    // arrives before the offer (common with Supabase Realtime ordering).
    if (!peer) {
      this.pendingIce.set(fromPeerId, [...(this.pendingIce.get(fromPeerId) ?? []), candidate]);
      return;
    }
    // Remote description not set yet — buffer until setRemoteDescription.
    if (!peer.pc.remoteDescription) {
      this.pendingIce.set(fromPeerId, [...(this.pendingIce.get(fromPeerId) ?? []), candidate]);
      return;
    }
    try {
      await peer.pc.addIceCandidate(new RTCIceCandidate(candidate));
    } catch {
      // ICE errors are common during connection teardown — ignore.
    }
  }

  /** Flush buffered ICE candidates for a peer after setRemoteDescription. */
  private async flushPendingIce(peerId: string): Promise<void> {
    const candidates = this.pendingIce.get(peerId);
    if (!candidates || candidates.length === 0) return;
    this.pendingIce.delete(peerId);
    const peer = this.peers.get(peerId);
    if (!peer) return;
    for (const candidate of candidates) {
      try {
        await peer.pc.addIceCandidate(new RTCIceCandidate(candidate));
      } catch {
        // Ignore — stale or duplicate.
      }
    }
  }

  // ─── Connection healing ─────────────────────────────────────────────────────

  /** True when the local side should create offers toward this peer. */
  private amOffererTo(peerId: string, theirIsSpeaker: boolean): boolean {
    if (this.isSpeaker && theirIsSpeaker) return this.myPeerId < peerId;
    return this.isSpeaker;
  }

  /** Wire self-healing handlers onto a freshly created peer connection. */
  private wirePeerHealing(entry: PeerEntry): void {
    const { pc, peerId } = entry;

    // Renegotiate after the initial handshake (track added, glare rollback
    // re-fired, transceiver direction change). Gated so the FIRST offer stays
    // owned by the designated offerer — keeps cross-platform startup stable.
    pc.onnegotiationneeded = () => {
      if (!entry.negotiationReady || entry.makingOffer) return;
      if (pc.signalingState !== "stable") {
        entry.queuedNegotiation = true;
        return;
      }
      void this.createOffer(entry);
    };

    // Drain renegotiations that queued while an offer/answer was in flight.
    pc.onsignalingstatechange = () => {
      if (pc.signalingState !== "stable") return;
      entry.lastProgressAt = Date.now();
      if (entry.queuedNegotiation && !entry.makingOffer) {
        entry.queuedNegotiation = false;
        void this.createOffer(entry);
      }
    };

    pc.oniceconnectionstatechange = () => {
      const state = pc.iceConnectionState;
      if (state === "checking" || state === "connected" || state === "completed") {
        entry.lastProgressAt = Date.now();
      }
      if (state === "failed") void this.recoverPeer(entry, "ice-failed");
    };

    pc.onconnectionstatechange = () => {
      if (pc.connectionState === "connected") {
        entry.attempts = 0;
        entry.negotiationReady = true;
        entry.everConnected = true;
        entry.lastProgressAt = Date.now();
        void this.recordConnectionPath(entry);
        const timer = this.disconnectTimers.get(peerId);
        if (timer) {
          clearTimeout(timer);
          this.disconnectTimers.delete(peerId);
        }
        this.ensureLocalTracksSent(entry);
        this.notifyParticipants();
        return;
      }
      if (pc.connectionState === "failed") {
        void this.recoverPeer(entry, "failed");
        this.notifyParticipants();
        return;
      }
      if (pc.connectionState === "disconnected") {
        // Brief ICE blips fire "disconnected" — grace period, then HEAL
        // instead of removing (removal forced everyone to rejoin manually).
        if (this.disconnectTimers.has(peerId)) return;
        this.disconnectTimers.set(
          peerId,
          setTimeout(() => {
            this.disconnectTimers.delete(peerId);
            const current = this.peers.get(peerId);
            if (current === entry && pc.connectionState !== "connected") {
              void this.recoverPeer(entry, "disconnected");
            }
          }, 8000),
        );
        this.notifyParticipants();
      }
    };
  }

  /** Renegotiate now when possible, otherwise queue for when stable. */
  private requestNegotiation(peer: PeerEntry): void {
    if (peer.makingOffer || peer.pc.signalingState !== "stable") {
      peer.queuedNegotiation = true;
      return;
    }
    void this.createOffer(peer);
  }

  /**
   * Verify every live local track is attached to this connection, attach the
   * missing ones, and renegotiate when required. Catches tracks orphaned by
   * glare rollbacks or lost renegotiation offers — the root cause of
   * "I could see them but couldn't hear them" one-way media.
   */
  private ensureLocalTracksSent(peer: PeerEntry): void {
    if (!this.isSpeaker || !this.localStream) return;
    const stream = this.localStream;
    let needsOffer = false;
    for (const track of stream.getTracks()) {
      if (track.readyState !== "live") continue;
      // All video replacement paths share the same queue, including health recovery.
      if (track.kind === "video") { void this.publishTrack(track).catch(() => undefined); continue; }
      const senders = peer.pc.getSenders();
      if (senders.some((s) => s.track === track)) continue;
      const kindSender = senders.find((s) => s.track?.kind === track.kind);
      if (kindSender) {
        // A sender exists but carries a stale/other track — swap in place.
        void kindSender.replaceTrack(track).catch(() => undefined);
        continue;
      }
      const transceiver = peer.pc
        .getTransceivers()
        .find(
          (t) =>
            t.currentDirection !== "stopped" &&
            t.receiver.track?.kind === track.kind &&
            !t.sender.track,
        );
      if (transceiver) {
        void transceiver.sender.replaceTrack(track).catch(() => undefined);
        try {
          transceiver.sender.setStreams?.(stream);
          transceiver.direction = "sendrecv";
        } catch {
          /* older browsers */
        }
        needsOffer = true;
        continue;
      }
      try {
        peer.pc.addTrack(track, stream);
        needsOffer = true;
      } catch {
        /* already attached */
      }
    }
    if (needsOffer) this.requestNegotiation(peer);
  }

  /**
   * Escalating recovery for a broken pair:
   *   1. ICE restart (offerer re-offers; answerer requests one via "reneg")
   *   2+. full rebuild on both ends via "reset"
   *   5.  give up — remove the tile (their rejoin recreates everything).
   */
  private async recoverPeer(entry: PeerEntry, reason: string): Promise<void> {
    if (this.hasLeft || this.peers.get(entry.peerId) !== entry || this.recoveringPeers.has(entry)) return;
    this.recoveringPeers.add(entry);
    try {
    entry.attempts += 1;
    entry.lastProgressAt = Date.now();
    console.warn(
      `[WhisperLiveRTC] healing peer ${entry.peerId} (${reason}) — attempt ${entry.attempts}`,
    );
    if (entry.attempts > 4) {
      this.forgetParticipant(entry.peerId, false);
      this.onError?.(
        `Couldn't reconnect to ${entry.name || "a participant"} — they may have lost network.`,
      );
      return;
    }
    // Recovery must gather with FRESH relay credentials — anything older
    // than 45s gets refetched and applied to the live pc before restart.
    await this.ensureIceServers(45_000);
    if (this.hasLeft || this.peers.get(entry.peerId) !== entry || entry.pc.connectionState === "connected") return;
    this.notifyParticipants();
    if (entry.attempts === 1) {
      if (entry.isOfferer || entry.negotiationReady) {
        try {
          entry.pc.restartIce();
        } catch {
          /* optional API */
        }
        await this.createOffer(entry, { iceRestart: true });
      } else {
        // Answerer that never completed negotiation — ask for a fresh offer.
        await this.sendSignal({ type: "reneg", from: this.myPeerId, to: entry.peerId });
      }
      return;
    }
    // Attempt 2+: rebuild the pair from scratch on both ends. A pair that
    // NEVER connected on "all" gets rebuilt TURN-only from here — phones on
    // carrier NATs regularly leave host/STUN checks spinning forever while a
    // relayed path would have connected in a second.
    const relayOnly = !entry.everConnected && this.hasTurn();
    if (relayOnly) {
      console.warn(
        `[WhisperLiveRTC] ${entry.name || entry.peerId}: direct pairs never completed — rebuilding relay-only`,
      );
    }
    await this.sendSignal({ type: "reset", from: this.myPeerId, to: entry.peerId });
    if (this.hasLeft || this.peers.get(entry.peerId) !== entry) return;
    await this.rebuildPeer(entry.peerId, entry.attempts, relayOnly);
    } finally { this.recoveringPeers.delete(entry); }
  }

  /** Tear down and recreate a pair, preserving identity and roles. */
  private async rebuildPeer(
    peerId: string,
    attempts: number,
    relayOnly: boolean = false,
  ): Promise<void> {
    const known = this.knownPeers.get(peerId);
    const old = this.peers.get(peerId);
    if (!known && !old) return;
    const name = old?.name ?? known?.name ?? "";
    const userId = old?.userId ?? known?.userId ?? "";
    const theirIsSpeaker = old?.isSpeaker ?? known?.isSpeaker ?? true;
    this.removePeer(peerId);
    if (!this.isSpeaker && !theirIsSpeaker) return;
    // Roles are normally preserved; from the 3rd attempt the answerer forces
    // itself to offer so the pair converges even when the other side never
    // received the reset (older app builds). Glare handling keeps it safe.
    const offerer = this.amOffererTo(peerId, theirIsSpeaker) || attempts >= 3;
    await this.createPeerConnection(peerId, userId, name, theirIsSpeaker, offerer, {
      relayOnly: relayOnly || (old?.relayOnly ?? false),
    });
    const fresh = this.peers.get(peerId);
    if (fresh) fresh.attempts = attempts;
  }

  /**
   * OS-level network switch (wifi→cellular, VPN toggle, waking from sleep).
   * Restart ICE on every pair immediately with fresh TURN credentials —
   * WebRTC's own timers take 5-15s to notice the old path died.
   */
  private async handleNetworkChange(reason: string): Promise<void> {
    if (!this.channel) return;
    const now = Date.now();
    if (now - this.lastNetworkRestartAt < 4000) return;
    this.lastNetworkRestartAt = now;
    console.warn(
      `[WhisperLiveRTC] network change (${reason}) — restarting ICE on ${this.peers.size} pair(s)`,
    );
    await this.ensureIceServers(0);
    for (const entry of this.peers.values()) {
      entry.attempts = 0;
      entry.lastProgressAt = Date.now();
      if (entry.isOfferer || entry.negotiationReady) {
        try {
          entry.pc.restartIce();
        } catch {
          /* optional API */
        }
        void this.createOffer(entry, { iceRestart: true });
      } else {
        // Answerer that never negotiated — ask the other side to re-offer.
        void this.sendSignal({ type: "reneg", from: this.myPeerId, to: entry.peerId });
      }
    }
    this.sweepConnections();
  }

  /** Start the connection health sweep (checks every 5 s). */
  private startHealthMonitor(): void {
    this.stopHealthMonitor();
    this.healthMonitor = setInterval(() => {
      this.sweepConnections();
    }, 5000);
  }

  private stopHealthMonitor(): void {
    if (this.healthMonitor) clearInterval(this.healthMonitor);
    this.healthMonitor = null;
  }

  /**
   * Find and heal broken pairs:
   *  - known peers we should be connected to but aren't (missed join/offer
   *    races) get a fresh connection;
   *  - pairs stuck outside "connected" with no negotiation progress for 9 s
   *    enter the recovery ladder.
   */
  private sweepConnections(): void {
    if (!this.channel) return;
    // Keep TURN credentials fresh proactively (no-op until near expiry) so
    // new pairs and ICE restarts never gather with stale relay creds.
    void this.ensureIceServers();
    // A hidden page (a phone showing the permission sheet, an app switch)
    // throttles timers and stalls ICE on its own — recovering pairs from
    // there only churns; the visibility handler sweeps the moment we return.
    if (typeof document !== "undefined" && document.hidden) return;
    const now = Date.now();
    for (const [peerId, known] of this.knownPeers) {
      if (this.peers.has(peerId)) continue;
      if (!this.isSpeaker && !known.isSpeaker) continue;
      void this.createPeerConnection(
        peerId,
        known.userId,
        known.name,
        known.isSpeaker,
        this.amOffererTo(peerId, known.isSpeaker),
      );
    }
    for (const entry of this.peers.values()) {
      if (entry.pc.connectionState === "connected") continue;
      // First connection gets a real chance — TURN allocation + ICE checks
      // over cellular routinely run past 10 s, and restarting ICE mid-
      // handshake was tearing down pairs that were about to connect.
      // Reconnects of a pair that already worked can be quicker.
      const stallMs = entry.everConnected ? 12_000 : 20_000;
      if (now - entry.lastProgressAt < stallMs) continue;
      void this.recoverPeer(entry, `stuck-${entry.pc.connectionState}`);
    }
  }

  /** Remove membership and media together; pair rebuilds retain membership. */
  forgetParticipant(peerId: string, retire = true): void {
    if (!peerId || peerId === this.myPeerId) return;
    if (retire) this.retiredPeerIds.add(peerId);
    this.knownPeers.delete(peerId);
    this.screenSharingPeers.delete(peerId);
    this.removePeer(peerId);
    this.notifyParticipants();
  }

  private async broadcastMediaState(): Promise<void> {
    await this.broadcast({ type: "screen-share", from: this.myPeerId, isOn: this.screenSharing });
    await this.broadcast({ type: "track-update", from: this.myPeerId,
      hasAudio: this.micOn, hasVideo: this.cameraOn || this.screenSharing });
  }

  private removePeer(peerId: string): void {
    const timer = this.disconnectTimers.get(peerId);
    if (timer) { clearTimeout(timer); this.disconnectTimers.delete(peerId); }
    const peer = this.peers.get(peerId);
    if (!peer) return;
    this.peers.delete(peerId);
    peer.pc.onconnectionstatechange = null;
    peer.pc.oniceconnectionstatechange = null;
    peer.pc.ontrack = null;
    try {
      peer.pc.close();
    } catch {
      /* already closed */
    }
    this.pendingIce.delete(peerId);
    this.notifyParticipants();
  }

  // ─── Speaker activity + participant tracking ────────────────────────────────

  private startSpeakerMonitor(): void {
    this.stopSpeakerMonitor();
    this.speakerMonitor = setInterval(() => {
      void this.refreshSpeakerActivity();
    }, 400);
    void this.refreshSpeakerActivity();
  }

  private stopSpeakerMonitor(): void {
    if (this.speakerMonitor) clearInterval(this.speakerMonitor);
    this.speakerMonitor = null;
    this.speakerStatsInFlight = false;
  }

  /** Uses WebRTC's remote inbound audio level without touching playback audio. */
  private async refreshSpeakerActivity(): Promise<void> {
    if (this.speakerStatsInFlight || this.peers.size === 0) return;
    this.speakerStatsInFlight = true;
    const now = Date.now();

    try {
      const levels = await Promise.all(
        Array.from(this.peers.entries()).map(async ([peerId, peer]) => {
          try {
            const report = await peer.pc.getStats();
            let level = 0;
            let localLevel = -1;
            report.forEach((stat) => {
              const item = stat as unknown as {
                type?: string;
                kind?: string;
                mediaType?: string;
                audioLevel?: number;
              };
              const kind = item.kind ?? item.mediaType;
              if (item.type === "inbound-rtp" && kind === "audio" && typeof item.audioLevel === "number") {
                level = Math.max(level, item.audioLevel);
              }
              // The same report carries OUR capture level (media-source) —
              // free input for the outgoing-mic silence watchdog.
              if (item.type === "media-source" && kind === "audio" && typeof item.audioLevel === "number") {
                localLevel = Math.max(localLevel, item.audioLevel);
              }
            });
            const connected = peer.pc.connectionState === "connected";
            return { peerId, level, localLevel, connected };
          } catch {
            return { peerId, level: 0, localLevel: -1, connected: false };
          }
        }),
      );

      let didChange = false;
      let outboundLevel = -1;
      for (const sample of levels) {
        if (sample.connected && sample.localLevel >= 0) {
          outboundLevel = Math.max(outboundLevel, sample.localLevel);
        }
        const peer = this.peers.get(sample.peerId);
        if (!peer) continue;
        const wasSpeaking = peer.isSpeaking;
        if (peer.micOn && sample.level >= 0.018) {
          peer.speakingUntil = now + 900;
        }
        const isSpeaking = peer.micOn && peer.speakingUntil > now;
        peer.isSpeaking = isSpeaking;
        if (wasSpeaking !== isSpeaking) didChange = true;
      }
      this.watchOutgoingMic(outboundLevel);
      if (didChange) this.notifyParticipants();
    } finally {
      this.speakerStatsInFlight = false;
    }
  }

  /**
   * Outgoing-mic silence watchdog. media-source audioLevel is what the
   * browser is CAPTURING from the mic — a healthy mic never sits at digital
   * zero (room noise keeps a floor). Flat zero for ~8s with the mic ON means
   * the capture is dead (OS-muted input, device stolen by another app,
   * driver drop): reacquire once automatically, then tell the user honestly
   * if it's still silent. Runs on the 400ms speaker-stats cadence.
   */
  private watchOutgoingMic(level: number): void {
    if (
      !this.isSpeaker ||
      !this.micOn ||
      this.auxMixTrack != null ||
      this.micRecoveryInFlight ||
      level < 0 // no connected pair reported media-source stats
    ) {
      this.micSilentSamples = 0;
      return;
    }
    const track = this.liveTrack("audio");
    if (!track || !track.enabled) {
      this.micSilentSamples = 0;
      return;
    }
    if (level > 0.0002) {
      this.micSilentSamples = 0;
      return;
    }
    this.micSilentSamples += 1;
    if (this.micSilentSamples === 20 && !this.micRecoveryAttempted) {
      this.micRecoveryAttempted = true;
      if (isMobileWebKit()) {
        // A fresh getUserMedia mid-call on an iPhone browser replaces the
        // ONE capture session — the camera track dies with it. Never
        // auto-reacquire here; the honest warning below still fires.
        console.warn("[WhisperLiveRTC] outgoing mic is flat-silent — skipping auto-reacquire on mobile WebKit");
        return;
      }
      this.micRecoveryInFlight = true;
      console.warn("[WhisperLiveRTC] outgoing mic is flat-silent — reacquiring the microphone");
      void (async () => {
        try {
          const mic = await this.acquireMedia({ audio: preferredAudioConstraints() });
          const fresh = mic.getAudioTracks()[0] ?? null;
          if (fresh) {
            const old = this.liveTrack("audio");
            if (old && old !== fresh) {
              this.localStream?.removeTrack(old);
              old.stop();
            }
            this.adoptTracks([fresh]);
            fresh.enabled = this.micOn;
            await this.publishTrack(this.liveTrack("audio") ?? fresh);
            this.notifyParticipants();
          }
        } catch (err) {
          console.warn("[WhisperLiveRTC] mic reacquire failed:", err);
        } finally {
          this.micRecoveryInFlight = false;
          this.micSilentSamples = 0;
        }
      })();
      return;
    }
    if (this.micSilentSamples >= 45 && !this.micSilenceWarned) {
      // ~18s of dead capture even after the automatic recovery — be honest.
      this.micSilenceWarned = true;
      this.onError?.(
        "Your microphone looks silent — others may not hear you. Check the mic selected in your browser's site settings and that it isn't muted at the system level.",
      );
    }
  }

  /** The mic DEVICE died mid-call (unplugged / revoked / stolen by the OS). */
  private handleAudioTrackEnded(track: MediaStreamTrack): void {
    if (!this.micOn || this.micRecoveryInFlight) return;
    if (this.auxMixTrack) return; // the mix owns the wire; toggle re-acquires
    const live = this.liveTrack("audio");
    if (live && live !== track) return; // another mic already live
    console.warn("[WhisperLiveRTC] mic track ended — reacquiring");
    this.micRecoveryInFlight = true;
    void (async () => {
      try {
        const mic = await this.acquireMedia({ audio: preferredAudioConstraints() });
        const fresh = mic.getAudioTracks()[0] ?? null;
        if (fresh) {
          this.localStream?.removeTrack(track);
          this.adoptTracks([fresh]);
          fresh.enabled = this.micOn;
          await this.publishTrack(this.liveTrack("audio") ?? fresh);
          this.notifyParticipants();
        }
      } catch {
        this.onError?.(
          "Your microphone disconnected — plug it back in or tap the mic button to retry.",
        );
      } finally {
        this.micRecoveryInFlight = false;
      }
    })();
  }

  private notifyParticipants(): void {
    const now = Date.now();
    const participants: LiveParticipantInfo[] = Array.from(this.peers.values()).map((p) => ({
      peerId: p.peerId,
      userId: p.userId,
      name: p.name,
      isSpeaker: p.isSpeaker,
      hasAudio: p.remoteStream.getAudioTracks().length > 0,
      // A presenter's screen is video even when their camera flag is off.
      hasVideo:
        (p.hasVideo || this.screenSharingPeers.has(p.peerId)) &&
        p.remoteStream.getVideoTracks().length > 0,
      micOn: p.micOn,
      isScreenSharing: this.screenSharingPeers.has(p.peerId),
      isSpeaking: p.isSpeaking,
      connectionState:
        p.pc.connectionState === "connected"
          ? ("connected" as const)
          : p.attempts > 0 ||
              p.pc.connectionState === "disconnected" ||
              p.pc.connectionState === "failed"
            ? ("reconnecting" as const)
            : ("connecting" as const),
      remoteStream: p.remoteStream,
    }));

    // Add self at the front. The speaker focus stays on remote people so the
    // personal view remains a stable, non-disruptive PIP on mobile. Audio and
    // video reflect ACTUAL live tracks, not just toggle intent, so the UI
    // never renders a camera tile that has no media behind it.
    const selfAudio = this.micOn && this.liveTrack("audio") != null;
    const selfVideo =
      this.screenSharing || (this.cameraOn && this.liveTrack("video") != null);
    participants.unshift({
      peerId: this.myPeerId,
      userId: this.userId,
      name: "You",
      isSpeaker: this.isSpeaker,
      hasAudio: selfAudio,
      hasVideo: selfVideo,
      micOn: selfAudio,
      isScreenSharing: this.screenSharing,
      isSpeaking: false,
      connectionState: "connected",
      remoteStream: this.localStream,
    });

    this.onParticipantUpdate?.(participants);
  }
}
