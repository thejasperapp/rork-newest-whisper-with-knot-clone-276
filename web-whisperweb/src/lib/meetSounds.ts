import { readMeetPrefs } from "@/lib/meetPrefs";

/**
 * Whisper Meet's sound kit — synthesized in WebAudio so it needs no network,
 * no assets, and plays the instant the browser allows audio (the Join click
 * is the user gesture that unlocks it). The grammar is Google Meet's: a soft
 * two-note "someone's here" chime when you land / someone joins, a gentler
 * descending pair when someone leaves, and a resolving three-note ding when
 * the meeting ends.
 */

let ctx: AudioContext | null = null;

function context(): AudioContext | null {
  if (typeof window === "undefined") return null;
  try {
    if (!ctx) {
      const Ctor =
        window.AudioContext ||
        (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!Ctor) return null;
      ctx = new Ctor();
    }
    if (ctx.state === "suspended") void ctx.resume().catch(() => undefined);
    return ctx;
  } catch {
    return null;
  }
}

interface Note {
  /** Frequency in Hz. */
  hz: number;
  /** Start offset from the sequence start, in seconds. */
  at: number;
  /** Decay length in seconds. */
  decay: number;
  /** Peak gain (0–1). */
  gain: number;
}

/**
 * A marimba-ish bell: fundamental + a quiet 2nd + 3rd harmonic, fast attack,
 * exponential decay. Warm and short — never a piercing beep.
 */
function bell(audio: AudioContext, note: Note, start: number): void {
  const t0 = start + note.at;
  const master = audio.createGain();
  master.gain.setValueAtTime(0.0001, t0);
  master.gain.exponentialRampToValueAtTime(note.gain, t0 + 0.012);
  master.gain.exponentialRampToValueAtTime(0.0001, t0 + note.decay);
  master.connect(audio.destination);

  const partials: Array<[number, number]> = [
    [1, 1],
    [2, 0.28],
    [3, 0.1],
  ];
  for (const [ratio, level] of partials) {
    const osc = audio.createOscillator();
    osc.type = "sine";
    osc.frequency.setValueAtTime(note.hz * ratio, t0);
    const g = audio.createGain();
    g.gain.setValueAtTime(level, t0);
    // Upper partials die faster — that's what makes it read as a struck bar.
    if (ratio > 1) g.gain.exponentialRampToValueAtTime(0.0001, t0 + note.decay * 0.45);
    osc.connect(g);
    g.connect(master);
    osc.start(t0);
    osc.stop(t0 + note.decay + 0.05);
  }
}

function play(notes: Note[]): void {
  if (!readMeetPrefs().sounds) return;
  const audio = context();
  if (!audio) return;
  const start = audio.currentTime + 0.02;
  for (const note of notes) bell(audio, note, start);
}

/** You landed in the room / someone joined — Meet's rising two-note chime. */
export function playMeetJoinChime(): void {
  play([
    { hz: 523.25, at: 0, decay: 0.55, gain: 0.16 }, // C5
    { hz: 783.99, at: 0.13, decay: 0.75, gain: 0.15 }, // G5
  ]);
}

/** Someone left — the same pair, falling, a touch softer. */
export function playMeetLeaveChime(): void {
  play([
    { hz: 783.99, at: 0, decay: 0.45, gain: 0.11 }, // G5
    { hz: 523.25, at: 0.13, decay: 0.7, gain: 0.11 }, // C5
  ]);
}

/** The meeting ended (for you or for everyone) — a resolving descent. */
export function playMeetEndDing(): void {
  play([
    { hz: 659.25, at: 0, decay: 0.5, gain: 0.15 }, // E5
    { hz: 523.25, at: 0.16, decay: 0.55, gain: 0.14 }, // C5
    { hz: 392.0, at: 0.34, decay: 1.1, gain: 0.15 }, // G4
  ]);
}

/** A tiny tick for hands / chat arrivals. */
export function playMeetTick(): void {
  play([{ hz: 987.77, at: 0, decay: 0.22, gain: 0.07 }]); // B5
}

/**
 * UI sounds — app-wide micro-feedback (deliberately tiny), NOT gated by the
 * meeting sound preference. Same bell math as the iOS kit, note for note.
 */
function playUI(notes: Note[]): void {
  const audio = context();
  if (!audio) return;
  const start = audio.currentTime + 0.01;
  for (const note of notes) bell(audio, note, start);
}

/** A soft two-note pop when you like something. */
export function playLikeSound(): void {
  playUI([
    { hz: 1046.5, at: 0, decay: 0.14, gain: 0.09 }, // C6
    { hz: 1567.98, at: 0.045, decay: 0.18, gain: 0.07 }, // G6
  ]);
}

/** A tiny low tick the moment a message lifts under a long press. */
export function playPressSound(): void {
  playUI([{ hz: 440, at: 0, decay: 0.08, gain: 0.05 }]); // A4
}

/**
 * Warm the audio context on a user gesture (the Join click) so the first
 * chime is never swallowed by autoplay policy.
 */
export function primeMeetSounds(): void {
  const audio = context();
  if (!audio) return;
  try {
    const buffer = audio.createBuffer(1, 1, 22050);
    const src = audio.createBufferSource();
    src.buffer = buffer;
    src.connect(audio.destination);
    src.start(0);
  } catch {
    /* priming is best-effort */
  }
}
