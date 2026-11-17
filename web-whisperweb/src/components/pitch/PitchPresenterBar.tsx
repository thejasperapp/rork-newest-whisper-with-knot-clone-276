import { useEffect, useState } from "react";
import {
  ArrowLeft,
  ArrowRight,
  Clock,
  Download,
  Expand,
  Frame,
  MessageSquareQuote,
  Monitor,
  RotateCcw,
  Trash2,
  Type,
} from "lucide-react";

import { usePitch } from "@/components/pitch/PitchContext";
import { PitchExportPdf } from "@/components/pitch/PitchExportPdf";
import { cn } from "@/lib/utils";

export function PitchPresenterBar() {
  const {
    activeSectionIndex,
    sections,
    goToNextSection,
    goToPrevSection,
    resetDemo,
    pitchLength,
    setPitchLength,
    phoneFrame,
    setPhoneFrame,
    speakerNotes,
    setSpeakerNotes,
    secrets,
    setSecrets,
    resetNotes,
  } = usePitch();

  const [isFullscreen, setIsFullscreen] = useState(false);

  const toggleFullscreen = () => {
    if (!document.fullscreenElement) {
      void document.documentElement.requestFullscreen().catch(() => null);
    } else {
      void document.exitFullscreen().catch(() => null);
    }
  };

  useEffect(() => {
    const onChange = () => setIsFullscreen(Boolean(document.fullscreenElement));
    document.addEventListener("fullscreenchange", onChange);
    return () => document.removeEventListener("fullscreenchange", onChange);
  }, []);

  const sectionLabel = sections[activeSectionIndex]?.id
    ? `${activeSectionIndex + 1}/${sections.length}`
    : "";

  return (
    <div className="fixed bottom-4 left-1/2 z-[70] flex -translate-x-1/2 items-center gap-1.5 rounded-full border border-border bg-background/95 px-2 py-1.5 shadow-xl backdrop-blur-md">
      <span className="hidden px-2 text-[11px] font-bold text-muted-foreground sm:block">
        {sectionLabel}
      </span>

      <button
        onClick={goToPrevSection}
        className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary text-foreground transition-transform active:scale-90"
        aria-label="Previous section"
        title="Previous section (←)"
      >
        <ArrowLeft className="h-4 w-4" />
      </button>
      <button
        onClick={goToNextSection}
        className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary text-foreground transition-transform active:scale-90"
        aria-label="Next section"
        title="Next section (→)"
      >
        <ArrowRight className="h-4 w-4" />
      </button>

      <div className="mx-1 h-5 w-px bg-border" />

      <button
        onClick={() => setPitchLength(pitchLength === "short" ? "long" : "short")}
        className={cn(
          "flex h-9 items-center gap-1.5 rounded-full px-3 text-[11px] font-bold transition-colors",
          pitchLength === "short" ? "bg-foreground text-background" : "bg-secondary text-foreground"
        )}
        title="Toggle pitch length (L)"
      >
        <Clock className="h-3.5 w-3.5" />
        {pitchLength === "short" ? "5 min" : "15 min"}
      </button>

      <button
        onClick={() => setPhoneFrame(!phoneFrame)}
        className={cn(
          "flex h-9 items-center gap-1.5 rounded-full px-3 text-[11px] font-bold transition-colors",
          phoneFrame ? "bg-foreground text-background" : "bg-secondary text-foreground"
        )}
        title="Toggle phone frame (F)"
      >
        <Frame className="h-3.5 w-3.5" />
        <span className="hidden sm:inline">Phone</span>
      </button>

      <button
        onClick={() => setSpeakerNotes(!speakerNotes)}
        className={cn(
          "flex h-9 items-center gap-1.5 rounded-full px-3 text-[11px] font-bold transition-colors",
          speakerNotes ? "bg-foreground text-background" : "bg-secondary text-foreground"
        )}
        title="Toggle speaker notes (N)"
      >
        <MessageSquareQuote className="h-3.5 w-3.5" />
        <span className="hidden sm:inline">Notes</span>
      </button>

      <button
        onClick={() => setSecrets(!secrets)}
        className={cn(
          "flex h-9 items-center gap-1.5 rounded-full px-3 text-[11px] font-bold transition-colors",
          secrets ? "bg-foreground text-background" : "bg-secondary text-foreground"
        )}
        title="Toggle secrets (S)"
      >
        <Type className="h-3.5 w-3.5" />
        <span className="hidden sm:inline">Secrets</span>
      </button>

      <div className="mx-1 h-5 w-px bg-border" />

      <button
        onClick={resetDemo}
        className="flex h-9 items-center gap-1.5 rounded-full bg-secondary px-3 text-[11px] font-bold text-foreground transition-transform active:scale-95"
        title="Reset demo (R)"
      >
        <RotateCcw className="h-3.5 w-3.5" />
        <span className="hidden sm:inline">Reset</span>
      </button>

      <PitchExportPdf />

      <button
        onClick={resetNotes}
        className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary text-foreground transition-transform active:scale-90"
        aria-label="Reset notes"
        title="Reset notes to defaults"
      >
        <Trash2 className="h-4 w-4" />
      </button>

      <button
        onClick={toggleFullscreen}
        className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary text-foreground transition-transform active:scale-90"
        aria-label="Fullscreen"
        title="Fullscreen (F11)"
      >
        {isFullscreen ? <Monitor className="h-4 w-4" /> : <Expand className="h-4 w-4" />}
      </button>
    </div>
  );
}
