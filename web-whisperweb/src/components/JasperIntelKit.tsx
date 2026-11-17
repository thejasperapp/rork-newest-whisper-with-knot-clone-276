import React, { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  Activity,
  ArrowUpRight,
  BookOpen,
  CalendarPlus,
  Check,
  Droplets,
  Dumbbell,
  HeartPulse,
  MessageCircle,
  PenSquare,
  Phone,
  ShoppingCart,
  Sparkles,
  Store,
  UserPlus,
  UtensilsCrossed,
} from "lucide-react";

import {
  JASPER_APP_MAP,
  jasperActionLabel,
  type JasperAction,
} from "@/lib/emberAtlas";
import {
  jasperGlassShellStyle,
  jasperMintShellStyle,
  jasperPillPalette,
  JASPER_SHEET_DARK,
  JASPER_SHEET_LIGHT,
  type JasperSheetTheme,
} from "@/lib/jasperIntel";
import { coachModeInfo, type EmberCoachMode } from "@/lib/emberBrain";
import { cn } from "@/lib/utils";

/**
 * Jasper Intelligence web kit — the shared visual language transcribed 1:1
 * from iOS: the MintShell personality pill, the dark-glass assistant box,
 * the JASPER reply card (header + personality chip + accent bar), the
 * meeting-flavor thinking rail, Jasper's rich-text rules, and the real
 * action buttons (same 14-kind grammar as iOS).
 */

// MARK: - Adaptive theme hook

export function useJasperDark(): boolean {
  const [dark, setDark] = useState<boolean>(() =>
    typeof document !== "undefined"
      ? document.documentElement.classList.contains("dark")
      : false
  );
  useEffect(() => {
    const root = document.documentElement;
    const sync = (): void => setDark(root.classList.contains("dark"));
    sync();
    const observer = new MutationObserver(sync);
    observer.observe(root, { attributes: true, attributeFilter: ["class"] });
    return () => observer.disconnect();
  }, []);
  return dark;
}

export function useJasperSheetTheme(): { theme: JasperSheetTheme; dark: boolean } {
  const dark = useJasperDark();
  return { theme: dark ? JASPER_SHEET_DARK : JASPER_SHEET_LIGHT, dark };
}

// MARK: - Mint pill (WhisperEmberMintShell capsule)

export function JasperMintPill({
  mode,
  children,
  compact = false,
  className,
  style,
}: {
  mode: EmberCoachMode;
  children: React.ReactNode;
  compact?: boolean;
  className?: string;
  style?: React.CSSProperties;
}) {
  return (
    <span
      className={cn("relative flex items-center rounded-full", className)}
      style={{ ...jasperMintShellStyle(mode, compact), ...style }}
    >
      {children}
    </span>
  );
}

// MARK: - Rich text (WhisperEmberRichText rules)

function inlineSpans(text: string, boldClass: string): React.ReactNode[] {
  return text.split("**").map((part, i) => {
    const content = part.split(/(https?:\/\/[^\s<>]+)/g).map((token, index) => {
      if (!/^https?:\/\//i.test(token)) return token;
      const href = token.replace(/[.,;!?)\]]+$/, "");
      try {
        const url = new URL(href);
        if (url.protocol !== "https:" && url.protocol !== "http:") return token;
        return <React.Fragment key={index}><a href={url.href} target="_blank" rel="noopener noreferrer" className="break-words underline decoration-current/40 underline-offset-2 hover:decoration-current">{href}</a>{token.slice(href.length)}</React.Fragment>;
      } catch { return token; }
    });
    return i % 2 === 1
      ? <strong key={i} className={boldClass}>{content}</strong>
      : <React.Fragment key={i}>{content}</React.Fragment>;
  });
}

/**
 * Jasper's answer formatting — headings ("## "), bullets ("- "), numbered
 * steps, dividers ("---"), inline **bold** — block spacing 7px, matching the
 * iOS renderer. `ink` drives the text color; `onDark` softens markers.
 */
export const JasperRichText = memo(function JasperRichText({
  text,
  ink,
  onDark = false,
  baseSize = 16,
}: {
  text: string;
  ink: string;
  onDark?: boolean;
  baseSize?: number;
}) {
  const soft = onDark ? "rgba(255,255,255,0.55)" : `${ink}80`;
  const lines = text.split(/\r?\n/);
  const blocks: React.ReactNode[] = [];
  lines.forEach((rawLine, idx) => {
    const line = rawLine.trimEnd();
    const trimmed = line.trim();
    if (!trimmed) return;
    if (trimmed === "---") {
      blocks.push(
        <div
          key={idx}
          className="my-0.5 h-px w-full"
          style={{ background: onDark ? "rgba(255,255,255,0.14)" : "rgba(0,0,0,0.08)" }}
        />
      );
      return;
    }
    const heading = /^(#{1,4})\s+(.*)$/.exec(trimmed);
    const boldLine = /^\*\*(.+)\*\*$/.exec(trimmed);
    if (heading || boldLine) {
      const level = heading ? heading[1].length : 3;
      const content = heading ? heading[2] : boldLine![1];
      const size = baseSize + (level === 1 ? 4 : level === 2 ? 3 : 1.5);
      blocks.push(
        <p
          key={idx}
          className={level <= 2 ? "font-black" : "font-bold"}
          style={{ fontSize: size, color: ink, paddingTop: 3, lineHeight: 1.25 }}
        >
          {inlineSpans(content, "font-black")}
        </p>
      );
      return;
    }
    const bullet = /^[-•]\s+(.*)$/.exec(trimmed);
    if (bullet) {
      blocks.push(
        <div key={idx} className="flex items-start gap-2">
          <span
            className="mt-[0.42em] h-[5px] w-[5px] shrink-0 rounded-full"
            style={{ background: soft }}
          />
          <span style={{ fontSize: baseSize, color: ink, lineHeight: 1.45 }}>
            {inlineSpans(bullet[1], "font-bold")}
          </span>
        </div>
      );
      return;
    }
    const numbered = /^(\d+)[.)]\s+(.*)$/.exec(trimmed);
    if (numbered) {
      blocks.push(
        <div key={idx} className="flex items-start gap-2">
          <span
            className="shrink-0 font-bold tabular-nums"
            style={{ fontSize: baseSize, color: soft }}
          >
            {numbered[1]}.
          </span>
          <span style={{ fontSize: baseSize, color: ink, lineHeight: 1.45 }}>
            {inlineSpans(numbered[2], "font-bold")}
          </span>
        </div>
      );
      return;
    }
    blocks.push(
      <p key={idx} style={{ fontSize: baseSize, color: ink, lineHeight: 1.45 }}>
        {inlineSpans(trimmed, "font-bold")}
      </p>
    );
  });
  return <div className="flex flex-col" style={{ gap: 7 }}>{blocks}</div>;
});

// MARK: - JASPER reply card (meeting box + analysis dock)

export function JasperReplyCard({
  mode,
  text,
  children,
  accent,
  soft,
  chipLabel,
}: {
  mode: EmberCoachMode;
  text: string;
  children?: React.ReactNode;
  /** Costume overrides — the dating dock's rose matchmaker look. */
  accent?: string;
  soft?: string;
  chipLabel?: string;
}) {
  const info = coachModeInfo(mode);
  const a = accent ?? info.accent;
  const s = soft ?? info.softAccent;
  return (
    <div
      className="relative rounded-2xl bg-white/5 py-[11px] pl-3.5 pr-[11px]"
      style={{ border: `1px solid ${a}33`, transition: "border-color 350ms ease-in-out" }}
    >
      <span
        className="absolute bottom-2.5 left-[5px] top-2.5 w-[3px] rounded-full"
        style={{ background: `${a}B3` }}
      />
      <div className="mb-1.5 flex items-center gap-1">
        <Sparkles className="h-2.5 w-2.5" strokeWidth={3} style={{ color: s }} />
        <span
          className="text-[9px] font-black uppercase"
          style={{ color: s, letterSpacing: "1.4px" }}
        >
          Knot
        </span>
        <span
          className="ml-auto rounded-full bg-white/[0.08] px-[7px] py-[3px] text-[8px] font-black uppercase text-white/45"
          style={{ letterSpacing: "0.8px" }}
        >
          {chipLabel ?? info.shortTitle}
        </span>
      </div>
      <JasperRichText text={text} ink="rgba(255,255,255,0.92)" onDark baseSize={15} />
      {children}
    </div>
  );
}

// MARK: - Meeting-flavor thinking rail (WhisperEmberThinkingSteps .meeting)

const MEETING_PHASES: { icon: string; label: string }[] = [
  { icon: "ear", label: "Reading the meeting" },
  { icon: "tray", label: "Pulling your Whisper context" },
  { icon: "bubble", label: "Writing your private answer" },
];

const ANALYTICAL_PHASES: { icon: string; label: string }[] = [
  { icon: "tray", label: "Reading your data" },
  { icon: "code", label: "Writing the analysis" },
  { icon: "play", label: "Running it on your numbers" },
];

export function JasperThinkingRail({
  mode,
  analytical = false,
  phases,
}: {
  mode: EmberCoachMode;
  analytical?: boolean;
  phases?: string[];
}) {
  const info = coachModeInfo(mode);
  const list = useMemo(
    () => phases ?? (analytical ? ANALYTICAL_PHASES : MEETING_PHASES).map((p) => p.label),
    [phases, analytical]
  );
  const [step, setStep] = useState<number>(0);
  useEffect(() => {
    setStep(0);
    const timer = setInterval(
      () => setStep((s) => Math.min(s + 1, list.length - 1)),
      950
    );
    return () => clearInterval(timer);
  }, [list]);
  return (
    <div
      className="flex flex-col gap-0 rounded-2xl px-[13px] py-2.5"
      style={{ background: "rgba(255,255,255,0.07)", border: "1px solid rgba(255,255,255,0.10)" }}
    >
      {list.map((label, i) => (
        <div key={label} className="flex items-stretch gap-2">
          <div className="flex w-4 flex-col items-center">
            <span className="flex h-4 w-4 items-center justify-center">
              {i < step ? (
                <Check className="h-2.5 w-2.5" strokeWidth={4} style={{ color: info.accent }} />
              ) : i === step ? (
                <span
                  className="h-3 w-3 animate-spin rounded-full border-[1.5px] border-transparent"
                  style={{ borderTopColor: info.accent, borderRightColor: info.accent }}
                />
              ) : (
                <span
                  className="h-[9px] w-[9px] rounded-full border-[1.5px]"
                  style={{ borderColor: "rgba(255,255,255,0.22)" }}
                />
              )}
            </span>
            {i < list.length - 1 && (
              <span className="w-[1.5px] flex-1" style={{ background: "rgba(255,255,255,0.16)", minHeight: 8 }} />
            )}
          </div>
          <span
            className={cn(
              "pb-1.5 text-[12px]",
              i === step ? "font-bold text-white" : i < step ? "font-semibold text-white" : "font-semibold text-white/50"
            )}
          >
            {label}
          </span>
        </div>
      ))}
    </div>
  );
}

// MARK: - Personality blob (WHISPER_PLANS.md §5b — the morphing mode blob)

/** §5b layer table: (scale, phase, opacity, speed). */
const BLOB_LAYERS: readonly [number, number, number, number][] = [
  [0.98, 0.0, 0.4, 0.7],
  [0.86, 1.7, 0.6, 1.05],
  [0.72, 3.3, 1.0, 1.45],
];

/** §5b canvas outline — the exact mode-blob wobble coefficients. */
function modeBlobPath(ctx: CanvasRenderingContext2D, cx: number, cy: number, R: number, t: number): void {
  ctx.beginPath();
  for (let i = 0; i <= 64; i++) {
    const a = (i / 64) * 2 * Math.PI;
    const wob =
      0.11 * Math.sin(3 * a + t) + 0.07 * Math.sin(5 * a - 1.3 * t) + 0.05 * Math.sin(2 * a + 0.7 * t);
    const r = R * (1 + wob);
    const x = cx + Math.cos(a) * r;
    const y = cy + Math.sin(a) * r;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.closePath();
}

/**
 * The morphing mode blob — WHISPER_PLANS.md §5b, exact construction: a
 * 64-point sine-wobbled outline, three stacked layers filled with the mode's
 * softAccent → accent → deepAccent gradient, a glassy white highlight blob,
 * the canvas 1.5× the size so the wobble overflows, and a drop shadow
 * `accent @ 0.38`. 30fps.
 */
export function JasperPersonalityBlob({
  accent,
  deepAccent,
  softAccent,
  icon,
  size = 40,
  className,
}: {
  accent: string;
  deepAccent?: string;
  softAccent?: string;
  icon?: React.ReactNode;
  size?: number;
  className?: string;
}) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const frame = size * 1.5;
  const deep = deepAccent ?? accent;
  const soft = softAccent ?? accent;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = frame * dpr;
    canvas.height = frame * dpr;

    let raf = 0;
    let last = 0;
    const draw = (now: number): void => {
      raf = requestAnimationFrame(draw);
      if (now - last < 1000 / 30) return; // 30fps is plenty (§5b)
      last = now;
      const t = now / 1000;
      const cx = (frame * dpr) / 2;
      const cy = (frame * dpr) / 2;
      const R = (size / 2) * dpr;
      ctx.clearRect(0, 0, canvas.width, canvas.height);

      const gradient = ctx.createLinearGradient(cx - R, cy - R, cx + R, cy + R);
      gradient.addColorStop(0, soft);
      gradient.addColorStop(0.5, accent);
      gradient.addColorStop(1, deep);

      for (const [scale, phase, opacity, speed] of BLOB_LAYERS) {
        ctx.globalAlpha = opacity;
        ctx.fillStyle = gradient;
        modeBlobPath(ctx, cx, cy, R * scale, t * speed + phase);
        ctx.fill();
      }

      // §5b glassy highlight: white @ 0.28, radius 0.42R, offset (−0.16R, −0.18R).
      ctx.globalAlpha = 1;
      ctx.fillStyle = "rgba(255,255,255,0.28)";
      modeBlobPath(ctx, cx - R * 0.16, cy - R * 0.18, R * 0.42, t * 1.6 + 0.6);
      ctx.fill();
    };
    raf = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(raf);
  }, [accent, deep, soft, size, frame]);

  return (
    <span
      className={cn("relative inline-flex items-center justify-center", className)}
      style={{ width: frame, height: frame, filter: `drop-shadow(0 4px 10px ${accent}61)` }}
    >
      <canvas ref={canvasRef} style={{ width: frame, height: frame }} aria-hidden />
      {icon && (
        <span
          className="absolute inline-flex"
          style={{ filter: `drop-shadow(0 1px 4px ${deep}80)` }}
        >
          {icon}
        </span>
      )}
    </span>
  );
}

// MARK: - Voice glyph (WhisperJasperVoiceGlyph — 5 breathing capsules)

export function JasperVoiceGlyph({
  tint,
  size = 17,
  active = false,
}: {
  tint: string;
  size?: number;
  active?: boolean;
}) {
  const barWidth = size * 0.13;
  const gap = size * 0.08;
  return (
    <span
      className="relative inline-flex items-center justify-center"
      style={{ width: size * 1.5, height: size * 1.4 }}
    >
      <span
        className="absolute rounded-full"
        style={{
          width: size * 1.5,
          height: size * 1.5,
          background: tint,
          opacity: active ? 0.34 : 0.2,
          filter: `blur(${size * 0.28}px)`,
          animation: "jasper-blob-breathe 2.2s ease-in-out infinite",
        }}
      />
      <span className="relative flex items-center" style={{ gap }}>
        {[0, 1, 2, 3, 4].map((i) => (
          <span
            key={i}
            className="rounded-full"
            style={{
              width: barWidth,
              height: size * (0.42 + 0.24 * Math.abs(2 - i) * 0.5 + 0.18 * (i % 2)),
              background: tint,
              animation: `jasper-voice-bar ${active ? 0.7 : 1.5}s ease-in-out ${i * 0.12}s infinite alternate`,
            }}
          />
        ))}
      </span>
    </span>
  );
}

/** One-time keyframes for the kit's living pieces. */
export function JasperKitKeyframes() {
  return (
    <style>{`
@keyframes jasper-blob-breathe { 0%,100% { transform: scale(1); } 50% { transform: scale(1.07); } }
@keyframes jasper-blob-drift-a { 0%,100% { transform: translate(0,0); } 50% { transform: translate(2px,-2px); } }
@keyframes jasper-blob-drift-b { 0%,100% { transform: translate(0,0); } 50% { transform: translate(-2px,2px); } }
@keyframes jasper-voice-bar { from { transform: scaleY(0.55); } to { transform: scaleY(1.15); } }
@keyframes jasper-bloom-drift-a { 0%,100% { transform: translate(38px,-262px); } 50% { transform: translate(-44px,-310px); } }
@keyframes jasper-bloom-drift-b { 0%,100% { transform: translate(-108px,128px); } 50% { transform: translate(-152px,46px); } }
@keyframes jasper-bloom-drift-c { 0%,100% { transform: translate(128px,392px); } 50% { transform: translate(172px,322px); } }
@keyframes jasper-dock-open { from { opacity: 0; transform: translateY(14px) scale(0.82); } to { opacity: 1; transform: translateY(0) scale(1); } }
@keyframes jasper-peek-in { from { opacity: 0; transform: translateY(120px); } to { opacity: 1; transform: translateY(0); } }
@keyframes jasper-glow-pulse { 0%,100% { opacity: 0.35; } 50% { opacity: 0.8; } }
@keyframes jasper-mascot-bob { 0%,100% { transform: translateY(-2px); } 50% { transform: translateY(2px); } }
`}</style>
  );
}

// MARK: - Canvas backdrop (WhisperEmberSheetTheme.Backdrop — 3 drifting blooms)

export function JasperCanvasBackdrop({
  bloom,
  lavender,
  canvas,
}: {
  bloom: string;
  lavender: string;
  canvas: string;
}) {
  return (
    <div
      className="pointer-events-none absolute inset-0 overflow-hidden"
      style={{ background: canvas, transition: "background 500ms ease-in-out" }}
    >
      <span
        className="absolute left-1/2 top-1/2 -ml-[280px] -mt-[280px] h-[560px] w-[560px] rounded-full"
        style={{
          background: bloom,
          filter: "blur(90px)",
          opacity: 0.85,
          animation: "jasper-bloom-drift-a 9s ease-in-out infinite",
          transition: "background 500ms ease-in-out",
        }}
      />
      <span
        className="absolute left-1/2 top-1/2 -ml-[180px] -mt-[180px] h-[360px] w-[360px] rounded-full"
        style={{
          background: bloom,
          filter: "blur(90px)",
          opacity: 0.36,
          animation: "jasper-bloom-drift-b 9s ease-in-out infinite",
          transition: "background 500ms ease-in-out",
        }}
      />
      <span
        className="absolute left-1/2 top-1/2 -ml-[235px] -mt-[235px] h-[470px] w-[470px] rounded-full"
        style={{
          background: lavender,
          filter: "blur(100px)",
          opacity: 0.32,
          animation: "jasper-bloom-drift-c 9s ease-in-out infinite",
        }}
      />
    </div>
  );
}

// MARK: - Action buttons (the 14-kind grammar, real routing)

const ACTION_ICONS: Record<JasperAction["kind"], React.ComponentType<{ className?: string; style?: React.CSSProperties }>> = {
  open: ArrowUpRight,
  call: Phone,
  message: MessageCircle,
  schedule: CalendarPlus,
  plan: Dumbbell,
  post: PenSquare,
  follow: UserPlus,
  bioage: HeartPulse,
  dietplan: UtensilsCrossed,
  groceries: ShoppingCart,
  clientdashboard: Activity,
  marketplace: Store,
  recipe: BookOpen,
  water: Droplets,
};

export interface JasperPanelRequest {
  kind: "marketplace" | "recipes" | "grocery" | "water" | "dietplan";
  query?: string;
  clientUsername?: string;
  recipeDraft?: JasperAction;
}

/**
 * Routes a Jasper action to its real surface — panels for the Jasper
 * modals, navigation for app routes, and inline editors (message /
 * schedule / plan / post) handled by the host via `onEditor`.
 */
export function useJasperActionRouter(opts: {
  openPanel: (request: JasperPanelRequest) => void;
  onEditor?: (action: JasperAction) => void;
  onClientDashboard?: (username: string) => void;
}): (action: JasperAction) => void {
  const navigate = useNavigate();
  const { openPanel, onEditor, onClientDashboard } = opts;
  return useCallback(
    (action: JasperAction): void => {
      switch (action.kind) {
        case "open": {
          if (action.route === "recipes") return openPanel({ kind: "recipes" });
          if (action.route === "water") return openPanel({ kind: "water" });
          const entry = JASPER_APP_MAP.find((e) => e.route === action.route);
          if (!entry) return;
          if (entry.arg && action.arg) {
            navigate(`${entry.path}${encodeURIComponent(action.arg)}`);
          } else {
            navigate(entry.path || "/");
          }
          return;
        }
        case "call":
        case "message":
        case "schedule":
        case "plan":
        case "post":
          onEditor?.(action);
          return;
        case "follow":
          onEditor?.(action);
          return;
        case "bioage":
          if (action.username && onClientDashboard) return onClientDashboard(action.username);
          navigate("/settings");
          return;
        case "dietplan":
          openPanel({ kind: "dietplan", clientUsername: action.username });
          return;
        case "groceries":
          openPanel({ kind: "grocery", clientUsername: action.username });
          return;
        case "clientdashboard":
          if (action.username && onClientDashboard) return onClientDashboard(action.username);
          navigate(`/coach${action.username ? `?client=${encodeURIComponent(action.username)}` : ""}`);
          return;
        case "marketplace":
          openPanel({ kind: "marketplace", query: action.arg });
          return;
        case "recipe":
          openPanel({ kind: "recipes", recipeDraft: action });
          return;
        case "water":
          openPanel({ kind: "water" });
          return;
      }
    },
    [navigate, openPanel, onEditor, onClientDashboard]
  );
}

/** The action button row Jasper attaches under a reply. */
export function JasperActionRow({
  actions,
  onRun,
  dark = false,
  ink,
  surface,
  stroke,
}: {
  actions: JasperAction[];
  onRun: (action: JasperAction) => void;
  dark?: boolean;
  ink: string;
  surface: string;
  stroke: string;
}) {
  if (actions.length === 0) return null;
  return (
    <div className="flex flex-col gap-2">
      {actions.map((action, i) => {
        const Icon = ACTION_ICONS[action.kind];
        return (
          <button
            key={`${action.kind}-${i}`}
            type="button"
            onClick={() => onRun(action)}
            className="flex items-center gap-2.5 rounded-2xl px-3.5 py-3 text-left transition-transform active:scale-[0.98]"
            style={{ background: surface, border: `1px solid ${stroke}` }}
          >
            <span
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full"
              style={{ background: dark ? "rgba(255,255,255,0.1)" : "rgba(18,20,31,0.07)" }}
            >
              <Icon className="h-4 w-4" style={{ color: ink }} />
            </span>
            <span className="min-w-0 flex-1 truncate text-[13.5px] font-bold" style={{ color: ink }}>
              {jasperActionLabel(action)}
            </span>
            <ArrowUpRight className="h-3.5 w-3.5 shrink-0 opacity-50" style={{ color: ink }} />
          </button>
        );
      })}
    </div>
  );
}

// MARK: - Glass box (shared shell for meeting box + analysis dock)

export function jasperBoxStyle(mode: EmberCoachMode): React.CSSProperties {
  const info = coachModeInfo(mode);
  return {
    ...jasperGlassShellStyle(info.accent),
    borderRadius: 24,
  };
}

export { jasperPillPalette };
