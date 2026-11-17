import { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { RotateCw, Sparkles, X, type LucideIcon } from "lucide-react";

import { EmberMascot } from "@/components/EmberMascot";
import { KnotWordmark } from "@/components/Knot";
import {
  JasperKitKeyframes,
  JasperMintPill,
  JasperReplyCard,
  JasperThinkingRail,
  jasperBoxStyle,
} from "@/components/JasperIntelKit";
import { jasperQuickAnalysis } from "@/lib/emberAtlas";
import { jasperGlassShellStyle, jasperPillPalette } from "@/lib/jasperIntel";
import { coachModeInfo, loadCoachMode } from "@/lib/emberBrain";
import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";

/**
 * Web port of the iOS `JasperAnalysisDock` — the meeting-style dock, 1:1:
 * the living mascot peeking from behind the pale MintShell personality pill;
 * tapping floats it into the dark-glass assistant box (same matched-header
 * motion, same springs) and runs `quickAnalysis` in place. The reply renders
 * as the JASPER card — header, personality chip, tinted accent bar — with a
 * Re-run chip below. Used at the bottom of the inbox and on every coach
 * client profile.
 */
/** Optional quick action rendered as a chip in the dock's footer — a
 * `lens` re-runs the analysis through a different instruction (cached per
 * lens, instant to flip back); `perform` hands control to the host screen. */
export interface JasperDockAction {
  id: string;
  label: string;
  icon: LucideIcon;
  kind: "lens" | "perform";
  focus?: string;
  onPerform?: () => void;
}

const DEFAULT_LENS = "read";

/** A full visual costume for the dock — the Dating hub's pink matchmaker
 * look (cupid mascot, cream pill, rose glass). Mirrors iOS `JasperDockCostume`. */
export interface JasperDockCostume {
  accent: string;
  softAccent: string;
  pillFill: string;
  pillRim: string;
  ink: string;
  chipLabel: string;
  /** Optional glyph masked + tinted with the accent, left of the pill label. */
  pillIconSrc?: string;
  /** Mascot body colours (soft → accent → deep gradient). */
  mascotPalette: { accent: string; softAccent: string; deepAccent: string };
  /** Heart eyes + lifted brows. */
  mascotSmitten?: boolean;
}

export function JasperAnalysisDock({
  pillLabel = "Knot's read",
  boxTitle = "Knot's read",
  focus,
  buildContext,
  emptyText = "Nothing to analyze here yet.",
  actions = [],
  costume,
  renderReply,
  className,
  alignToContent = false,
}: {
  pillLabel?: string;
  boxTitle?: string;
  /** The brain instruction for THIS surface. */
  focus: string;
  /** Live context lines; null/empty = honest empty state. */
  buildContext: () => string | null;
  emptyText?: string;
  /** Surface-tailored quick actions — lenses and/or host tools. */
  actions?: JasperDockAction[];
  /** Optional costume — the Dating hub wears the pink matchmaker outfit. */
  costume?: JasperDockCostume;
  /** Optional structured renderer — return a node to replace the plain reply
   *  card (the matchmaker's match cards); null falls back to text. */
  renderReply?: (text: string, lensId: string) => React.ReactNode | null;
  /** Positions the fixed dock (default bottom-center above mobile nav). */
  className?: string;
  /** Keep the inbox dock centered in its conversation column, not the browser. */
  alignToContent?: boolean;
}) {
  const { user } = useAuth();
  const anchorRef = useRef<HTMLSpanElement>(null);
  const [contentBounds, setContentBounds] = useState<{ left: number; width: number } | null>(null);
  useEffect(() => {
    if (!alignToContent) return;
    const column = anchorRef.current?.closest("main");
    if (!column) return;
    const sync = () => {
      const bounds = column.getBoundingClientRect();
      setContentBounds({ left: bounds.left, width: bounds.width });
    };
    sync();
    const observer = new ResizeObserver(sync);
    observer.observe(column);
    window.addEventListener("resize", sync);
    return () => { observer.disconnect(); window.removeEventListener("resize", sync); };
  }, [alignToContent]);
  const capture = useChatOperationGuard(user?.id ?? "", focus);
  const [open, setOpen] = useState<boolean>(false);
  const [busy, setBusy] = useState<boolean>(false);
  const [replies, setReplies] = useState<Record<string, string>>({});
  const [activeLens, setActiveLens] = useState<string>(DEFAULT_LENS);
  useEffect(() => { setOpen(false); setBusy(false); setReplies({}); }, [user?.id, focus]);
  const mode = loadCoachMode();
  const info = coachModeInfo(mode);
  const palette = jasperPillPalette(mode);

  const accent = costume?.accent ?? info.accent;
  const inkColor = alignToContent ? "var(--knot-ink, #202729)" : costume?.ink ?? palette.ink;
  /** Cream/pink pill overrides — spread over the MintShell recipe. */
  const pillStyle: React.CSSProperties | undefined = costume
    ? {
        background: `linear-gradient(to bottom, rgba(255,255,255,0.6), rgba(255,255,255,0) 50%), ${costume.pillFill}`,
        border: `1.5px solid ${costume.pillRim}F2`,
        boxShadow: `0 4px 10px ${costume.accent}57, 0 5px 8px rgba(0,0,0,0.13)`,
        color: costume.ink,
      }
    : alignToContent ? { background: "var(--knot-glass-fill, rgba(255,255,255,.64))", border: "1px solid #80889029", boxShadow: "0 2px 8px #0000000a", color: inkColor, backdropFilter: "blur(20px) saturate(1.1)" } : undefined;
  const boxStyle: React.CSSProperties = costume
    ? { ...jasperGlassShellStyle(costume.accent), borderRadius: 24 }
    : jasperBoxStyle(mode);

  const reply = replies[activeLens] ?? null;
  const hasLenses = actions.some((a) => a.kind === "lens");

  const focusFor = useCallback(
    (lensId: string): string => {
      if (lensId === DEFAULT_LENS) return focus;
      const lens = actions.find((a) => a.id === lensId && a.kind === "lens");
      return lens?.focus ?? focus;
    },
    [actions, focus]
  );

  const run = useCallback(
    async (force: boolean, lensId?: string): Promise<void> => {
      const lens = lensId ?? activeLens;
      const check = capture();
      setBusy(true);
      try {
        const context = (buildContext() ?? "").trim();
        if (!context) {
          setReplies((r) => ({ ...r, [lens]: emptyText }));
          return;
        }
        const text = (
          await jasperQuickAnalysis(context, focusFor(lens), force)
        ).trim();
        check();
        setReplies((r) => ({ ...r, [lens]: text.length > 0 ? text : emptyText }));
      } catch {
        try { check(); setReplies((r) => ({ ...r, [lens]: "Couldn't reach Knot. Use Re-run to try again." })); } catch { /* Obsolete analysis. */ }
      } finally {
        try { check(); setBusy(false); } catch { /* Another account owns the dock. */ }
      }
    },
    [activeLens, buildContext, emptyText, focusFor, capture]
  );

  /**
   * The living mascot peeking from behind the pill / box top edge.
   * Centering lives on the OUTER span (inline transform) while the bob
   * animation lives on an INNER span — keyframes animate `transform`, so
   * putting both on one element let the bob stomp the -50% X translation
   * and shove Jasper off-center.
   */
  const mascot = (top: number) => (
    <span
      className="pointer-events-none absolute left-1/2 z-0"
      style={{ top, transform: "translateX(-50%)" }}
    >
      <span className="relative block">
        {busy && (
          <span
            className="absolute left-1/2 top-1/2 h-11 w-11 -translate-x-1/2 -translate-y-1/2 rounded-full"
            style={{
              background: accent,
              filter: "blur(14px)",
              animation: "jasper-glow-pulse 0.9s ease-in-out infinite",
            }}
          />
        )}
        <EmberMascot
          size={48}
          coachMode={mode}
          isActive={false}
          expression={
            busy ? "thinking" : reply ? (costume ? "delighted" : info.signatureExpression) : "calm"
          }
          cyclesExpressions={false}
          palette={costume?.mascotPalette ?? { accent: "#F6F8FB", softAccent: "#FFFFFF", deepAccent: "#EDF1F6" }}
          smitten={costume?.mascotSmitten ?? false}
        />
      </span>
    </span>
  );

  // Rendered through a PORTAL onto <body>: page containers animate in with
  // transforms, and a transformed ancestor silently turns position:fixed into
  // "fixed to that ancestor" — the dock would ride the page scroll instead of
  // staying pinned to the viewport like iOS. On body, fixed means fixed.
  return <><span ref={anchorRef} aria-hidden="true" />{createPortal(
    <div
      className={cn(
        // Steady placement: PINNED right above the mobile bottom nav (nav =
        // 8px pad-top + 40px items + max(6px, safe-area) pad-bottom, plus a
        // 6px breathing gap — the iOS anchoring, measured); on desktop (no
        // bottom nav) it hugs the viewport bottom instead.
        "pointer-events-none fixed inset-x-0 bottom-[calc(54px+max(0.375rem,env(safe-area-inset-bottom)))] z-40 flex justify-center px-4 lg:bottom-6",
        className
      )}
      style={alignToContent && contentBounds ? { left: contentBounds.left, width: contentBounds.width, right: "auto" } : undefined}
    >
      <JasperKitKeyframes />
      {open ? (
        <div
          className="pointer-events-auto w-[min(380px,calc(100vw-24px))]"
          style={{
            animation: "jasper-dock-open 450ms cubic-bezier(0.34, 1.3, 0.5, 1) both",
            transformOrigin: "bottom center",
          }}
        >
          <div className="relative overflow-visible pb-2.5" style={boxStyle}>
            {/* The mascot peeks over the box's top edge — same -24 as iOS. */}
            {mascot(-24)}
            {/* MintShell header — the collapsed pill floats up into this. */}
            <div className="relative z-10 mx-2.5 mt-2.5">
              <JasperMintPill mode={mode} className="h-9 w-full justify-between pl-4 pr-[7px]" style={pillStyle}>
                <span className="truncate text-[14px] font-black" style={{ color: inkColor }}>
                  {boxTitle}
                </span>
                <button
                  type="button"
                  aria-label="Close Knot"
                  onClick={() => setOpen(false)}
                  className="flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-full transition-colors"
                  style={{ background: `color-mix(in srgb, ${inkColor} 8%, transparent)`, color: inkColor }}
                >
                  <X className="h-2.5 w-2.5" strokeWidth={3.2} />
                </button>
              </JasperMintPill>
            </div>
            {/* Conversation area — thinking rail or the JASPER reply card. */}
            <div className="max-h-[280px] overflow-y-auto px-3.5 py-3">
              {busy ? (
                <JasperThinkingRail mode={mode} analytical />
              ) : reply ? (
                (renderReply?.(reply, activeLens) ?? null) || (
                  <JasperReplyCard
                    mode={mode}
                    text={reply}
                    accent={costume?.accent}
                    soft={costume?.softAccent}
                    chipLabel={costume?.chipLabel}
                  />
                )
              ) : null}
            </div>
            <div className="scrollbar-none flex items-center gap-1.5 overflow-x-auto px-3">
              <button
                type="button"
                onClick={() => void run(true)}
                disabled={busy}
                className="flex shrink-0 items-center gap-1.5 rounded-full border border-white/[0.12] bg-white/[0.08] px-3 py-[7px] text-[12px] font-bold text-white/85 transition-colors hover:bg-white/15 disabled:opacity-50"
              >
                <RotateCw className={cn("h-2.5 w-2.5", busy && "animate-spin")} strokeWidth={3} />
                {busy ? "Reading…" : "Re-run"}
              </button>
              {hasLenses && (
                <button
                  type="button"
                  onClick={() => {
                    setActiveLens(DEFAULT_LENS);
                    if (!replies[DEFAULT_LENS] && !busy) void run(false, DEFAULT_LENS);
                  }}
                  className="flex shrink-0 items-center gap-1.5 rounded-full border px-3 py-[7px] text-[12px] font-bold transition-colors"
                  style={
                    activeLens === DEFAULT_LENS
                      ? { background: accent, borderColor: accent, color: inkColor }
                      : { background: "rgba(255,255,255,0.08)", borderColor: "rgba(255,255,255,0.12)", color: "rgba(255,255,255,0.85)" }
                  }
                >
                  <Sparkles className="h-2.5 w-2.5" strokeWidth={3} />
                  Read
                </button>
              )}
              {actions.map((action) => {
                const Icon = action.icon;
                if (action.kind === "perform") {
                  return (
                    <button
                      key={action.id}
                      type="button"
                      onClick={() => {
                        setOpen(false);
                        action.onPerform?.();
                      }}
                      className="flex shrink-0 items-center gap-1.5 rounded-full border border-white/[0.12] bg-white/[0.08] px-3 py-[7px] text-[12px] font-bold text-white/85 transition-colors hover:bg-white/15"
                    >
                      <Icon className="h-2.5 w-2.5" strokeWidth={3} />
                      {action.label}
                    </button>
                  );
                }
                const selected = activeLens === action.id;
                return (
                  <button
                    key={action.id}
                    type="button"
                    onClick={() => {
                      setActiveLens(action.id);
                      if (!replies[action.id] && !busy) void run(false, action.id);
                    }}
                    className="flex shrink-0 items-center gap-1.5 rounded-full border px-3 py-[7px] text-[12px] font-bold transition-colors"
                    style={
                      selected
                        ? { background: accent, borderColor: accent, color: inkColor }
                        : { background: "rgba(255,255,255,0.08)", borderColor: "rgba(255,255,255,0.12)", color: "rgba(255,255,255,0.85)" }
                    }
                  >
                    <Icon className="h-2.5 w-2.5" strokeWidth={3} />
                    {action.label}
                  </button>
                );
              })}
            </div>
          </div>
        </div>
      ) : (
        <button
          type="button"
          onClick={() => {
            setOpen(true);
            if (!reply && !busy) void run(false);
          }}
          className="group pointer-events-auto relative mt-[35px] min-h-11 active:opacity-70"
          aria-label={pillLabel}
        >
          {/* Mascot peeking from BEHIND the pill's top edge. */}
          {mascot(-33.56)}
          <JasperMintPill mode={mode} className={cn("relative z-10 justify-center gap-2 px-[19px]", alignToContent ? "h-9 min-w-[90px]" : "h-[34px]")} style={pillStyle}>
            {costume?.pillIconSrc && (
              <span
                aria-hidden
                className="inline-block h-[14px] w-[24px] shrink-0"
                style={{
                  WebkitMaskImage: `url(${costume.pillIconSrc})`,
                  maskImage: `url(${costume.pillIconSrc})`,
                  WebkitMaskSize: "contain",
                  maskSize: "contain",
                  WebkitMaskRepeat: "no-repeat",
                  maskRepeat: "no-repeat",
                  WebkitMaskPosition: "center",
                  maskPosition: "center",
                  background: accent,
                }}
              />
            )}
            {alignToContent && !busy ? <KnotWordmark width={52} /> : <span className="text-[14px] font-semibold" style={{ color: inkColor }}>{busy ? "Thinking…" : pillLabel}</span>}
          </JasperMintPill>
        </button>
      )}
    </div>,
    document.body
  )}</>;
}
