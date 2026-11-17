/**
 * THE Whisper gradient — the one brand sweep every surface shares, on both
 * apps: the LIVE gradient. Rose → live orange → amber glow — the exact sweep
 * the LIVE rings, LIVE badges, and "Go live" already wear, promoted to the
 * brand. Matches `WhisperBrandGradient` on iOS 1:1. Use these instead of
 * ad-hoc gradients so the algorithm headline, the Waves mark, the paywalls,
 * the type-in text, and every premium moment read as the same brand.
 */
export const WHISPER_BRAND_COLORS: readonly [string, string, string] = [
  "#F22659",
  "#FF7340",
  "#FFA94D",
] as const;

/** Left → right — text fills, headlines, progress bars. */
export const WHISPER_BRAND_GRADIENT =
  "linear-gradient(90deg, #F22659 0%, #FF7340 50%, #FFA94D 100%)";

/** Top-left → bottom-right — buttons, tiles, icon chips. */
export const WHISPER_BRAND_GRADIENT_DIAGONAL =
  "linear-gradient(135deg, #F22659 0%, #FF7340 50%, #FFA94D 100%)";

/** Top → bottom — hero washes and scrims. */
export const WHISPER_BRAND_GRADIENT_VERTICAL =
  "linear-gradient(180deg, #F22659 0%, #FF7340 50%, #FFA94D 100%)";

/** Tailwind arbitrary-value class carrying the diagonal sweep. */
export const WHISPER_BRAND_GRADIENT_TW =
  "bg-[linear-gradient(135deg,#F22659,#FF7340,#FFA94D)]";

/** The live-orange mid-stop — the single accent when one color has to stand in. */
export const WHISPER_BRAND_ACCENT = "#FF7340";
/** The amber end-stop. */
export const WHISPER_BRAND_AMBER = "#FFA94D";
/** The rose start-stop. */
export const WHISPER_BRAND_ROSE = "#F22659";

// Legacy names kept so older call sites keep compiling on the new sweep.
export const WHISPER_BRAND_INDIGO = "#F22659";
export const WHISPER_BRAND_MINT = "#FFA94D";
