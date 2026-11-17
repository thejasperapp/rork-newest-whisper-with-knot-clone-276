import { useState } from "react";
import { BadgeDollarSign, Plus, Trash2, X } from "lucide-react";

import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import type {
  CoachProgram,
  ProgramDay,
  ProgramExercise,
} from "@/lib/coach";

/**
 * Editor for a coach training program — title, focus, schedule, and a list of
 * days, each with its own exercises. Mirrors the iOS `WhisperCoachProgramsView`
 * builder. Local working copy is committed only on save.
 */
export function ProgramEditor({
  program,
  saving,
  onCancel,
  onSave,
}: {
  program: CoachProgram;
  saving: boolean;
  onCancel: () => void;
  onSave: (p: CoachProgram) => void;
}) {
  const [draft, setDraft] = useState<CoachProgram>(program);

  const update = (patch: Partial<CoachProgram>): void =>
    setDraft((d) => ({ ...d, ...patch }));

  const updateDay = (dayId: string, patch: Partial<ProgramDay>): void =>
    setDraft((d) => ({
      ...d,
      days: d.days.map((day) =>
        day.id === dayId ? { ...day, ...patch } : day
      ),
    }));

  const updateExercise = (
    dayId: string,
    exId: string,
    patch: Partial<ProgramExercise>
  ): void =>
    setDraft((d) => ({
      ...d,
      days: d.days.map((day) =>
        day.id === dayId
          ? {
              ...day,
              exercises: day.exercises.map((ex) =>
                ex.id === exId ? { ...ex, ...patch } : ex
              ),
            }
          : day
      ),
    }));

  const addDay = (): void =>
    setDraft((d) => ({
      ...d,
      days: [
        ...d.days,
        {
          id: crypto.randomUUID(),
          name: `Day ${d.days.length + 1}`,
          focus: "Full body",
          exercises: [],
        },
      ],
    }));

  const removeDay = (dayId: string): void =>
    setDraft((d) => ({ ...d, days: d.days.filter((day) => day.id !== dayId) }));

  const addExercise = (dayId: string): void =>
    setDraft((d) => ({
      ...d,
      days: d.days.map((day) =>
        day.id === dayId
          ? {
              ...day,
              exercises: [
                ...day.exercises,
                {
                  id: crypto.randomUUID(),
                  name: "",
                  sets: 3,
                  reps: "8-10",
                  restSeconds: 90,
                  note: null,
                },
              ],
            }
          : day
      ),
    }));

  const removeExercise = (dayId: string, exId: string): void =>
    setDraft((d) => ({
      ...d,
      days: d.days.map((day) =>
        day.id === dayId
          ? { ...day, exercises: day.exercises.filter((ex) => ex.id !== exId) }
          : day
      ),
    }));

  const canSave = draft.title.trim().length > 0;

  return (
    <Dialog open onOpenChange={(o) => !o && onCancel()}>
      <DialogContent className="max-h-[88vh] max-w-lg gap-0 overflow-y-auto p-0">
        <DialogHeader className="sticky top-0 z-10 border-b border-border/60 bg-background/95 px-5 py-4 backdrop-blur">
          <DialogTitle>Program</DialogTitle>
        </DialogHeader>

        <div className="space-y-5 px-5 py-5">
          <Field label="Title">
            <input
              value={draft.title}
              onChange={(e) => update({ title: e.target.value })}
              placeholder="e.g. 8-Week Hypertrophy"
              className="w-full rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-foreground/40"
            />
          </Field>

          <div className="grid grid-cols-3 gap-3">
            <Field label="Focus">
              <input
                value={draft.focus}
                onChange={(e) => update({ focus: e.target.value })}
                className="w-full rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-foreground/40"
              />
            </Field>
            <Field label="Weeks">
              <input
                type="number"
                value={draft.weeks}
                onChange={(e) =>
                  update({ weeks: Math.max(1, Number(e.target.value) || 1) })
                }
                className="w-full rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-foreground/40"
              />
            </Field>
            <Field label="Days/wk">
              <input
                type="number"
                value={draft.sessionsPerWeek}
                onChange={(e) =>
                  update({
                    sessionsPerWeek: Math.max(1, Number(e.target.value) || 1),
                  })
                }
                className="w-full rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-foreground/40"
              />
            </Field>
          </div>

          <Field label="Summary">
            <textarea
              value={draft.summary}
              onChange={(e) => update({ summary: e.target.value })}
              rows={2}
              placeholder="What's this program about?"
              className="w-full resize-none rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-foreground/40"
            />
          </Field>

          <Field label="Price">
            <div className="flex items-center gap-2 rounded-xl border border-border bg-card px-3 py-2.5">
              <BadgeDollarSign className="h-4 w-4 shrink-0 text-muted-foreground" />
              <span className="text-sm font-semibold text-muted-foreground">$</span>
              <input
                type="number"
                min={0}
                max={2000}
                value={draft.priceCents > 0 ? Math.round(draft.priceCents / 100) : ""}
                onChange={(e) => {
                  const dollars = Math.max(0, Math.min(2000, Number(e.target.value) || 0));
                  update({ priceCents: dollars * 100 });
                }}
                placeholder="0"
                aria-label="Program price in dollars"
                className="w-full bg-transparent text-sm outline-none"
              />
              <span className="shrink-0 text-xs text-muted-foreground">
                {draft.priceCents > 0 ? "one-time" : "free"}
              </span>
            </div>
            <p className="mt-1 text-[11px] text-muted-foreground">
              Set $5–$2,000 to sell this program — clients pay in-app before the
              full plan opens. Leave 0 to share it free.
            </p>
          </Field>

          {/* Days */}
          <div className="space-y-3">
            {draft.days.map((day) => (
              <div
                key={day.id}
                className="rounded-2xl border border-border bg-card/50 p-3"
              >
                <div className="flex items-center gap-2">
                  <input
                    value={day.name}
                    onChange={(e) => updateDay(day.id, { name: e.target.value })}
                    className="min-w-0 flex-1 rounded-lg bg-transparent px-1 py-1 text-sm font-bold outline-none"
                  />
                  <input
                    value={day.focus}
                    onChange={(e) =>
                      updateDay(day.id, { focus: e.target.value })
                    }
                    placeholder="focus"
                    className="w-28 rounded-lg bg-secondary px-2 py-1 text-xs outline-none"
                  />
                  <button
                    onClick={() => removeDay(day.id)}
                    aria-label="Remove day"
                    className="flex h-7 w-7 items-center justify-center rounded-full text-muted-foreground hover:text-destructive"
                  >
                    <X className="h-4 w-4" />
                  </button>
                </div>

                <div className="mt-2 space-y-2">
                  {day.exercises.map((ex) => (
                    <div key={ex.id} className="flex items-center gap-1.5">
                      <input
                        value={ex.name}
                        onChange={(e) =>
                          updateExercise(day.id, ex.id, {
                            name: e.target.value,
                          })
                        }
                        placeholder="Exercise"
                        className="min-w-0 flex-1 rounded-lg border border-border bg-background px-2 py-1.5 text-sm outline-none focus:border-foreground/40"
                      />
                      <input
                        type="number"
                        value={ex.sets}
                        onChange={(e) =>
                          updateExercise(day.id, ex.id, {
                            sets: Number(e.target.value) || 0,
                          })
                        }
                        aria-label="Sets"
                        className="w-12 rounded-lg border border-border bg-background px-2 py-1.5 text-center text-sm outline-none focus:border-foreground/40"
                      />
                      <span className="text-xs text-muted-foreground">×</span>
                      <input
                        value={ex.reps}
                        onChange={(e) =>
                          updateExercise(day.id, ex.id, {
                            reps: e.target.value,
                          })
                        }
                        aria-label="Reps"
                        className="w-16 rounded-lg border border-border bg-background px-2 py-1.5 text-center text-sm outline-none focus:border-foreground/40"
                      />
                      <button
                        onClick={() => removeExercise(day.id, ex.id)}
                        aria-label="Remove exercise"
                        className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-muted-foreground hover:text-destructive"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </div>
                  ))}
                  <button
                    onClick={() => addExercise(day.id)}
                    className="flex items-center gap-1 px-1 py-1 text-xs font-semibold text-primary"
                  >
                    <Plus className="h-3.5 w-3.5" />
                    Add exercise
                  </button>
                </div>
              </div>
            ))}

            <button
              onClick={addDay}
              className="flex w-full items-center justify-center gap-1.5 rounded-2xl border border-dashed border-border py-3 text-sm font-semibold text-muted-foreground transition-colors hover:bg-secondary/50"
            >
              <Plus className="h-4 w-4" />
              Add day
            </button>
          </div>
        </div>

        <div className="sticky bottom-0 flex gap-2 border-t border-border/60 bg-background/95 px-5 py-4 backdrop-blur">
          <button
            onClick={onCancel}
            className="flex-1 rounded-2xl bg-secondary py-3 text-sm font-bold transition-colors hover:bg-secondary/70"
          >
            Cancel
          </button>
          <button
            onClick={() => canSave && onSave(draft)}
            disabled={!canSave || saving}
            className="flex-[2] rounded-2xl bg-primary py-3 text-sm font-bold text-primary-foreground transition-transform active:scale-[0.98] disabled:opacity-50"
          >
            {saving ? "Saving…" : "Save program"}
          </button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <label className="mb-1.5 block text-xs font-semibold text-muted-foreground">
        {label}
      </label>
      {children}
    </div>
  );
}
