import { useEffect, useState, useRef } from "react";
import { cn } from "@/lib/utils";

export type CircleOrigin = "bottom" | "center" | "top" | "left" | "right";
export type CircleMode = "viewport" | "content";

interface CircleZoomTransitionProps {
  /** Trigger the transition whenever this flips to true. */
  active: boolean;
  /** Color of the expanding circle. */
  color?: string;
  /** Where the circle starts from. */
  origin?: CircleOrigin;
  /**
   * `viewport` (default) fills the whole screen like a route change.
   * `content` covers only the nearest positioned ancestor — perfect for
   * step changes inside a card/onboarding sheet.
   */
  mode?: CircleMode;
  /** Duration in ms. Defaults to 900ms. */
  duration?: number;
  /** Called right after the circle has fully covered the content. */
  onComplete?: () => void;
  /** Called when the transition has fully reset. */
  onReset?: () => void;
  /** Optional content shown inside the circle during the transition. */
  children?: React.ReactNode;
}

/**
 * Chime-style circular reveal transition. A colored disc expands from a point
 * to fill the entire viewport, then a callback fires so the next screen/step
 * can be mounted. Used for sign-in → onboarding and for step changes inside
 * onboarding and the applicant questionnaire.
 *
 * Implementation: a fixed overlay is clipped to a circle that scales from 0 to
 * a radius large enough to cover the longest screen diagonal. The origin is
 * translated to the requested quadrant. After the expansion phase completes,
 * `onComplete` fires. The component then auto-resets to hidden so it can be
 * re-triggered.
 */
export function CircleZoomTransition({
  active,
  color = "hsl(var(--primary))",
  origin = "bottom",
  mode = "viewport",
  duration = 900,
  onComplete,
  onReset,
  children,
}: CircleZoomTransitionProps) {
  const [phase, setPhase] = useState<"idle" | "expanding" | "holding" | "resetting">("idle");
  const completeCalledRef = useRef(false);
  const resetCalledRef = useRef(false);

  useEffect(() => {
    if (!active || phase !== "idle") return;
    completeCalledRef.current = false;
    resetCalledRef.current = false;
    setPhase("expanding");
  }, [active, phase]);

  useEffect(() => {
    if (phase !== "expanding") return;
    const timer = window.setTimeout(() => {
      setPhase("holding");
    }, duration);
    return () => window.clearTimeout(timer);
  }, [phase, duration]);

  useEffect(() => {
    if (phase !== "holding") return;
    if (!completeCalledRef.current) {
      completeCalledRef.current = true;
      onComplete?.();
    }
    const timer = window.setTimeout(() => {
      setPhase("resetting");
    }, 120);
    return () => window.clearTimeout(timer);
  }, [phase, onComplete]);

  useEffect(() => {
    if (phase !== "resetting") return;
    const timer = window.setTimeout(() => {
      setPhase("idle");
      if (!resetCalledRef.current) {
        resetCalledRef.current = true;
        onReset?.();
      }
    }, 80);
    return () => window.clearTimeout(timer);
  }, [phase, onReset]);

  const originClasses: Record<CircleOrigin, string> = {
    bottom: "left-1/2 bottom-0 -translate-x-1/2 translate-y-1/2",
    center: "left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2",
    top: "left-1/2 top-0 -translate-x-1/2 -translate-y-1/2",
    left: "left-0 top-1/2 -translate-x-1/2 -translate-y-1/2",
    right: "right-0 top-1/2 translate-x-1/2 -translate-y-1/2",
  };

  if (phase === "idle") return null;

  const isContent = mode === "content";

  return (
    <div
      className={cn(
        "pointer-events-none z-[100] overflow-hidden",
        isContent ? "absolute inset-0" : "fixed inset-0"
      )}
      aria-hidden="true"
    >
      <div
        className={cn(
          "absolute aspect-square rounded-full",
          originClasses[origin],
          phase === "expanding" && "animate-circle-zoom-in",
          phase === "holding" && "scale-[6]",
          phase === "resetting" && "opacity-0 transition-opacity duration-75"
        )}
        style={{
          backgroundColor: color,
          width: isContent ? "max(200%, 200%)" : "max(200vw, 200vh)",
          animationDuration: phase === "expanding" ? `${duration}ms` : undefined,
        }}
      >
        {children && (
          <div className="flex h-full w-full items-center justify-center text-primary-foreground">
            {children}
          </div>
        )}
      </div>
    </div>
  );
}

/** A small hook-style helper that returns a `trigger()` function and state. */
export function useCircleZoom(opts: Omit<CircleZoomTransitionProps, "active">) {
  const [active, setActive] = useState(false);
  const trigger = () => setActive(true);
  return { active, setActive, trigger, props: { active, ...opts } as CircleZoomTransitionProps };
}
