import { memo, useMemo, type CSSProperties, type ReactNode } from "react";
import { CheckCircle2, Dumbbell, Loader2, ShoppingCart, Store, UtensilsCrossed, X, Zap } from "lucide-react";

import {
  EMBER_INK,
  JASPER_BRONZE,
  JASPER_EMBER_GRADIENT,
  JASPER_MACROS,
  emberGlowCardStyle,
  emberGlowIconStyle,
  emberGlowShadows,
  emberInset,
  emberKicker,
  emberSubtle,
} from "@/lib/jasperIntel";
import { useJasperDark } from "@/components/JasperIntelKit";
import { cn } from "@/lib/utils";

/**
 * WHISPER_PLANS.md — the ember glow box and both plan-card anatomies,
 * transcribed 1:1 from the published spec (§2 glow box, §3 workout card,
 * §4 diet card + the mandatory breathing generate state).
 */

// MARK: - plan_shapes parsing (render-only; reps stay verbatim STRINGS)

export interface PlanShapeExercise {
  name: string;
  sets: number;
  reps: string;
  restSeconds: number;
}

export interface PlanShapeDay {
  dayName: string;
  weekNumber?: number;
  weekday?: number;
  phase?: string;
  focus: string;
  exercises: PlanShapeExercise[];
}

export interface PlanShape {
  title: string;
  overview: string;
  goal: string;
  days: PlanShapeDay[];
  exerciseCount: number;
  setCount: number;
  metaLine: string;
}

function rec(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null ? (value as Record<string, unknown>) : {};
}

function str(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function num(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/** Parses a `plan_shapes.programs` payload for rendering — never mutates it. */
export function parsePlanShape(payload: unknown, fallbackTitle = "", fallbackGoal = ""): PlanShape {
  const p = rec(payload);
  const rawDays = Array.isArray(p.workoutDays) ? p.workoutDays : Array.isArray(p.days) ? p.days : [];
  const days: PlanShapeDay[] = rawDays.map((raw, index) => {
    const day = rec(raw);
    const exercises: PlanShapeExercise[] = (Array.isArray(day.exercises) ? day.exercises : []).map((rawEx) => {
      const ex = rec(rawEx);
      const reps = typeof ex.reps === "string" ? ex.reps : typeof ex.reps === "number" ? String(ex.reps) : "—";
      return {
        name: str(ex.name) ?? "Exercise",
        sets: num(ex.sets) ?? 3,
        reps,
        restSeconds: num(ex.restSeconds) ?? num(ex.rest_seconds) ?? 0,
      };
    });
    return {
      dayName: [num(day.weekNumber) !== null && Number.isInteger(day.weekNumber) && Number(day.weekNumber) > 0 ? `Week ${day.weekNumber}` : null, str(day.dayName) ?? str(day.name) ?? `Day ${index + 1}`].filter(Boolean).join(" · "),
      weekNumber: num(day.weekNumber) ?? undefined,
      weekday: num(day.weekday) ?? undefined,
      phase: str(day.phase) ?? undefined,
      focus: str(day.focus) ?? "",
      exercises,
    };
  });
  const exerciseCount = days.reduce((acc, d) => acc + d.exercises.length, 0);
  const setCount = days.reduce((acc, d) => acc + d.exercises.reduce((a, e) => a + e.sets, 0), 0);
  return {
    title: str(p.title) ?? str(p.name) ?? fallbackTitle,
    overview: str(p.overview) ?? str(p.summary) ?? "",
    goal: str(p.goal) ?? fallbackGoal,
    days,
    exerciseCount,
    setCount,
    metaLine: `${days.length} session${days.length === 1 ? "" : "s"} · ${exerciseCount} exercise${exerciseCount === 1 ? "" : "s"} · ${setCount} sets`,
  };
}

// MARK: - Keyframes (entrance spring + the breathing aura)

export const EmberPlanKeyframes = memo(function EmberPlanKeyframes() {
  return (
    <style>{`
      @keyframes jasper-plan-in {
        from { transform: scale(0.96); opacity: 0; }
        to { transform: scale(1); opacity: 1; }
      }
      @keyframes ember-breathe-light {
        from { box-shadow: ${emberGlowShadows(false, 0.5)}; }
        to { box-shadow: ${emberGlowShadows(false, 1)}; }
      }
      @keyframes ember-breathe-dark {
        from { box-shadow: ${emberGlowShadows(true, 0.5)}; }
        to { box-shadow: ${emberGlowShadows(true, 1)}; }
      }
      @keyframes ember-shimmer-bar {
        from { opacity: 1; }
        to { opacity: 0.45; }
      }
    `}</style>
  );
});

// MARK: - The glow box + glow icon

interface EmberGlowCardProps {
  glow?: number;
  radius?: number;
  /** §4 mandatory generate state — the aura pulses 0.5 ↔ 1.0, 1.4s forever. */
  breathing?: boolean;
  className?: string;
  style?: CSSProperties;
  children: ReactNode;
}

/** The §2 `emberGlowCard` — opaque cream/charcoal, gradient hairline, ember aura. */
export function EmberGlowCard({ glow = 1, radius = 22, breathing = false, className, style, children }: EmberGlowCardProps) {
  const dark = useJasperDark();
  const base = useMemo(() => emberGlowCardStyle(dark, glow, radius), [dark, glow, radius]);
  return (
    <div
      className={className}
      style={{
        ...base,
        ...(breathing
          ? { animation: `${dark ? "ember-breathe-dark" : "ember-breathe-light"} 1.4s ease-in-out infinite alternate` }
          : {}),
        ...style,
      }}
    >
      {children}
    </div>
  );
}

/** §2 `EmberGlowIcon` — the ember-glowing tile anchoring every plan header. */
export function EmberGlowIcon({ size = 40, monogram, children }: { size?: number; monogram?: string; children?: ReactNode }) {
  const dark = useJasperDark();
  return (
    <div style={emberGlowIconStyle(dark, size)}>
      {monogram ? (
        <span style={{ fontSize: size * 0.42, fontWeight: 700, textShadow: "0 0 5px rgba(243,144,87,0.75)" }}>
          {monogram}
        </span>
      ) : (
        <span style={{ filter: "drop-shadow(0 0 5px rgba(243,144,87,0.75))", display: "flex" }}>{children}</span>
      )}
    </div>
  );
}

/** §2 kicker — caption bold uppercase, deepOrange light / orange dark. */
export function EmberKicker({ text, secondary = false }: { text: string; secondary?: boolean }) {
  const dark = useJasperDark();
  return (
    <p
      className="text-[11px] font-bold uppercase"
      style={{ letterSpacing: "0.06em", color: secondary ? emberSubtle(dark, 0.55) : emberKicker(dark) }}
    >
      {text}
    </p>
  );
}

/** §3.1 teal Saved/Live chip. */
export function JasperTealChip({ label, live = false }: { label: string; live?: boolean }) {
  return (
    <span
      className="inline-flex shrink-0 items-center gap-1 rounded-full px-2 py-1 text-[11px] font-bold"
      style={{ color: JASPER_MACROS.protein, background: "rgba(92,219,184,0.13)" }}
    >
      {live ? <Zap className="h-3 w-3" fill="currentColor" /> : <CheckCircle2 className="h-3 w-3" />}
      {label}
    </span>
  );
}

/** §3.4 — the 25pt ember-gradient numbered day dot. */
export function EmberDayDot({ index }: { index: number }) {
  return (
    <span
      className="flex h-[25px] w-[25px] shrink-0 items-center justify-center rounded-full text-[11px] font-bold text-white"
      style={{ background: JASPER_EMBER_GRADIENT }}
    >
      {index}
    </span>
  );
}

/** §3.5 primary — the full-width ember-gradient capsule. */
export function EmberCapsuleButton({
  label,
  busy = false,
  onClick,
}: {
  label: string;
  busy?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      disabled={busy}
      className="flex min-w-0 flex-1 items-center justify-center gap-1.5 rounded-full py-3 text-[13.5px] font-bold text-white transition-transform active:scale-[0.98]"
      style={{ background: JASPER_EMBER_GRADIENT }}
    >
      {busy && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
      {label}
    </button>
  );
}

/** §3.5 — the 44px quiet circle button beside the primary capsule. */
export function EmberCircleButton({
  busy = false,
  onClick,
  title,
  children,
}: {
  busy?: boolean;
  onClick: () => void;
  title: string;
  children: ReactNode;
}) {
  const dark = useJasperDark();
  return (
    <button
      onClick={onClick}
      disabled={busy}
      title={title}
      className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full transition-transform active:scale-95"
      style={{
        background: dark ? "rgba(255,255,255,0.10)" : "rgba(33,28,26,0.06)",
        color: dark ? "#FFFFFF" : EMBER_INK,
      }}
    >
      {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : children}
    </button>
  );
}

/** §4.2 — the 4 macro stat tiles in the canonical colors. */
export function JasperMacroTiles({
  kcal,
  protein,
  carbs,
  fat,
}: {
  kcal: number | null;
  protein: number | null;
  carbs: number | null;
  fat: number | null;
}) {
  const dark = useJasperDark();
  const tiles = [
    [kcal, "kcal", JASPER_MACROS.kcal],
    [protein, "Protein", JASPER_MACROS.protein],
    [carbs, "Carbs", JASPER_MACROS.carbs],
    [fat, "Fat", JASPER_MACROS.fat],
  ] as const;
  return (
    <div className="flex gap-2">
      {tiles.map(([value, label, color]) => (
        <div
          key={label}
          className="min-w-0 flex-1 rounded-[14px] py-2.5 text-center"
          style={{
            background: `${color}${dark ? "29" : "1A"}`,
            border: `1px solid ${color}38`,
          }}
        >
          <p className="truncate px-1 text-[17px] font-bold" style={{ color, fontVariantNumeric: "tabular-nums" }}>
            {value ?? "—"}
          </p>
          <p className="text-[10.5px]" style={{ color: emberSubtle(dark, 0.55) }}>
            {label}
          </p>
        </div>
      ))}
    </div>
  );
}

export type EmberPublishState = "hidden" | "publishable" | "publishing" | "published";

function PublishedLine() {
  return (
    <p className="flex items-center gap-1.5 text-[11.5px] font-semibold" style={{ color: JASPER_MACROS.protein }}>
      <CheckCircle2 className="h-3.5 w-3.5" /> On the marketplace — re-publishing updates in place
    </p>
  );
}

// MARK: - §3 Workout program glow card

export function JasperWorkoutPlanCard({
  plan,
  glow = 0.5,
  live = false,
  saved = false,
  chips = [],
  primaryLabel = "View program",
  onView,
  publishState = "hidden",
  onPublish,
}: {
  plan: PlanShape;
  glow?: number;
  live?: boolean;
  saved?: boolean;
  chips?: string[];
  primaryLabel?: string;
  onView?: () => void;
  publishState?: EmberPublishState;
  onPublish?: () => void;
}) {
  const dark = useJasperDark();
  const shown = plan.days.slice(0, 4);
  return (
    <EmberGlowCard glow={glow} className="p-4" style={{ animation: "jasper-plan-in 420ms cubic-bezier(0.34,1.3,0.5,1)" }}>
      <div className="flex items-center gap-3">
        <EmberGlowIcon>
          <Dumbbell className="h-4 w-4" strokeWidth={2.4} />
        </EmberGlowIcon>
        <div className="min-w-0 flex-1">
          <EmberKicker text="Workout plan" />
        </div>
        {saved ? <JasperTealChip label="Saved" /> : live ? <JasperTealChip label="Live" live /> : null}
      </div>
      {/* Title spans the FULL card width — beside the icon it wrapped into a
          one-word-per-line column on narrow studio columns. */}
      <p className="mt-2.5 text-[17px] font-bold leading-tight">{plan.title}</p>
      <p className="mt-1 text-[12.5px] font-semibold" style={{ color: emberSubtle(dark) }}>
        {plan.metaLine}
      </p>

      {plan.overview && (
        <p
          className="mt-4 rounded-[16px] p-[13px] text-[13px] leading-snug"
          style={{ background: emberInset(dark), color: emberSubtle(dark, 0.74) }}
        >
          {plan.overview}
        </p>
      )}

      {chips.length > 0 && (
        <div className="mt-4 flex flex-wrap gap-2">
          {chips.map((chip) => (
            <span
              key={chip}
              className="rounded-full px-2.5 py-1.5 text-[11px] font-bold"
              style={{
                color: emberKicker(dark),
                background: `rgba(243,144,87,${dark ? 0.16 : 0.1})`,
                border: "0.7px solid rgba(243,144,87,0.24)",
              }}
            >
              {chip}
            </span>
          ))}
        </div>
      )}

      {shown.length > 0 && (
        <div className="mt-4">
          <EmberKicker text="Weekly structure" secondary />
          <div className="mt-2.5 space-y-2.5">
            {shown.map((day, i) => (
              <div
                key={`${day.dayName}-${i}`}
                className="flex items-start gap-2.5 rounded-[15px] p-[11px]"
                style={{ background: emberInset(dark, true) }}
              >
                <EmberDayDot index={i + 1} />
                <div className="min-w-0 flex-1">
                  <p className="text-[13.5px] font-bold leading-tight">{day.dayName}</p>
                  {day.focus && (
                    <p className="text-[11.5px] font-semibold" style={{ color: emberSubtle(dark, 0.55) }}>
                      {day.focus}
                    </p>
                  )}
                  {day.exercises.length > 0 && (
                    <p className="mt-0.5 line-clamp-2 text-[11.5px]" style={{ color: emberSubtle(dark) }}>
                      {day.exercises.slice(0, 3).map((e) => e.name).join(" · ")}
                    </p>
                  )}
                </div>
              </div>
            ))}
          </div>
          {plan.days.length > 4 && (
            <p className="mt-2 text-[11.5px] font-semibold" style={{ color: emberKicker(dark) }}>
              + {plan.days.length - 4} more session{plan.days.length - 4 === 1 ? "" : "s"}
            </p>
          )}
        </div>
      )}

      <div className="mt-4 flex items-center gap-2.5">
        {onView && <EmberCapsuleButton label={primaryLabel} onClick={onView} />}
        {publishState !== "hidden" && publishState !== "published" && onPublish && (
          <EmberCircleButton onClick={onPublish} busy={publishState === "publishing"} title="Publish to marketplace">
            <Store className="h-4 w-4" />
          </EmberCircleButton>
        )}
      </div>
      {publishState === "published" && (
        <div className="mt-2.5">
          <PublishedLine />
        </div>
      )}
    </EmberGlowCard>
  );
}

// MARK: - §4 Diet plan glow card (studio row form)

export function JasperDietPlanGlowCard({
  name,
  metaLine,
  attribution,
  kcal = null,
  protein = null,
  carbs = null,
  fat = null,
  glow = 0.5,
  live = false,
  groceryCount = 0,
  primaryLabel = "View plan",
  onView,
  publishState = "hidden",
  onPublish,
}: {
  name: string;
  metaLine: string;
  attribution?: string;
  kcal?: number | null;
  protein?: number | null;
  carbs?: number | null;
  fat?: number | null;
  glow?: number;
  live?: boolean;
  groceryCount?: number;
  primaryLabel?: string;
  onView?: () => void;
  publishState?: EmberPublishState;
  onPublish?: () => void;
}) {
  const dark = useJasperDark();
  const hasMacros = kcal !== null || protein !== null || carbs !== null || fat !== null;
  return (
    <EmberGlowCard glow={glow} className="p-4" style={{ animation: "jasper-plan-in 420ms cubic-bezier(0.34,1.3,0.5,1)" }}>
      <div className="flex items-center gap-3">
        <EmberGlowIcon>
          <UtensilsCrossed className="h-4 w-4" strokeWidth={2.4} />
        </EmberGlowIcon>
        <div className="min-w-0 flex-1">
          <EmberKicker text="Diet plan" />
        </div>
        {live && <JasperTealChip label="Live" live />}
      </div>
      <p className="mt-2.5 text-[17px] font-bold leading-tight">{name}</p>
      <p className="mt-1 text-[12.5px] font-semibold" style={{ color: emberSubtle(dark) }}>
        {metaLine}
      </p>
      {attribution && (
        <p className="mt-0.5 text-[11.5px] font-semibold" style={{ color: JASPER_BRONZE }}>
          {attribution}
        </p>
      )}

      {hasMacros && (
        <div className="mt-4">
          <JasperMacroTiles kcal={kcal} protein={protein} carbs={carbs} fat={fat} />
        </div>
      )}

      <div className="mt-4 flex items-center gap-2.5">
        {onView && <EmberCapsuleButton label={primaryLabel} onClick={onView} />}
        {publishState !== "hidden" && publishState !== "published" && onPublish && (
          <EmberCircleButton onClick={onPublish} busy={publishState === "publishing"} title="Publish to marketplace">
            <Store className="h-4 w-4" />
          </EmberCircleButton>
        )}
      </div>
      {groceryCount > 0 && (
        <p className="mt-2.5 flex items-center gap-1.5 text-[11px]" style={{ color: emberSubtle(dark, 0.55) }}>
          <ShoppingCart className="h-3 w-3" /> {groceryCount} grocery items ride this plan — shared with Jasper
        </p>
      )}
      {publishState === "published" && (
        <div className="mt-2.5">
          <PublishedLine />
        </div>
      )}
    </EmberGlowCard>
  );
}

// MARK: - §3 detail surface (day-by-day glow boxes)

export function JasperProgramDetailModal({
  plan,
  onClose,
  ctaLabel,
  ctaBusy = false,
  ctaDone = false,
  onCta,
}: {
  plan: PlanShape;
  onClose: () => void;
  ctaLabel?: string;
  ctaBusy?: boolean;
  ctaDone?: boolean;
  onCta?: () => void;
}) {
  const dark = useJasperDark();
  return (
    <div className="fixed inset-0 z-[95] flex items-end justify-center sm:items-center" role="dialog" aria-modal>
      <button className="absolute inset-0 bg-black/55 backdrop-blur-[2px]" onClick={onClose} aria-label="Close" />
      <div
        className="relative flex max-h-[92dvh] w-full max-w-[560px] flex-col overflow-hidden rounded-t-[26px] sm:rounded-[26px]"
        style={{
          background: dark ? "#171310" : "#FBF4E4",
          animation: "jasper-plan-in 420ms cubic-bezier(0.34,1.3,0.5,1)",
        }}
      >
        <div className="flex items-start gap-3 px-5 pb-3 pt-5">
          <EmberGlowIcon size={44}>
            <Dumbbell className="h-[18px] w-[18px]" strokeWidth={2.4} />
          </EmberGlowIcon>
          <div className="min-w-0 flex-1" style={{ color: dark ? "#FFFFFF" : EMBER_INK }}>
            <EmberKicker text={plan.goal || "Workout plan"} />
            <p className="text-[20px] font-black leading-tight">{plan.title}</p>
            <p className="mt-0.5 text-[12.5px] font-semibold" style={{ color: emberSubtle(dark) }}>
              {plan.metaLine}
            </p>
          </div>
          <button
            onClick={onClose}
            className="flex h-[34px] w-[34px] shrink-0 items-center justify-center rounded-full"
            style={{ background: emberInset(dark), color: emberSubtle(dark, 0.65) }}
            aria-label="Close program"
          >
            <X className="h-4 w-4" strokeWidth={2.6} />
          </button>
        </div>

        <div
          className="min-h-0 flex-1 space-y-3 overflow-y-auto px-5 pb-6"
          style={{ color: dark ? "#FFFFFF" : EMBER_INK, overscrollBehavior: "contain" }}
        >
          {plan.overview && (
            <p
              className="rounded-[16px] p-[13px] text-[13px] leading-snug"
              style={{ background: emberInset(dark), color: emberSubtle(dark, 0.74) }}
            >
              {plan.overview}
            </p>
          )}
          {plan.days.map((day, i) => (
            <EmberGlowCard key={`${day.dayName}-${i}`} glow={0.5} className="p-4">
              <div className="flex items-center gap-2.5">
                <EmberDayDot index={i + 1} />
                <div className="min-w-0 flex-1">
                  <p className="text-[13.5px] font-bold leading-tight">{day.dayName}</p>
                  {day.focus && (
                    <p className="text-[11.5px] font-semibold" style={{ color: emberSubtle(dark, 0.55) }}>
                      {day.focus}
                    </p>
                  )}
                </div>
              </div>
              <div className="mt-2.5 space-y-2">
                {day.exercises.map((ex, j) => (
                  <div key={`${ex.name}-${j}`} className="flex items-baseline gap-2">
                    <p className="min-w-0 flex-1 text-[13px] font-semibold leading-snug">{ex.name}</p>
                    <p className="shrink-0 text-[13px] font-bold" style={{ color: emberKicker(dark) }}>
                      {ex.sets} × {ex.reps}
                    </p>
                    {ex.restSeconds > 0 && (
                      <span
                        className="shrink-0 rounded-full px-1.5 py-0.5 text-[10px] font-bold"
                        style={{ background: emberInset(dark), color: emberSubtle(dark, 0.6) }}
                      >
                        {ex.restSeconds}s rest
                      </span>
                    )}
                  </div>
                ))}
                {day.exercises.length === 0 && (
                  <p className="text-[11.5px]" style={{ color: emberSubtle(dark, 0.5) }}>
                    Rest day.
                  </p>
                )}
              </div>
            </EmberGlowCard>
          ))}
        </div>

        {ctaLabel && onCta && (
          <div className="px-5 pb-5 pt-2">
            <button
              onClick={onCta}
              disabled={ctaBusy || ctaDone}
              className={cn(
                "flex h-14 w-full items-center justify-center gap-2 rounded-full text-[15px] font-black text-white transition-transform active:scale-[0.98]",
                ctaDone && "text-[#5CDBB8]"
              )}
              style={
                ctaDone
                  ? { background: "rgba(92,219,184,0.13)" }
                  : { background: JASPER_EMBER_GRADIENT, boxShadow: "0 8px 18px rgba(231,111,58,0.30)" }
              }
            >
              {ctaBusy ? <Loader2 className="h-4 w-4 animate-spin" /> : ctaDone ? <CheckCircle2 className="h-4 w-4" /> : null}
              {ctaDone ? "Saved to Jasper" : ctaLabel}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

// MARK: - §4 mandatory generate loading state

export function JasperGeneratingCard({ status }: { status: string }) {
  const dark = useJasperDark();
  const bar = (width: string, height = 12) => (
    <div
      className="rounded-full"
      style={{
        width,
        height,
        background: emberInset(dark),
        animation: "ember-shimmer-bar 0.9s ease-in-out infinite alternate",
      }}
    />
  );
  return (
    <EmberGlowCard glow={0.5} breathing className="p-4">
      <div className="flex items-center gap-3">
        <EmberGlowIcon>
          <UtensilsCrossed className="h-4 w-4" strokeWidth={2.4} />
        </EmberGlowIcon>
        <div className="flex-1 space-y-1.5">
          {bar("42%", 10)}
          {bar("68%", 14)}
        </div>
      </div>
      <div className="mt-3.5 space-y-2">
        {bar("70%")}
        {bar("55%")}
        {bar("63%")}
      </div>
      <p className="mt-3 text-[12px]" style={{ color: emberSubtle(dark, 0.55) }}>
        {status}
      </p>
    </EmberGlowCard>
  );
}
