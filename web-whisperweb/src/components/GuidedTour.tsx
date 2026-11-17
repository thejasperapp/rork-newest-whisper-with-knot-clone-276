import { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { Lightbulb, MousePointerClick, X } from "lucide-react";

/**
 * GuidedTour — a real-time walkthrough that frames live elements. Each step
 * highlights an element (matched by its `data-tour` attribute) with a crisp
 * cut-out window — a sharp accent ring with a numbered tag, no blur, no
 * feathered spotlight — plus a step card connected to the target by a beak.
 * "Click here" steps demand a REAL click on the highlighted element to
 * advance, so tab-hop steps genuinely navigate the app while teaching it.
 *
 * The overlay never intercepts the pointer — every click lands on the real
 * UI underneath — and the window GLIDES between targets.
 */

export interface TourStep {
  /** Matches an element carrying data-tour="<target>". */
  target: string;
  title: string;
  body: string;
  /** Optional extra tip rendered with a lightbulb. */
  tip?: string;
  /** Advance only when the user clicks the highlighted element. */
  clickToAdvance?: boolean;
}

interface SpotRect {
  top: number;
  left: number;
  width: number;
  height: number;
}

const RING_PAD = 8;
const CARD_W = 344;
const EASE = "cubic-bezier(0.22, 1, 0.36, 1)";
/** Crisp dim painted around the cut-out window (no feather). */
const DIM = "rgba(8, 9, 14, 0.6)";

export function GuidedTour({
  steps,
  open,
  accent,
  onClose,
}: {
  steps: TourStep[];
  open: boolean;
  accent: string;
  /** completed=true when the user reached the end; false on skip/close. */
  onClose: (completed: boolean) => void;
}) {
  const [index, setIndex] = useState<number>(0);
  const [rect, setRect] = useState<SpotRect | null>(null);
  const [missing, setMissing] = useState<boolean>(false);
  const lastRectRef = useRef<SpotRect | null>(null);
  const step = steps[index] ?? null;
  const last = index === steps.length - 1;

  useEffect(() => {
    if (open) {
      setIndex(0);
      setRect(null);
      lastRectRef.current = null;
      setMissing(false);
    }
  }, [open]);

  // NOTE: the previous rect is intentionally KEPT while moving between steps
  // so the highlight window glides from the old spot to the new one.
  const advance = useCallback((): void => {
    setMissing(false);
    setIndex((i) => {
      if (i >= steps.length - 1) {
        onClose(true);
        return i;
      }
      return i + 1;
    });
  }, [onClose, steps.length]);

  const back = useCallback((): void => {
    setMissing(false);
    setIndex((i) => Math.max(0, i - 1));
  }, []);

  // Find + continuously track the target element (views mount lazily and
  // pages scroll — a one-shot measure would drift immediately).
  useEffect(() => {
    if (!open || !step) return;
    let raf = 0;
    let timer = 0;
    let tries = 0;
    let el: HTMLElement | null = null;
    let stopped = false;
    const clickHandler = (): void => {
      // Let the app's own handler run (tab switch, sheet open) first.
      window.setTimeout(() => advance(), 380);
    };

    const track = (): void => {
      if (stopped || !el) return;
      const r = el.getBoundingClientRect();
      const prev = lastRectRef.current;
      if (
        !prev ||
        Math.abs(prev.top - r.top) > 0.5 ||
        Math.abs(prev.left - r.left) > 0.5 ||
        Math.abs(prev.width - r.width) > 0.5 ||
        Math.abs(prev.height - r.height) > 0.5
      ) {
        const next: SpotRect = {
          top: r.top,
          left: r.left,
          width: r.width,
          height: r.height,
        };
        lastRectRef.current = next;
        setRect(next);
      }
      raf = window.requestAnimationFrame(track);
    };

    const find = (): void => {
      if (stopped) return;
      el = document.querySelector<HTMLElement>(
        `[data-tour="${step.target}"]`
      );
      if (!el) {
        tries += 1;
        if (tries > 26) {
          setMissing(true);
          return;
        }
        timer = window.setTimeout(find, 150);
        return;
      }
      setMissing(false);
      try {
        el.scrollIntoView({ block: "center", behavior: "smooth" });
      } catch {
        /* older browsers */
      }
      if (step.clickToAdvance) {
        el.addEventListener("click", clickHandler, { once: true });
      }
      track();
    };
    find();

    return () => {
      stopped = true;
      if (raf) window.cancelAnimationFrame(raf);
      if (timer) window.clearTimeout(timer);
      if (el) el.removeEventListener("click", clickHandler);
    };
  }, [open, step, advance]);

  // Escape closes.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === "Escape") onClose(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  if (!open || !step) return null;

  const vw = window.innerWidth;
  const vh = window.innerHeight;
  const huge = !!rect && rect.height > vh * 0.55;
  const showCentered = missing || !rect;

  // Tooltip placement: below the highlight, above it, or pinned to the
  // bottom center when the highlighted region is most of the screen.
  let cardStyle: React.CSSProperties;
  let placement: "below" | "above" | "pinned" = "pinned";
  let cardLeft = 0;
  const cardW = Math.min(CARD_W, vw - 24);
  if (showCentered || huge) {
    cardStyle = {
      left: "50%",
      bottom: 24,
      transform: "translateX(-50%)",
      width: cardW,
    };
  } else if (rect.top + rect.height + 240 < vh) {
    placement = "below";
    cardLeft = Math.min(
      Math.max(12, rect.left + rect.width / 2 - cardW / 2),
      vw - cardW - 12
    );
    cardStyle = {
      top: rect.top + rect.height + 20,
      left: cardLeft,
      width: cardW,
    };
  } else {
    placement = "above";
    cardLeft = Math.min(
      Math.max(12, rect.left + rect.width / 2 - cardW / 2),
      vw - cardW - 12
    );
    cardStyle = {
      bottom: vh - rect.top + 20,
      left: cardLeft,
      width: cardW,
    };
  }

  // Beak x — points at the target's center, clamped inside the card.
  const beakLeft = rect
    ? Math.min(
        Math.max(rect.left + rect.width / 2 - cardLeft - 7, 20),
        cardW - 34
      )
    : 0;

  const spotRadius = rect
    ? Math.min(20, Math.max(12, Math.min(rect.height, rect.width) / 2))
    : 16;

  return createPortal(
    <div className="fixed inset-0 z-[200]" style={{ pointerEvents: "none" }}>
      <style>{`
        @keyframes tour-card-in {
          from { opacity: 0; transform: translateY(8px) scale(0.985); }
          to { opacity: 1; transform: translateY(0) scale(1); }
        }
        @keyframes tour-card-in-centered {
          from { opacity: 0; transform: translate(-50%, 8px) scale(0.985); }
          to { opacity: 1; transform: translate(-50%, 0) scale(1); }
        }
        @keyframes tour-click-nudge {
          0%, 100% { transform: translateY(0); }
          50% { transform: translateY(3px); }
        }
        @keyframes tour-dim-in {
          from { opacity: 0; }
          to { opacity: 1; }
        }
        @keyframes tour-tag-pop {
          0% { opacity: 0; transform: scale(0.6); }
          70% { transform: scale(1.08); }
          100% { opacity: 1; transform: scale(1); }
        }
      `}</style>

      {/* The cut-out window: a crisp dim with a sharp accent ring — no blur,
          no feather. It glides between targets and never catches the
          pointer, so "click here" steps hit the real element. */}
      {rect && !missing ? (
        <div
          className="absolute"
          style={{
            top: rect.top - RING_PAD,
            left: rect.left - RING_PAD,
            width: rect.width + RING_PAD * 2,
            height: rect.height + RING_PAD * 2,
            borderRadius: spotRadius,
            boxShadow: `inset 0 0 0 1px rgba(255,255,255,0.55), 0 0 0 2px ${accent}, 0 0 0 7px ${accent}30, 0 0 0 200vmax ${DIM}`,
            transition: `top 0.5s ${EASE}, left 0.5s ${EASE}, width 0.5s ${EASE}, height 0.5s ${EASE}, border-radius 0.5s ${EASE}`,
            animation: "tour-dim-in 0.35s ease both",
          }}
        >
          {/* Numbered tag pinned to the frame's top-left corner. */}
          <div
            key={`tag-${index}`}
            className="absolute flex h-[26px] min-w-[26px] items-center justify-center rounded-full px-1.5 text-[12px] font-black text-white"
            style={{
              top: -13,
              left: 12,
              backgroundColor: accent,
              boxShadow: "0 4px 12px rgba(0,0,0,0.35)",
              animation: "tour-tag-pop 0.35s ease both",
            }}
          >
            {index + 1}
          </div>
        </div>
      ) : (
        <div
          className="absolute inset-0"
          style={{ background: DIM, animation: "tour-dim-in 0.35s ease both" }}
        />
      )}

      {/* The step card */}
      <div
        key={index}
        className="absolute rounded-[20px] border border-white/12 bg-[#0C0C11]/[0.97] p-4 text-white shadow-[0_18px_50px_rgba(0,0,0,0.5)] backdrop-blur-xl"
        style={{
          ...cardStyle,
          pointerEvents: "auto",
          animation:
            showCentered || huge
              ? "tour-card-in-centered 0.3s ease both"
              : "tour-card-in 0.3s ease both",
        }}
      >
        {/* Beak pointing at the highlighted element. */}
        {!showCentered && !huge && (
          <span
            aria-hidden
            className="absolute h-3.5 w-3.5 rotate-45 bg-[#0C0C11]"
            style={
              placement === "below"
                ? {
                    top: -8,
                    left: beakLeft,
                    borderTop: "1px solid rgba(255,255,255,0.14)",
                    borderLeft: "1px solid rgba(255,255,255,0.14)",
                  }
                : {
                    bottom: -8,
                    left: beakLeft,
                    borderBottom: "1px solid rgba(255,255,255,0.14)",
                    borderRight: "1px solid rgba(255,255,255,0.14)",
                  }
            }
          />
        )}

        <div className="flex items-center justify-between gap-3">
          <span
            className="rounded-full px-2 py-0.5 text-[10px] font-black uppercase tracking-[0.14em]"
            style={{ color: accent, backgroundColor: `${accent}1F` }}
          >
            Step {index + 1} of {steps.length}
          </span>
          <button
            onClick={() => onClose(false)}
            aria-label="Skip walkthrough"
            className="-m-1 rounded-full p-1 text-white/50 transition-colors hover:text-white"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Segmented progress — one tick per step. */}
        <div className="mt-2.5 flex gap-[3px]">
          {steps.map((_, i) => (
            <span
              key={i}
              className="h-[3px] flex-1 rounded-full transition-colors duration-300"
              style={{
                backgroundColor:
                  i <= index ? accent : "rgba(255,255,255,0.12)",
              }}
            />
          ))}
        </div>

        <p className="mt-2.5 text-[15px] font-extrabold leading-snug">
          {step.title}
        </p>
        <p className="mt-1 text-[12.5px] leading-relaxed text-white/75">
          {step.body}
        </p>
        {step.tip && (
          <p className="mt-2 flex items-start gap-1.5 rounded-[12px] bg-white/[0.07] px-2.5 py-2 text-[11.5px] leading-snug text-white/80">
            <Lightbulb
              className="mt-0.5 h-3.5 w-3.5 shrink-0"
              style={{ color: accent }}
            />
            {step.tip}
          </p>
        )}
        <div className="mt-3 flex items-center gap-2">
          {step.clickToAdvance && !showCentered ? (
            <span
              className="flex flex-1 items-center gap-1.5 text-[12px] font-extrabold"
              style={{ color: accent }}
            >
              <MousePointerClick
                className="h-4 w-4"
                style={{ animation: "tour-click-nudge 1s ease-in-out infinite" }}
              />
              Click the framed spot
            </span>
          ) : (
            <span className="flex-1" />
          )}
          {index > 0 && (
            <button
              onClick={back}
              className="rounded-full px-3 py-2 text-[12px] font-bold text-white/60 transition-colors hover:text-white"
            >
              Back
            </button>
          )}
          {(!step.clickToAdvance || showCentered) && (
            <button
              onClick={advance}
              className="rounded-full px-4 py-2 text-[12px] font-extrabold text-white transition-transform active:scale-95"
              style={{ backgroundColor: accent }}
            >
              {last ? "Done" : "Next"}
            </button>
          )}
        </div>
      </div>
    </div>,
    document.body
  );
}
