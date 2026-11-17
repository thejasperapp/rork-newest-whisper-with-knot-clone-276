import type { CalendarEventType } from "@/lib/calendar";

/**
 * Lightweight spoken-date detection for meeting voice transcripts — the web
 * counterpart of the iOS NSDataDetector flow. Scans a single finalized
 * caption ("let's film Friday at 3") for a concrete future date so the
 * meeting can offer a one-tap shared-calendar event.
 */
export interface SpokenSchedule {
  date: Date;
  snippet: string;
  eventType: CalendarEventType;
}

const WEEKDAYS = [
  "sunday",
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday",
];

const MONTHS = [
  "january",
  "february",
  "march",
  "april",
  "may",
  "june",
  "july",
  "august",
  "september",
  "october",
  "november",
  "december",
];

function parseTime(lower: string): { hours: number; minutes: number } | null {
  const ampm = /(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)/i.exec(lower);
  if (ampm) {
    let hours = parseInt(ampm[1], 10);
    const minutes = ampm[2] ? parseInt(ampm[2], 10) : 0;
    if (hours >= 1 && hours <= 12 && minutes >= 0 && minutes <= 59) {
      const isPm = ampm[3].toLowerCase().startsWith("p");
      if (isPm && hours !== 12) hours += 12;
      if (!isPm && hours === 12) hours = 0;
      return { hours, minutes };
    }
  }
  const at = /\bat\s+(\d{1,2})(?::(\d{2}))?\b(?!\s*(?:am|pm|a\.m\.|p\.m\.))/i.exec(
    lower,
  );
  if (at) {
    let hours = parseInt(at[1], 10);
    const minutes = at[2] ? parseInt(at[2], 10) : 0;
    if (hours >= 0 && hours <= 23 && minutes >= 0 && minutes <= 59) {
      // Spoken "at 3" almost always means the afternoon for 1–7.
      if (hours >= 1 && hours <= 7) hours += 12;
      return { hours, minutes };
    }
  }
  if (/\bnoon\b/.test(lower)) return { hours: 12, minutes: 0 };
  if (/\bmidnight\b/.test(lower)) return { hours: 0, minutes: 0 };
  return null;
}

/**
 * Detects a concrete future date in one utterance. Relative phrases are
 * always trusted because captions are real-time. Returns null when nothing
 * scheduling-worthy is found (10 min – 90 days out).
 */
export function detectSpokenSchedule(
  text: string,
  now: Date = new Date(),
): SpokenSchedule | null {
  const clean = text.trim();
  if (clean.length < 8 || clean.length > 400) return null;
  const lower = clean.toLowerCase();
  const time = parseTime(lower);

  let base: Date | null = null;

  if (/\btomorrow\b/.test(lower)) {
    base = new Date(now);
    base.setDate(base.getDate() + 1);
  } else if (/\btonight\b/.test(lower)) {
    base = new Date(now);
  } else if (/\btoday\b/.test(lower) && time) {
    base = new Date(now);
  }

  if (!base) {
    for (let i = 0; i < WEEKDAYS.length; i++) {
      if (new RegExp(`\\b(?:next\\s+)?${WEEKDAYS[i]}\\b`).test(lower)) {
        base = new Date(now);
        let delta = (i - base.getDay() + 7) % 7;
        if (delta === 0) delta = 7; // "Friday" said on a Friday → next week
        base.setDate(base.getDate() + delta);
        break;
      }
    }
  }

  if (!base) {
    const m =
      /\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b/.exec(
        lower,
      );
    if (m) {
      const monthIndex = MONTHS.findIndex((name) => name.startsWith(m[1]));
      const day = parseInt(m[2], 10);
      if (monthIndex >= 0 && day >= 1 && day <= 31) {
        base = new Date(now.getFullYear(), monthIndex, day);
        if (base.getTime() < now.getTime() - 86_400_000) {
          base.setFullYear(base.getFullYear() + 1);
        }
      }
    }
  }

  if (!base) {
    const m = /\b(\d{1,2})\/(\d{1,2})\b/.exec(lower);
    if (m) {
      const month = parseInt(m[1], 10);
      const day = parseInt(m[2], 10);
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        base = new Date(now.getFullYear(), month - 1, day);
        if (base.getTime() < now.getTime() - 86_400_000) {
          base.setFullYear(base.getFullYear() + 1);
        }
      }
    }
  }

  if (!base) return null;

  if (time) base.setHours(time.hours, time.minutes, 0, 0);
  else if (/\btonight\b/.test(lower)) base.setHours(19, 0, 0, 0);
  else base.setHours(12, 0, 0, 0);

  const ms = base.getTime();
  if (ms < now.getTime() + 10 * 60 * 1000) return null;
  if (ms > now.getTime() + 90 * 86_400_000) return null;

  return {
    date: base,
    snippet: clean.slice(0, 90),
    eventType: scheduleCategory(clean),
  };
}

/** Keyword auto-categorization — mirrors the iOS detector exactly. */
export function scheduleCategory(text: string): CalendarEventType {
  const lower = text.toLowerCase();
  const has = (words: string[]): boolean =>
    words.some((word) => lower.includes(word));
  if (
    has(["train", "workout", "gym", "lift", "session", "cardio", "leg day", "run together"])
  ) {
    return "training";
  }
  if (has(["film", "shoot", "record", "collab", "content", "reel", "podcast"])) {
    return "content_collab";
  }
  if (has(["deadline", "due by", "submit", "deliver by"])) return "deadline";
  if (has(["competition", "race", "expo", "meetup", "launch party"])) return "event";
  return "meet";
}

export const SCHEDULE_TYPE_LABELS: Record<CalendarEventType, string> = {
  meet: "Meet up",
  content_collab: "Content collab",
  training: "Training",
  event: "Event",
  deadline: "Deadline",
  other: "Other",
};

export const SCHEDULE_TYPE_COLORS: Record<CalendarEventType, string> = {
  meet: "#3b82f6",
  content_collab: "#a855f7",
  training: "#22c55e",
  event: "#f59e0b",
  deadline: "#ef4444",
  other: "#6b7280",
};

/** Types that make sense to open with a video meeting pre-attached. */
export function attachesMeetingByDefault(type: CalendarEventType): boolean {
  return type === "meet" || type === "content_collab";
}

/** "Training with @sam" / "Training with @sam +2" — group-aware title. */
export function suggestedScheduleTitle(
  type: CalendarEventType,
  names: string[],
): string {
  const base =
    type === "training"
      ? "Training"
      : type === "content_collab"
        ? "Content collab"
        : type === "event"
          ? "Event"
          : type === "deadline"
            ? "Deadline"
            : "Follow-up";
  const first = names[0];
  if (!first) return base;
  if (names.length === 1) return `${base} with @${first}`;
  return `${base} with @${first} +${names.length - 1}`;
}

/** Epoch ms → `datetime-local` input value in the user's timezone. */
export function toLocalInputValue(ms: number): string {
  const d = new Date(ms);
  const pad = (n: number): string => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** Compact "Fri, Aug 15 · 3:00 PM" line for the prompt banner. */
export function formatSpokenDate(ms: number): string {
  return new Date(ms).toLocaleString(undefined, {
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}
