import { FlaskConical } from "lucide-react";

export function PitchDemoBanner() {
  return (
    <div className="sticky top-0 z-50 mx-auto max-w-2xl px-4 pt-3">
      <div className="flex items-center justify-center gap-2 rounded-full border border-amber-500/30 bg-amber-500/10 px-4 py-2 text-[12px] font-bold text-amber-600 backdrop-blur-sm">
        <FlaskConical className="h-3.5 w-3.5" />
        Demo data · no real backend calls · everything is local to this screen
      </div>
    </div>
  );
}
