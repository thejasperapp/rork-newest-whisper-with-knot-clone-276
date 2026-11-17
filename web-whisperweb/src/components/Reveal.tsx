import { createElement, type ReactNode } from "react";
import { useReveal } from "@/hooks/useReveal";
import { cn } from "@/lib/utils";

type RevealVariant = "up" | "left" | "scale" | "fade";

const INIT_CLASS: Record<RevealVariant, string> = {
  up: "reveal-init",
  left: "reveal-left-init",
  scale: "reveal-scale-init",
  fade: "reveal-fade-init",
};

const IN_CLASS: Record<RevealVariant, string> = {
  up: "reveal-in",
  left: "reveal-left-in",
  scale: "reveal-scale-in",
  fade: "reveal-fade-in",
};

interface RevealProps {
  children: ReactNode;
  variant?: RevealVariant;
  /** Apply stagger to direct children instead of the wrapper itself. */
  stagger?: boolean;
  className?: string;
  as?: keyof JSX.IntrinsicElements;
  threshold?: number;
  rootMargin?: string;
}

/**
 * Reveal — a declarative scroll-reveal wrapper. Fades/slides its content
 * in when it scrolls into view. Use `stagger` to cascade children.
 */
export function Reveal({
  children,
  variant = "up",
  stagger = false,
  className,
  as: tag = "div",
  threshold,
  rootMargin,
}: RevealProps) {
  const [ref, visible] = useReveal<HTMLDivElement>({
    threshold,
    rootMargin,
  });

  if (stagger) {
    return createElement(tag, {
      ref: ref as React.RefObject<HTMLElement>,
      className: cn("reveal-stagger", visible && "reveal-in", className),
      children,
    });
  }

  return createElement(tag, {
    ref: ref as React.RefObject<HTMLElement>,
    className: cn(INIT_CLASS[variant], visible && IN_CLASS[variant], className),
    children,
  });
}
