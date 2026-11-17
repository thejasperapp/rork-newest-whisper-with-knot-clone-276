import { memo, useEffect, useRef, useState } from "react";
import { Atom, ChevronLeft, ChevronRight, Flame, Shield, Sparkles, Wand2, X } from "lucide-react";

import { EmberMascot } from "@/components/EmberMascot";
import { useJasperDark } from "@/components/JasperIntelKit";
import type { EmberCoachMode } from "@/lib/emberBrain";
import {
  COACH_MODES,
  autoMoodReason,
  coachModeInfo,
  refreshAutoMood,
  resolveAutoConcrete,
  saveCoachMode,
} from "@/lib/emberBrain";

/**
 * The full-screen Ember mood selector — WHISPER_PLANS.md §5c, exact geometry:
 * pure white/black canvas washed by two radial gradients tinted to the
 * PREVIEWED mode, a pulsing light beam behind the stage, the previewed ghost
 * 150px centre-stage with dimmed 118px neighbours at ±104, and a
 * high-contrast 56px Select capsule pinned to the bottom. Swipe (threshold
 * ±22px) or tap a side ghost to advance.
 */

export const MODE_ICONS: Record<EmberCoachMode, typeof Sparkles> = {
  auto: Wand2,
  regular: Sparkles,
  guardian: Shield,
  drill_sergeant: Flame,
  scientist: Atom,
};

/** §5c descriptions — longer copy under the big title (matches iOS). */
const MODE_DESCRIPTIONS: Record<EmberCoachMode, string> = {
  auto: "Jasper reads today's readiness and picks the right coach for you.",
  regular:
    "The everyday Jasper — balanced, clever, and honest with your numbers. Warm when you need it, direct when it matters.",
  guardian:
    "Protective and calm. Angel lowers the pressure, validates your effort, and always leads with recovery-first advice.",
  drill_sergeant:
    "Zero excuses. The Drill Sergeant brings tough-love intensity and holds you accountable to every single rep.",
  scientist:
    "Data-first explanations. The Scientist reasons through the physiology, trends, and mechanisms behind every recommendation.",
};

function EmberCoachModePickerBase({
  open,
  selection,
  onSelect,
  onClose,
}: {
  open: boolean;
  selection: EmberCoachMode;
  onSelect: (mode: EmberCoachMode) => void;
  onClose: () => void;
}) {
  const dark = useJasperDark();
  const [preview, setPreview] = useState<EmberCoachMode>(selection);
  const [autoStamp, setAutoStamp] = useState<number>(0);
  const touchX = useRef<number | null>(null);

  useEffect(() => {
    if (open) setPreview(selection);
  }, [open, selection]);

  useEffect(() => {
    if (!open) return;
    // Fresh readiness the moment the selector opens — Auto's ghost and
    // reason line must be honest, never yesterday's cache.
    void refreshAutoMood(true).then(() => setAutoStamp((t) => t + 1));
  }, [open]);

  // Desktop web has no swipe instinct — ← → keys browse the ghosts and
  // Esc closes, mirroring the on-screen arrows.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent): void => {
      const all = [coachModeInfo("auto"), ...COACH_MODES];
      const idx = Math.max(0, all.findIndex((m) => m.id === preview));
      if (e.key === "ArrowLeft") {
        setPreview(all[(idx + all.length - 1) % all.length].id);
      } else if (e.key === "ArrowRight") {
        setPreview(all[(idx + 1) % all.length].id);
      } else if (e.key === "Escape") {
        onClose();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, preview, onClose]);

  if (!open) return null;

  // Auto rides first — wearing the ghost readiness actually picked today.
  void autoStamp;
  const modes = [coachModeInfo("auto"), ...COACH_MODES];
  const info = coachModeInfo(preview);
  const index = Math.max(0, modes.findIndex((m) => m.id === preview));
  const prev = modes[(index + modes.length - 1) % modes.length];
  const next = modes[(index + 1) % modes.length];
  /** Concrete ghost for the mascot's expression cycle. */
  const ghostMode = (id: EmberCoachMode): EmberCoachMode =>
    id === "auto" ? resolveAutoConcrete() : id;
  const background = dark ? "#000000" : "#FFFFFF";
  const primary = dark ? "#FFFFFF" : "#000000";

  const confirm = (): void => {
    onSelect(preview);
    saveCoachMode(preview);
    onClose();
  };

  return (
    <div
      className="fixed inset-0 z-[96] flex flex-col"
      role="dialog"
      aria-modal
      style={{ background }}
      onTouchStart={(e) => {
        touchX.current = e.touches[0]?.clientX ?? null;
      }}
      onTouchEnd={(e) => {
        const start = touchX.current;
        touchX.current = null;
        if (start === null) return;
        const dx = (e.changedTouches[0]?.clientX ?? start) - start;
        // §5c swipe threshold ±22.
        if (dx < -22) setPreview(next.id);
        else if (dx > 22) setPreview(prev.id);
      }}
    >
      <style>{`
        @keyframes jasper-beam-pulse {
          from { transform: scaleX(0.90); opacity: 0.55; }
          to { transform: scaleX(1.16); opacity: 0.92; }
        }
        @keyframes jasper-band-pulse {
          from { opacity: 0.52; }
          to { opacity: 0.88; }
        }
      `}</style>

      {/* §5c backdrop washes — recolour live with the previewed mode. */}
      <div
        className="pointer-events-none absolute inset-0 transition-[background] duration-500"
        style={{
          background: `radial-gradient(430px circle at 50% 18%, ${info.accent}${dark ? "42" : "2E"}, transparent 70%), radial-gradient(520px circle at 100% 100%, ${info.deepAccent}${dark ? "33" : "1A"}, transparent 70%)`,
        }}
      />

      {/* Close — bare xmark, 42px hit area, top-right. */}
      <div className="relative flex justify-end px-3 pt-2" style={{ paddingTop: "max(0.5rem, env(safe-area-inset-top))" }}>
        <button
          onClick={onClose}
          aria-label="Close"
          className="flex h-[42px] w-[42px] items-center justify-center"
          style={{ color: `${primary}B3` }}
        >
          <X className="h-[18px] w-[18px]" strokeWidth={2.6} />
        </button>
      </div>

      {/* §5c header — 32px bold rounded title + 15px description, 2 lines. */}
      <div className="relative px-6 pt-5 text-center">
        <h1 className="text-[32px] font-bold leading-tight" style={{ color: primary }}>
          {info.title}
        </h1>
        <p
          className={`mx-auto mt-2.5 max-w-[310px] text-[15px] font-medium ${preview === "auto" ? "line-clamp-3" : "line-clamp-2"}`}
          style={{ color: dark ? "rgba(255,255,255,0.50)" : "rgba(0,0,0,0.46)", lineHeight: "1.45" }}
        >
          {preview === "auto" ? `${MODE_DESCRIPTIONS.auto} ${autoMoodReason()}` : MODE_DESCRIPTIONS[preview]}
        </p>
      </div>

      {/* §5c ghost stage — height 238, beam + blur bands + three ghosts. */}
      <div className="relative mt-auto mb-auto flex h-[238px] items-center justify-center">
        {/* Light beam: 170×330 vertical gradient, blur 24, pulsing. */}
        <div
          className="pointer-events-none absolute"
          style={{
            width: 170,
            height: 330,
            background: `linear-gradient(to bottom, transparent, ${info.accent}38, ${dark ? "rgba(255,255,255,0.10)" : "rgba(255,255,255,0.34)"}, ${info.deepAccent}29, transparent)`,
            filter: "blur(24px)",
            animation: "jasper-beam-pulse 1.8s ease-in-out infinite alternate",
          }}
        />
        {/* Soft blur bands above and below the stage (72px) with pulsing capsules. */}
        {(["top", "bottom"] as const).map((edge) => (
          <div
            key={edge}
            className="pointer-events-none absolute inset-x-0 flex h-[72px] items-center justify-center"
            style={{
              [edge]: -8,
              background: `linear-gradient(${edge === "top" ? "to bottom" : "to top"}, ${background}FA, ${background}B8, transparent)`,
              filter: "blur(10px)",
            }}
          >
            <div
              style={{
                width: 210,
                height: 22,
                borderRadius: 999,
                background: `${info.accent}${dark ? "2E" : "1F"}`,
                filter: "blur(24px)",
                animation: "jasper-band-pulse 1.8s ease-in-out infinite alternate",
              }}
            />
          </div>
        ))}

        {/* Side ghosts — 118px at ±104, y +18, blur 3.2, scale 0.88. */}
        {([[prev, -1], [next, 1]] as const).map(([mode, side]) => (
          <button
            key={mode.id}
            onClick={() => setPreview(mode.id)}
            aria-label={`Preview ${mode.title}`}
            className="absolute transition-transform active:scale-90"
            style={{
              transform: `translate(${side * 104}px, 18px) scale(0.88)`,
              filter: "blur(3.2px)",
              opacity: dark ? 0.48 : 0.42,
            }}
          >
            <EmberMascot size={118} isActive={false} expression={mode.signatureExpression} coachMode={ghostMode(mode.id)} />
          </button>
        ))}

        {/* Explicit arrows — web users shouldn't have to guess the swipe;
            they page exactly like tapping a side ghost. */}
        <button
          onClick={() => setPreview(prev.id)}
          aria-label={`Previous — ${prev.title}`}
          className="absolute left-3 top-1/2 z-10 flex h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full border backdrop-blur-md transition-transform hover:scale-105 active:scale-90 sm:left-10"
          style={{
            borderColor: `${primary}24`,
            background: dark ? "rgba(255,255,255,0.07)" : "rgba(0,0,0,0.045)",
            color: `${primary}C7`,
          }}
        >
          <ChevronLeft className="h-5 w-5" strokeWidth={2.8} />
        </button>
        <button
          onClick={() => setPreview(next.id)}
          aria-label={`Next — ${next.title}`}
          className="absolute right-3 top-1/2 z-10 flex h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full border backdrop-blur-md transition-transform hover:scale-105 active:scale-90 sm:right-10"
          style={{
            borderColor: `${primary}24`,
            background: dark ? "rgba(255,255,255,0.07)" : "rgba(0,0,0,0.045)",
            color: `${primary}C7`,
          }}
        >
          <ChevronRight className="h-5 w-5" strokeWidth={2.8} />
        </button>

        {/* Centre ghost — 150px at y −2, accent shadow 0.48. */}
        <div
          className="relative transition-transform duration-300"
          style={{
            transform: "translateY(-2px)",
            filter: `drop-shadow(0 10px 30px ${info.accent}7A)`,
          }}
        >
          <EmberMascot size={150} isActive expression={info.signatureExpression} coachMode={ghostMode(preview)} cyclesExpressions />
          {preview === "auto" && (
            <div
              className="absolute -bottom-7 left-1/2 flex -translate-x-1/2 items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 py-1"
              style={{
                background: `${info.accent}${dark ? "3D" : "4D"}`,
                border: `1px solid ${info.deepAccent}59`,
                color: dark ? "rgba(255,255,255,0.85)" : "rgba(0,0,0,0.75)",
              }}
            >
              <Wand2 className="h-[10px] w-[10px]" strokeWidth={3} />
              <span className="text-[10px] font-black">
                Today: {coachModeInfo(resolveAutoConcrete()).shortTitle}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* §5c select — 56px capsule, black/white flip, accent shadow. */}
      <div className="relative px-5" style={{ paddingBottom: "max(1rem, env(safe-area-inset-bottom))" }}>
        <button
          onClick={confirm}
          className="h-14 w-full rounded-full text-[16px] font-black transition-transform active:scale-[0.98]"
          style={{
            background: primary,
            color: background,
            boxShadow: `0 8px 18px ${info.accent}${dark ? "42" : "2E"}`,
          }}
        >
          Select {info.shortTitle}
        </button>
      </div>
    </div>
  );
}

export const EmberCoachModePicker = memo(EmberCoachModePickerBase);
