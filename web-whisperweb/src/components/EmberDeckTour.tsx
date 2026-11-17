import { useEffect, useMemo, useRef, type ReactNode } from "react";
import {
  Briefcase,
  Calculator,
  Check,
  ChevronLeft,
  ChevronRight,
  Flame,
  Loader2,
  Pause,
  Play,
  Sparkles,
  Volume2,
  X,
} from "lucide-react";

import { PitchProvider } from "@/components/pitch/PitchContext";
import { WppCalculator } from "@/components/pitch/WppCalculator";
import { BrandMarketDemo } from "@/components/pitch/BrandMarketDemo";
import { EMBER_TOUR_SLIDES, clampTourPosition } from "@/lib/emberDeckTour";
import { cn } from "@/lib/utils";

/**
 * In-meeting Ember walkthrough + interactive pitch tools.
 *
 * The overlay shows the deck slide Ember is currently narrating, highlights
 * the exact line being read, and embeds the REAL interactive pitch
 * components — the WPP slider calculator and the brand marketplace card
 * modals — so nobody has to leave the meeting screen.
 */

/** Pitch demo components expect a PitchProvider (toasts, demo resets). */
function MeetingPitchScope({ children }: { children: ReactNode }) {
  const deckUrl = useMemo<string>(() => {
    try {
      return `${window.location.origin}/pitch/creators`;
    } catch {
      return "/pitch/creators";
    }
  }, []);
  return (
    <PitchProvider
      deckUrl={deckUrl}
      deckTitle="Whisper live walkthrough"
      deckId="meeting-live"
    >
      {children}
    </PitchProvider>
  );
}

function ToolDialogShell({
  icon,
  title,
  subtitle,
  onClose,
  children,
}: {
  icon: ReactNode;
  title: string;
  subtitle: string;
  onClose: () => void;
  children: ReactNode;
}) {
  return (
    <div
      className="fixed inset-0 z-[74] flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm"
      onClick={onClose}
    >
      <div
        className="flex max-h-[88vh] w-full max-w-lg flex-col overflow-hidden rounded-[24px] border border-white/15 bg-zinc-950 shadow-2xl"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="flex items-center justify-between gap-3 border-b border-white/10 px-4 py-3">
          <div className="flex min-w-0 items-center gap-2.5">
            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl bg-orange-500/15 text-orange-400">
              {icon}
            </span>
            <div className="min-w-0">
              <p className="truncate text-[14.5px] font-bold text-white">{title}</p>
              <p className="truncate text-[11px] text-white/50">{subtitle}</p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-white/60 transition-colors hover:bg-white/10 hover:text-white"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto bg-background p-4 text-foreground">
          {children}
        </div>
      </div>
    </div>
  );
}

/** The real WPP slider calculator, in a meeting modal. */
export function WppCalculatorDialog({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}) {
  if (!open) return null;
  return (
    <ToolDialogShell
      icon={<Calculator className="h-4 w-4" />}
      title="WPP earnings calculator"
      subtitle="Real partner tiers — drag the sliders, the math is live"
      onClose={onClose}
    >
      <MeetingPitchScope>
        <WppCalculator />
      </MeetingPitchScope>
    </ToolDialogShell>
  );
}

/** The real brand marketplace cards + detail modals, in a meeting modal. */
export function BrandCardsDialog({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}) {
  if (!open) return null;
  return (
    <ToolDialogShell
      icon={<Briefcase className="h-4 w-4" />}
      title="Brand marketplace"
      subtitle="The actual sponsor cards from the pitch deck — tap one open"
      onClose={onClose}
    >
      <MeetingPitchScope>
        <BrandMarketDemo />
      </MeetingPitchScope>
    </ToolDialogShell>
  );
}

export interface EmberDeckTourOverlayProps {
  slideIndex: number;
  segmentIndex: number;
  playing: boolean;
  driverName: string;
  /** True on the machine running Ember's voice (shows presenter controls). */
  isDriver: boolean;
  /** Driver-side voice line status (viewers always receive "live"). */
  voiceState: "off" | "connecting" | "live";
  /** True when narration plays locally on every device (iOS-driven tours)
   *  instead of riding the driver's call audio. */
  deviceNarration?: boolean;
  onClose: () => void;
  onPrevSlide: () => void;
  onNextSlide: () => void;
  onTogglePlay: () => void;
}

/** Full-screen synced walkthrough overlay with the live reading highlight. */
export function EmberDeckTourOverlay({
  slideIndex,
  segmentIndex,
  playing,
  driverName,
  isDriver,
  voiceState,
  deviceNarration = false,
  onClose,
  onPrevSlide,
  onNextSlide,
  onTogglePlay,
}: EmberDeckTourOverlayProps) {
  const pos = clampTourPosition(slideIndex, segmentIndex);
  const slide = EMBER_TOUR_SLIDES[pos.slide];
  const activeSegRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    activeSegRef.current?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }, [pos.slide, pos.segment]);

  const statusLine = isDriver
    ? voiceState === "live"
      ? "Live — everyone in the meeting hears Jasper"
      : voiceState === "connecting"
        ? "Warming up Jasper's voice…"
        : "Voice off"
    : deviceNarration
      ? `@${driverName} is presenting — Jasper narrates on this device`
      : `@${driverName} is presenting — Jasper reads over their audio`;

  return (
    <div className="fixed inset-0 z-[72] flex items-center justify-center bg-black/80 p-3 backdrop-blur-md sm:p-6">
      <div className="flex h-[min(90vh,800px)] w-full max-w-5xl flex-col overflow-hidden rounded-[28px] border border-white/12 bg-[#0b0b0d] shadow-2xl">
        {/* Header */}
        <div className="flex items-center justify-between gap-3 border-b border-white/10 px-4 py-3 sm:px-5">
          <div className="flex min-w-0 items-center gap-2.5">
            <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-2xl bg-orange-500/15">
              {voiceState === "connecting" && isDriver ? (
                <Loader2 className="h-4.5 w-4.5 animate-spin text-orange-400" />
              ) : (
                <Flame
                  className={cn(
                    "h-4.5 w-4.5 text-orange-400",
                    playing && "animate-pulse",
                  )}
                />
              )}
            </span>
            <div className="min-w-0">
              <p className="truncate text-[14.5px] font-bold text-white">
                Jasper deck walkthrough
              </p>
              <p className="truncate text-[11px] text-white/50">{statusLine}</p>
            </div>
          </div>
          <div className="flex shrink-0 items-center gap-3">
            <div className="hidden items-center gap-1.5 sm:flex">
              {EMBER_TOUR_SLIDES.map((s, idx) => (
                <span
                  key={s.id}
                  className={cn(
                    "h-1.5 rounded-full transition-all duration-300",
                    idx === pos.slide ? "w-5 bg-orange-400" : "w-1.5 bg-white/20",
                  )}
                />
              ))}
            </div>
            <button
              type="button"
              onClick={onClose}
              aria-label={isDriver ? "End walkthrough" : "Hide walkthrough"}
              className="flex h-8 w-8 items-center justify-center rounded-full text-white/60 transition-colors hover:bg-white/10 hover:text-white"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>

        {/* Body */}
        <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-4 sm:p-5 md:flex-row md:overflow-hidden">
          {/* Reading panel — the highlight follows Ember's voice. */}
          <div
            className={cn(
              "flex min-h-0 flex-col",
              slide.interactive
                ? "md:w-[44%] md:shrink-0"
                : "md:mx-auto md:w-full md:max-w-2xl",
            )}
          >
            <p className="text-[10.5px] font-black uppercase tracking-[0.14em] text-orange-400">
              {slide.kicker}
            </p>
            <h2 className="mt-1 text-[22px] font-black leading-tight text-white sm:text-[26px]">
              {slide.title}
            </h2>
            <div className="mt-3 min-h-0 flex-1 space-y-2 overflow-y-auto pr-1">
              {slide.segments.map((segment, idx) => {
                const isActive = idx === pos.segment;
                const isRead = idx < pos.segment;
                return (
                  <div
                    key={segment.id}
                    ref={isActive ? activeSegRef : undefined}
                    className={cn(
                      "flex items-start gap-2.5 rounded-2xl border px-3.5 py-3 transition-all duration-300",
                      isActive
                        ? "border-orange-400/50 bg-orange-500/12 shadow-[0_0_24px_rgba(251,146,60,0.16)]"
                        : isRead
                          ? "border-transparent bg-white/[0.04]"
                          : "border-transparent opacity-45",
                    )}
                  >
                    <span className="mt-0.5 shrink-0">
                      {isRead ? (
                        <Check className="h-3.5 w-3.5 text-orange-300/80" />
                      ) : isActive ? (
                        <Flame
                          className={cn(
                            "h-3.5 w-3.5 text-orange-400",
                            playing && "animate-pulse",
                          )}
                        />
                      ) : (
                        <span className="mt-1 block h-1.5 w-1.5 rounded-full bg-white/25" />
                      )}
                    </span>
                    <p
                      className={cn(
                        "text-[13.5px] leading-relaxed sm:text-[14px]",
                        isActive
                          ? "font-semibold text-white"
                          : isRead
                            ? "text-white/60"
                            : "text-white/55",
                      )}
                    >
                      {segment.text}
                    </p>
                  </div>
                );
              })}
            </div>
            {slide.stats.length > 0 && (
              <div className="mt-3 grid shrink-0 grid-cols-3 gap-2">
                {slide.stats.map((stat) => (
                  <div
                    key={stat.label}
                    className="rounded-2xl bg-white/[0.06] p-3 text-center"
                  >
                    <p className="text-[16px] font-black text-white">{stat.value}</p>
                    <p className="mt-0.5 text-[9.5px] font-semibold uppercase tracking-wide text-white/45">
                      {stat.label}
                    </p>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Interactive panel — the real product components, live. */}
          {slide.interactive && (
            <div className="flex min-h-0 flex-1 flex-col">
              {slide.interactiveHint && (
                <p className="mb-2 flex items-center gap-1.5 text-[11.5px] font-bold text-orange-300">
                  <Sparkles className="h-3.5 w-3.5 shrink-0" />
                  {slide.interactiveHint}
                </p>
              )}
              <div className="min-h-0 flex-1 overflow-y-auto rounded-[24px] bg-background p-3.5 text-foreground sm:p-4">
                <MeetingPitchScope>
                  {slide.interactive === "wpp" ? <WppCalculator /> : <BrandMarketDemo />}
                </MeetingPitchScope>
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between gap-3 border-t border-white/10 px-4 py-3 sm:px-5">
          {isDriver ? (
            <>
              <div className="flex items-center gap-1.5">
                <button
                  type="button"
                  onClick={onPrevSlide}
                  disabled={pos.slide === 0}
                  aria-label="Previous slide"
                  className="flex h-10 w-10 items-center justify-center rounded-full bg-white/10 text-white transition-colors hover:bg-white/18 disabled:opacity-35"
                >
                  <ChevronLeft className="h-4.5 w-4.5" />
                </button>
                <button
                  type="button"
                  onClick={onTogglePlay}
                  className="flex h-10 items-center gap-1.5 rounded-full bg-orange-500 px-4 text-[12.5px] font-bold text-slate-950 transition-colors hover:bg-orange-400"
                >
                  {playing ? (
                    <Pause className="h-4 w-4" />
                  ) : (
                    <Play className="h-4 w-4" />
                  )}
                  {playing ? "Pause" : "Resume"}
                </button>
                <button
                  type="button"
                  onClick={onNextSlide}
                  disabled={pos.slide === EMBER_TOUR_SLIDES.length - 1}
                  aria-label="Next slide"
                  className="flex h-10 w-10 items-center justify-center rounded-full bg-white/10 text-white transition-colors hover:bg-white/18 disabled:opacity-35"
                >
                  <ChevronRight className="h-4.5 w-4.5" />
                </button>
              </div>
              <p className="hidden text-[11px] font-semibold text-white/45 sm:block">
                Slide {pos.slide + 1} of {EMBER_TOUR_SLIDES.length}
              </p>
              <button
                type="button"
                onClick={onClose}
                className="rounded-full bg-red-500/90 px-4 py-2.5 text-[12px] font-bold text-white transition-colors hover:bg-red-400"
              >
                End walkthrough
              </button>
            </>
          ) : (
            <>
              <p className="flex min-w-0 items-center gap-1.5 text-[11.5px] text-white/55">
                <Volume2 className="h-3.5 w-3.5 shrink-0 text-orange-300" />
                <span className="truncate">
                  {deviceNarration
                    ? "Jasper's narration plays right on this device"
                    : `Jasper's voice plays through @${driverName}'s audio`}
                </span>
              </p>
              <p className="shrink-0 text-[11px] font-semibold text-white/45">
                {pos.slide + 1} / {EMBER_TOUR_SLIDES.length}
              </p>
              <button
                type="button"
                onClick={onClose}
                className="shrink-0 rounded-full bg-white/10 px-4 py-2.5 text-[12px] font-bold text-white/80 transition-colors hover:bg-white/16"
              >
                Hide
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
