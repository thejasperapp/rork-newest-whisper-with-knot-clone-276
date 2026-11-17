import { memo, useEffect, useMemo, useState } from "react";
import {
  Check,
  ChevronRight,
  Code2,
  Inbox,
  LineChart as LineChartIcon,
  Loader2,
  MessageSquareText,
  Play,
  Sparkles,
} from "lucide-react";

import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { EmberMascot } from "@/components/EmberMascot";
import { EmberBlockCard } from "@/components/EmberBlocks";
import type { EmberCoachMode, InterpretResult } from "@/lib/emberBrain";
import {
  interpretChipLabel,
  interpretDisplayCode,
  interpretIsPython,
  interpretRealDataChart,
  interpretSheetHeader,
} from "@/lib/emberBrain";
import { cn } from "@/lib/utils";

/**
 * Web port of the iOS `WhisperEmberThinkingSteps` (the live reasoning rail
 * shown while a turn runs), `WhisperEmberThinkingChip` (the tappable summary
 * under a reply) and the interpreter detail sheet — real code, real output,
 * real charts. Labels are generic and never fabricate numbers.
 */

/**
 * The adaptive step labels for an ask — the iOS `WhisperEmberThinkingSteps`
 * grammar: web-search asks search, image asks paint, health asks read your
 * data, post/profile asks look at your activity, plan asks structure.
 * Shared by the live rail and the "Thought for Ns" foldout.
 */
export function thinkingPhaseLabels(opts: {
  isAnalytical: boolean;
  resolvedLabel: string | null;
  question?: string | null;
}): string[] {
  const q = (opts.question ?? "").toLowerCase();
  if (opts.isAnalytical) {
    return [
      "Reading your data",
      "Writing the analysis",
      "Running it on your numbers",
      opts.resolvedLabel ?? "Drawing the chart",
    ];
  }
  if (/\b(latest|news|today|current|price|score|who won|weather|stock|when is|release date)\b/.test(q)) {
    return ["Searching the web", "Reading sources", "Writing it up with sources"];
  }
  if (/\b(imagine|draw|paint|picture of|image of|render|illustrat)/.test(q)) {
    return ["Painting your image"];
  }
  if (/\b(sleep|steps|heart rate|workout|calories|recovery|hrv|weight|macros)\b/.test(q)) {
    return ["Reading your health data", "Composing your answer"];
  }
  if (/\b(my post|my profile|my followers|engagement|my waves|my reels|my whisps)\b/.test(q)) {
    return ["Looking at your Whisper activity", "Composing your answer"];
  }
  if (/\b(plan|schedule|program|routine|roadmap)\b/.test(q)) {
    return ["Thinking", "Structuring the plan"];
  }
  return ["Thinking", "Composing your answer"];
}

/**
 * The ONE-LINE thinking rail — iOS round 71's grammar: while Jasper works
 * you see a single line of shimmering text showing only the current step,
 * crossfading as he advances. No box, no card, no step list, no mascot.
 */
export function EmberThinkingStepsBase({
  coachMode,
  resolvedLabel,
  isAnalytical,
  question,
}: {
  coachMode: EmberCoachMode;
  resolvedLabel: string | null;
  isAnalytical: boolean;
  question?: string | null;
}) {
  void coachMode;
  const labels = useMemo(
    () => thinkingPhaseLabels({ isAnalytical, resolvedLabel, question }),
    [isAnalytical, resolvedLabel, question],
  );

  const [active, setActive] = useState<number>(0);

  useEffect(() => {
    const t = window.setInterval(() => {
      setActive((a) => (a < labels.length - 1 ? a + 1 : a));
    }, 1100);
    return () => window.clearInterval(t);
  }, [labels.length]);

  // When the real intent lands, jump the rail to the final phase.
  useEffect(() => {
    if (resolvedLabel) setActive(labels.length - 1);
  }, [resolvedLabel, labels.length]);

  const label = labels[Math.min(active, labels.length - 1)] ?? "Thinking";

  return (
    <div className="flex items-center py-1 pl-0.5" aria-live="polite">
      <span key={label} className="jasper-shimmer-text text-[14.5px] font-semibold">
        {label}
      </span>
    </div>
  );
}

/** "Thought for Ns ⌄" — the quiet foldout above a landed answer. */
export function EmberThoughtFor({
  seconds,
  steps,
  open,
  onToggle,
}: {
  seconds: number;
  steps: string[];
  open: boolean;
  onToggle: () => void;
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <button
        type="button"
        onClick={onToggle}
        className="flex items-center gap-1 self-start text-[12.5px] font-semibold text-muted-foreground transition-colors hover:text-foreground"
        aria-expanded={open}
      >
        Thought for {seconds}s
        <ChevronRight className={cn("h-3.5 w-3.5 transition-transform", open ? "rotate-90" : "rotate-0")} />
      </button>
      {open && (
        <ul className="ml-1 space-y-1 border-l border-border pl-3">
          {steps.map((s) => (
            <li key={s} className="flex items-center gap-1.5 text-[12.5px] text-muted-foreground">
              <Check className="h-3 w-3" strokeWidth={3} />
              {s}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

void Inbox;
void LineChartIcon;
void Loader2;
void MessageSquareText;
void Play;
void Sparkles;
void EmberMascot;

export const EmberThinkingSteps = memo(EmberThinkingStepsBase);

/** Tappable summary chip under an Ember bubble when real analysis ran. */
function EmberThinkingChipBase({
  result,
  onClick,
}: {
  result: InterpretResult;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex max-w-full items-center gap-1.5 rounded-full border border-border bg-card px-3 py-1.5 text-xs font-semibold transition-colors hover:bg-secondary/60"
    >
      <Code2 className="h-3 w-3 shrink-0 text-muted-foreground" />
      <span className="truncate">{interpretChipLabel(result)}</span>
      <ChevronRight className="h-3 w-3 shrink-0 text-muted-foreground" />
    </button>
  );
}

export const EmberThinkingChip = memo(EmberThinkingChipBase);

/** Detail sheet — the real executed code, output, charts, and agent rounds. */
export function EmberInterpretSheet({
  result,
  open,
  onClose,
}: {
  result: InterpretResult | null;
  open: boolean;
  onClose: () => void;
}) {
  if (!result) return null;
  const code = interpretDisplayCode(result);
  const chart = interpretRealDataChart(result);
  const artifacts = (result.artifacts ?? []).filter((a) => a.base64);
  const rounds = result.rounds ?? [];

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-h-[85dvh] max-w-lg overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-base">
            <span className="flex h-7 w-7 items-center justify-center rounded-full bg-foreground text-background">
              <Code2 className="h-3.5 w-3.5" />
            </span>
            {interpretSheetHeader(result)}
          </DialogTitle>
        </DialogHeader>

        {result.intent && (
          <p className="text-sm font-semibold">{result.intent}</p>
        )}

        {rounds.length > 1 && (
          <p className="text-xs text-muted-foreground">
            Knot ran {rounds.length} self-directed analysis steps, each building
            on the last.
          </p>
        )}

        {code && (
          <div>
            <p className="mb-1 text-[11px] font-extrabold uppercase tracking-widest opacity-70">
              {interpretIsPython(result) ? "Executed Python" : "Computation"}
            </p>
            <pre className="max-h-56 overflow-auto rounded-xl border border-border bg-secondary/50 p-3 text-[11px] leading-relaxed">
              <code>{code}</code>
            </pre>
          </div>
        )}

        {result.output && (
          <div>
            <p className="mb-1 text-[11px] font-extrabold uppercase tracking-widest opacity-70">
              Output
            </p>
            <pre className="max-h-48 overflow-auto whitespace-pre-wrap rounded-xl border border-border bg-secondary/50 p-3 text-[11px] leading-relaxed">
              {result.output}
            </pre>
          </div>
        )}

        {chart && <EmberBlockCard block={{ kind: "chart", chart }} />}

        {artifacts.map((a, i) => (
          <img
            key={a.id ?? i}
            src={`data:${a.mimeType ?? "image/png"};base64,${a.base64}`}
            alt={a.title ?? "Analysis artifact"}
            className="w-full rounded-xl border border-border"
          />
        ))}

        {typeof result.ms === "number" && (
          <p className="text-right text-[10px] text-muted-foreground">
            Ran in {(result.ms / 1000).toFixed(1)}s
          </p>
        )}
      </DialogContent>
    </Dialog>
  );
}
