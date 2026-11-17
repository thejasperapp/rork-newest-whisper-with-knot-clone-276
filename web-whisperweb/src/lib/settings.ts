import { useCallback, useEffect, useState } from "react";

/**
 * Local Whisper preferences, persisted in localStorage. Mirrors the iOS
 * `WhisperNotificationPrefs` + ghost/muted-words settings. These are
 * client-side toggles (the private-account flag is server-backed instead).
 */

export type NotificationCategory =
  | "dm"
  | "mention"
  | "like"
  | "comment"
  | "follow"
  | "storyResponse";

export interface NotificationCategoryMeta {
  id: NotificationCategory;
  title: string;
  subtitle: string;
}

export const NOTIFICATION_CATEGORIES: NotificationCategoryMeta[] = [
  { id: "dm", title: "Direct messages", subtitle: "New DMs and message embeds" },
  {
    id: "mention",
    title: "@mentions",
    subtitle: "When someone tags you in a post, comment, or DM",
  },
  { id: "like", title: "Likes", subtitle: "When someone likes your post" },
  { id: "comment", title: "Comments", subtitle: "Replies on your posts" },
  { id: "follow", title: "New followers", subtitle: "Someone started following you" },
  {
    id: "storyResponse",
    title: "Story responses",
    subtitle: "Poll votes, slider ratings, and question replies",
  },
];

const PREFIX = "whisper.settings.";

function readBool(key: string, fallback: boolean): boolean {
  try {
    const raw = localStorage.getItem(PREFIX + key);
    return raw === null ? fallback : raw === "1";
  } catch {
    return fallback;
  }
}

function writeBool(key: string, value: boolean): void {
  try {
    localStorage.setItem(PREFIX + key, value ? "1" : "0");
    window.dispatchEvent(new Event("whisper-settings"));
  } catch {
    // storage unavailable — ignore
  }
}

function readList(key: string): string[] {
  try {
    const raw = localStorage.getItem(PREFIX + key);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as unknown;
    return Array.isArray(parsed) ? (parsed as string[]) : [];
  } catch {
    return [];
  }
}

function writeList(key: string, value: string[]): void {
  try {
    localStorage.setItem(PREFIX + key, JSON.stringify(value));
    window.dispatchEvent(new Event("whisper-settings"));
  } catch {
    // ignore
  }
}

/** Timestamp (ms) the user last opened the Notifications screen. */
export function getActivitySeenAt(): number {
  try {
    return Number(localStorage.getItem(PREFIX + "activitySeenAt") ?? 0) || 0;
  } catch {
    return 0;
  }
}

export function markActivitySeen(): void {
  try {
    localStorage.setItem(PREFIX + "activitySeenAt", String(Date.now()));
    window.dispatchEvent(new Event("whisper-settings"));
  } catch {
    // ignore
  }
}

/** Words/phrases the user wants hidden from their feed (lowercased). */
export function getMutedWords(): string[] {
  return readList("mutedWords");
}

export function setMutedWords(words: string[]): void {
  writeList("mutedWords", words);
}

/** True if a piece of text should be hidden based on the muted-words list. */
export function isMuted(text: string | null | undefined, muted: string[]): boolean {
  if (!text || muted.length === 0) return false;
  const haystack = text.toLowerCase();
  return muted.some((w) => w && haystack.includes(w.toLowerCase()));
}

interface WhisperSettings {
  pushEnabled: boolean;
  quietMode: boolean;
  ghostMode: boolean;
  categories: Record<NotificationCategory, boolean>;
  mutedWords: string[];
}

function readAll(): WhisperSettings {
  const categories = {} as Record<NotificationCategory, boolean>;
  for (const c of NOTIFICATION_CATEGORIES) {
    categories[c.id] = readBool(`cat.${c.id}`, true);
  }
  return {
    pushEnabled: readBool("push", true),
    quietMode: readBool("quiet", false),
    ghostMode: readBool("ghost", false),
    categories,
    mutedWords: getMutedWords(),
  };
}

/** Reactive hook over the local Whisper settings (syncs across tabs/components). */
export function useSettings(): {
  settings: WhisperSettings;
  setPushEnabled: (v: boolean) => void;
  setQuietMode: (v: boolean) => void;
  setGhostMode: (v: boolean) => void;
  setCategory: (id: NotificationCategory, v: boolean) => void;
  updateMutedWords: (words: string[]) => void;
} {
  const [settings, setSettings] = useState<WhisperSettings>(readAll);

  useEffect(() => {
    const sync = (): void => setSettings(readAll());
    window.addEventListener("whisper-settings", sync);
    window.addEventListener("storage", sync);
    return () => {
      window.removeEventListener("whisper-settings", sync);
      window.removeEventListener("storage", sync);
    };
  }, []);

  const setPushEnabled = useCallback((v: boolean) => writeBool("push", v), []);
  const setQuietMode = useCallback((v: boolean) => writeBool("quiet", v), []);
  const setGhostMode = useCallback((v: boolean) => writeBool("ghost", v), []);
  const setCategory = useCallback(
    (id: NotificationCategory, v: boolean) => writeBool(`cat.${id}`, v),
    []
  );
  const updateMutedWords = useCallback(
    (words: string[]) => setMutedWords(words),
    []
  );

  return {
    settings,
    setPushEnabled,
    setQuietMode,
    setGhostMode,
    setCategory,
    updateMutedWords,
  };
}
