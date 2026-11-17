/**
 * Appearance control for Whisper web — mirrors the iOS app's appearance
 * setting (System / Light / Dark / Pitch black). "Pitch black" is the OLED
 * theme: the dark palette with pure-black surfaces, exactly like the iOS
 * "Pitch black" toggle in Settings → Appearance.
 */
export type AppearanceMode = "system" | "light" | "dark" | "pitch-black";

const STORAGE_KEY = "whisper.appearance";

export const APPEARANCE_MODES: { id: AppearanceMode; label: string; subtitle: string }[] = [
  { id: "system", label: "System", subtitle: "Match your device appearance" },
  { id: "light", label: "Light", subtitle: "Always use the light theme" },
  { id: "dark", label: "Dark", subtitle: "Deep indigo, like the app" },
  { id: "pitch-black", label: "Pitch black", subtitle: "True black — easy on OLED screens" },
];

export function getAppearance(): AppearanceMode {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw === "light" || raw === "dark" || raw === "pitch-black" || raw === "system") {
      return raw;
    }
  } catch {
    // storage unavailable — fall through to system
  }
  return "system";
}

let systemWatcher: MediaQueryList | null = null;
let systemListener: ((e: MediaQueryListEvent) => void) | null = null;

function stopFollowingSystem(): void {
  if (systemWatcher && systemListener) {
    systemWatcher.removeEventListener("change", systemListener);
  }
  systemWatcher = null;
  systemListener = null;
}

/** Applies the appearance classes to <html>. Safe to call before React mounts. */
export function applyAppearance(mode: AppearanceMode): void {
  const root = document.documentElement;
  stopFollowingSystem();
  root.classList.remove("light", "dark", "pitch-black");
  if (mode === "light") {
    root.classList.add("light");
    root.style.colorScheme = "light";
  } else if (mode === "dark") {
    root.classList.add("dark");
    root.style.colorScheme = "dark";
  } else if (mode === "pitch-black") {
    root.classList.add("dark", "pitch-black");
    root.style.colorScheme = "dark";
  } else {
    root.style.colorScheme = "light dark";
    // SYSTEM MODE — THE DARK-MODE ROOT CAUSE. The CSS variables follow
    // prefers-color-scheme on their own, but every Tailwind `dark:` variant
    // is CLASS-driven: with no `dark` class on <html>, dark: utilities
    // silently stayed light while the page went dark (light-pink cards with
    // white text, cream coach cards on a black page). Mirror the OS into the
    // class and keep following it while the OS flips.
    const mq = typeof window !== "undefined" && window.matchMedia
      ? window.matchMedia("(prefers-color-scheme: dark)")
      : null;
    if (mq) {
      const sync = (dark: boolean): void => {
        root.classList.toggle("dark", dark);
      };
      sync(mq.matches);
      systemListener = (e) => sync(e.matches);
      mq.addEventListener("change", systemListener);
      systemWatcher = mq;
    }
  }
}

export function setAppearance(mode: AppearanceMode): void {
  try {
    localStorage.setItem(STORAGE_KEY, mode);
  } catch {
    // ignore private-mode storage failures
  }
  applyAppearance(mode);
}
