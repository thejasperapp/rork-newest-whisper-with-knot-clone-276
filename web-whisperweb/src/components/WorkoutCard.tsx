import { memo, useState } from "react";
import { Dumbbell, Clock, Flame, Layers, ChevronDown } from "lucide-react";

import { cn } from "@/lib/utils";
import { Avatar } from "@/components/Avatar";
import type { WorkoutPayload } from "@/lib/workout";
import type { WhisperProfile } from "@/lib/types";

interface WorkoutCardProps {
  payload: WorkoutPayload;
  accentHex?: string | null;
  /** Author info for the compact feed preview (profile pic + handle). */
  author?: WhisperProfile;
  authorUsername?: string;
}

/** Normalise a `#RRGGBB`/`RRGGBB` hex into a CSS color, defaulting to the
 * Whisper warm-orange brand accent if the value is missing/invalid. */
function resolveAccent(hex?: string | null): string {
  if (!hex) return "#FA9452";
  const s = hex.startsWith("#") ? hex : `#${hex}`;
  return /^#[0-9a-fA-F]{6}$/.test(s) ? s : "#FA9452";
}

/**
 * Compact workout preview card matching the refined iOS `WhisperWorkoutPostCard` —
 * a minimal, premium surface with the author's profile picture and @handle up top,
 * the session title with a thin accent tick, a quiet monospaced stat string, and
 * a chevron that expands to reveal the exercise list inline. Designed to be
 * smaller and less cluttered than the old banner version.
 */
function WorkoutCardBase({ payload, accentHex, author, authorUsername }: WorkoutCardProps) {
  const [expanded, setExpanded] = useState<boolean>(false);
  const accent = resolveAccent(accentHex);
  const minutes = Math.max(0, Math.floor(payload.durationSeconds / 60));
  const focus = payload.focus.trim();
  const handle = author?.username ?? authorUsername ?? "you";

  return (
    <div className="mt-2 overflow-hidden rounded-xl border border-border bg-card">
      {/* Author row — profile pic + @handle + "Shared a workout" */}
      <div className="flex items-center gap-2 px-3 pt-2.5 pb-1">
        <Avatar
          url={author?.profile_image_url}
          name={handle}
          size={22}
        />
        <span className="truncate text-[12px] font-semibold">@{handle}</span>
        <span className="text-[11px] text-muted-foreground">· Shared a workout</span>
      </div>

      <button
        type="button"
        onClick={() => setExpanded((v) => !v)}
        className="flex w-full items-center gap-2.5 px-3 pb-2.5 text-left"
      >
        {/* Thin accent tick */}
        <span
          className="h-8 w-1 shrink-0 rounded-full"
          style={{ backgroundColor: accent }}
        />

        <span className="min-w-0 flex-1">
          <span className="block truncate text-[14px] font-bold leading-tight">
            {payload.displayName}
          </span>
          <span className="mt-0.5 flex items-center gap-2.5 text-[11px] font-medium text-muted-foreground tabular-nums">
            <span className="flex items-center gap-0.5">
              <Clock className="h-3 w-3" />
              {minutes}m
            </span>
            <span className="flex items-center gap-0.5">
              <Layers className="h-3 w-3" />
              {payload.totalSets} sets
            </span>
            <span className="flex items-center gap-0.5">
              <Flame className="h-3 w-3" />
              {payload.calories}
            </span>
          </span>
        </span>

        <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-secondary text-muted-foreground">
          <ChevronDown
            className={cn("h-3 w-3 transition-transform", expanded && "rotate-180")}
          />
        </span>
      </button>

      {expanded && payload.exerciseNames.length > 0 && (
        <div className="border-t border-border px-3 pb-3 pt-2.5">
          <p className="mb-1.5 text-[10px] font-bold uppercase tracking-[0.12em] text-muted-foreground">
            Exercises
          </p>
          <ul className="space-y-1">
            {payload.exerciseNames.map((name, i) => (
              <li
                key={`${name}-${i}`}
                className="flex items-center gap-2 text-[13px]"
              >
                <span className="flex h-4 w-4 items-center justify-center rounded-full bg-secondary text-[9px] font-bold text-muted-foreground tabular-nums">
                  {i + 1}
                </span>
                <span className="truncate">{name}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

export const WorkoutCard = memo(WorkoutCardBase);
