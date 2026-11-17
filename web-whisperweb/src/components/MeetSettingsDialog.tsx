import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Camera,
  Check,
  Headphones,
  Mic,
  Settings2,
  Volume2,
  X,
} from "lucide-react";

import { cn } from "@/lib/utils";
import { useMeetPrefs, type MeetPrefs } from "@/lib/meetPrefs";

type Tab = "audio" | "video" | "general";

interface DeviceLists {
  mics: MediaDeviceInfo[];
  cams: MediaDeviceInfo[];
  speakers: MediaDeviceInfo[];
}

const EMPTY_DEVICES: DeviceLists = { mics: [], cams: [], speakers: [] };

function labelFor(device: MediaDeviceInfo, index: number, kind: string): string {
  return device.label?.trim() || `${kind} ${index + 1}`;
}

/** True when the browser lets us route output audio to a chosen speaker. */
export function canPickSpeaker(): boolean {
  return (
    typeof HTMLMediaElement !== "undefined" &&
    "setSinkId" in HTMLMediaElement.prototype
  );
}

interface MeetSettingsDialogProps {
  open: boolean;
  onClose: () => void;
  /** Where the dialog opened from — the landing skips the layout section. */
  context?: "landing" | "room";
  initialTab?: Tab;
  /** Borrowed call media: settings never starts or stops another capture in-room. */
  callStream?: MediaStream | null;
}

/**
 * Google-Meet-style two-pane settings: Audio (mic/speaker + level meter and a
 * speaker test), Video (camera picker + live preview), General (join
 * defaults + captions). Everything persists through meetPrefs so the RTC
 * engine, lobby, and room read the same choices.
 */
export function MeetSettingsDialog({
  open,
  onClose,
  context = "room",
  initialTab = "audio",
  callStream = null,
}: MeetSettingsDialogProps): JSX.Element | null {
  const [prefs, setPrefs] = useMeetPrefs();
  const [tab, setTab] = useState<Tab>(initialTab);
  const [devices, setDevices] = useState<DeviceLists>(EMPTY_DEVICES);
  const [micLevel, setMicLevel] = useState<number>(0);
  const [previewStream, setPreviewStream] = useState<MediaStream | null>(null);
  const [testingSpeaker, setTestingSpeaker] = useState<boolean>(false);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const meterStreamRef = useRef<MediaStream | null>(null);
  const audioCtxRef = useRef<AudioContext | null>(null);
  const rafRef = useRef<number>(0);

  useEffect(() => {
    if (open) setTab(initialTab);
  }, [open, initialTab]);

  const refreshDevices = useCallback(async (): Promise<void> => {
    if (!navigator.mediaDevices?.enumerateDevices) return;
    try {
      const all = await navigator.mediaDevices.enumerateDevices();
      setDevices({
        mics: all.filter((d) => d.kind === "audioinput"),
        cams: all.filter((d) => d.kind === "videoinput"),
        speakers: all.filter((d) => d.kind === "audiooutput"),
      });
    } catch {
      setDevices(EMPTY_DEVICES);
    }
  }, []);

  useEffect(() => {
    if (!open) return;
    void refreshDevices();
    const md = navigator.mediaDevices;
    md?.addEventListener?.("devicechange", refreshDevices);
    return () => md?.removeEventListener?.("devicechange", refreshDevices);
  }, [open, refreshDevices]);

  // ── Mic level meter (Audio tab) ──────────────────────────────────────────
  useEffect(() => {
    if (!open || tab !== "audio") return;
    let cancelled = false;
    const start = async (): Promise<void> => {
      try {
        const stream = context === "room" ? callStream : await navigator.mediaDevices.getUserMedia({
          audio: prefs.micId ? { deviceId: { ideal: prefs.micId } } : true,
        });
        if (!stream?.getAudioTracks().length) { setMicLevel(0); return; }
        if (cancelled) {
          if (context !== "room") stream.getTracks().forEach((t) => t.stop());
          return;
        }
        meterStreamRef.current = context === "room" ? null : stream;
        void refreshDevices();
        const Ctx =
          window.AudioContext ??
          (window as unknown as { webkitAudioContext?: typeof AudioContext })
            .webkitAudioContext;
        if (!Ctx) return;
        const ctx = new Ctx();
        audioCtxRef.current = ctx;
        const src = ctx.createMediaStreamSource(stream);
        const analyser = ctx.createAnalyser();
        analyser.fftSize = 512;
        src.connect(analyser);
        const data = new Uint8Array(analyser.frequencyBinCount);
        const tick = (): void => {
          analyser.getByteTimeDomainData(data);
          let sum = 0;
          for (let i = 0; i < data.length; i++) {
            const v = (data[i] - 128) / 128;
            sum += v * v;
          }
          const rms = Math.sqrt(sum / data.length);
          setMicLevel(Math.min(1, rms * 4));
          rafRef.current = requestAnimationFrame(tick);
        };
        tick();
      } catch {
        setMicLevel(0);
      }
    };
    void start();
    return () => {
      cancelled = true;
      cancelAnimationFrame(rafRef.current);
      meterStreamRef.current?.getTracks().forEach((t) => t.stop());
      meterStreamRef.current = null;
      void audioCtxRef.current?.close().catch(() => undefined);
      audioCtxRef.current = null;
      setMicLevel(0);
    };
  }, [open, tab, prefs.micId, refreshDevices, context, callStream]);

  // ── Camera preview (Video tab) ───────────────────────────────────────────
  useEffect(() => {
    if (!open || tab !== "video") return;
    let cancelled = false;
    let stream: MediaStream | null = null;
    const start = async (): Promise<void> => {
      try {
        stream = context === "room" ? callStream : await navigator.mediaDevices.getUserMedia({
          video: prefs.camId
            ? { deviceId: { ideal: prefs.camId }, width: { ideal: 1280 } }
            : { width: { ideal: 1280 } },
        });
        if (cancelled) {
          if (context !== "room") stream?.getTracks().forEach((t) => t.stop());
          return;
        }
        setPreviewStream(stream?.getVideoTracks().some((track) => track.enabled && track.readyState === "live") ? stream : null);
        void refreshDevices();
      } catch {
        setPreviewStream(null);
      }
    };
    void start();
    return () => {
      cancelled = true;
      if (context !== "room") stream?.getTracks().forEach((t) => t.stop());
      setPreviewStream(null);
    };
  }, [open, tab, prefs.camId, refreshDevices, context, callStream]);

  useEffect(() => {
    const el = videoRef.current;
    if (!el) return;
    el.srcObject = previewStream;
    if (previewStream) void el.play().catch(() => undefined);
  }, [previewStream]);

  const testSpeaker = useCallback(async (): Promise<void> => {
    if (testingSpeaker) return;
    setTestingSpeaker(true);
    try {
      const Ctx =
        window.AudioContext ??
        (window as unknown as { webkitAudioContext?: typeof AudioContext })
          .webkitAudioContext;
      if (!Ctx) return;
      const ctx = new Ctx();
      const dest = ctx.createMediaStreamDestination();
      const audio = new Audio();
      audio.srcObject = dest.stream;
      if (prefs.speakerId && canPickSpeaker()) {
        await (
          audio as HTMLAudioElement & { setSinkId: (id: string) => Promise<void> }
        )
          .setSinkId(prefs.speakerId)
          .catch(() => undefined);
      }
      const gain = ctx.createGain();
      gain.gain.value = 0.15;
      gain.connect(dest);
      const notes = [523.25, 659.25, 783.99];
      notes.forEach((freq, i) => {
        const osc = ctx.createOscillator();
        osc.type = "sine";
        osc.frequency.value = freq;
        osc.connect(gain);
        osc.start(ctx.currentTime + i * 0.18);
        osc.stop(ctx.currentTime + i * 0.18 + 0.16);
      });
      await audio.play().catch(() => undefined);
      await new Promise((r) => setTimeout(r, 750));
      audio.pause();
      await ctx.close().catch(() => undefined);
    } finally {
      setTestingSpeaker(false);
    }
  }, [prefs.speakerId, testingSpeaker]);

  const tabs = useMemo(
    () =>
      [
        { id: "audio" as Tab, label: "Audio", icon: Headphones },
        { id: "video" as Tab, label: "Video", icon: Camera },
        { id: "general" as Tab, label: "General", icon: Settings2 },
      ] as const,
    []
  );

  if (!open) return null;

  const set = (patch: Partial<MeetPrefs>): void => {
    setPrefs(patch);
  };

  return (
    <div
      className="fixed inset-0 z-[70] flex items-center justify-center bg-black/55 p-4 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-label="Meeting settings"
      onClick={onClose}
    >
      <div
        className="flex h-[min(560px,92vh)] w-full max-w-[860px] overflow-hidden rounded-[28px] bg-[#111214] text-white shadow-2xl ring-1 ring-white/10"
        onClick={(e) => e.stopPropagation()}
      >
        <aside className="hidden w-[220px] shrink-0 flex-col border-r border-white/8 bg-[#0c0d0f] p-4 sm:flex">
          <div className="px-2 pb-4 pt-1 text-[15px] font-semibold tracking-tight">
            Settings
          </div>
          {tabs.map((t) => {
            const Icon = t.icon;
            const active = tab === t.id;
            return (
              <button
                key={t.id}
                type="button"
                onClick={() => setTab(t.id)}
                className={cn(
                  "mb-1 flex items-center gap-3 rounded-full px-4 py-2.5 text-left text-[14px] transition-colors",
                  active
                    ? "bg-white/12 font-semibold text-white"
                    : "text-white/70 hover:bg-white/6 hover:text-white"
                )}
              >
                <Icon className="h-[18px] w-[18px]" />
                {t.label}
              </button>
            );
          })}
        </aside>

        <div className="flex min-w-0 flex-1 flex-col">
          <header className="flex items-center gap-2 border-b border-white/8 px-5 py-3">
            <div className="flex gap-1 sm:hidden">
              {tabs.map((t) => (
                <button
                  key={t.id}
                  type="button"
                  onClick={() => setTab(t.id)}
                  className={cn(
                    "rounded-full px-3 py-1.5 text-[13px]",
                    tab === t.id ? "bg-white/12 font-semibold" : "text-white/65"
                  )}
                >
                  {t.label}
                </button>
              ))}
            </div>
            <h2 className="hidden text-[17px] font-semibold sm:block">
              {tabs.find((t) => t.id === tab)?.label}
            </h2>
            <button
              type="button"
              onClick={onClose}
              aria-label="Close settings"
              className="ml-auto grid h-9 w-9 place-items-center rounded-full text-white/70 hover:bg-white/10 hover:text-white"
            >
              <X className="h-5 w-5" />
            </button>
          </header>

          <div className="flex-1 overflow-y-auto px-5 py-5 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            {tab === "audio" && (
              <div className="space-y-6">
                <Field label="Microphone" icon={Mic}>
                  <Select
                    value={prefs.micId}
                    onChange={(v) => set({ micId: v })}
                    options={[
                      { value: "", label: "System default" },
                      ...devices.mics.map((d, i) => ({
                        value: d.deviceId,
                        label: labelFor(d, i, "Microphone"),
                      })),
                    ]}
                  />
                  <div className="mt-3 flex items-center gap-2">
                    <span className="text-[12px] text-white/55">Input level</span>
                    <div className="flex flex-1 gap-[3px]">
                      {Array.from({ length: 18 }).map((_, i) => (
                        <span
                          key={i}
                          className={cn(
                            "h-2 flex-1 rounded-full transition-colors duration-75",
                            i / 18 < micLevel
                              ? "bg-[#34d399]"
                              : "bg-white/12"
                          )}
                        />
                      ))}
                    </div>
                  </div>
                </Field>
                <Field label="Speakers" icon={Volume2}>
                  <div className="flex gap-2">
                    <div className="flex-1">
                      <Select
                        value={prefs.speakerId}
                        onChange={(v) => set({ speakerId: v })}
                        disabled={!canPickSpeaker()}
                        options={[
                          { value: "", label: "System default" },
                          ...devices.speakers.map((d, i) => ({
                            value: d.deviceId,
                            label: labelFor(d, i, "Speaker"),
                          })),
                        ]}
                      />
                    </div>
                    <button
                      type="button"
                      onClick={() => void testSpeaker()}
                      disabled={testingSpeaker}
                      className="shrink-0 rounded-full border border-white/15 px-4 text-[13px] font-medium hover:bg-white/8 disabled:opacity-50"
                    >
                      {testingSpeaker ? "Playing…" : "Test"}
                    </button>
                  </div>
                  {!canPickSpeaker() && (
                    <p className="mt-2 text-[12px] text-white/45">
                      This browser plays through the system speaker; change it in
                      your OS sound settings.
                    </p>
                  )}
                </Field>
              </div>
            )}

            {tab === "video" && (
              <div className="space-y-5">
                <div className="relative aspect-video w-full overflow-hidden rounded-2xl bg-black/60 ring-1 ring-white/10">
                  {previewStream ? (
                    <video
                      ref={videoRef}
                      autoPlay
                      playsInline
                      muted
                      className="h-full w-full -scale-x-100 object-cover"
                    />
                  ) : (
                    <div className="grid h-full place-items-center text-[13px] text-white/50">
                      Camera preview unavailable
                    </div>
                  )}
                </div>
                <Field label="Camera" icon={Camera}>
                  <Select
                    value={prefs.camId}
                    onChange={(v) => set({ camId: v })}
                    options={[
                      { value: "", label: "System default" },
                      ...devices.cams.map((d, i) => ({
                        value: d.deviceId,
                        label: labelFor(d, i, "Camera"),
                      })),
                    ]}
                  />
                </Field>
              </div>
            )}

            {tab === "general" && (
              <div className="space-y-2">
                <ToggleRow
                  title="Join with microphone on"
                  hint="Turn off to always enter muted."
                  value={prefs.joinMic}
                  onChange={(v) => set({ joinMic: v })}
                />
                <ToggleRow
                  title="Join with camera on"
                  hint="Turn off to enter with your camera off."
                  value={prefs.joinCam}
                  onChange={(v) => set({ joinCam: v })}
                />
                <ToggleRow
                  title="Show captions"
                  hint="Live captions appear as people speak."
                  value={prefs.captions}
                  onChange={(v) => set({ captions: v })}
                />
                {context === "room" && (
                  <ToggleRow
                    title="Hide tiles without video"
                    hint="Keep the stage to people with their camera on."
                    value={prefs.hideNoVideo}
                    onChange={(v) => set({ hideNoVideo: v })}
                  />
                )}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function Field({
  label,
  icon: Icon,
  children,
}: {
  label: string;
  icon: typeof Mic;
  children: React.ReactNode;
}): JSX.Element {
  return (
    <section>
      <div className="mb-2 flex items-center gap-2 text-[13px] font-medium text-white/80">
        <Icon className="h-4 w-4 text-white/60" />
        {label}
      </div>
      {children}
    </section>
  );
}

function Select({
  value,
  onChange,
  options,
  disabled,
}: {
  value: string;
  onChange: (value: string) => void;
  options: { value: string; label: string }[];
  disabled?: boolean;
}): JSX.Element {
  return (
    <select
      value={value}
      disabled={disabled}
      onChange={(e) => onChange(e.target.value)}
      className="h-11 w-full appearance-none rounded-xl border border-white/12 bg-white/5 px-4 text-[14px] text-white outline-none focus:border-white/35 disabled:opacity-50"
    >
      {options.map((o) => (
        <option key={o.value || "default"} value={o.value} className="bg-[#111214]">
          {o.label}
        </option>
      ))}
    </select>
  );
}

function ToggleRow({
  title,
  hint,
  value,
  onChange,
}: {
  title: string;
  hint: string;
  value: boolean;
  onChange: (value: boolean) => void;
}): JSX.Element {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={value}
      onClick={() => onChange(!value)}
      className="flex w-full items-center gap-4 rounded-2xl px-3 py-3 text-left hover:bg-white/5"
    >
      <div className="min-w-0 flex-1">
        <div className="text-[14px] font-medium">{title}</div>
        <div className="text-[12px] text-white/50">{hint}</div>
      </div>
      <span
        className={cn(
          "relative h-6 w-11 shrink-0 rounded-full transition-colors",
          value ? "bg-[#34d399]" : "bg-white/20"
        )}
      >
        <span
          className={cn(
            "absolute top-0.5 grid h-5 w-5 place-items-center rounded-full bg-white transition-transform",
            value ? "translate-x-[22px]" : "translate-x-0.5"
          )}
        >
          {value && <Check className="h-3 w-3 text-[#0a6b48]" />}
        </span>
      </span>
    </button>
  );
}
