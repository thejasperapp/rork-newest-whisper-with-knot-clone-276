import { memo } from "react";

import { TraceLogo } from "@/components/TraceLogo";

/**
 * Full-screen branded splash shown on cold launch while auth state warms —
 * mirrors the iOS `WhisperSplashView`: the traced wordmark centered on the
 * surface, with a "from Arcane" attribution (ghost + wordmark) at the bottom.
 */
function SplashBase() {
  return (
    <div className="fixed inset-0 z-50 flex flex-col items-center justify-center bg-background">
      <div className="flex flex-1 items-center justify-center">
        <TraceLogo size={220} className="max-w-[60vw]" />
      </div>

      <div className="flex flex-col items-center gap-1.5 pb-10">
        <span className="text-[13px] text-muted-foreground">from</span>
        <div className="flex items-center gap-1.5">
          <img
            src="/jasper-ghost.png"
            alt=""
            className="whisper-logo h-5 w-5 object-contain"
            draggable={false}
          />
          <span className="text-lg font-semibold">Arcane</span>
        </div>
      </div>
    </div>
  );
}

export const Splash = memo(SplashBase);
