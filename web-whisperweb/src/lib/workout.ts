/**
 * Mirrors the iOS `WhisperWorkoutEmbed` format. A workout post's caption begins
 * with a unique prefix followed by a single line of compact JSON; any user copy
 * follows on subsequent lines. We parse the payload to render a rich card and
 * strip the embed so the raw JSON never leaks into the feed.
 */
const WORKOUT_PREFIX = "::whisper-workout-v1::";

export interface WorkoutPayload {
  id: string;
  displayName: string;
  focus: string;
  durationSeconds: number;
  calories: number;
  exerciseNames: string[];
  totalSets: number;
  date: number;
}

/** Decode the workout payload from a caption, or null if there isn't one. */
export function parseWorkoutEmbed(
  caption: string | null | undefined
): WorkoutPayload | null {
  if (!caption || !caption.startsWith(WORKOUT_PREFIX)) return null;
  const body = caption.slice(WORKOUT_PREFIX.length);
  const line = body.split("\n", 1)[0] ?? "";
  try {
    const obj = JSON.parse(line) as Partial<WorkoutPayload>;
    if (typeof obj.displayName !== "string") return null;
    return {
      id: obj.id ?? "",
      displayName: obj.displayName,
      focus: obj.focus ?? "",
      durationSeconds: obj.durationSeconds ?? 0,
      calories: obj.calories ?? 0,
      exerciseNames: Array.isArray(obj.exerciseNames) ? obj.exerciseNames : [],
      totalSets: obj.totalSets ?? 0,
      date: obj.date ?? 0,
    };
  } catch {
    return null;
  }
}

/** The visible caption text with the workout embed line removed. */
export function stripWorkoutEmbed(caption: string | null | undefined): string {
  if (!caption) return "";
  if (!caption.startsWith(WORKOUT_PREFIX)) return caption;
  const body = caption.slice(WORKOUT_PREFIX.length);
  const nl = body.indexOf("\n");
  return nl >= 0 ? body.slice(nl + 1).trim() : "";
}
