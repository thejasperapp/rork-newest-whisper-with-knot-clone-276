import type { CSSProperties } from "react";

import type { EmberCoachMode } from "@/lib/emberBrain";

/**
 * Jasper Intelligence design tokens — the EXACT values from the iOS
 * `WhisperEmberPillStyle.swift` (pill palette + mint shell) and
 * `WhisperEmberSheetTheme` (adaptive chat canvas), so web renders 1:1
 * with the native app. Every hex here is transcribed from source.
 */

// MARK: - Personality pill palette (pale pill surfaces)

export interface JasperPillPalette {
  /** Pale capsule fill. */
  fill: string;
  /** Edge tracing. */
  rim: string;
  /** Colored shadow / glow. */
  glow: string;
  /** Text on the pill. */
  ink: string;
  /** Small status dot. */
  badge: string;
}

const PILL: Record<Exclude<EmberCoachMode, "auto">, JasperPillPalette> = {
  regular: { fill: "#EFF4F1", rim: "#ABE7CB", glow: "#33D499", ink: "#0A1712", badge: "#3DC794" },
  guardian: { fill: "#FFF9E4", rim: "#F0C96B", glow: "#FFC742", ink: "#1C1405", badge: "#DB8C0D" },
  drill_sergeant: { fill: "#FFEDE9", rim: "#F59985", glow: "#F53329", ink: "#210A08", badge: "#A30D0A" },
  scientist: { fill: "#F0EDFF", rim: "#B39EF5", glow: "#9461FF", ink: "#120D24", badge: "#522BB8" },
};

/**
 * Resolves "auto" to today's readiness-picked ghost. Reads the cached
 * resolution emberBrain maintains (source of truth: `resolveAutoConcrete`)
 * without importing it — keeps this token file dependency-free.
 */
function concreteMode(mode: EmberCoachMode): Exclude<EmberCoachMode, "auto"> {
  if (mode !== "auto") return mode;
  try {
    const raw = localStorage.getItem("whisper_ember_auto_resolved_mode");
    if (raw === "regular" || raw === "guardian" || raw === "drill_sergeant" || raw === "scientist") {
      return raw;
    }
  } catch {
    /* storage unavailable */
  }
  return "regular";
}

export function jasperPillPalette(mode: EmberCoachMode): JasperPillPalette {
  return PILL[concreteMode(mode)] ?? PILL.regular;
}

// MARK: - Adaptive sheet theme (WhisperEmberSheetTheme)

export interface JasperSheetTheme {
  canvas: string;
  mintGlow: string;
  lavenderGlow: string;
  card: string;
  ink: string;
  muted: string;
  hairline: string;
  violet: string;
  surface: string;
  surfaceStrong: string;
  stroke: string;
  /** Opaque chrome (header pill, menu circle, plus button). */
  pillFill: string;
  pillStroke: string;
  userBubble: string;
  userBubbleInk: string;
  primaryFill: string;
  primaryInk: string;
  fieldFill: string;
  cardShadow: string;
}

export const JASPER_SHEET_LIGHT: JasperSheetTheme = {
  canvas: "#F4F4F8",
  mintGlow: "#C9F2E0",
  lavenderGlow: "#DBD4FA",
  card: "#FFFFFF",
  ink: "#1A1A24",
  muted: "#707385",
  hairline: "rgba(0,0,0,0.07)",
  violet: "#7061E0",
  surface: "rgba(18,20,31,0.05)",
  surfaceStrong: "rgba(18,20,31,0.09)",
  stroke: "rgba(0,0,0,0.06)",
  pillFill: "#FFFFFF",
  pillStroke: "rgba(0,0,0,0.08)",
  userBubble: "#4278F5",
  userBubbleInk: "#FFFFFF",
  primaryFill: "#1A1A24",
  primaryInk: "#FFFFFF",
  fieldFill: "#FFFFFF",
  cardShadow: "rgba(0,0,0,0.10)",
};

export const JASPER_SHEET_DARK: JasperSheetTheme = {
  canvas: "#0C0C14",
  mintGlow: "#1A3B2F",
  lavenderGlow: "#302A59",
  card: "#20212F",
  ink: "#F0F2FA",
  muted: "#999EB3",
  hairline: "rgba(255,255,255,0.09)",
  violet: "#A18FFF",
  surface: "rgba(255,255,255,0.07)",
  surfaceStrong: "rgba(255,255,255,0.12)",
  stroke: "rgba(255,255,255,0.09)",
  pillFill: "#222433",
  pillStroke: "rgba(255,255,255,0.16)",
  userBubble: "rgba(255,255,255,0.10)",
  userBubbleInk: "#F0F2FA",
  primaryFill: "#FFFFFF",
  primaryInk: "#0D0D17",
  fieldFill: "rgba(255,255,255,0.07)",
  cardShadow: "rgba(0,0,0,0.30)",
};

/** Canvas bloom per personality — `WhisperEmberSheetTheme.bloom(for:)`. */
const BLOOM_LIGHT: Record<Exclude<EmberCoachMode, "auto">, string> = {
  regular: "#C7F2DE",
  guardian: "#FFE6A6",
  drill_sergeant: "#FFD4C7",
  scientist: "#DED1FF",
};
const BLOOM_DARK: Record<Exclude<EmberCoachMode, "auto">, string> = {
  regular: "#1A3B2F",
  guardian: "#45360F",
  drill_sergeant: "#471712",
  scientist: "#332666",
};

export function jasperBloom(mode: EmberCoachMode, dark: boolean): string {
  return (dark ? BLOOM_DARK : BLOOM_LIGHT)[concreteMode(mode)] ?? BLOOM_LIGHT.regular;
}

// MARK: - Shared motion (iOS springs → CSS approximations)

export const JASPER_SPRING_OPEN = "450ms cubic-bezier(0.34, 1.3, 0.5, 1)";
export const JASPER_SPRING_CLOSE = "360ms cubic-bezier(0.3, 1.1, 0.5, 1)";
export const JASPER_SPRING_PEEK = "750ms cubic-bezier(0.34, 1.45, 0.64, 1)";
export const JASPER_RECOLOR = "350ms ease-in-out";

/** Jasper brand (glow surfaces — coach tools, celebration, builders). */
export const JASPER_EMBER = "#F39057";
export const JASPER_EMBER_DEEP = "#E76F3A";
export const JASPER_EMBER_GRADIENT = `linear-gradient(135deg, ${JASPER_EMBER}, ${JASPER_EMBER_DEEP})`;
export const JASPER_ORANGE = "#F39057";

// MARK: - The ember glow box (WHISPER_PLANS.md §1–§2, exact values)

/** §2 card fills — warm cream (light) / charcoal (dark), always OPAQUE. */
export const EMBER_CREAM = "#FCF6E9";
export const EMBER_CHARCOAL = "#24201D";
/** Near-black warm ink on the cream card. */
export const EMBER_INK = "#211C1A";
/** §1 coach attribution accent. */
export const JASPER_BRONZE = "#9E6B40";

/** §4 canonical macro accents — kcal ember · protein teal · carbs amber · fat blue. */
export const JASPER_MACROS = {
  kcal: "#F39057",
  protein: "#5CDBB8",
  carbs: "#F2B14D",
  fat: "#3394E0",
} as const;

/** §2 layered ember aura — two orange shadows scaled by `glow` + one neutral contact shadow. */
export function emberGlowShadows(dark: boolean, glow = 1): string {
  const orange = ((dark ? 0.26 : 0.32) * glow).toFixed(3);
  const deep = ((dark ? 0.10 : 0.14) * glow).toFixed(3);
  const contact = dark ? 0.45 : 0.05;
  return `0 5px 16px rgba(243,144,87,${orange}), 0 10px 34px rgba(231,111,58,${deep}), 0 2px 8px rgba(0,0,0,${contact})`;
}

/**
 * The exact `emberGlowCard` recipe: opaque cream/charcoal fill, 1px warm
 * gradient hairline, layered ember aura. `glow` scales ONLY the orange
 * shadows — 1.0 hero/solo, 0.5 stacked in lists.
 */
export function emberGlowCardStyle(dark: boolean, glow = 1, radius = 22): CSSProperties {
  const fill = dark ? EMBER_CHARCOAL : EMBER_CREAM;
  const hairline = dark
    ? "linear-gradient(135deg, rgba(243,144,87,0.34), rgba(255,255,255,0.06))"
    : "linear-gradient(135deg, rgba(243,144,87,0.55), rgba(231,111,58,0.16))";
  return {
    background: `linear-gradient(${fill}, ${fill}) padding-box, ${hairline} border-box`,
    border: "1px solid transparent",
    borderRadius: radius,
    boxShadow: emberGlowShadows(dark, glow),
    color: dark ? "#FFFFFF" : EMBER_INK,
  };
}

/** §2 quiet ink insets — overview blocks / meal cards, and quieter stacked rows. */
export function emberInset(dark: boolean, row = false): string {
  if (dark) return row ? "rgba(255,255,255,0.065)" : "rgba(255,255,255,0.08)";
  return row ? "rgba(33,28,26,0.035)" : "rgba(33,28,26,0.045)";
}

/** Secondary text on the glow card — ink/white @ 0.58. */
export function emberSubtle(dark: boolean, alpha = 0.58): string {
  return dark ? `rgba(255,255,255,${alpha})` : `rgba(33,28,26,${alpha})`;
}

/** §2 kicker color — deepOrange on cream, orange on charcoal. */
export function emberKicker(dark: boolean): string {
  return dark ? JASPER_EMBER : JASPER_EMBER_DEEP;
}

/** §2 `EmberGlowIcon` tile — radial ember gradient, hairline, twin shadows. */
export function emberGlowIconStyle(dark: boolean, size = 40): CSSProperties {
  return {
    width: size,
    height: size,
    borderRadius: size * 0.3,
    background: `radial-gradient(circle at center, rgba(243,144,87,${dark ? 0.44 : 0.42}) 0%, rgba(243,144,87,0.12) 100%)`,
    border: `1px solid rgba(243,144,87,${dark ? 0.36 : 0.38})`,
    boxShadow: "0 2px 7px rgba(243,144,87,0.5), 0 4px 14px rgba(231,111,58,0.22)",
    color: dark ? "#FCF2E3" : "#000000",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    flexShrink: 0,
  };
}

/** Readiness spec colors (Jasper native looks). */
export function jasperReadinessColor(score: number): string {
  if (score >= 75) return "#5CDBB8";
  if (score >= 50) return "#3394E0";
  return "#F26659";
}

/** MintShell layer recipe as CSS (fill + gloss + rim + twin shadows). */
export function jasperMintShellStyle(
  mode: EmberCoachMode,
  compact = false
): CSSProperties {
  const p = jasperPillPalette(mode);
  return {
    background: `linear-gradient(to bottom, rgba(255,255,255,0.6), rgba(255,255,255,0) 50%), ${p.fill}`,
    border: `1.5px solid ${p.rim}${compact ? "D9" : "F2"}`,
    boxShadow: compact
      ? `0 2px 6px ${p.glow}38, 0 2px 4px rgba(0,0,0,0.08)`
      : `0 4px 10px ${p.glow}57, 0 5px 8px rgba(0,0,0,0.13)`,
    color: p.ink,
    transition: `background ${JASPER_RECOLOR}, border-color ${JASPER_RECOLOR}, box-shadow ${JASPER_RECOLOR}`,
  };
}

/** The 4-layer dark glass shell (meeting box + analysis dock). */
export function jasperGlassShellStyle(accent: string, compact = false): CSSProperties {
  return {
    background: `linear-gradient(to bottom, ${accent}${compact ? "29" : "33"}, transparent), rgba(6,8,12,0.62)`,
    backdropFilter: "blur(22px)",
    WebkitBackdropFilter: "blur(22px)",
    border: `1px solid ${accent}${compact ? "66" : "52"}`,
    boxShadow: compact
      ? `0 4px 11px ${accent}52, 0 6px 13px rgba(0,0,0,0.35)`
      : `0 5px 16px ${accent}40, 0 10px 22px rgba(0,0,0,0.45)`,
  };
}
